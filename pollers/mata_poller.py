"""MATA poller (design plan 6.1, phase 1): collection only.

Every 30 s: GTFS-Realtime VehiclePositions -> one JSON line per vehicle
report (deduplicated on vehicle + timestamp within the run).
Every 15 min: GTFS-Realtime Alerts (announced cancellations and detours).
Once per run: the static GTFS zip, which MATA regenerates nightly as a
rolling 30-day window and does not keep, so the archive is the only record
of which schedule was in force on a given date.

Every poll attempt, successful or not, is written to the polls log.

Usage: python pollers/mata_poller.py --minutes 125 --out data/poller
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

from google.transit import gtfs_realtime_pb2

from common import JsonlGzWriter, fetch, iso, run_loop, utc_now

RT_BASE = "https://gtfsrt.mata.cadavl.com/ProfilGtfsRt2_0RSProducer-MATA"
VEHICLE_URL = f"{RT_BASE}/VehiclePosition.pb"
ALERT_URL = f"{RT_BASE}/Alert.pb"
STATIC_URL = "https://gtfs.mata.cadavl.com/MATA/GTFS/GTFS_MATA.zip"


def decode_vehicles(body: bytes) -> tuple[int | None, list[dict]]:
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.ParseFromString(body)
    header_ts = feed.header.timestamp if feed.header.HasField("timestamp") else None
    out = []
    for ent in feed.entity:
        if not ent.HasField("vehicle"):
            continue
        v = ent.vehicle
        rec = {
            "entity_id": ent.id,
            "vehicle_id": v.vehicle.id if v.HasField("vehicle") else None,
            "vehicle_label": v.vehicle.label if v.HasField("vehicle") else None,
            "trip_id": v.trip.trip_id if v.HasField("trip") else None,
            "route_id": v.trip.route_id if v.HasField("trip") else None,
            "direction_id": v.trip.direction_id if v.HasField("trip") and v.trip.HasField("direction_id") else None,
            "start_date": v.trip.start_date if v.HasField("trip") else None,
            "schedule_relationship": (gtfs_realtime_pb2.TripDescriptor.ScheduleRelationship.Name(
                v.trip.schedule_relationship) if v.HasField("trip") else None),
            "lat": v.position.latitude if v.HasField("position") else None,
            "lon": v.position.longitude if v.HasField("position") else None,
            "bearing": v.position.bearing if v.HasField("position") and v.position.HasField("bearing") else None,
            "speed": v.position.speed if v.HasField("position") and v.position.HasField("speed") else None,
            "current_status": (gtfs_realtime_pb2.VehiclePosition.VehicleStopStatus.Name(v.current_status)
                               if v.HasField("current_status") else None),
            "stop_id": v.stop_id or None,
            "current_stop_sequence": v.current_stop_sequence if v.HasField("current_stop_sequence") else None,
            "timestamp": v.timestamp if v.HasField("timestamp") else None,
            "occupancy_status": (gtfs_realtime_pb2.VehiclePosition.OccupancyStatus.Name(v.occupancy_status)
                                 if v.HasField("occupancy_status") else None),
        }
        out.append(rec)
    return header_ts, out


def decode_alerts(body: bytes) -> tuple[int | None, list[dict]]:
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.ParseFromString(body)
    header_ts = feed.header.timestamp if feed.header.HasField("timestamp") else None

    def text(ts):
        return " | ".join(t.text for t in ts.translation) if ts.translation else None

    out = []
    for ent in feed.entity:
        if not ent.HasField("alert"):
            continue
        a = ent.alert
        out.append({
            "alert_id": ent.id,
            "header": text(a.header_text),
            "description": text(a.description_text),
            "cause": gtfs_realtime_pb2.Alert.Cause.Name(a.cause) if a.HasField("cause") else None,
            "effect": gtfs_realtime_pb2.Alert.Effect.Name(a.effect) if a.HasField("effect") else None,
            "active_periods": [{"start": p.start or None, "end": p.end or None} for p in a.active_period],
            "informed": [{"route_id": s.route_id or None, "stop_id": s.stop_id or None,
                          "trip_id": s.trip.trip_id if s.HasField("trip") else None}
                         for s in a.informed_entity],
        })
    return header_ts, out


class MataPoller:
    def __init__(self, out_dir: Path, run_id: str, fetcher=fetch):
        self.fetch = fetcher
        self.out_dir = out_dir
        self.positions = JsonlGzWriter(out_dir / f"mata_positions_{run_id}.jsonl.gz", flush_every=500)
        self.alerts = JsonlGzWriter(out_dir / f"mata_alerts_{run_id}.jsonl.gz", flush_every=1)
        self.polls = JsonlGzWriter(out_dir / f"mata_polls_{run_id}.jsonl.gz", flush_every=20)
        self.seen: set[tuple] = set()

    def _log(self, feed: str, res, **extra) -> None:
        self.polls.write({"poll_time": iso(utc_now()), "feed": feed, "ok": res.ok, "status": res.status,
                          "error": res.error, "elapsed_ms": res.elapsed_ms, "bytes": len(res.body), **extra})

    def poll_vehicles(self) -> None:
        polled = iso(utc_now())
        res = self.fetch(VEHICLE_URL)
        if not res.ok:
            self._log("vehicle_positions", res)
            return
        try:
            header_ts, recs = decode_vehicles(res.body)
        except Exception as e:  # malformed protobuf: log, don't crash
            res.ok, res.error = False, f"decode: {e}"
            self._log("vehicle_positions", res)
            return
        new = 0
        for r in recs:
            key = (r["vehicle_id"] or r["entity_id"], r["timestamp"])
            if key in self.seen:
                continue
            self.seen.add(key)
            r["poll_time"] = polled
            r["header_timestamp"] = header_ts
            self.positions.write(r)
            new += 1
        self._log("vehicle_positions", res, header_timestamp=header_ts, entities=len(recs), new_reports=new)

    def poll_alerts(self) -> None:
        polled = iso(utc_now())
        res = self.fetch(ALERT_URL)
        if not res.ok:
            self._log("alerts", res)
            return
        try:
            header_ts, alerts = decode_alerts(res.body)
        except Exception as e:
            res.ok, res.error = False, f"decode: {e}"
            self._log("alerts", res)
            return
        self.alerts.write({"poll_time": polled, "header_timestamp": header_ts, "alerts": alerts})
        self._log("alerts", res, header_timestamp=header_ts, entities=len(alerts))

    def archive_static(self) -> None:
        res = self.fetch(STATIC_URL, timeout=120)
        if not res.ok or not res.body.startswith(b"PK"):
            res.ok = False
            res.error = res.error or "not a zip"
            self._log("static_gtfs", res)
            return
        digest = hashlib.sha256(res.body).hexdigest()
        day = utc_now().strftime("%Y-%m-%d")
        path = self.out_dir / f"mata_gtfs_{day}_{digest[:12]}.zip"
        if not path.exists():
            path.write_bytes(res.body)
        self._log("static_gtfs", res, sha256=digest, file=path.name)

    def close(self) -> None:
        for w in (self.positions, self.alerts, self.polls):
            w.flush()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--minutes", type=float, default=125)
    ap.add_argument("--out", default="data/poller")
    ap.add_argument("--vehicle-interval", type=float, default=30)
    ap.add_argument("--alert-interval", type=float, default=900)
    args = ap.parse_args()
    start = utc_now()
    out = Path(args.out) / "mata" / start.strftime("%Y-%m-%d")
    p = MataPoller(out, start.strftime("%Y%m%dT%H%M%SZ"))
    try:
        p.archive_static()
        run_loop(args.minutes * 60, [(args.vehicle_interval, p.poll_vehicles),
                                     (args.alert_interval, p.poll_alerts)])
    finally:
        p.close()


if __name__ == "__main__":
    main()
