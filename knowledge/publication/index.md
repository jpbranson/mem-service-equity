# Publication

* [What passes the publish gate, and who signed it](gate-status.md) - Five metrics (three for 311, two for permits) pass the publish gate since 2026-10-06; Claude froze their specs and audited them at the owner's direction (D33), and no person has reviewed them.
* [How a pipeline failure reaches the owner](failure-alerting.md) - The daily deploy publishes 311 even when permits fails; a permits-alert job turns the run red (D34), and the tracker health names the failed checks. A new 311 request type no longer halts the run; it is counted, and the tracker health warns and names it (D35).
