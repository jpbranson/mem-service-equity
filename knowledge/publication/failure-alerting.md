---
type: Operations
title: How a pipeline failure reaches the owner
description: The daily deploy publishes 311 even when permits fails; since D34 a permits-alert job turns the run red, and the tracker health names the failed checks. Permits was off the site 2026-11-01 to 11-10 without notice before this.
tags: [publication, deploy, health, permits, alerting, d26, d34]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-11-11T07:58:00-06:00 }
stale_after: 2027-02-11T00:00:00-06:00
sources:
  - id: decisions
    resource: ../../DECISIONS.md
    title: DECISIONS.md D26 and D34
    last_modified: 2026-11-11T07:54:46-06:00
  - id: deploy
    resource: ../../.github/workflows/deploy-site.yml
    title: The daily deploy workflow
    last_modified: 2026-11-11T07:54:46-06:00
  - id: site-build
    resource: ../../site/build_site_data.R
    title: Site data build and tracker health
    last_modified: 2026-11-11T07:54:46-06:00
  - id: permits-maps
    resource: ../../pipelines/permits/config/category_map.csv
    title: Permits category map
    last_modified: 2026-11-11T07:54:46-06:00
---

# What runs daily, and what may fail

`deploy-site.yml` tests and runs 311, then permits, builds the gated site
data and deploys it. A 311 failure fails the build job, so nothing deploys.
The permits steps are `continue-on-error`: when they fail, the site deploys
without permits and the permits panel says it has no outputs.[^deploy][^decisions]

# Where a permits failure shows

- **The workflow run.** The `permits-alert` job runs after `deploy` and fails
  when the permits tests or run did not succeed. The site is already
  deployed, but the run is red and GitHub notifies the owner. Before D34 the
  run stayed green.[^deploy][^decisions]
- **The tracker health** in `site/data/manifest.json`. Each daily pipeline is
  a part. A permits run that halted on validation is `fail`, and its detail
  names the checks that stopped it. Without a report it says only that the
  pipeline or its tests failed. The document-level status reports the build,
  not the parts.[^site-build]
- **The `validation-reports` artifact** of the run, kept 14 days, holds the
  report itself.[^deploy]

# The 2026-11 incident

The City's DPD refresh of 2026-11-01 added 77 certificates of occupancy
(`COO-` record numbers, coded `CER` / `OF `). Neither code was mapped, so
permits halted on validation every day until 2026-11-10. The runs stayed
green, and the two published permits metrics were off the site for ten
days.[^decisions] The codes now map to `excluded`. Those rows are counted
as `not_a_permit` and never enter a metric.[^permits-maps][^decisions]

# How to apply

- A red deploy run with a green `deploy` job means the site is up without
  permits. Read the `permits-alert` message and the validation report. A
  new source code usually needs a mapping decision recorded in DECISIONS.md,
  not just a new row in the map.[^decisions]
- When the City adds a record class that is not a permit, map it to
  `excluded`, and check that no frozen spec's computed values change.[^decisions]

[^decisions]: DECISIONS.md D26 and D34
[^deploy]: The daily deploy workflow
[^site-build]: Site data build and tracker health
[^permits-maps]: Permits category map
