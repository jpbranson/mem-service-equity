"""Independent recomputation of the 311 golden file (DECISIONS.md H20).

Plan 5.3 asks for golden outputs checked by hand. This script is the
mechanical half of that check: a second implementation, written from the
specs (specs/311/*.md) and DECISIONS.md (D5 business days, D6 near
duplicates, D8 boundary rule, D9 censoring), that shares no code with the R
pipeline. It uses only the Python standard library: its own US Central time
conversion, its own Lambert conformal conic projection for EPSG:32136, its own
point-in-polygon, Kaplan-Meier and Wilson intervals.

Inputs shared with the R pipeline: the raw golden records, the config files
(status map, request types and targets, reference neighborhoods), the boundary
files, and the holiday dates (the calendar is checked separately, H13).

Usage (from the repository root):
  Rscript pipelines/311/tests/independent/export_golden.R <dir>
  python pipelines/311/tests/independent/recompute_golden.py <dir> [--out <dir>]

Writes comparison.csv (every golden row beside the recomputed value) and
prints a summary. Exit status 1 if any row disagrees.
"""

import csv
import datetime as dt
import json
import math
import os
import sys
from collections import defaultdict

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
AS_OF = dt.date(2025, 7, 1)          # build_golden.R
THROUGH = AS_OF - dt.timedelta(days=1)
MIGRATION = dt.date(2023, 10, 16)
WINDOWS = {"90d": 90, "12m": 365}
BBOX = (-90.32, 34.99, -89.63, 35.42)  # generous Shelby County box (bad-coordinate filter)
MIN_N_PROPORTION, MIN_N_MEDIAN = 30, 20
Z = 1.959963984540054
GEO_LEVELS = ["citywide", "zcta", "council_district", "super_district", "reference_neighborhood"]
REOPEN_VARIANTS = [("primary", 30, 50), ("window_14d", 14, 50), ("window_60d", 60, 50),
                   ("radius_25m", 30, 25), ("radius_100m", 30, 100)]


# ---- time: UTC instant -> America/Chicago calendar date ----------------------

def nth_sunday(year, month, n):
    d = dt.date(year, month, 1)
    d += dt.timedelta(days=(6 - d.weekday()) % 7)
    return d + dt.timedelta(weeks=n - 1)


def chicago_date(ts):
    """US Central: CDT (UTC-5) from 2nd Sunday of March 08:00 UTC to 1st
    Sunday of November 07:00 UTC, else CST (UTC-6). Rules in force since 2007."""
    y = ts.year
    start = dt.datetime.combine(nth_sunday(y, 3, 2), dt.time(8), dt.timezone.utc)
    end = dt.datetime.combine(nth_sunday(y, 11, 1), dt.time(7), dt.timezone.utc)
    offset = -5 if start <= ts < end else -6
    return (ts + dt.timedelta(hours=offset)).date()


def parse_ts(s):
    if not s:
        return None
    return dt.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)


# ---- projection: EPSG:32136 (NAD83 / Tennessee), Lambert conformal conic 2SP --

A, F = 6378137.0, 1 / 298.257222101
E = math.sqrt(2 * F - F * F)
PHI1, PHI2, PHI0 = math.radians(36 + 25 / 60), math.radians(35.25), math.radians(34 + 20 / 60)
LAM0, FE, FN = math.radians(-86.0), 600000.0, 0.0


def _m(phi):
    return math.cos(phi) / math.sqrt(1 - (E * math.sin(phi)) ** 2)


def _t(phi):
    es = E * math.sin(phi)
    return math.tan(math.pi / 4 - phi / 2) / ((1 - es) / (1 + es)) ** (E / 2)


_N = (math.log(_m(PHI1)) - math.log(_m(PHI2))) / (math.log(_t(PHI1)) - math.log(_t(PHI2)))
_F = _m(PHI1) / (_N * _t(PHI1) ** _N)
_RHO0 = A * _F * _t(PHI0) ** _N


def project(lon, lat):
    rho = A * _F * _t(math.radians(lat)) ** _N
    theta = _N * (math.radians(lon) - LAM0)
    return FE + rho * math.sin(theta), FN + _RHO0 - rho * math.cos(theta)


# ---- polygons: point in polygon and distance to boundary, grid-indexed ------

class Area:
    CELL = 100.0

    def __init__(self, geo_id, rings):
        self.geo_id = geo_id
        self.segs = []
        for ring in rings:
            pts = [project(x, y) for x, y in ring]
            self.segs += [(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
        xs = [p[0] for s in self.segs for p in s]
        ys = [p[1] for s in self.segs for p in s]
        self.bbox = (min(xs), min(ys), max(xs), max(ys))
        self.rows = defaultdict(list)   # y-strip -> segments spanning it (ray casting)
        self.grid = defaultdict(list)   # cell -> segments touching it (distance)
        for k, ((x1, y1), (x2, y2)) in enumerate(self.segs):
            for r in range(int(min(y1, y2) // self.CELL), int(max(y1, y2) // self.CELL) + 1):
                self.rows[r].append(k)
            for cx in range(int(min(x1, x2) // self.CELL), int(max(x1, x2) // self.CELL) + 1):
                for cy in range(int(min(y1, y2) // self.CELL), int(max(y1, y2) // self.CELL) + 1):
                    self.grid[(cx, cy)].append(k)

    def contains(self, x, y):
        inside = False
        for k in self.rows.get(int(y // self.CELL), ()):
            (x1, y1), (x2, y2) = self.segs[k]
            if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                inside = not inside
        return inside

    def within(self, x, y, tol):
        cx, cy = int(x // self.CELL), int(y // self.CELL)
        for gx in (cx - 1, cx, cx + 1):
            for gy in (cy - 1, cy, cy + 1):
                for k in self.grid.get((gx, gy), ()):
                    if seg_dist(x, y, *self.segs[k]) <= tol:
                        return True
        return False


def seg_dist(px, py, a, b):
    (x1, y1), (x2, y2) = a, b
    dx, dy = x2 - x1, y2 - y1
    L = dx * dx + dy * dy
    u = 0.0 if L == 0 else max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / L))
    return math.hypot(px - (x1 + u * dx), py - (y1 + u * dy))


def load_areas(geo_type):
    with open(os.path.join(REPO, "geography", "boundaries", "registry.csv"), encoding="utf-8") as fh:
        row = next(r for r in csv.DictReader(fh) if r["geo_type"] == geo_type)
    with open(os.path.join(REPO, "geography", "boundaries", row["file"]), encoding="utf-8") as fh:
        gj = json.load(fh)
    areas = []
    for feat in gj["features"]:
        g = feat["geometry"]
        polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        rings = [ring for poly in polys for ring in poly]   # holes flip parity in ray casting
        areas.append(Area(str(feat["properties"][row["id_field"]]), rings))
    return areas


def assign(areas, x, y, tol=1.0):
    """D8: inside one area and not within 1 m of another -> that area; within
    1 m of several (or of one without being inside) -> the lowest geo_id."""
    inside, near = [], []
    for a in areas:
        b = a.bbox
        if not (b[0] - tol <= x <= b[2] + tol and b[1] - tol <= y <= b[3] + tol):
            continue
        i = a.contains(x, y)
        if i:
            inside.append(a.geo_id)
        if i or a.within(x, y, tol):
            near.append(a.geo_id)
    cands = near if (len(near) > 1 or not inside) else inside
    return min(cands) if cands else None


# ---- business days (D5) --------------------------------------------------------

def business_days(start, end, holidays):
    """Business days d with start < d <= end (0 when end <= start)."""
    if start is None or end is None or end <= start:
        return 0 if (start is not None and end is not None) else None
    n, d = 0, start + dt.timedelta(days=1)
    while d <= end:
        if d.weekday() < 5 and d not in holidays:
            n += 1
        d += dt.timedelta(days=1)
    return n


# ---- statistics ------------------------------------------------------------------

def wilson(x, n):
    p = x / n
    den = 1 + Z * Z / n
    mid = (p + Z * Z / (2 * n)) / den
    half = Z * math.sqrt(p * (1 - p) / n + Z * Z / (4 * n * n)) / den
    return p, mid - half, mid + half


def proportion(x, n):
    if n < MIN_N_PROPORTION:
        return dict(value=None, ci_low=None, ci_high=None, n=n, suppressed=True)
    v, lo, hi = wilson(x, n)
    return dict(value=v, ci_low=lo, ci_high=hi, n=n, suppressed=False)


def km_median(times, events):
    """Kaplan-Meier median with a log-log interval (Greenwood variance). When
    the curve sits exactly at 0.5 the midpoint to the next event time is used
    (survival::quantile convention)."""
    n = len(times)
    if n < MIN_N_MEDIAN:
        return dict(value=None, ci_low=None, ci_high=None, n=n, suppressed=True)
    by_t = defaultdict(lambda: [0, 0])
    for t, e in zip(times, events):
        by_t[t][0 if e else 1] += 1
    at_risk, s, var = n, 1.0, 0.0
    ev_t, surv, lo_b, hi_b = [], [], [], []
    for t in sorted(by_t):
        d, c = by_t[t]
        if d:
            s *= 1 - d / at_risk
            var = var + d / (at_risk * (at_risk - d)) if at_risk > d else math.inf
            if 0 < s < 1 and math.isfinite(var):
                th, se = math.log(-math.log(s)), math.sqrt(var) / abs(math.log(s))
                lo, hi = math.exp(-math.exp(th + Z * se)), math.exp(-math.exp(th - Z * se))
            else:
                lo = hi = (0.0 if s == 0 else 1.0)
            ev_t.append(t); surv.append(s); lo_b.append(lo); hi_b.append(hi)
        at_risk -= d + c

    def q(curve):
        tol = math.sqrt(2.220446049250313e-16)
        for i, v in enumerate(curve):
            if v <= 0.5 + tol:
                if abs(v - 0.5) < tol and i + 1 < len(ev_t):
                    return (ev_t[i] + ev_t[i + 1]) / 2
                return float(ev_t[i])
        return None

    med = q(surv)
    if med is None:
        return dict(value=None, ci_low=None, ci_high=None, n=n, suppressed=True)
    hi = q(hi_b)
    return dict(value=med, ci_low=q(lo_b), ci_high=math.inf if hi is None else hi, n=n,
                suppressed=False)


# ---- pipeline, from the specs -----------------------------------------------------

def read_csv(path):
    with open(path, encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def main(export_dir, out_dir):
    cfg = os.path.join(REPO, "pipelines", "311", "config")
    status_state = {r["status"]: r["state"] for r in read_csv(os.path.join(cfg, "status_map.csv"))}
    targets = {r["request_type"]: (int(r["target_low_bd"]), int(r["target_high_bd"]))
               for r in read_csv(os.path.join(cfg, "request_types.csv")) if r["target_high_bd"]}
    ref_nb = {r["zip"]: r["neighborhood"]
              for r in read_csv(os.path.join(REPO, "geography", "reference_neighborhoods.csv"))}
    holidays = {dt.date.fromisoformat(r["date"]) for r in read_csv(os.path.join(export_dir, "holidays.csv"))}
    raw = read_csv(os.path.join(export_dir, "golden_raw.csv"))
    areas = {g: load_areas(g) for g in ["citywide", "zcta", "council_district", "super_district"]}

    recs = []
    for k, r in enumerate(raw):
        opened = parse_ts(r["created_date"])
        open_date = chicago_date(opened)
        status = r["REQUEST_STATUS"]
        state = status_state.get(status, "unmapped")
        closed_ts = parse_ts(r["Closed_Date"])
        close_raw = chicago_date(closed_ts) if closed_ts else None
        problem = None
        if state == "closed":
            if close_raw is None:
                problem = "missing_close_date"
            elif close_raw < MIGRATION:
                problem = "sentinel_close_date"
            elif close_raw < open_date:
                problem = "close_before_open"
            elif close_raw > THROUGH + dt.timedelta(days=1):
                problem = "close_in_future"
        closed = state == "closed" and problem is None
        close_date = close_raw if closed else None
        excl = None
        if not r["REQUEST_TYPE"]:
            excl = "missing_request_type"
        elif open_date < MIGRATION:
            excl = "pre_migration"
        elif open_date > THROUGH:
            excl = "partial_day"
        elif r["SYSREVSTATUS"] == "DUPLICATE":
            excl = "city_duplicate"
        elif state in ("unknown", "unmapped"):
            excl = "unknown_status"
        try:
            lon, lat = float(r["longitude"]), float(r["latitude"])
        except ValueError:
            lon = lat = None
        located = (lon is not None and BBOX[0] <= lon <= BBOX[2] and BBOX[1] <= lat <= BBOX[3])
        rec = dict(k=k, sr_id=r["INCIDENT_NUMBER"], type=r["REQUEST_TYPE"], opened=opened,
                   open_date=open_date, close_date=close_date, closed=closed, problem=problem,
                   excl=excl, located=located,
                   bd_close=business_days(open_date, close_date, holidays) if closed else None,
                   age=business_days(open_date, THROUGH, holidays))
        if located:
            x, y = project(lon, lat)
            rec["xy"] = (x, y)
            for g, a in areas.items():
                rec[g] = assign(a, x, y)
            rec["reference_neighborhood"] = ref_nb.get(rec["zcta"])
        else:
            rec["xy"] = None
            for g in GEO_LEVELS:
                rec[g] = None
        rec["in_city"] = rec["citywide"] is not None
        recs.append(rec)

    # D6 near-duplicates among included, located records, in time order.
    cand = sorted((r for r in recs if r["excl"] is None and r["located"]),
                  key=lambda r: (r["opened"], r["k"]))
    primaries = defaultdict(list)       # type -> earlier primaries, in time order
    for r in cand:
        r["dup_of"] = None
        for p in primaries[r["type"]]:
            lag = (r["opened"] - p["opened"]).total_seconds() / 86400
            if 0 <= lag <= 7 and math.dist(r["xy"], p["xy"]) <= 50:
                r["dup_of"] = p["sr_id"]
                break
        if r["dup_of"] is None:
            primaries[r["type"]].append(r)
    for r in recs:
        r.setdefault("dup_of", None)

    base = [r for r in recs if r["excl"] is None and r["dup_of"] is None and r["in_city"]]
    out, members = {}, {}

    def emit(metric, variant, window_start, groups, fun):
        for (ty, g, gid), rows in groups.items():
            key = (metric, variant, ty, g, gid, window_start.isoformat())
            out[key] = fun(rows)
            members[key] = rows

    def group(rows):
        gr = defaultdict(list)
        for r in rows:
            for g in GEO_LEVELS:
                if r[g] is not None:
                    gr[(r["type"], g, r[g])].append(r)
        return gr

    for w, days in WINDOWS.items():
        start = THROUGH - dt.timedelta(days=days - 1)
        inwin = [r for r in base if start <= r["open_date"] <= THROUGH and r["problem"] is None]
        emit("median_business_days_to_close", "primary", start, group(inwin),
             lambda rows: km_median([r["bd_close"] if r["closed"] else r["age"] for r in rows],
                                    [r["closed"] for r in rows]))
        for variant, idx in (("primary", 1), ("lower_bound", 0)):
            elig = [r for r in inwin if r["type"] in targets and r["age"] >= targets[r["type"]][idx]]
            emit("pct_within_target", variant, start, group(elig),
                 lambda rows, idx=idx: proportion(
                     sum(r["closed"] and r["bd_close"] <= targets[r["type"]][idx] for r in rows),
                     len(rows)))

    # Re-reports: a closed primary is re-reported when any included, located,
    # in-city request of the same type opens 1..N days after its close date
    # within R meters (duplicates count as re-reports).
    pool = [r for r in recs if r["excl"] is None and r["in_city"] and r["located"]]
    by_type = defaultdict(list)
    for r in pool:
        by_type[r["type"]].append(r)
    for r in pool:
        r["lag"] = {}
        if r["dup_of"] is None and r["closed"]:
            for m in (25, 50, 100):
                lags = [(o["open_date"] - r["close_date"]).days for o in by_type[r["type"]]
                        if 0 < (o["open_date"] - r["close_date"]).days <= 60
                        and math.dist(r["xy"], o["xy"]) <= m]
                r["lag"][m] = min(lags) if lags else None
    prim_pool = [r for r in pool if r["dup_of"] is None]
    for variant, vdays, meters in REOPEN_VARIANTS:
        for w, days in WINDOWS.items():
            start = THROUGH - dt.timedelta(days=days - 1)
            rows = [r for r in prim_pool if r["closed"] and start <= r["close_date"] <= THROUGH
                    and r["close_date"] <= THROUGH - dt.timedelta(days=vdays)]
            emit("reopen_rate", variant, start, group(rows),
                 lambda rs, vd=vdays, mm=meters: proportion(
                     sum(r["lag"][mm] is not None and r["lag"][mm] <= vd for r in rs), len(rs)))

    # ---- compare with the golden file ----
    gold = read_csv(os.path.join(REPO, "pipelines", "311", "tests", "golden", "golden_metrics.csv"))
    num = lambda s: None if s in ("", "NA") else float(s)
    rows_out, bad = [], 0
    seen = set()
    for g in gold:
        key = (g["metric"], g["variant"], g["subgroup"], g["geo_type"], g["geo_id"], g["window_start"])
        seen.add(key)
        mine = out.get(key)
        want = dict(value=num(g["value"]), ci_low=num(g["ci_low"]), ci_high=num(g["ci_high"]),
                    n=int(g["n"]), suppressed=g["suppressed"] == "TRUE")
        if mine is None:
            agree, why = False, "row missing in recomputation"
        else:
            def same(a, b):
                if a is None or b is None:
                    return a is None and b is None
                if math.isinf(a) or math.isinf(b):
                    return a == b
                return abs(a - b) <= 1e-9 * max(1.0, abs(b))
            diffs = [f for f in ("value", "ci_low", "ci_high") if not same(mine[f], want[f])]
            if mine["n"] != want["n"]:
                diffs.insert(0, "n")
            if mine["suppressed"] != want["suppressed"]:
                diffs.append("suppressed")
            agree, why = not diffs, ", ".join(diffs)
        bad += not agree
        rows_out.append(dict(zip(("metric", "variant", "subgroup", "geo_type", "geo_id", "window_start"), key),
                             golden_value=g["value"], golden_n=g["n"],
                             recomputed_value="" if mine is None or mine["value"] is None else mine["value"],
                             recomputed_n="" if mine is None else mine["n"],
                             agree=agree, differs_in=why))
    extra = [k for k in out if k not in seen]
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "comparison.csv")
    with open(path, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows_out[0]))
        w.writeheader()
        w.writerows(rows_out)
    write_worksheets(out, members, targets, out_dir)
    n_dup = sum(r["dup_of"] is not None for r in recs)
    print(f"records: {len(recs)}; included in-city primaries: {len(base)}; near-duplicates: {n_dup}")
    print(f"golden rows: {len(gold)}; agree: {len(gold) - bad}; disagree: {bad}; "
          f"recomputed rows not in golden: {len(extra)}")
    for k in extra[:10]:
        print("  extra:", k)
    print("wrote", path)
    return 1 if bad or extra else 0


def write_worksheets(out, members, targets, out_dir):
    """For the smallest published zcta row of each metric (primary variant),
    list every record behind it so a person can redo the arithmetic with a
    calendar (H20). Blank columns are for the reviewer."""
    for metric in ("median_business_days_to_close", "pct_within_target", "reopen_rate"):
        keys = [k for k in out if k[0] == metric and k[1] == "primary" and k[3] == "zcta"
                and not out[k]["suppressed"]]
        if not keys:
            continue
        key = min(keys, key=lambda k: (out[k]["n"], k))
        rows = sorted(members[key], key=lambda r: (r["open_date"], r["sr_id"]))
        path = os.path.join(out_dir, f"handcheck_{metric}.csv")
        with open(path, "w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh)
            res = out[key]
            w.writerow([f"# {metric} | {key[2]} | zcta {key[4]} | window from {key[5]} to {THROUGH} | "
                        f"value {res['value']} | CI {res['ci_low']} to {res['ci_high']} | n {res['n']}"])
            head = ["sr_id", "open_date_local", "close_date_local", "state_closed",
                    "business_days_to_close", "age_business_days_at_through"]
            if metric == "pct_within_target":
                head += ["target_bd", "on_time"]
            if metric == "reopen_rate":
                head += ["days_to_first_rereport_within_50m"]
            w.writerow(head + ["reviewer_agrees", "reviewer_notes"])
            for r in rows:
                line = [r["sr_id"], r["open_date"], r["close_date"] or "", r["closed"],
                        "" if r["bd_close"] is None else r["bd_close"], r["age"]]
                if metric == "pct_within_target":
                    t = targets[r["type"]][1]
                    line += [t, r["closed"] and r["bd_close"] <= t]
                if metric == "reopen_rate":
                    line += ["" if r["lag"][50] is None else r["lag"][50]]
                w.writerow(line + ["", ""])


if __name__ == "__main__":
    args = sys.argv[1:]
    out = args[args.index("--out") + 1] if "--out" in args else args[0]
    sys.exit(main(args[0], out))
