# Food inspection inbox

The default `--inbox` of `pipelines/food-safety/run.R`. The files are **not
committed**: only this README is tracked.

The data are TDH's records-request export (DECISIONS.md H11, D32):
`Shelby County Information Request.xlsx`, whose two sheets
`../config/column_map.yml` names. The validation report records the file's
md5. The workbook names inspectors and billing contacts, so it stays here,
uncommitted.

When a new export arrives, put it here (remove the old one: the first file
whose name matches `file_pattern` is read) and, before the first run:

1. Check every sheet and column name in `../config/column_map.yml`
   against the file, and every inspection-type and permit-type value in
   `../config/*.csv`. The run fails on a missing required field or an
   unmapped value.
2. Record the date received, the sender and any reference number in
   DECISIONS.md H11.
3. Run `Rscript pipelines/food-safety/run.R` from the repository root.

Keep the original files unchanged and note their names and checksums in the
H11 entry, so the published numbers can be traced back to them.
