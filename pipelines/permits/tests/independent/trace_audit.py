"""Independent trace of a permits audit worksheet (DECISIONS.md H3, D33).

For each sampled permit, and with no code shared with the R pipeline:

- re-fetches the permit from the City's DPD Building Permits layer
  (read-only query; the free-text Description is not requested);
- recomputes the local issue date, and reads sector and kind of work a second
  way, from the permit number itself (RES-ALT-25-001360 is a residential
  alteration), beside the Sub_Type and Construction_Type the pipeline maps;
- compares the point with the worksheet's, and with the permit's street
  address geocoded by the Census Bureau;
- re-assigns ZIP code (ZCTA) and council district with its own
  point-in-polygon, and compares the layer's own ZIP_Code field.

It then refetches every permit and recomputes, from the specs, every
published row a count or a sum can check: permits per 1,000 parcels (primary
and excl_minor) and the declared-value total and median (primary and
median_per_permit), for the city, ZIP codes and council districts. Intervals
are not recomputed.

It writes the worksheet with `ev_*` columns and a file comparing each
recomputed row with the published one. It answers nothing: the auditor reads
the evidence and fills in the check columns.

The projection, point-in-polygon and geocoder helpers are the 311 pipeline's
independent ones (pipelines/311/tests/independent/).

Usage (from the repository root):
  python pipelines/permits/tests/independent/trace_audit.py <audit_sample_YYYY-MM-DD.csv> \
      <published permits dir> <out evidence.csv> <out rows.csv>
"""

import csv
import datetime as dt
import json
import math
import os
import re
import statistics
import sys
import time
import urllib.parse
import urllib.request
from collections import defaultdict

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "pipelines", "311", "tests", "independent"))
import recompute_golden as rg   # noqa: E402
import audit_evidence as ae     # noqa: E402

LAYER = ("https://services2.arcgis.com/saWmpKJIUAjyyNVc/arcgis/rest/services/"
         "DPD_Building_Permits/FeatureServer/0")
FIELDS = ["ObjectId", "Record_ID", "Issued_Date", "Sub_Type", "Construction_Type", "Valuation",
          "Address", "City", "ZIP_Code", "Latitude", "Longitude"]
UA = "memphis-service-equity (https://github.com/jpbranson/mem-service-equity)"
ID_SECTOR = {"RES": "residential", "COM": "commercial"}
ID_WORK = {"NEW": ("new", "new"), "ALT": ("alteration", "renovation"), "ADD": ("addition", "renovation"),
           "ACC": ("accessory", "accessory")}
CATEGORIES, SECTORS = ["new", "renovation", "accessory"], ["residential", "commercial"]
MIN_PARCELS, MIN_N_VALUE, MINOR_VALUE = 250, 20, 5000
GEOS = ["citywide", "zcta", "council_district"]


def get(path, **params):
    data = urllib.parse.urlencode(dict(params, f="json")).encode()
    req = urllib.request.Request(LAYER + path, data=data if path else None, headers={"User-Agent": UA})
    if not path:
        req = urllib.request.Request(LAYER + "?f=json", headers={"User-Agent": UA})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                body = json.loads(resp.read().decode("utf-8"))
            if "error" in body:
                raise RuntimeError(body["error"])
            return body
        except Exception:
            if attempt == 4:
                raise
            time.sleep(2 ** attempt)


def fetch_all():
    out, after = [], 0
    while True:
        feats = get("/query", where=f"ObjectId > {after}", outFields=",".join(FIELDS),
                    orderByFields="ObjectId ASC", resultRecordCount=1000, returnGeometry="false")["features"]
        if not feats:
            return [f["attributes"] for f in out]
        out += feats
        after = feats[-1]["attributes"]["ObjectId"]


def utc(ms):
    return None if ms is None else dt.datetime.fromtimestamp(ms / 1000, dt.timezone.utc)


def years_before(day, years):
    return day.replace(year=day.year - years)


def read_map(name, key):
    return {r[key]: r for r in rg.read_csv(os.path.join(REPO, "pipelines", "permits", "config", name))}


def from_id(record_id):
    """Sector, work and category read from the permit number, or Nones."""
    m = re.match(r"^(RES|COM)-(NEW|ALT|ADD|ACC)-\d", record_id or "")
    return (ID_SECTOR[m.group(1)],) + ID_WORK[m.group(2)] if m else (None, None, None)


def main(sheet_path, published, out_path, rows_path):
    as_of = dt.date.fromisoformat(re.search(r"(\d{4}-\d{2}-\d{2})", os.path.basename(sheet_path)).group(1))
    sector_map, category_map = read_map("sector_map.csv", "sub_type"), read_map("category_map.csv", "construction_type")
    areas = {g: rg.load_areas(g) for g in GEOS}
    sheet = rg.read_csv(sheet_path)

    # Data run through the end of the month before the layer's last edit.
    info = get("")["editingInfo"]
    edit_day = rg.chicago_date(utc(info.get("dataLastEditDate") or info["lastEditDate"]))
    through = min(edit_day.replace(day=1) - dt.timedelta(days=1), as_of - dt.timedelta(days=1))

    raw = fetch_all()
    print(f"{len(raw)} permits fetched; layer last edited {edit_day}; complete through {through}")
    permits, by_id = [], {}
    for a in raw:
        issued = utc(a["Issued_Date"])
        p = dict(id=a["Record_ID"], issue_date=rg.chicago_date(issued) if issued else None,
                 sector=(sector_map.get(a["Sub_Type"] or "") or {}).get("sector"),
                 work=(category_map.get(a["Construction_Type"] or "") or {}).get("work"),
                 category=(category_map.get(a["Construction_Type"] or "") or {}).get("category"),
                 value=a["Valuation"] if (a["Valuation"] or 0) > 0 else None, raw=a)
        lon, lat = a["Longitude"], a["Latitude"]
        p["located"] = (lon is not None and lat is not None
                        and rg.BBOX[0] <= lon <= rg.BBOX[2] and rg.BBOX[1] <= lat <= rg.BBOX[3])
        for g in GEOS:
            p[g] = None
        if p["located"]:
            p["xy"] = rg.project(lon, lat)
            for g in GEOS:
                p[g] = rg.assign(areas[g], *p["xy"])
        p["counted"] = (p["issue_date"] is not None and p["sector"] is not None and p["category"] is not None
                        and p["issue_date"] <= through and p["citywide"] is not None)
        permits.append(p)
        by_id[p["id"]] = p

    # How often the permit number and the mapped fields say the same thing.
    both = [(from_id(p["id"]), p) for p in permits if from_id(p["id"])[0] and p["sector"] and p["category"]]
    agree = sum(1 for (s, w, c), p in both if s == p["sector"] and c == p["category"])
    print(f"permit number agrees with the mapped sector and category on {agree} of {len(both)} permits "
          f"({len(permits) - len(both)} have another number format or an unmapped type)")

    # ---- each sampled permit ----
    to_geocode = []
    for r in sheet:
        p = by_id.get(r["permit_id"])
        if p and re.match(r"^\d+\s", (p["raw"]["Address"] or "").strip()):
            a = p["raw"]
            to_geocode.append((r["permit_id"], a["Address"].strip(), (a["City"] or "Memphis").strip(), "TN",
                               (a["ZIP_Code"] or "").strip()[:5]))
    geocoded = ae.census_geocode(to_geocode) if to_geocode else {}
    print(f"geocoder: {len(geocoded)} of {len(to_geocode)} street addresses matched")
    for r in sheet:
        p = by_id.get(r["permit_id"])
        r["ev_found_in_source"] = "yes" if p else "no"
        if not p:
            continue
        a = p["raw"]
        r["ev_issue_date"] = "" if p["issue_date"] is None else p["issue_date"].isoformat()
        r["ev_issue_date_matches"] = "yes" if r["ev_issue_date"] == r["issue_date"] else "no"
        r["ev_sub_type"], r["ev_construction_type"] = a["Sub_Type"] or "", a["Construction_Type"] or ""
        s, w, c = from_id(p["id"])
        r["ev_id_says"] = "" if s is None else f"{s} {w}"
        r["ev_category_matches_source_fields"] = "yes" if (p["sector"], p["work"], p["category"]) == (
            r["sector"], r["work"], r["category"]) else "no"
        r["ev_category_matches_id"] = "" if s is None else (
            "yes" if (s, w, c) == (r["sector"], r["work"], r["category"]) else "no")
        want = "" if p["value"] is None else p["value"]
        r["ev_value_matches"] = "yes" if (r["declared_value"] == "" and want == "") or (
            r["declared_value"] != "" and want != "" and abs(float(r["declared_value"]) - want) < 0.005) else "no"
        r["ev_point_matches"] = "yes" if (p["located"] and abs(float(r["longitude"]) - a["Longitude"]) < 1e-6
                                          and abs(float(r["latitude"]) - a["Latitude"]) < 1e-6) else "no"
        if p["located"]:
            r["ev_in_city"] = "yes" if p["citywide"] else "no"
            r["ev_zcta"], r["ev_council_district"] = p["zcta"] or "", p["council_district"] or ""
            r["ev_geography_matches"] = "yes" if (r["ev_zcta"] == r["zcta"] and
                                                   r["ev_council_district"] == r["council_district"]) else "no"
            r["ev_source_zip"] = (a["ZIP_Code"] or "").strip()[:5]
            r["ev_source_zip_matches"] = "yes" if r["ev_source_zip"] == r["zcta"] else "no"
            r["ev_within_100m_of_zcta_boundary"] = "yes" if any(
                ar.within(*p["xy"], 100) for ar in areas["zcta"]) else "no"
            if r["permit_id"] in geocoded:
                lon, lat, kind = geocoded[r["permit_id"]]
                r["ev_geocode_match"] = kind
                gxy = rg.project(lon, lat)
                r["ev_geocode_distance_m"] = round(math.dist(p["xy"], gxy))
                # Would the geocoded address land in the same areas as the point?
                r["ev_geocode_same_areas"] = "yes" if (
                    (rg.assign(areas["zcta"], *gxy) or "") == r["zcta"] and
                    (rg.assign(areas["council_district"], *gxy) or "") == r["council_district"]) else "no"
            else:
                r["ev_geocode_match"] = "no match"

    # ---- every published row a count or a sum can check ----
    parcels = defaultdict(dict)
    reg = rg.read_csv(os.path.join(REPO, "geography", "parcels", "registry.csv"))[0]
    for row in rg.read_csv(os.path.join(REPO, "geography", "parcels", reg["file"])):
        parcels[row["geo_type"]][row["geo_id"]] = int(row["parcels"])
    counted = [p for p in permits if p["counted"]]

    def in_subgroup(p, name):
        if name == "all":
            return True
        cat, _, sec = name.partition("_")
        return p["category"] == cat and (not sec or p["sector"] == sec)

    subgroups = ["all"] + SECTORS_ALL + [c for c in CATEGORIES] + [f"{c}_{s}" for c in CATEGORIES for s in SECTORS]
    mine = {}
    for years, _ in ((1, "12m"), (5, "5y")):
        start = years_before(through + dt.timedelta(days=1), years)
        inwin = [p for p in counted if start <= p["issue_date"] <= through]
        for sub in subgroups:
            rows = [p for p in inwin if (in_subgroup(p, sub) if not sub.startswith("all_")
                                         else p["sector"] == sub[4:])]
            for g in GEOS:
                groups = defaultdict(list)
                for p in rows:
                    if p[g] is not None:
                        groups[p[g]].append(p)
                for gid, n_parcels in parcels[g].items():
                    ps = groups.get(gid, [])
                    key = (g, gid, sub, start.isoformat())
                    small = n_parcels < MIN_PARCELS
                    mine[("permits_per_1000_parcels", "primary") + key] = dict(
                        n=len(ps), value=None if small else len(ps) / n_parcels * 1000)
                    kept = [p for p in ps if p["value"] is None or p["value"] >= MINOR_VALUE]
                    mine[("permits_per_1000_parcels", "excl_minor") + key] = dict(
                        n=len(kept), value=None if small else len(kept) / n_parcels * 1000)
                    vals = [p["value"] for p in ps if p["value"] is not None]
                    hidden = small or len(vals) < MIN_N_VALUE
                    mine[("declared_value_per_1000_parcels", "primary") + key] = dict(
                        n=len(vals), value=None if hidden else sum(vals) / n_parcels * 1000)
                    mine[("declared_value_per_1000_parcels", "median_per_permit") + key] = dict(
                        n=len(vals), value=None if hidden else statistics.median(vals))

    num = lambda s: None if s in ("", "NA") else float(s)
    compared, seen = [], set()
    for g in GEOS:
        for row in rg.read_csv(os.path.join(published, f"metrics_permits_by_{g}.csv")):
            key = (row["metric"], row["variant"], g, row["geo_id"], row["subgroup"], row["window_start"])
            if key not in mine:
                continue
            seen.add(key)
            got = mine[key]
            diffs = [] if got["n"] == int(row["n"]) else ["n"]
            pv = num(row["value"])
            if (got["value"] is None) != (pv is None) or (pv is not None and
                                                           abs(got["value"] - pv) > 1e-9 * max(1.0, abs(pv))):
                diffs.append("value")
            compared.append(dict(metric=row["metric"], variant=row["variant"], geo_type=g, geo_id=row["geo_id"],
                                 subgroup=row["subgroup"], window_start=row["window_start"],
                                 published_n=row["n"], recomputed_n=got["n"], published_value=row["value"],
                                 recomputed_value="" if got["value"] is None else got["value"],
                                 agree="no" if diffs else "yes", differs_in=", ".join(diffs)))
    missing = [k for k in mine if k not in seen]
    bad = sum(c["agree"] == "no" for c in compared)
    print(f"published rows recomputed: {len(compared)}; agree: {len(compared) - bad}; differ: {bad}; "
          f"recomputed rows with no published row: {len(missing)}")

    # Which of those rows each sampled permit counts in.
    cell_ok = defaultdict(lambda: [0, 0])
    for c in compared:
        k = (c["geo_type"], c["geo_id"])
        cell_ok[k][0] += 1
        cell_ok[k][1] += c["agree"] == "yes"
    for r in sheet:
        k = ("zcta", r["zcta"])
        if k in cell_ok:
            r["ev_published_zip_rows_recomputed"], r["ev_published_zip_rows_agree"] = cell_ok[k]

    cols = list(rg.read_csv(sheet_path)[0].keys())
    human = [c for c in cols if re.match(r"^\d+_", c) or c in ("auditor", "notes")]
    ev = []
    for r in sheet:
        ev += [c for c in r if c.startswith("ev_") and c not in ev]
    with open(out_path, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=[c for c in cols if c not in human] + ev + human, restval="")
        w.writeheader()
        w.writerows(sheet)
    with open(rows_path, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(compared[0]))
        w.writeheader()
        w.writerows(compared)
    print("wrote", out_path, "and", rows_path)


SECTORS_ALL = [f"all_{s}" for s in SECTORS]

if __name__ == "__main__":
    main(*sys.argv[1:5])
