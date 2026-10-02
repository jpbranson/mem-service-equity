#!/usr/bin/env Rscript
# MLGW pipeline: poller archive -> snapshots -> outage events (OUTAGE_NO
# chains) -> geography -> metrics (plan 6.2; specs v0.2, DECISIONS.md H19).
#
# Usage (from the repository root):
#   Rscript pipelines/mlgw/run.R --archive DIR [--through YYYY-MM-DD] [--as-of YYYY-MM-DD]
#     [--out DIR] [--min-window-coverage 0.9]
#
# DIR holds the poller's files (mlgw_snapshots_*, mlgw_polls_*), e.g. weekly
# archive releases downloaded with
#   gh release download archive-mlgw-2026-W39 --dir data/cache/mlgw
# Set TESTS_PASSED=true when the metric tests have passed in the same CI run.

suppressPackageStartupMessages({
  library(memequity)
  library(data.table)
})

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default = NULL) {
  i <- match(paste0("--", name), args)
  if (is.na(i)) default else args[i + 1]
}
here <- file.path("pipelines", "mlgw")
for (f in list.files(file.path(here, "R"), full.names = TRUE)) source(f)
log <- function(...) message(format(Sys.time(), "%H:%M:%S"), "  ", ...)
as_of <- as.Date(arg("as-of", format(Sys.time(), tz = "America/Chicago", "%Y-%m-%d")))
archive <- arg("archive")
if (is.null(archive)) stop("--archive DIR is required", call. = FALSE)
out_dir <- arg("out", file.path("data", "published", "mlgw"))
causes <- utils::read.csv(file.path(here, "config", "out_causes.csv"), stringsAsFactors = FALSE,
                          colClasses = c(out_cause = "character"), na.strings = character())

# ---- read the archive and build events ------------------------------------------
snap <- read_snapshots(archive)
attempts <- read_poll_log(archive)
spans <- covered_spans(snap$polls)
last_day <- as.Date(format(max(snap$polls), tz = "America/Chicago", "%Y-%m-%d"))
through <- as.Date(arg("through", format(min(last_day, as_of - 1))))
log(length(snap$polls), " snapshots, ", nrow(snap$obs), " outage sightings; through ", format(through))

ev <- build_events(snap$obs, snap$polls, causes$out_cause[causes$planned])
pts <- points_from_lonlat(as.data.frame(ev), "lon", "lat")
for (g in AREA_GEOS) pts <- assign_geography(pts, load_boundaries(g), g)
ev[, (AREA_GEOS) := lapply(AREA_GEOS, function(g) pts[[g]])]
ev[, h3_9 := h3_cell(pts, res = 9L)]
ev[, in_city := !is.na(citywide)]
pts$in_city <- ev$in_city
log(nrow(ev), " events (", sum(ev$planned), " planned), ", sum(ev$in_city), " inside the city")

# ---- validate ---------------------------------------------------------------------
rep <- validation_report("mlgw", as_of, source = paste("poller archive:", archive))
rep <- add_check(rep, "archive has snapshots and poll logs", "volume",
                 length(snap$polls) > 0 && nrow(attempts) > 0,
                 list(snapshots = length(snap$polls), poll_attempts = nrow(attempts)))
rep <- add_check(rep, "every outage has the fields the specs use", "schema",
                 !length(snap$missing_fields), list(missing = as.list(snap$missing_fields)))
seen_causes <- unique(trimws(as.character(snap$obs$OUT_CAUSE)))
seen_causes[is.na(seen_causes)] <- ""
rep <- check_referential(rep, seen_causes, causes$out_cause, "every OUT_CAUSE is listed in config/out_causes.csv")
unparsed <- function(x) { x <- trimws(as.character(x)); sum(!is.na(x) & nzchar(x) & is.na(parse_local_time(x))) }
rep <- add_check(rep, "outage start and estimated repair times parse", "schema",
                 unparsed(snap$obs$TIME_STAMP) == 0 && unparsed(snap$obs$EST_REPAIR_TIME) == 0,
                 list(start_unparsed = unparsed(snap$obs$TIME_STAMP),
                      estimate_unparsed = unparsed(snap$obs$EST_REPAIR_TIME)))
cust <- suppressWarnings(as.numeric(snap$obs$CUR_CUST_AFF))
rep <- add_check(rep, "customers affected are whole numbers, zero or more", "schema",
                 !anyNA(cust) && all(cust >= 0 & cust == round(cust)), list(bad = sum(is.na(cust) | cust < 0)))
unlocated <- sum(sf::st_is_empty(pts))
rep <- add_check(rep, "at most 1% of events have no location", "geocoding",
                 unlocated <= 0.01 * max(1, nrow(ev)), list(unlocated = unlocated), severity = "warning")
failed <- sum(!attempts$ok)
rep <- add_check(rep, "at most 5% of poll attempts failed", "freshness",
                 failed <= 0.05 * max(1, nrow(attempts)), list(attempts = nrow(attempts), failed = failed),
                 severity = "warning")
win_from <- as.POSIXct(format(through - max(WINDOW_DAYS) + 1), tz = "America/Chicago")
win_to <- as.POSIXct(format(through + 1), tz = "America/Chicago")
coverage <- span_coverage(spans, win_from, win_to)
rep <- add_check(rep, "the poller covered at least 90% of the 12-month window (DECISIONS.md H22)", "freshness",
                 coverage >= 0.9, list(share_of_window = round(coverage, 3)), severity = "warning")
rep <- add_count(rep, "snapshots", length(snap$polls))
rep <- add_count(rep, "poll_attempts", nrow(attempts))
rep <- add_count(rep, "poll_failures", failed)
rep <- add_count(rep, "events", nrow(ev))
rep <- add_count(rep, "events_planned", sum(ev$planned))
rep <- add_count(rep, "events_reappeared", sum(ev$reappeared))
rep <- add_count(rep, "events_still_on", sum(!ev$confirmed))
rep <- add_count(rep, "events_in_city", sum(ev$in_city))
rep$geography <- lapply(c("zcta", "council_district"), function(g) assignment_summary(pts[pts$in_city, ], g))
path <- write_validation_report(finalize_report(rep), out_dir)
log("validation: ", finalize_report(rep)$status, " -> ", path)
stop_if_failed(rep)

# ---- metrics -------------------------------------------------------------------------
# A window is computed only when the poller covered most of it; lower
# --min-window-coverage to inspect partial windows during development. The
# specs stay blocked until six months of history exist (plan 6.2).
min_cov <- as.numeric(arg("min-window-coverage", "0.9"))
denominators <- rbindlist(lapply(AREA_GEOS, function(g) {
  pop <- as.data.table(area_population(g))
  hh <- as.data.table(load_demographic_components(g))[variable == "B11001_001", .(geo_id, households = estimate)]
  merge(pop[, .(geo_type = g, geo_id, population)], hh, by = "geo_id", all.x = TRUE)
}))
if (coverage >= min_cov) {
  m <- compute_metrics_mlgw(ev[in_city == TRUE], denominators, through)
  m <- as_metrics_table(as.data.frame(m), NA, through)
  for (g in unique(m$geo_type)) {
    f <- write_metrics(m[m$geo_type == g, ], "mlgw", g, out_dir)
    log("wrote ", f, " (", sum(m$geo_type == g), " rows)")
  }
} else {
  log("the poller covered ", round(100 * coverage, 1), "% of the 12-month window (needs ",
      min_cov * 100, "%); no metrics written")
  m <- data.frame(metric = character(), suppressed = logical(), ci_low = numeric(), ci_high = numeric())
}
# One row per event, for checking the event rules by hand (spec objections).
fwrite(ev, file.path(out_dir, "events_mlgw.csv"))

# ---- methodology, publish status --------------------------------------------------
render_methodology("mlgw", "specs", out_dir, title = "Power outages (MLGW)",
                   reconciliation_note = paste(
                     "No official figure is reconciled yet. MLGW's SAIDI and SAIFI (EIA-861) are annual,",
                     "so reconciling against them needs a full year of poller history."))
gate_pipeline("mlgw", rep, m, NULL, as_of, out_dir)
log("done")
