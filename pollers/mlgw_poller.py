"""MLGW outage poller (design plan 6.2, phase 1): collection only.

Every 5 min: the outage map's GeoJSON (one point per active outage, with
OUTAGE_NO, start time, status, estimated restoration time and customers
affected). Outages vanish when restored and fields are revised in place, so
the full snapshot is stored every time; events and restoration times are
reconstructed later from the sequence of snapshots.
Every 15 min: the summary page's customer totals (with / without power).

The site's firewall answers some clients with HTTP 200 and an HTML
"Request Rejected" page, so success means "parsed as the expected JSON",
not "HTTP 200". Every attempt is logged so storm-time gaps are measurable.

Usage: python pollers/mlgw_poller.py --minutes 125 --out data/poller
"""

from __future__ import annotations

import argparse
import html
import json
import re
from pathlib import Path

from common import JsonlGzWriter, fetch, iso, run_loop, utc_now

GEOJSON_URL = "https://outagemap.mlgw.org/geojson.php"
SUMMARY_URL = "https://outagemap.mlgw.org/OutageSummary.php"

EXPECTED_PROPS = {"OUTAGE_NO", "TIME_STAMP", "STATUS", "EST_REPAIR_TIME", "CUR_CUST_AFF"}


def parse_outages(body: bytes) -> list[dict]:
    """Parse the outage GeoJSON; raise ValueError if it is not what we expect."""
    try:
        doc = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        raise ValueError(f"not JSON: {body[:80]!r}") from e
    if doc.get("type") != "FeatureCollection" or not isinstance(doc.get("features"), list):
        raise ValueError("not a FeatureCollection")
    out = []
    for f in doc["features"]:
        props = f.get("properties") or {}
        missing = EXPECTED_PROPS - props.keys()
        if missing:
            raise ValueError(f"feature missing properties: {sorted(missing)}")
        coords = (f.get("geometry") or {}).get("coordinates") or [None, None]
        rec = {k: (v.strip() if isinstance(v, str) else v) for k, v in props.items()}
        rec["lon"], rec["lat"] = coords[0], coords[1]
        out.append(rec)
    return out


SUMMARY_RE = re.compile(
    r"([\d.]+)%\s*Customers With Power\s*([\d,]+)\s*([\d.]+)%\s*Customers Without Power\s*([\d,]+)"
    r".*?CURRENT AS OF\s*(\d{2}/\d{2}/\d{4}\s+\d{1,2}:\d{2}\s*[AP]M)", re.S)


def parse_summary(body: bytes) -> dict:
    text = html.unescape(re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", body.decode("utf-8", "replace"))))
    m = SUMMARY_RE.search(text)
    if not m:
        raise ValueError("summary totals not found")
    return {"pct_with_power": float(m.group(1)), "customers_with_power": int(m.group(2).replace(",", "")),
            "pct_without_power": float(m.group(3)),
            "customers_without_power": int(m.group(4).replace(",", "")),
            "current_as_of_local": m.group(5)}


class MlgwPoller:
    def __init__(self, out_dir: Path, run_id: str, fetcher=fetch):
        self.fetch = fetcher
        self.snapshots = JsonlGzWriter(out_dir / f"mlgw_snapshots_{run_id}.jsonl.gz", flush_every=1)
        self.summaries = JsonlGzWriter(out_dir / f"mlgw_summary_{run_id}.jsonl.gz", flush_every=1)
        self.polls = JsonlGzWriter(out_dir / f"mlgw_polls_{run_id}.jsonl.gz", flush_every=1)

    def _log(self, feed, res, **extra):
        self.polls.write({"poll_time": iso(utc_now()), "feed": feed, "ok": res.ok, "status": res.status,
                          "error": res.error, "elapsed_ms": res.elapsed_ms, "bytes": len(res.body), **extra})

    def poll_outages(self) -> None:
        polled = iso(utc_now())
        res = self.fetch(GEOJSON_URL, timeout=60)
        if res.ok:
            try:
                outages = parse_outages(res.body)
            except ValueError as e:
                res.ok, res.error = False, str(e)
        if not res.ok:
            self._log("outages", res)
            return
        self.snapshots.write({"poll_time": polled, "outages": outages})
        self._log("outages", res, outages=len(outages),
                  customers_affected=sum(o.get("CUR_CUST_AFF") or 0 for o in outages))

    def poll_summary(self) -> None:
        polled = iso(utc_now())
        res = self.fetch(SUMMARY_URL, timeout=60)
        if res.ok:
            try:
                summary = parse_summary(res.body)
            except ValueError as e:
                res.ok, res.error = False, str(e)
        if not res.ok:
            self._log("summary", res)
            return
        self.summaries.write({"poll_time": polled, **summary})
        self._log("summary", res)

    def close(self):
        for w in (self.snapshots, self.summaries, self.polls):
            w.flush()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--minutes", type=float, default=125)
    ap.add_argument("--out", default="data/poller")
    ap.add_argument("--outage-interval", type=float, default=300)
    ap.add_argument("--summary-interval", type=float, default=900)
    args = ap.parse_args()
    start = utc_now()
    out = Path(args.out) / "mlgw" / start.strftime("%Y-%m-%d")
    p = MlgwPoller(out, start.strftime("%Y%m%dT%H%M%SZ"))
    try:
        run_loop(args.minutes * 60, [(args.outage_interval, p.poll_outages),
                                     (args.summary_interval, p.poll_summary)])
    finally:
        p.close()


if __name__ == "__main__":
    main()
