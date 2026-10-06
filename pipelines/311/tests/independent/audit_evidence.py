"""Evidence for the 311 audit beyond the pre-trace (DECISIONS.md H3, D33).

trace_audit.py re-reads each sampled request and redoes the pipeline's
arithmetic with independent code. This script adds the checks the packet
left for the auditor (docs/reviews/h3-audit/README.md), using evidence that
does not come from the pipeline:

- the City's own fields on each record: REPORTED_DATE against the open date,
  ZipCode and cd_name against the areas the pipeline assigned;
- the record's street address, geocoded by the Census Bureau, against the
  record's point;
- how many requests share the record's exact close time (a bulk closure);
- the business days counted a third way (whole weeks, not day by day);
- for each marked near-duplicate, the earlier request it points to;
- for every sampled request, the published ZIP-code rows it counts in,
  recomputed from a fresh fetch of its request type with independent code
  (recompute_golden.py's projection, point-in-polygon and Kaplan-Meier).

It writes the worksheet with `ev_*` columns and a second file comparing each
recomputed row with the published one. It answers nothing: the auditor reads
the evidence and fills in the check columns.

Only read-only queries are made. No contact or free-text field is requested,
and addresses are used for the geocoder but not written out.

Usage (from the repository root):
  python pipelines/311/tests/independent/audit_evidence.py <pretrace.csv> <holidays.csv> \
      <published 311 dir> <out evidence.csv> <out rows.csv> [<time the run fetched, ISO with offset>]
"""

import csv
import datetime as dt
import io
import json
import math
import os
import re
import sys
import time
import urllib.parse
import urllib.request
import uuid
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import recompute_golden as rg  # noqa: E402
import trace_audit as ta       # noqa: E402

GEOCODER = "https://geocoding.geo.census.gov/geocoder/locations/addressbatch"
EXTRA = ["INCIDENT_NUMBER", "REPORTED_DATE", "Closed_Date", "last_edited_date", "Location_Address",
         "ZipCode", "cd_name", "created_date"]
TYPE_FIELDS = ["OBJECTID", "INCIDENT_NUMBER", "REQUEST_STATUS", "created_date", "Closed_Date",
               "SYSREVSTATUS", "last_edited_date"]
PAGE = 3000


def census_geocode(rows):
    """rows: (id, street, city, state, zip). Returns id -> (lon, lat, match type)."""
    buf = io.StringIO()
    csv.writer(buf, lineterminator="\n").writerows(rows)
    boundary = uuid.uuid4().hex
    parts = [f'--{boundary}\r\nContent-Disposition: form-data; name="benchmark"\r\n\r\nPublic_AR_Current\r\n',
             f'--{boundary}\r\nContent-Disposition: form-data; name="addressFile"; filename="a.csv"\r\n'
             f'Content-Type: text/csv\r\n\r\n{buf.getvalue()}\r\n', f'--{boundary}--\r\n']
    req = urllib.request.Request(GEOCODER, data="".join(parts).encode("utf-8"), headers={
        "Content-Type": f"multipart/form-data; boundary={boundary}", "User-Agent": ta.UA})
    with urllib.request.urlopen(req, timeout=600) as resp:
        text = resp.read().decode("utf-8", "replace")
    out = {}
    for r in csv.reader(io.StringIO(text)):
        if len(r) >= 6 and r[2] == "Match":
            lon, lat = (float(v) for v in r[5].split(","))
            out[r[0]] = (lon, lat, r[3])
    return out


def count_where(where):
    """Number of records matching `where` (ta.query returns features only)."""
    data = urllib.parse.urlencode(dict(where=where, returnCountOnly="true", f="json")).encode()
    req = urllib.request.Request(ta.LAYER + "/query", data=data, headers={"User-Agent": ta.UA})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                return json.loads(resp.read().decode("utf-8"))["count"]
        except Exception:
            if attempt == 4:
                raise
            time.sleep(2 ** attempt)


def split_address(a, zip_code):
    """Street, city, state and ZIP for the geocoder, from a Location_Address
    like '7737 Reese Rd, Memphis, TN, 38133, USA' or '7737 REESE RD'. None
    when it is not a street address (an intersection or a mile marker)."""
    street = (a or "").split(",")[0].strip()
    if not re.match(r"^[1-9]\d*\s+\S", street):   # "0 MICHIGAN" is a street, not an address
        return None
    return street, "Memphis", "TN", (zip_code or "").strip()[:5]


def weekdays_between(start, end, holidays):
    """Business days d with start < d <= end, by whole weeks rather than a
    day-by-day loop (a different method from rg.business_days)."""
    if end <= start:
        return 0
    first = start + dt.timedelta(days=1)
    days = (end - first).days + 1
    weeks, rest = divmod(days, 7)
    n = weeks * 5 + sum((first.weekday() + i) % 7 < 5 for i in range(rest))
    return n - sum(1 for h in holidays if first <= h <= end and h.weekday() < 5)


def fetch_type(request_type):
    out, after = [], 0
    quoted = request_type.replace("'", "''")
    while True:
        feats = ta.query(dict(where=f"REQUEST_TYPE = '{quoted}' AND OBJECTID > {after}",
                              outFields=",".join(TYPE_FIELDS), orderByFields="OBJECTID ASC",
                              resultRecordCount=PAGE, outSR=4326, returnGeometry="true"))
        if not feats:
            return out
        out += feats
        after = feats[-1]["attributes"]["OBJECTID"]


def build_records(feats, through, holidays, status_state, areas):
    """One request type's records, with the specs' exclusions, close-date
    problems and geography (the same rules as rg.main, on live records)."""
    recs = []
    for f in feats:
        a, g = f["attributes"], f.get("geometry") or {}
        opened = ta.ts(a["created_date"])
        open_date = rg.chicago_date(opened)
        state = status_state.get(a["REQUEST_STATUS"] or "", "unmapped")
        closed_ts = ta.ts(a["Closed_Date"])
        close_raw = rg.chicago_date(closed_ts) if closed_ts else None
        problem = None
        if state == "closed":
            if close_raw is None:
                problem = "missing"
            elif close_raw < rg.MIGRATION or close_raw < open_date or close_raw > through + dt.timedelta(days=1):
                problem = "bad"
        closed = state == "closed" and problem is None
        excl = None
        if open_date < rg.MIGRATION:
            excl = "pre_migration"
        elif open_date > through:
            excl = "partial_day"
        elif a["SYSREVSTATUS"] == "DUPLICATE":
            excl = "city_duplicate"
        elif state in ("unknown", "unmapped"):
            excl = "unknown_status"
        lon, lat = g.get("x"), g.get("y")   # a few records carry "NaN"
        located = (isinstance(lon, (int, float)) and isinstance(lat, (int, float))
                   and rg.BBOX[0] <= lon <= rg.BBOX[2] and rg.BBOX[1] <= lat <= rg.BBOX[3])
        r = dict(k=a["OBJECTID"], sr_id=a["INCIDENT_NUMBER"], opened=opened, open_date=open_date,
                 close_date=close_raw if closed else None, closed=closed, problem=problem, excl=excl,
                 located=located, edited=ta.ts(a["last_edited_date"]), xy=None, zcta=None, in_city=False,
                 bd_close=rg.business_days(open_date, close_raw, holidays) if closed else None,
                 age=rg.business_days(open_date, through, holidays), dup=False)
        if located:
            r["xy"] = rg.project(lon, lat)
            r["in_city"] = rg.assign(areas["citywide"], *r["xy"]) is not None
            r["zcta"] = rg.assign(areas["zcta"], *r["xy"])
        recs.append(r)
    # D6: a near-duplicate has an earlier primary within 50 m and 7 days.
    cell = lambda xy: (int(xy[0] // 50), int(xy[1] // 50))
    primaries = defaultdict(list)
    for r in sorted((r for r in recs if r["excl"] is None and r["located"]), key=lambda r: (r["opened"], r["k"])):
        cx, cy = cell(r["xy"])
        for gx in (cx - 1, cx, cx + 1):
            for gy in (cy - 1, cy, cy + 1):
                for p in primaries.get((gx, gy), ()):
                    if (r["opened"] - p["opened"]).total_seconds() <= 7 * 86400 and math.dist(r["xy"], p["xy"]) <= 50:
                        r["dup"] = True
                        break
                if r["dup"]:
                    break
            if r["dup"]:
                break
        if not r["dup"]:
            primaries[(cx, cy)].append(r)
    return recs


def recompute_rows(recs, zctas, through):
    """The primary ZIP-code rows of the three audited metrics, for `zctas`."""
    base = [r for r in recs if r["excl"] is None and not r["dup"] and r["in_city"]]
    pool = [r for r in recs if r["excl"] is None and r["in_city"] and r["located"]]
    grid = defaultdict(list)
    for o in pool:
        grid[(int(o["xy"][0] // 50), int(o["xy"][1] // 50))].append(o)

    def rereported(r):
        cx, cy = int(r["xy"][0] // 50), int(r["xy"][1] // 50)
        for gx in (cx - 1, cx, cx + 1):
            for gy in (cy - 1, cy, cy + 1):
                for o in grid.get((gx, gy), ()):
                    if 0 < (o["open_date"] - r["close_date"]).days <= 30 and math.dist(r["xy"], o["xy"]) <= 50:
                        return True
        return False

    out = {}
    for days in rg.WINDOWS.values():
        start = through - dt.timedelta(days=days - 1)
        for z in zctas:
            mine = [r for r in base if r["zcta"] == z]
            opened = [r for r in mine if start <= r["open_date"] <= through]
            timed = [r for r in opened if r["problem"] is None]
            out[("median_business_days_to_close", z, start)] = rg.km_median(
                [r["bd_close"] if r["closed"] else r["age"] for r in timed], [r["closed"] for r in timed])
            out[("requests_per_1000", z, start)] = dict(n=len(opened))
            closed = [r for r in mine if r["located"] and r["closed"] and start <= r["close_date"] <= through
                      and r["close_date"] <= through - dt.timedelta(days=30)]
            out[("reopen_rate", z, start)] = rg.proportion(sum(rereported(r) for r in closed), len(closed))
    return out


def same(a, b):
    if a is None or b is None:
        return a is None and b is None
    if math.isinf(a) or math.isinf(b):
        return a == b
    return abs(a - b) <= 1e-9 * max(1.0, abs(b))


def main(sheet_path, holidays_path, published, out_path, rows_path, fetched_at=None):
    as_of = dt.date.fromisoformat(re.search(r"(\d{4}-\d{2}-\d{2})", os.path.basename(sheet_path)).group(1))
    through = as_of - dt.timedelta(days=1)
    holidays = {dt.date.fromisoformat(r["date"]) for r in rg.read_csv(holidays_path)}
    status_state = {r["status"]: r["state"]
                    for r in rg.read_csv(os.path.join(rg.REPO, "pipelines", "311", "config", "status_map.csv"))}
    areas = {g: rg.load_areas(g) for g in ("citywide", "zcta", "council_district")}
    sheet = rg.read_csv(sheet_path)
    # When the run read the source: records edited later can differ from it.
    run_time = (dt.datetime.fromisoformat(fetched_at) if fetched_at else dt.datetime.fromtimestamp(
        os.path.getmtime(os.path.join(published, "metrics_311_by_zcta.csv")), dt.timezone.utc))

    # ---- the City's own fields, and the address for the geocoder ----
    ids = [r["sr_id"] for r in sheet] + [r["duplicate_of"] for r in sheet if r["duplicate_of"]]
    src = {}
    for k in range(0, len(ids), 50):
        where = "INCIDENT_NUMBER IN (" + ",".join("'" + i + "'" for i in ids[k:k + 50]) + ")"
        for f in ta.query(dict(where=where, outFields=",".join(EXTRA), outSR=4326, returnGeometry="true")):
            src[f["attributes"]["INCIDENT_NUMBER"]] = f
    to_geocode = []
    for r in sheet:
        sa = src[r["sr_id"]]["attributes"] if r["sr_id"] in src else None
        parts = split_address(sa["Location_Address"], sa["ZipCode"]) if sa else None
        if parts:
            to_geocode.append((r["sr_id"],) + parts)
    geocoded = census_geocode(to_geocode) if to_geocode else {}
    print(f"geocoder: {len(geocoded)} of {len(to_geocode)} street addresses matched "
          f"({len(sheet) - len(to_geocode)} records have no street address)")

    for r in sheet:
        f = src.get(r["sr_id"])
        if f is None:
            r["ev_summary"] = "not in the source"
            continue
        a, g = f["attributes"], f.get("geometry") or {}
        opened = ta.ts(a["created_date"])
        open_date = rg.chicago_date(opened)
        reported = ta.ts(a["REPORTED_DATE"])
        r["ev_reported_date"] = "" if reported is None else reported.date().isoformat()
        r["ev_reported_matches_open_date"] = "" if reported is None else (
            "yes" if reported.date() == open_date else "no")
        closed_ts = ta.ts(a["Closed_Date"])
        r["ev_closed_local"] = "" if closed_ts is None else ta.local_str(closed_ts)
        if closed_ts is not None and r["close_date"]:
            time.sleep(0.2)
            r["ev_requests_closed_same_second"] = count_where(f"Closed_Date = {ta.sql_ts(closed_ts)}")
        if r["close_date"]:
            close_date = dt.date.fromisoformat(r["close_date"])
            r["ev_business_days_by_weeks"] = weekdays_between(open_date, close_date, holidays)
            r["ev_business_days_match"] = "yes" if str(r["ev_business_days_by_weeks"]) == r[
                "business_days_to_close"] else "no"
        r["ev_age_by_weeks"] = weekdays_between(open_date, through, holidays)
        r["ev_age_matches"] = "yes" if str(r["ev_age_by_weeks"]) == r["age_business_days"] else "no"
        r["ev_city_zip"] = (a["ZipCode"] or "").strip()[:5]
        r["ev_city_zip_matches"] = "yes" if r["ev_city_zip"] == r["zcta"] else "no"
        r["ev_city_council_district"] = "" if a["cd_name"] is None else str(a["cd_name"])
        r["ev_city_council_matches"] = "yes" if r["ev_city_council_district"] == r["council_district"] else "no"
        if "x" in g:
            x, y = rg.project(g["x"], g["y"])
            for geo, tol in (("zcta", 100), ("council_district", 100)):
                near = [ar.geo_id for ar in areas[geo] if ar.within(x, y, tol)]
                r[f"ev_within_100m_of_{geo}_boundary"] = "yes" if near else "no"
            if r["sr_id"] in geocoded:
                lon, lat, kind = geocoded[r["sr_id"]]
                r["ev_geocode_match"] = kind
                gxy = rg.project(lon, lat)
                r["ev_geocode_distance_m"] = round(math.dist((x, y), gxy))
                # Would the geocoded address land in the same areas as the point?
                r["ev_geocode_same_areas"] = "yes" if (
                    (rg.assign(areas["zcta"], *gxy) or "") == r["zcta"] and
                    (rg.assign(areas["council_district"], *gxy) or "") == r["council_district"]) else "no"
            else:
                r["ev_geocode_match"] = ("no match" if split_address(a["Location_Address"], a["ZipCode"])
                                         else "no street address")
            d = src.get(r["duplicate_of"]) if r["duplicate_of"] else None
            if d is not None:
                dg = d.get("geometry") or {}
                lag = (opened - ta.ts(d["attributes"]["created_date"])).total_seconds() / 86400
                r["ev_duplicate_lag_days"] = round(lag, 2)
                r["ev_duplicate_distance_m"] = round(math.dist((x, y), rg.project(dg["x"], dg["y"])), 1)
                r["ev_duplicate_same_address"] = "yes" if (d["attributes"]["Location_Address"] or "").strip().lower() == (
                    a["Location_Address"] or "").strip().lower() else "no"

    # ---- published rows, recomputed from a fresh fetch of each request type ----
    published_rows = {}
    for row in rg.read_csv(os.path.join(published, "metrics_311_by_zcta.csv")):
        if row["variant"] == "primary":
            published_rows[(row["metric"], row["subgroup"], row["geo_id"], row["window_start"])] = row
    num = lambda s: None if s in ("", "NA") else float(s)
    by_type = defaultdict(set)
    for r in sheet:
        if r["zcta"]:
            by_type[r["request_type"]].add(r["zcta"])
    compared, verdict = [], {}
    for t in sorted(by_type):
        feats = fetch_type(t)
        recs = build_records(feats, through, holidays, status_state, areas)
        late = sum(1 for r in recs if r["edited"] and r["edited"] > run_time)
        mine = recompute_rows(recs, by_type[t], through)
        print(f"{t}: {len(feats)} records fetched, {late} edited after the run")
        for (metric, z, start), got in sorted(mine.items()):
            pub = published_rows.get((metric, t, z, start.isoformat()))
            if pub is None:
                agree, why = got["n"] == 0, "no published row" + ("" if got["n"] else " (and none expected: n = 0)")
            else:
                diffs = [] if got["n"] == int(pub["n"]) else ["n"]
                if metric != "requests_per_1000":
                    diffs += [f for f in ("value", "ci_low", "ci_high") if not same(got[f], num(pub[f]))]
                    if got["suppressed"] != (pub["suppressed"] == "TRUE"):
                        diffs.append("suppressed")
                agree, why = not diffs, ", ".join(diffs)
            compared.append(dict(request_type=t, zcta=z, metric=metric, window_start=start.isoformat(),
                                 published_n="" if pub is None else pub["n"], recomputed_n=got["n"],
                                 published_value="" if pub is None else pub["value"],
                                 recomputed_value="" if got.get("value") is None else got["value"],
                                 agree="yes" if agree else "no", differs_in=why,
                                 records_edited_after_run=late))
            verdict.setdefault((t, z), []).append(agree)
    for r in sheet:
        v = verdict.get((r["request_type"], r["zcta"]))
        if v:
            r["ev_published_rows_recomputed"] = len(v)
            r["ev_published_rows_agree"] = sum(v)

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
    bad = sum(c["agree"] == "no" for c in compared)
    print(f"published rows recomputed: {len(compared)}; agree: {len(compared) - bad}; differ: {bad}")
    print("wrote", out_path, "and", rows_path)


if __name__ == "__main__":
    main(*sys.argv[1:7])
