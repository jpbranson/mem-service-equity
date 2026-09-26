# Food inspection export inbox

Put the records-request export here (DECISIONS.md H11). The files are **not
committed**: only this README is tracked. Before the first run:

1. Check every column name in `../config/column_map.yml` against the files,
   and every inspection-type value in `../config/inspection_types.csv`. The
   run fails on a missing required field or an unmapped type.
2. Record the date received, the sender and any reference number in
   DECISIONS.md H11.
3. Run `Rscript pipelines/food-safety/run.R` from the repository root.

Keep the original files unchanged and note their names and checksums in the
H11 entry, so the published numbers can be traced back to them.
