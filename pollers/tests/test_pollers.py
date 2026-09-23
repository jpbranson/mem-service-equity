import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from common import FetchResult, JsonlGzWriter, read_jsonl_gz, run_loop  # noqa: E402
from mata_poller import MataPoller, decode_alerts, decode_vehicles  # noqa: E402
from mlgw_poller import MlgwPoller, parse_outages, parse_summary  # noqa: E402

FIX = Path(__file__).parent / "fixtures"


def ok(body: bytes, ctype="application/octet-stream"):
    return FetchResult(True, 200, ctype, body, None, 5)


def fail(msg="timeout"):
    return FetchResult(False, None, None, b"", msg, 5)


# ---- MATA -------------------------------------------------------------

def test_decode_vehicle_positions_fixture():
    header_ts, recs = decode_vehicles((FIX / "VehiclePosition.pb").read_bytes())
    assert header_ts and header_ts > 1_700_000_000
    assert len(recs) >= 10
    r = recs[0]
    for k in ("vehicle_id", "trip_id", "route_id", "lat", "lon", "timestamp", "stop_id"):
        assert r[k] is not None, k
    assert 34.9 < r["lat"] < 35.5 and -90.4 < r["lon"] < -89.5


def test_decode_alerts_fixture():
    header_ts, alerts = decode_alerts((FIX / "Alert.pb").read_bytes())
    assert header_ts
    assert all("header" in a for a in alerts)


def test_vehicle_poll_dedupes_and_logs(tmp_path):
    body = (FIX / "VehiclePosition.pb").read_bytes()
    responses = iter([ok(body), ok(body), fail()])
    p = MataPoller(tmp_path, "t", fetcher=lambda url, **kw: next(responses))
    p.poll_vehicles(); p.poll_vehicles(); p.poll_vehicles()
    p.close()
    positions = read_jsonl_gz(tmp_path / "mata_positions_t.jsonl.gz")
    polls = read_jsonl_gz(tmp_path / "mata_polls_t.jsonl.gz")
    _, recs = decode_vehicles(body)
    assert len(positions) == len(recs)          # the repeat poll adds nothing
    assert [x["ok"] for x in polls] == [True, True, False]
    assert polls[1]["new_reports"] == 0
    assert polls[2]["error"] == "timeout"       # failures are logged, not dropped


def test_malformed_protobuf_is_logged_not_raised(tmp_path):
    p = MataPoller(tmp_path, "t", fetcher=lambda url, **kw: ok(b"<html>rejected</html>"))
    p.poll_vehicles(); p.close()
    polls = read_jsonl_gz(tmp_path / "mata_polls_t.jsonl.gz")
    assert polls[0]["ok"] is False and polls[0]["error"].startswith("decode")


def test_static_archive_rejects_non_zip(tmp_path):
    p = MataPoller(tmp_path, "t", fetcher=lambda url, **kw: ok(b"<html>"))
    p.archive_static(); p.close()
    assert not list(tmp_path.glob("*.zip"))
    p2 = MataPoller(tmp_path, "u", fetcher=lambda url, **kw: ok(b"PK\x03\x04fake"))
    p2.archive_static(); p2.close()
    assert len(list(tmp_path.glob("mata_gtfs_*.zip"))) == 1


# ---- MLGW -------------------------------------------------------------

def test_parse_outage_fixture():
    outages = parse_outages((FIX / "mlgw_geojson.json").read_bytes())
    assert len(outages) > 0
    o = outages[0]
    assert isinstance(o["OUTAGE_NO"], int)
    assert o["OUT_CAUSE"] == ""                 # whitespace-only strings are stripped
    assert -90.4 < o["lon"] < -89.5


def test_firewall_rejection_page_is_a_failure(tmp_path):
    rejected = b"<html><head><title>Request Rejected</title></head><body>The requested URL was rejected.</body></html>"
    with pytest.raises(ValueError):
        parse_outages(rejected)
    p = MlgwPoller(tmp_path, "t", fetcher=lambda url, **kw: ok(rejected, "text/html"))
    p.poll_outages(); p.close()
    polls = read_jsonl_gz(tmp_path / "mlgw_polls_t.jsonl.gz")
    assert polls[0]["ok"] is False
    assert not (tmp_path / "mlgw_snapshots_t.jsonl.gz").exists()


def test_parse_summary_fixture():
    s = parse_summary((FIX / "OutageSummary.html").read_bytes())
    assert s["customers_with_power"] == 427471
    assert s["customers_without_power"] == 517
    assert s["current_as_of_local"] == "09/23/2026 09:47 AM"


def test_outage_snapshot_written(tmp_path):
    body = (FIX / "mlgw_geojson.json").read_bytes()
    p = MlgwPoller(tmp_path, "t", fetcher=lambda url, **kw: ok(body, "application/json"))
    p.poll_outages(); p.close()
    snaps = read_jsonl_gz(tmp_path / "mlgw_snapshots_t.jsonl.gz")
    assert len(snaps) == 1 and snaps[0]["outages"]
    polls = read_jsonl_gz(tmp_path / "mlgw_polls_t.jsonl.gz")
    assert polls[0]["customers_affected"] == sum(o["CUR_CUST_AFF"] for o in snaps[0]["outages"])


# ---- shared -------------------------------------------------------------

def test_gzip_writer_appends_members(tmp_path):
    path = tmp_path / "x.jsonl.gz"
    w = JsonlGzWriter(path, flush_every=2)
    for i in range(5):
        w.write({"i": i})
    w.flush()
    w2 = JsonlGzWriter(path)
    w2.write({"i": 5}); w2.flush()
    assert [r["i"] for r in read_jsonl_gz(path)] == list(range(6))


def test_run_loop_cadence_without_catch_up_bursts():
    t = [0.0]
    calls = {"a": [], "b": []}
    clock = lambda: t[0]  # noqa: E731

    def sleep(s):
        t[0] += s

    def a():
        calls["a"].append(t[0])

    def b():
        calls["b"].append(t[0])
        t[0] += 100  # a slow task

    run_loop(300, [(30, a), (120, b)], sleep=sleep, clock=clock)
    assert calls["a"][0] == 0 and calls["b"][0] == 0
    gaps = [y - x for x, y in zip(calls["a"], calls["a"][1:])]
    assert all(g >= 30 for g in gaps)          # never faster than the interval
    assert len(calls["b"]) <= 3
