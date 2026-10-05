---
type: Decision
title: Design plan v0.2 is current
description: The v0.2 design plan governs the project; a v0.3 revision was drafted and rejected on 2026-09-23 and was never committed.
tags: [project, design-plan]
status: draft
generated: { by: claude-code/claude-opus-5-5, at: 2026-10-04T20:50:00-05:00 }
stale_after: 2027-01-04T00:00:00-06:00
sources:
  - id: plan
    resource: ../../memphis-service-equity-design-plan-v0.2.md
    title: Memphis Service Equity design plan v0.2
    last_modified: 2026-09-23T11:19:03-05:00
  - id: session-2026-09-23
    resource: "The owner's choice in a Claude Code session on 2026-09-23, kept in Claude's private project memory until it was moved here on 2026-10-04"
    title: Owner's review of the v0.3 draft
    author: human:jpbranson
---

# Decision

On 2026-09-23 the owner reviewed a draft v0.3 of the design plan and chose
to stay with v0.2, the plan the code was built against. They decided this
after seeing how much of the built code v0.3 would change, and gave no
further reason.[^session-2026-09-23] The v0.3 draft was never committed;
the repo holds only `memphis-service-equity-design-plan-v0.2.md`.[^plan]

# What v0.3 would have changed

- Reconciliation would no longer be a publication gate.
- Audits would use 20 records.
- Golden files would be dropped.
- The pollers would move off GitHub Actions.
- Metrics would be grouped into tiers.
- Food safety would report per establishment only.
- A push channel would be added in Phase 3.

# How to apply

- Treat the v0.2 section numbers in code comments, the README and
  DECISIONS.md as correct.
- Do not propose v0.3 changes (tiers, a Worker proxy, removing the reopen
  rate or the golden files, and so on) unless the owner brings v0.3 back.
- Moving the pollers to an always-on host is not a v0.3 revival. It is H22,
  a fix for measured coverage gaps; see
  [poller scheduling](/data-collection/poller-scheduling.md).

[^plan]: Memphis Service Equity design plan v0.2
[^session-2026-09-23]: Owner's review of the v0.3 draft
