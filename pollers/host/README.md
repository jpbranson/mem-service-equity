# Always-on pollers (H22)

On GitHub Actions about half of the scheduled poller runs never start, so
MATA and MLGW are covered only about half the time (DECISIONS.md H22). A
self-hosted runner would not help: the runs are missing because GitHub
never triggers them, not for lack of a runner. This directory runs both
pollers continuously on any always-on Linux host instead, with systemd.

Nothing changes downstream. Each source still runs as consecutive runs
(`RUN_MINUTES`, default 120), with only seconds between them. The runs use
the same poller, archive and status scripts as the workflows, and upload
to the same weekly `archive-<source>-<week>` releases and the `status`
release (D7, D28). Duplicates between overlapping runs are removed
downstream, as now (D15).

## What the host needs

- Linux with systemd, Python 3.12 or later, `git`, `gzip` and the GitHub
  CLI (`gh`). One vCPU and 512 MB of memory are enough, and so is any small
  VM, or a Raspberry Pi on a reliable connection.
- About 1 GB of disk. MATA writes about 20 MB a day, most of it the static
  GTFS zip (1.5 MB) that each run fetches and keeps; MLGW writes well
  under 1 MB. Uploaded runs are kept for `KEEP_DAYS` (30).
- A fine-grained GitHub token scoped to this repository only, with
  **Contents: read and write** (needed to create and upload release
  assets). Note its expiry date: when it expires, uploads stop, and the
  tracker shows the pollers as stale (D28).

## Setup

```sh
sudo useradd --system --create-home --home-dir /var/lib/mse-pollers mse
sudo git clone https://github.com/jpbranson/mem-service-equity /opt/mem-service-equity
sudo python3 -m venv /opt/mem-service-equity/.venv
sudo /opt/mem-service-equity/.venv/bin/pip install -r /opt/mem-service-equity/pollers/requirements.txt

sudo install -m 600 -o mse /dev/null /etc/mse-pollers.env
sudo tee /etc/mse-pollers.env >/dev/null <<'EOF'
GH_TOKEN=<the fine-grained token>
GH_REPO=jpbranson/mem-service-equity
EOF

sudo cp /opt/mem-service-equity/pollers/host/mse-poller@.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now mse-poller@mata mse-poller@mlgw
```

To try it out first, from a checkout, with output under `/tmp`:

```sh
GH_TOKEN=... GH_REPO=jpbranson/mem-service-equity MSE_DATA=/tmp/mse RUN_MINUTES=10 \
  bash pollers/host/run_forever.sh mlgw
```

## Check that it works

- `journalctl -u mse-poller@mata -f` shows each upload as it happens.
- The `status` release's `mata.json` and `mlgw.json` refresh every 30 minutes.
- After a full day, download that week's archive and run the MATA pipeline
  (see CLAUDE.md). Its validation report's check "the poller covered at
  least 90% of service hours" should pass. `share_of_service_hours` was
  about 0.5 on GitHub Actions.

## Switching over

1. Leave the GitHub schedules on for a few days while the host runs. The
   overlap does no harm, because duplicates are removed downstream.
2. Once the host's coverage is confirmed, remove the `schedule:` trigger
   from `.github/workflows/poll-mata.yml` and `poll-mlgw.yml`. Keep
   `workflow_dispatch`, so a manual run is still available as a fallback.
3. Record the host, its cost and the switch date under H22 in DECISIONS.md,
   and update D15.

## Running it

- **Code updates** are manual: `sudo git -C /opt/mem-service-equity pull`,
  then `sudo systemctl restart mse-poller@mata mse-poller@mlgw`. The host
  never pulls by itself, so nothing pushed to main runs there until you
  choose to update it.
- **A stop or restart** loses at most each writer's unflushed buffer, as a
  cancelled workflow run does. The interrupted run's files are uploaded
  before the next run starts.
- **Uploads failing** (expired token, GitHub outage): runs keep polling and
  stay in `/var/lib/mse-pollers/<source>/runs/` until an upload succeeds.
  Nothing is deleted before it is uploaded.
