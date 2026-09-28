# Food inspection inbox

The default `--inbox` of `pipelines/food-safety/run.R`. The files are **not
committed**: only this README is tracked.

The current data are the owner's collector output (DECISIONS.md D29). Point
`--inbox` at the collector's data directory, or copy its `inspections.csv`
here. The validation report records the file's md5.

If the records-request export (H11) arrives, put it here and, before the
first run:

1. Check every column name in `../config/column_map.yml` against the files,
   and every inspection-type, program and permit-type value in
   `../config/*.csv`. The run fails on a missing required field or an
   unmapped value.
2. Record the date received, the sender and any reference number in
   DECISIONS.md H11.
3. Run `Rscript pipelines/food-safety/run.R` from the repository root.

Keep the original files unchanged and note their names and checksums in the
H11 entry, so the published numbers can be traced back to them.
