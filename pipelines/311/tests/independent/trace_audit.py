"""Automated pre-trace of a 311 audit worksheet (DECISIONS.md H3).

The manual audit (plan 5.6) traces at least 100 random records by hand from
the source to the published metric. This script does the mechanical part
first, so the person doing the audit can focus on judgment:

- re-fetches each sampled request from the City's 311 layer (read-only
  query, no contact or free-text fields);
- recomputes the local open date, close date, business days to close and
  age, with the independent code in recompute_golden.py;
- re-assigns ZIP code (ZCTA) and council district with its own
  point-in-polygon;
- asks the layer for earlier requests of the same type within 60 m and 7
  days, to test the near-duplicate call (D6).

It writes the worksheet back with `auto_*` columns. The audit columns
(1_found_in_source ... 5_geography_correct, auditor, notes) stay blank: they
are for a person, and the publish gate only counts a sheet whose columns a
person has filled in (D23).

Usage (from the repository root):
  Rscript pipelines/311/tests/independent/export_holidays.R <holidays.csv>
  python pipelines/311/tests/independent/trace_audit.py <audit_sample_YYYY-MM-DD.csv> <holidays.csv> <out.csv>
"""

import csv
import datetime as dt
import json
import math
import os
import re
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import recompute_golden as rg  # noqa: E402

LAYER = "https://311.memphistn.gov/server/rest/services/311/311_Request_Map_PROD/FeatureServer/0"
FIELDS = ["OBJECTID", "INCIDENT_NUMBER", "REQUEST_TYPE", "REQUEST_STATUS", "created_date",
          "Closed_Date", "SYSREVSTATUS", "cd_name", "ZipCode"]
UA = "memphis-service-equity (https://github.com/jpbranson/mem-service-equity)"


def query(params):
    params = dict(params, f="json")
    req = urllib.request.Request(LAYER + "/query", data=urllib.parse.urlencode(params).encode(),
                                 headers={"User-Agent": UA})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                body = json.loads(resp.read().decode("utf-8"))
            if "error" in body:
                raise RuntimeError(body["error"])
            return body.get("features", [])
        except Exception:  # retry dropped connections and server errors
            if attempt == 4:
                raise
            time.sleep(2 ** attempt)


def ts(ms):
    return None if ms is None else dt.datetime.fromtimestamp(ms / 1000, dt.timezone.utc)


def _is_cdt(t):
    """Central daylight time in force (same rule as rg.chicago_date)."""
    y = t.year
    start = dt.datetime.combine(rg.nth_sunday(y, 3, 2), dt.time(8), dt.timezone.utc)
    end = dt.datetime.combine(rg.nth_sunday(y, 11, 1), dt.time(7), dt.timezone.utc)
    return start <= t < end


def local_str(t):
    local = t - dt.timedelta(hours=5 if _is_cdt(t) else 6)
    return local.strftime("%Y-%m-%d %H:%M")


def sql_ts(t):
    return "TIMESTAMP '" + t.strftime("%Y-%m-%d %H:%M:%S") + "'"


def main(sheet_path, holidays_path, out_path):
    as_of = dt.date.fromisoformat(re.search(r"(\d{4}-\d{2}-\d{2})", os.path.basename(sheet_path)).group(1))
    through = as_of - dt.timedelta(days=1)
    holidays = {dt.date.fromisoformat(r["date"]) for r in rg.read_csv(holidays_path)}
    status_state = {r["status"]: r["state"]
                    for r in rg.read_csv(os.path.join(rg.REPO, "pipelines", "311", "config", "status_map.csv"))}
    areas = {g: rg.load_areas(g) for g in ("citywide", "zcta", "council_district")}
    sheet = rg.read_csv(sheet_path)

    ids = [r["sr_id"] for r in sheet]
    src = {}
    for k in range(0, len(ids), 50):
        chunk = ids[k:k + 50]
        where = "INCIDENT_NUMBER IN (" + ",".join("'" + i.replace("'", "''") + "'" for i in chunk) + ")"
        for f in query(dict(where=where, outFields=",".join(FIELDS), outSR=4326, returnGeometry="true")):
            src[f["attributes"]["INCIDENT_NUMBER"]] = f

    out = []
    for r in sheet:
        f = src.get(r["sr_id"])
        auto = dict(auto_found_in_source="no")
        problems = []
        if f is None:
            problems.append("not found in the source now")
        else:
            a, g = f["attributes"], f.get("geometry") or {}
            opened = ts(a["created_date"])
            open_date = rg.chicago_date(opened)
            state = status_state.get(a["REQUEST_STATUS"] or "", "unmapped")
            closed_raw = ts(a["Closed_Date"])
            close_date = rg.chicago_date(closed_raw) if (state == "closed" and closed_raw) else None
            if close_date and (close_date < rg.MIGRATION or close_date < open_date
                               or close_date > through + dt.timedelta(days=1)):
                close_date = None      # a close problem; the pipeline leaves these out too
            auto.update(
                auto_found_in_source="yes",
                auto_type_matches="yes" if a["REQUEST_TYPE"] == r["request_type"] else "no",
                auto_status_now=a["REQUEST_STATUS"] or "",
                auto_opened_local=local_str(opened),
                auto_opened_matches="yes" if local_str(opened) == r["opened_local"] else "no",
                auto_close_date_now="" if close_date is None else close_date.isoformat(),
                auto_close_matches="yes" if (close_date.isoformat() if close_date else "") == r["close_date"]
                else "no",
                auto_business_days=("" if close_date is None
                                    else rg.business_days(open_date, close_date, holidays)),
                auto_age_business_days=rg.business_days(open_date, through, holidays))
            auto["auto_business_days_match"] = "yes" if str(auto["auto_business_days"]) == r[
                "business_days_to_close"] else "no"
            auto["auto_age_matches"] = "yes" if str(auto["auto_age_business_days"]) == r["age_business_days"] else "no"
            if auto["auto_type_matches"] == "no":
                problems.append("request type differs")
            if auto["auto_opened_matches"] == "no":
                problems.append("open time differs")
            if a["REQUEST_STATUS"] != r["status"]:
                problems.append(f"status changed since the run ({r['status']} -> {a['REQUEST_STATUS']})")
            if auto["auto_close_matches"] == "no":
                problems.append("close date differs (check whether it changed after the run)")
            elif auto["auto_business_days_match"] == "no" or auto["auto_age_matches"] == "no":
                problems.append("business days differ")
            if "x" in g:
                x, y = rg.project(g["x"], g["y"])
                auto["auto_lon"], auto["auto_lat"] = round(g["x"], 6), round(g["y"], 6)
                auto["auto_in_city"] = "yes" if rg.assign(areas["citywide"], x, y) else "no"
                auto["auto_zcta"] = rg.assign(areas["zcta"], x, y) or ""
                auto["auto_council_district"] = rg.assign(areas["council_district"], x, y) or ""
                auto["auto_geography_matches"] = "yes" if (auto["auto_zcta"] == r["zcta"] and
                                                           auto["auto_council_district"] == r["council_district"]) else "no"
                if auto["auto_in_city"] == "no":
                    problems.append("point is outside the city")
                if auto["auto_geography_matches"] == "no":
                    problems.append("ZIP or council district differs")
                # D6: earlier requests of the same type within 50 m and 7 days.
                time.sleep(0.3)
                t0 = opened - dt.timedelta(days=7)
                where = (f"REQUEST_TYPE = '{a['REQUEST_TYPE'].replace(chr(39), chr(39) * 2)}' AND "
                         f"created_date >= {sql_ts(t0)} AND created_date <= {sql_ts(opened)}")
                geom = json.dumps({"x": g["x"], "y": g["y"], "spatialReference": {"wkid": 4326}})
                near = query(dict(where=where, geometry=geom, geometryType="esriGeometryPoint", inSR=4326,
                                  spatialRel="esriSpatialRelIntersects", distance=60, units="esriSRUnit_Meter",
                                  outFields="INCIDENT_NUMBER,created_date,SYSREVSTATUS,OBJECTID", outSR=4326,
                                  returnGeometry="true"))
                earlier = []
                for n in near:
                    na = n["attributes"]
                    if na["INCIDENT_NUMBER"] == r["sr_id"] or (na.get("SYSREVSTATUS") == "DUPLICATE"):
                        continue
                    nt = ts(na["created_date"])
                    if nt > opened or (nt == opened and na["OBJECTID"] >= a["OBJECTID"]):
                        continue
                    ng = n.get("geometry") or {}
                    if "x" not in ng or math.dist((x, y), rg.project(ng["x"], ng["y"])) > 50:
                        continue
                    earlier.append(na["INCIDENT_NUMBER"])
                auto["auto_earlier_same_type_within_50m_7d"] = " ".join(earlier)
                dup = r["duplicate_of"]
                if dup and dup not in earlier:
                    problems.append(f"marked duplicate of {dup}, which is not an earlier request within 50 m/7 days")
                if not dup and earlier:
                    problems.append("earlier same-type requests nearby but not marked a duplicate "
                                    "(fine if those were duplicates or excluded themselves)")
            else:
                problems.append("no location in the source")
        auto["auto_summary"] = "ok" if not problems else "; ".join(problems)
        out.append({**r, **auto})

    cols = list(sheet[0].keys())
    human = [c for c in cols if re.match(r"^\d+_", c) or c in ("auditor", "notes")]
    base = [c for c in cols if c not in human]
    auto_cols = []
    for row in out:
        for c in row:
            if c.startswith("auto_") and c not in auto_cols:
                auto_cols.append(c)
    with open(out_path, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=base + auto_cols + human, restval="")
        w.writeheader()
        w.writerows(out)
    ok = sum(r["auto_summary"] == "ok" for r in out)
    print(f"{len(out)} records traced; {ok} with nothing to flag; {len(out) - ok} flagged for a closer look")
    print("wrote", out_path)


if __name__ == "__main__":
    main(*sys.argv[1:4])
