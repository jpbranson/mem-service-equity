"""Shared helpers for the continuous pollers (design plan 6.1, 6.2, 9).

Every poll attempt is logged, successful or not, so that poller uptime can
be published and gaps excluded from metric denominators instead of being
mistaken for ghost buses or restored outages.
"""

from __future__ import annotations

import gzip
import json
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

USER_AGENT = (
    "memphis-service-equity/0.1 (+https://github.com/jpbranson/mem-service-equity; "
    "civic research poller)"
)


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso(ts: datetime) -> str:
    return ts.strftime("%Y-%m-%dT%H:%M:%SZ")


@dataclass
class FetchResult:
    ok: bool
    status: int | None
    content_type: str | None
    body: bytes
    error: str | None
    elapsed_ms: int


def fetch(url: str, timeout: float = 30.0, retries: int = 2, backoff: float = 3.0) -> FetchResult:
    """GET a URL with an identifying user agent and bounded retries."""
    last_err = None
    for attempt in range(retries + 1):
        started = time.monotonic()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                body = resp.read()
                return FetchResult(True, resp.status, resp.headers.get("Content-Type"), body, None,
                                   int((time.monotonic() - started) * 1000))
        except urllib.error.HTTPError as e:
            last_err = FetchResult(False, e.code, None, b"", f"HTTP {e.code}",
                                   int((time.monotonic() - started) * 1000))
        except Exception as e:  # network errors, timeouts
            last_err = FetchResult(False, None, None, b"", f"{type(e).__name__}: {e}",
                                   int((time.monotonic() - started) * 1000))
        if attempt < retries:
            time.sleep(backoff * (attempt + 1))
    assert last_err is not None
    return last_err


class JsonlGzWriter:
    """Append JSON lines to a gzip file, one gzip member per flush.

    Concatenated gzip members form a valid gzip stream, so a crash loses at
    most the unflushed buffer and never corrupts earlier data.
    """

    def __init__(self, path: Path, flush_every: int = 50):
        self.path = path
        self.flush_every = flush_every
        self.buffer: list[str] = []
        path.parent.mkdir(parents=True, exist_ok=True)

    def write(self, record: dict) -> None:
        self.buffer.append(json.dumps(record, separators=(",", ":"), ensure_ascii=False))
        if len(self.buffer) >= self.flush_every:
            self.flush()

    def flush(self) -> None:
        if not self.buffer:
            return
        with gzip.open(self.path, "at", encoding="utf-8") as f:
            f.write("\n".join(self.buffer) + "\n")
        self.buffer = []


def read_jsonl_gz(path: Path) -> list[dict]:
    with gzip.open(path, "rt", encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def run_loop(duration_s: float, tasks: list[tuple[float, callable]], sleep=time.sleep,
             clock=time.monotonic) -> None:
    """Run each (interval_s, fn) task on its own cadence until duration elapses.

    Tasks run immediately at start and then every interval. A slow task
    delays the others but never causes a burst of catch-up requests.
    """
    start = clock()
    next_run = [start for _ in tasks]
    while True:
        now = clock()
        if now - start >= duration_s:
            return
        for i, (interval, fn) in enumerate(tasks):
            ran_at = clock()
            if ran_at >= next_run[i]:
                fn()
                # On schedule: keep the cadence. Late: restart the interval
                # from now, never firing twice in quick succession.
                next_run[i] = max(next_run[i] + interval, ran_at + interval)
        wait = min(next_run) - clock()
        if wait > 0:
            sleep(min(wait, max(0.0, duration_s - (clock() - start))))
