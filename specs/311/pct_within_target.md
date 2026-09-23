---
id: pct_within_target
pipeline: "311"
title: Share of 311 requests resolved within the city's target
version: "0.1"
status: draft
unit: proportion
formula: >
  Among requests of a type with a published target, opened in the window and
  whose target deadline (open date + target business days) has passed by the
  computation date: count(closed on or before the deadline) / count(all such
  requests). Requests still open past the deadline count as late.
windows: [90d, 12m]
geographies: [citywide, zcta, council_district, h3_8]
min_n: 30
promise:
  kind: official
  text: >
    The City of Memphis publishes target resolution timeframes per request
    type (e.g. potholes 3-7 business days, streetlights 5-10, graffiti 3-10)
    and reports a citywide on-time percentage.
  source_url: ""
thresholds:
  - name: which end of the published range is the deadline
    primary: "upper bound (e.g. 7 business days for potholes)"
    alternatives: ["lower bound (e.g. 3 business days)", "the city's own on-time rule, once identified"]
    arbitrary: true
inclusions:
  - Requests whose type has a published target timeframe.
  - Deduplicated primary requests only (shared near-duplicate rule, DECISIONS.md D6).
  - Requests with an accepted geocode (for sub-city geographies); all requests for citywide.
exclusions:
  - Requests whose deadline has not yet passed (outcome not yet known).
  - Requests closed as duplicates by the city itself.
  - Requests spanning the October 2023 platform migration; pre- and post-migration series are never combined.
  - Test or internal records identified in source validation.
confounders:
  - Closing a request is not the same as fixing the problem; see closed_without_action_rate.
  - Request mix differs by area; the metric is always reported per request type.
  - Weather and seasonality drive pothole volume; comparisons use the same window citywide.
objections:
  - objection: "Your on-time rule is stricter than ours: we count against the upper end of the range, or we measure calendar days."
    response: "The primary series uses the upper end of the published range, the most generous reading. The lower bound and, once identified, the city's exact rule are published alongside. The city's own citywide figure is reproduced first (reconciliation) before any neighborhood breakdown is shown."
  - objection: "You count duplicate tickets as separate failures, which punishes busy streets."
    response: "Requests are deduplicated (same type, within 50 m, within 7 days of an earlier primary) before any metric is computed; raw and deduplicated counts are both published, and a property test shows the metric does not change when duplicates are added."
  - objection: "Open requests make recent windows look better or worse than they are."
    response: "Only requests whose deadline has already passed are included, so every included request has a known outcome: closed in time, closed late, or still open and therefore late."
---

## Definition

Of the 311 requests near you whose deadline has come and gone, what share
were closed by the deadline the city itself publishes?

## Details and edge cases

- Business days use the shared calendar (`memequity::business_days_between`)
  in Memphis local time: a request's age counts business days strictly after
  the open date up to and including the close date.
- The deadline is `add_business_days(open_date, target_days)`. A request
  closed on the deadline date is on time.
- Types without a published target are excluded from this metric and appear
  only in `median_business_days_to_close`.
- `source_url` must be filled from `docs/research/311.md` before freezing.

## Sensitivity plan

Published under the upper bound (primary) and lower bound of each range. If
an area is "not clearly different" from the citywide value under one and
different under the other, the panel says the conclusion depends on the
threshold.

## Change log

- 0.1 — first draft from design plan 6.3.
