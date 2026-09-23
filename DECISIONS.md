# Decision log

Two lists. **Needs a human** holds the items that block part of the plan
until a person acts. They are grouped by who can resolve them, and each
names what it blocks. **Decisions made** records the implementation choices
made while building, so a reviewer can challenge them.

## Needs a human

### Accounts, credentials and access

- [ ] **H1. Object storage (Cloudflare R2 or S3).** Plan section 9 stores
  published flat files and poller archives in free-tier object storage.
  Create a bucket and add `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`,
  `R2_SECRET_ACCESS_KEY` and `R2_BUCKET` as repository secrets.
  *Blocks:* durable poller archives and versioned dataset storage. *Interim:*
  pollers commit compressed daily files to the `data` branch of this repo
  (see D7).
- [ ] **H2. GitHub Pages.** Enable Pages for this repo with source "GitHub
  Actions". *Blocks:* the public site.

### Field and manual work (plan 5.6)

- [ ] **H3. Pre-launch manual audit, per panel.** Trace at least 100 random
  records by hand, from source to published metric, using the audit sheet
  that each pipeline generates under `audits/`. Commit the completed sheet.
- [ ] **H4. 311 disposition audit.** Read a few hundred closed requests and
  confirm or correct the draft disposition mapping. *Blocks:* the
  closed-without-action metric.
- [ ] **H5. MATA stopwatch audit.** Record actual arrivals for an hour at
  three stops: a terminal, a mid-route stop and a timepoint. *Blocks:* the
  MATA panel launch.
- [ ] **H6. Geocoder accuracy check.** Hand-check the 200-address sample in
  `geography/geocoder_validation/` (plan 7).
- [ ] **H7. Independent reviewer.** Candidates are Data Midsouth, a
  University of Memphis faculty member or a former agency analyst (plan 13).
- [ ] **H8. Agency courtesy previews.** Send each panel and its methodology
  to the agency two weeks before launch.

### Judgment calls to confirm

- [ ] **H9. Reference-neighborhood ZIP groupings.** The draft is in
  `geography/reference_neighborhoods.csv`. Confirm it or edit it.
- [ ] **H10. Spec review and freeze.** Every spec under `specs/` is `draft`.
  A human reviewer must read each one, including its adversarial objections,
  and set it to `frozen`. No metric can publish until this happens (5.7).

## Decisions made

- **D1. Language split.** Batch pipelines and the shared core are in R, as
  plan section 9 specifies. The MATA and MLGW pollers are Python standard
  library only, because long-running collectors are easier to keep running
  on GitHub Actions without an R toolchain.
- **D2. Shared core as an R package.** The geography layer, calendar, stats,
  validation harness, output writers, spec parser and publish gate live in
  `packages/memequity`.
- **D3. Validation harness is built in-house, not pointblank.** The plan
  allows pointblank or pandera. The report format is fixed by plan section 8
  and has to be identical for the R pipelines and the Python pollers. A small
  harness writing that JSON directly (`R/validation.R`) is simpler than
  converting pointblank output, and it keeps dependencies light.
- **D4. Output schema extension.** `metrics_*.csv` adds a `variant` column
  so the threshold alternatives required by 5.1 sit beside the primary
  series. `citywide_median` holds the citywide median for median metrics and
  the citywide pooled value for proportions and rates.
- **D5. Business-day convention.** A request's age in business days counts
  the business days `d` with `open_date < d <= close_date`, in Memphis local
  time. A request opened and closed the same day is 0 days old. This must
  still be checked against any worked examples the city publishes; see the
  311 spec.
- **D6. Near-duplicate rule.** A record duplicates the earliest earlier
  *primary* record of the same type within 50 m and 7 days. The rule is not
  transitive, so a pothole re-reported every 5 days for a month produces a
  new primary each week, not a single cluster.
- **D8. Boundary rule.** A point within 1 m of more than one polygon goes to
  the lowest `geo_id` among them and is flagged `on_boundary`.
- **D9. Censored durations.** Median time-to-close uses a Kaplan–Meier
  median with a log-log interval, so requests still open are treated as
  right-censored rather than dropped.
