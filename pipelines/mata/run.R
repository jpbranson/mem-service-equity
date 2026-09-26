#!/usr/bin/env Rscript
# MATA pipeline: poller archive -> dedupe -> schedule in force per service
# date -> trip matching -> arrival inference -> metrics (plan 6.1).
#
# Usage (from the repository root):
#   Rscript pipelines/mata/run.R --archive DIR [--through YYYY-MM-DD] [--as-of YYYY-MM-DD] [--out DIR]
#
# DIR holds the poller's files for the period (mata_positions_*, mata_polls_*,
# mata_gtfs_*), e.g. the weekly archive releases downloaded with
#   gh release download archive-mata-2026-W39 --dir data/cache/mata/2026-W39
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
here <- file.path("pipelines", "mata")
for (f in list.files(file.path(here, "R"), full.names = TRUE)) source(f)
log <- function(...) message(format(Sys.time(), "%H:%M:%S"), "  ", ...)
as_of <- as.Date(arg("as-of", format(Sys.time(), tz = "America/Chicago", "%Y-%m-%d")))
archive <- arg("archive")
if (is.null(archive)) stop("--archive DIR is required", call. = FALSE)
out_dir <- arg("out", file.path("data", "published", "mata"))

# ---- read the archive --------------------------------------------------------
pos <- read_positions(archive)
spans <- covered_spans(archive)
dates <- sort(unique(pos$service_date))
through <- as.Date(arg("through", format(max(dates[dates < as_of]))))
dates <- dates[dates <= through & dates > through - max(WINDOW_DAYS)]
log(nrow(pos), " vehicle reports; service dates ", format(min(dates)), " to ", format(through))

# ---- per service date ------------------------------------------------------------
days <- lapply(dates, function(d) {
  log("service date ", format(d))
  process_date(archive, d, pos, spans)
})
names(days) <- format(dates)

# ---- validate ------------------------------------------------------------------------
rep <- validation_report("mata", as_of, source = paste("poller archive:", archive))
rep <- add_check(rep, "archive has positions, polls and schedules", "volume",
                 nrow(pos) > 0 && nrow(spans) > 0 && !is.null(gtfs_zip_for_date(archive, through)),
                 list(positions = nrow(pos), covered_spans = nrow(spans)))
rep <- add_check(rep, "every service date has an archived schedule in force", "referential",
                 all(!vapply(days, is.null, logical(1))),
                 list(missing = as.list(names(days)[vapply(days, is.null, logical(1))])))
sched_keys <- unlist(lapply(Filter(Negate(is.null), days), function(d) paste(d$date, d$cls$primary$trip_id)))
in_sched <- mean(paste(pos[service_date %in% dates]$service_date, pos[service_date %in% dates]$trip_id) %in% sched_keys)
rep <- add_check(rep, "at least 95% of vehicle reports are on a scheduled trip", "referential",
                 in_sched >= 0.95, list(share = in_sched), severity = "warning")
# Coverage of service hours (05:00-23:00 local): about half on GitHub Actions (H22).
svc <- rbindlist(lapply(dates, function(d) data.table(
  start = as.POSIXct(paste(format(d), "05:00:00"), tz = "America/Chicago"),
  end = as.POSIXct(paste(format(d), "23:00:00"), tz = "America/Chicago"))))
for (col in c("start", "end")) attr(svc[[col]], "tzone") <- "UTC"   # same zone as the spans
covered <- sum(vapply(seq_len(nrow(svc)), function(i) {
  s <- spans[end > svc$start[i] & start < svc$end[i]]
  sum(pmin(as.numeric(s$end), as.numeric(svc$end[i])) - pmax(as.numeric(s$start), as.numeric(svc$start[i])))
}, numeric(1))) / sum(as.numeric(svc$end) - as.numeric(svc$start))
rep <- add_check(rep, "the poller covered at least 90% of service hours (DECISIONS.md H22)", "freshness",
                 covered >= 0.9, list(share_of_service_hours = round(covered, 3)), severity = "warning")
all_cls <- rbindlist(lapply(Filter(Negate(is.null), days), function(d) d$cls$primary))
rep <- add_count(rep, "vehicle_reports", nrow(pos))
rep <- add_count(rep, "scheduled_trips", nrow(all_cls))
rep <- add_count(rep, "measurable_trips", sum(all_cls$measurable))
for (s in c("observed", "ghost", "unobserved"))
  rep <- add_count(rep, paste0("measurable_", s), sum(all_cls$measurable & all_cls$status == s))
path <- write_validation_report(finalize_report(rep), out_dir)
log("validation: ", finalize_report(rep)$status, " -> ", path)
stop_if_failed(rep)

# ---- metrics ----------------------------------------------------------------
# A window is computed only when archived data cover most of its days; lower
# --min-window-coverage to inspect partial windows during development.
min_cov <- as.numeric(arg("min-window-coverage", "0.9"))
res <- compute_metrics_mata(days, through, min_cov)
if (nrow(res$metrics)) {
  m <- as_metrics_table(as.data.frame(res$metrics), NA, through)
  for (g in unique(m$geo_type)) {
    f <- write_metrics(m[m$geo_type == g, ], "mata", g, out_dir)
    log("wrote ", f, " (", sum(m$geo_type == g), " rows)")
  }
} else {
  log("no window has data on ", min_cov * 100, "% of its days yet (", length(dates),
      " service dates archived); no metrics written")
  m <- data.frame(metric = character(), suppressed = logical(), ci_low = numeric(), ci_high = numeric())
}
# Match rates per route: the floor for on_time_pct (spec), over each
# computed window, or over everything archived when no window qualifies.
mr_windows <- if (length(res$windows)) res$windows else c(archive = length(dates))
mr <- rbindlist(lapply(names(mr_windows), function(w) {
  d <- in_window(res$classified, through, mr_windows[[w]])[measurable == TRUE]
  r <- d[, .(measurable = .N, observed = sum(status == "observed"), ghost = sum(status == "ghost"),
             unobserved = sum(status == "unobserved")), by = route_id]
  r[, `:=`(window = w, match_rate = observed / measurable, above_floor = observed / measurable >= MATCH_RATE_FLOOR)]
}))
fwrite(mr, file.path(out_dir, "match_rates_mata.csv"))

# ---- methodology, publish status ------------------------------------------------
specs_dir <- "specs"
render_methodology("mata", specs_dir, out_dir, title = "Transit (MATA)",
                   reconciliation_note = paste(
                     "No official figure is reconciled yet. MATA's monthly on-time series on the Memphis",
                     "Data Hub has no published definition (DECISIONS.md H16)."))
specs <- read_specs("mata", specs_dir)
audit_file <- sort(list.files(file.path(here, "audits"), pattern = "^audit_.*\\.csv$", full.names = TRUE),
                   decreasing = TRUE)
gates <- lapply(specs, function(s) publish_gate(
  s, finalize_report(rep), tests_passed = identical(Sys.getenv("TESTS_PASSED"), "true"),
  metrics = m[m$metric == s$id, ], reconciliation = NULL,
  audit_path = if (length(audit_file)) audit_file[1] else NULL, as_of = as_of))
write_publish_status(gates, "mata", out_dir)
log("done")
