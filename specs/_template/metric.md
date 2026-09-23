---
# Metric specification template (design plan 5.1).
# Copy to specs/<pipeline>/<metric_id>.md. The YAML block is machine-read:
# the methodology page and the publish gate are generated from it.
id: pipeline_metric_id
pipeline: pipeline-name
title: Plain-English metric name
version: "0.1"          # MAJOR.MINOR. A definition change bumps MAJOR and starts a new series.
status: draft           # draft -> review -> frozen. Only frozen specs can publish.
unit: proportion        # proportion | business_days | minutes | count_per_1000 | ...
formula: >
  Exact formula, in terms of named fields of the normalized data.
windows: [90d, 12m]     # rolling windows the metric is published over
geographies: [zcta, council_district, h3_8]
min_n: 30               # 30 for proportions, 20 for medians unless argued otherwise
promise:
  kind: official        # official (a stated standard) | comparison (citywide median only)
  text: The promise, quoted or paraphrased from its source.
  source_url: ""        # required for a frozen official promise
thresholds:
  - name: example threshold
    primary: "value used for the headline"
    alternatives: ["alternative 1", "alternative 2"]
    arbitrary: true     # arbitrary thresholds must list >= 2 alternatives, all published
inclusions:
  - Which records count.
exclusions:
  - Which records are removed, and why.
confounders:
  - Known confounders a reader should keep in mind.
objections:
  # The three most damaging objections an agency analyst would raise, each
  # answered here or resolved by changing the metric. A frozen spec needs >= 3.
  - objection: ""
    response: ""
---

## Definition

Plain-English definition a resident can follow.

## Details and edge cases

Window boundaries, time zones, business-day counting, missing values, how
duplicates and reopened records are handled, censoring.

## Sensitivity plan

Which alternatives are published and what a reader should conclude if the
answer changes between them.

## Change log

- 0.1 — first draft.
