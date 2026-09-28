#!/usr/bin/env Rscript
# Build the static site's data files from the published flat files
# (plan section 8: the front end reads only pipeline outputs).
#
# Usage: Rscript site/build_site_data.R [published_dir] [site_data_dir] [--preview]
#
# By default only metrics that pass the publish gate (plan 5.7) are written, so
# unpublished numbers never reach the deployed site. --preview keeps every
# metric and marks the manifest as a preview, for local review only; never
# deploy a preview build.
#
# Writes:
#   manifest.json               pipelines, freshness, validation, publish status,
#                               and metric labels read from the specs
#   311/areas.json              citywide / ZIP / district / reference-neighborhood
#                               metrics for the headline request types
#   311/hex/<res6 parent>.json  address-level (H3 res-9 disk) metrics, plus each
#                               cell's ZIP and council district, sharded so the
#                               browser loads one small file per lookup
#   311/points/<res6>.json      individual recent requests for the address view
#                               (column-major, to keep files small)
#   permits/areas.json          citywide / ZIP / council-district permit metrics
#                               for every category subgroup
#   food-safety/areas.json      citywide / ZIP / council-district inspection metrics
#   demographics.json           ACS context per area with margins of error and
#                               measure labels (D20; not gated: Census estimates,
#                               not project metrics)

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

args <- commandArgs(trailingOnly = TRUE)
preview <- "--preview" %in% args
args <- setdiff(args, "--preview")
pub <- if (length(args) >= 1) args[1] else file.path("data", "published")
out <- if (length(args) >= 2) args[2] else file.path("site", "data")
dir.create(out, showWarnings = FALSE, recursive = TRUE)

write_json_min <- function(x, path) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  jsonlite::write_json(x, path, auto_unbox = TRUE, digits = 6, na = "null", null = "null")
}

latest <- function(dir, pattern) {
  f <- sort(list.files(dir, pattern = pattern, full.names = TRUE), decreasing = TRUE)
  if (length(f)) f[1] else NA_character_
}

# Columns kept for the browser, in this order (arrays, not objects, to keep
# files small).
COLS <- c("metric", "variant", "subgroup", "window_start", "window_end", "value", "ci_low",
          "ci_high", "n", "suppressed", "citywide_median")

compact <- function(d) {
  d <- as.data.table(d)[, ..COLS]
  d[, ci_high := ifelse(is.infinite(ci_high), -1, ci_high)]  # -1 encodes "longer than observed"
  lapply(seq_len(nrow(d)), function(i) unname(as.list(d[i])))
}

manifest <- list(generated_at = format(Sys.time(), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ"),
                 preview = preview, columns = COLS, pipelines = list())

# ---- 311 ---------------------------------------------------------------------
d311 <- file.path(pub, "311")
if (dir.exists(d311)) {
  cfg <- fread(file.path("pipelines", "311", "config", "request_types.csv"))
  headline <- cfg[headline == TRUE, request_type]
  pubstat <- fromJSON(file.path(d311, "publish_status_311.json"), simplifyVector = FALSE)
  shown <- vapply(pubstat$metrics, function(m) m$metric, "")
  if (!preview) shown <- shown[vapply(pubstat$metrics, function(m) isTRUE(m$publishable), TRUE)]
  read_m <- function(g, gated = TRUE) {
    f <- file.path(d311, sprintf("metrics_311_by_%s.csv", g))
    if (!file.exists(f)) return(NULL)
    m <- fread(f, colClasses = c(geo_id = "character"))
    if (gated) m[metric %in% shown] else m
  }
  areas <- list()
  for (g in c("citywide", "zcta", "council_district", "super_district", "reference_neighborhood")) {
    m <- read_m(g)
    if (is.null(m)) next
    m <- m[subgroup %in% headline]
    areas[[g]] <- lapply(split(m, m$geo_id), compact)
  }
  write_json_min(areas, file.path(out, "311", "areas.json"))

  # Every cell keeps its ZIP and district lookup even when no metric is shown.
  hex_all <- read_m("h3_9", gated = FALSE)
  if (!is.null(hex_all)) {
    hex <- hex_all[metric %in% shown]
    cells <- unique(hex_all$geo_id)
    parent <- h3jsr::get_parent(cells, res = 6)
    # Each cell's ZIP and council district, from the cell center.
    ctr <- h3jsr::cell_to_point(cells, simple = FALSE)
    ctr$cell <- cells
    geo_dir <- file.path("geography")
    for (g in c("zcta", "council_district")) {
      b <- memequity::load_boundaries(g, geo_dir)
      a <- memequity::assign_geography(ctr, b, g)
      ctr[[g]] <- a[[g]]
    }
    look <- data.table(cell = cells, parent = parent, zcta = ctr$zcta, cd = ctr$council_district)
    hex[, parent := look$parent[match(geo_id, look$cell)]]
    unlink(file.path(out, "311", "hex"), recursive = TRUE)
    for (p in unique(look$parent)) {
      h <- hex[parent == p]
      cells_p <- look[parent == p]
      shard <- list(
        geo = setNames(lapply(seq_len(nrow(cells_p)), function(i) list(cells_p$zcta[i], cells_p$cd[i])),
                       cells_p$cell),
        metrics = lapply(split(h, h$geo_id), compact))
      write_json_min(shard, file.path(out, "311", "hex", paste0(p, ".json")))
    }
    message("311 hex shards: ", length(unique(look$parent)))
  }

  pts_file <- file.path(d311, "points_311.geojson")
  if (file.exists(pts_file)) {
    p <- sf::st_read(pts_file, quiet = TRUE)
    xy <- sf::st_coordinates(p)
    p9 <- h3jsr::point_to_cell(p, res = 6)
    tab <- data.table(parent = p9, lon = round(xy[, 1], 5), lat = round(xy[, 2], 5),
                      id = p$sr_id, type = match(p$request_type, headline) - 1L,
                      opened = p$open_date, closed = p$close_date, bd = p$bd_to_close,
                      dup = as.integer(p$duplicate))
    unlink(file.path(out, "311", "points"), recursive = TRUE)
    for (pp in unique(tab$parent)) {
      t <- tab[parent == pp, !"parent"]
      # Column-major: by_column[[i]] holds every value of columns[i].
      write_json_min(list(columns = names(t), types = headline, by_column = unname(as.list(t))),
                     file.path(out, "311", "points", paste0(pp, ".json")))
    }
  }

  val <- fromJSON(latest(d311, "^validation_311_.*\\.json$"), simplifyVector = FALSE)
  file.copy(file.path(d311, "methodology_311.md"), file.path(out, "311", "methodology.md"), overwrite = TRUE)
  file.copy(latest(d311, "^validation_311_.*\\.json$"), file.path(out, "311", "validation.json"), overwrite = TRUE)
  cw <- read_m("citywide", gated = FALSE)
  manifest$pipelines[["311"]] <- list(
    title = "City services (311)",
    status = "live",
    noun = "request",
    data_current_through = cw$data_current_through[1],
    freshness_limit_days = 3,
    validation = list(status = val$status, run_date = val$run_date, summary = val$summary,
                      record_counts = val$record_counts),
    publish = pubstat$metrics,
    # Labels come from the specs so the front end never restates a definition.
    specs = lapply(memequity::read_specs("311", "specs"), function(s) list(
      title = s$title, version = s$version, status = s$status, unit = s$unit, min_n = s$min_n,
      min_population = s$min_population, geographies = I(unlist(s$geographies)),
      promise_kind = s$promise$kind, promise_text = trimws(s$promise$text))),
    headline_types = headline,
    targets = cfg[!is.na(target_high_bd), list(request_type, target_low_bd, target_high_bd, target_source_url)])
}

# ---- demographics (D20) --------------------------------------------------------
# ACS context for each area: Census estimates with their margins of error,
# not project metrics, so they are not subject to the publish gate. They are
# checked when fetched (geography/demographics/validation_demographics_*.json).
geo_dir <- file.path("geography")
if (file.exists(file.path(geo_dir, "demographics", "registry.csv"))) {
  reg <- memequity::demographics_registry(geo_dir)
  ms <- memequity::demographic_measures(geo_dir)
  comp <- memequity::load_demographic_components(dir = geo_dir)
  demo_areas <- list()
  for (g in c("citywide", "zcta", "council_district", "super_district", "reference_neighborhood")) {
    d <- as.data.table(memequity::load_demographics(g, geo_dir))
    digits <- ifelse(ms$unit[match(d$measure, ms$id)] == "proportion", 4, 0)
    d[, `:=`(value = round(value, digits), moe = round(moe, digits))]
    cov <- as.data.table(comp[comp$geo_type == g & comp$variable %in% c("POP100", "POP100_all"), ])
    cov <- dcast(cov, geo_id ~ variable, value.var = "estimate")
    demo_areas[[g]] <- lapply(split(d, d$geo_id), function(x) {
      x <- x[match(ms$id, x$measure)]
      cv <- cov[geo_id == x$geo_id[1]]
      list(values = lapply(seq_len(nrow(x)), function(i) list(x$value[i], x$moe[i], x$reliability[i])),
           share_in_city = if (nrow(cv) && cv$POP100_all > 0) round(cv$POP100 / cv$POP100_all, 3) else NULL)
    })
  }
  write_json_min(list(
    source = reg$source[1], acs_vintage = reg$acs_vintage[1], universe = reg$universe[1],
    weights = reg$weights[1],
    measures = lapply(seq_len(nrow(ms)), function(i) as.list(ms[i, c("id", "label", "unit", "note")])),
    areas = demo_areas), file.path(out, "demographics.json"))
  manifest$demographics <- list(file = "demographics.json", acs_vintage = reg$acs_vintage[1])
}

# ---- permits (investment) --------------------------------------------------------
dper <- file.path(pub, "permits")
if (file.exists(file.path(dper, "publish_status_permits.json"))) {
  pubstat_p <- fromJSON(file.path(dper, "publish_status_permits.json"), simplifyVector = FALSE)
  shown_p <- vapply(pubstat_p$metrics, function(m) m$metric, "")
  if (!preview) shown_p <- shown_p[vapply(pubstat_p$metrics, function(m) isTRUE(m$publishable), TRUE)]
  areas_p <- list()
  for (g in c("citywide", "zcta", "council_district")) {
    f <- file.path(dper, sprintf("metrics_permits_by_%s.csv", g))
    if (!file.exists(f)) next
    m <- fread(f, colClasses = c(geo_id = "character"))[metric %in% shown_p]
    areas_p[[g]] <- lapply(split(m, m$geo_id), compact)
  }
  write_json_min(areas_p, file.path(out, "permits", "areas.json"))
  file.copy(file.path(dper, "methodology_permits.md"), file.path(out, "permits", "methodology.md"),
            overwrite = TRUE)
  val_p <- latest(dper, "^validation_permits_.*\\.json$")
  file.copy(val_p, file.path(out, "permits", "validation.json"), overwrite = TRUE)
  val_p <- fromJSON(val_p, simplifyVector = FALSE)
  cw_p <- fread(file.path(dper, "metrics_permits_by_citywide.csv"))
  labels <- fread(file.path("pipelines", "permits", "config", "subgroups.csv"))
  # Demolitions come from a separate snapshot with its own data-through date (D30).
  is_demo <- cw_p$subgroup == "demolition" | cw_p$metric == "demolition_to_new_ratio"
  manifest$pipelines[["permits"]] <- list(
    title = "Investment (building permits)",
    status = "live",
    noun = "permit",
    data_current_through = max(cw_p$data_current_through[!is_demo]),
    demolitions_through = if (any(is_demo)) min(cw_p$data_current_through[is_demo]),
    # The source is refreshed monthly, so a month-old data date is normal.
    freshness_limit_days = 75,
    validation = list(status = val_p$status, run_date = val_p$run_date, summary = val_p$summary,
                      record_counts = val_p$record_counts),
    publish = pubstat_p$metrics,
    specs = lapply(memequity::read_specs("permits", "specs"), function(s) list(
      title = s$title, version = s$version, status = s$status, unit = s$unit, min_n = s$min_n,
      min_parcels = s$min_parcels, geographies = I(unlist(s$geographies)),
      promise_kind = s$promise$kind, promise_text = trimws(s$promise$text))),
    subgroups = lapply(seq_len(nrow(labels)), function(i) list(id = labels$subgroup[i],
                                                               label = labels$label[i])))
}

# ---- food safety -----------------------------------------------------------------
dfood <- file.path(pub, "food-safety")
if (file.exists(file.path(dfood, "publish_status_food-safety.json"))) {
  pubstat_f <- fromJSON(file.path(dfood, "publish_status_food-safety.json"), simplifyVector = FALSE)
  shown_f <- vapply(pubstat_f$metrics, function(m) m$metric, "")
  if (!preview) shown_f <- shown_f[vapply(pubstat_f$metrics, function(m) isTRUE(m$publishable), TRUE)]
  areas_f <- list()
  for (g in c("citywide", "zcta", "council_district")) {
    f <- file.path(dfood, sprintf("metrics_food-safety_by_%s.csv", g))
    if (!file.exists(f)) next
    m <- fread(f, colClasses = c(geo_id = "character"))[metric %in% shown_f]
    areas_f[[g]] <- lapply(split(m, m$geo_id), compact)
  }
  write_json_min(areas_f, file.path(out, "food-safety", "areas.json"))
  file.copy(file.path(dfood, "methodology_food-safety.md"), file.path(out, "food-safety", "methodology.md"),
            overwrite = TRUE)
  val_f <- latest(dfood, "^validation_food-safety_.*\\.json$")
  file.copy(val_f, file.path(out, "food-safety", "validation.json"), overwrite = TRUE)
  val_f <- fromJSON(val_f, simplifyVector = FALSE)
  cw_f <- fread(file.path(dfood, "metrics_food-safety_by_citywide.csv"))
  manifest$pipelines[["food-safety"]] <- list(
    title = "Food safety",
    status = "live",
    noun = "establishment",
    data_current_through = cw_f$data_current_through[1],
    # The collector runs by hand for now (D29); the pipeline warns at 60 days.
    freshness_limit_days = 60,
    validation = list(status = val_f$status, run_date = val_f$run_date, summary = val_f$summary,
                      record_counts = val_f$record_counts),
    publish = pubstat_f$metrics,
    # reinspection_rate counts inspections; every other metric counts establishments.
    specs = lapply(memequity::read_specs("food-safety", "specs"), function(s) list(
      title = s$title, version = s$version, status = s$status, unit = s$unit, min_n = s$min_n,
      noun = if (identical(s$id, "reinspection_rate")) "inspection" else "establishment",
      geographies = I(unlist(s$geographies)),
      promise_kind = s$promise$kind, promise_text = trimws(s$promise$text))),
    subgroups = list(list(id = "all", label = "Restaurants and bars")))
}

# ---- panels not yet producing metrics ----------------------------------------
if (is.null(manifest$pipelines[["food-safety"]]))
  manifest$pipelines[["food-safety"]] <- list(
    title = "Food safety", status = "in_development",
    note = paste("Inspection data come from the state portal through the project owner's collector",
                 "(DECISIONS.md D29), which does not run with this build yet. The pipeline is built",
                 "and runs on the collected data."))
manifest$pipelines[["mata"]] <- list(
  title = "Transit (MATA)", status = "collecting", collecting_since = "2026-09-23",
  note = paste("Bus positions are archived every 30 seconds while the collector runs, which so far",
               "is about half the day (DECISIONS.md H22). The panel goes live after the trip-matching",
               "rule clears its match-rate floor and a stopwatch audit at real stops."))
manifest$pipelines[["mlgw"]] <- list(
  title = "Power (MLGW)", status = "collecting", collecting_since = "2026-09-23",
  note = paste("Outage snapshots are archived every 5 minutes while the collector runs, which so",
               "far is about half the day (DECISIONS.md H22). The panel goes live after six months",
               "of history that include a significant weather event."))
if (is.null(manifest$pipelines[["permits"]]))
  manifest$pipelines[["permits"]] <- list(
    title = "Investment (building permits)", status = "in_development",
    note = paste("The permits pipeline has not produced outputs in this build. It uses the City's",
                 "DPD building permits; demolitions need another source (DECISIONS.md H21)."))

# ---- health (read by the project tracker) --------------------------------------
# The tracker's status contract: this build is the document and each daily
# pipeline a part. The tracker judges the age of last_success_at itself, so a
# build or pipeline that stops running shows up as stale. A failed volume check
# warns (D26); schema warnings and reconciliation gaps are not health (D27).
pipeline_health <- function(dir, pattern, entry) {
  report <- latest(dir, pattern)
  if (is.na(report) || !identical(entry$status, "live"))
    return(list(status = "fail", last_success_at = NULL, expect_every = "1d",
                detail = "no outputs in this build: the pipeline or its tests failed"))
  val <- fromJSON(report, simplifyVector = FALSE)
  outliers <- Filter(function(c) identical(c$type, "volume") && !isTRUE(c$passed), val$checks)
  notes <- vapply(outliers, function(c) {
    day <- if (length(c$details$days)) c$details$days[[1]]
    if (is.null(day$count)) return(c$name)
    sprintf("volume outlier on %s: %.0f rows, band %.0f-%.0f", day$date, as.numeric(day$count),
            as.numeric(day$low), as.numeric(day$high))
  }, "")
  list(status = if (length(outliers)) "warn" else "ok", last_success_at = val$run_at, expect_every = "1d",
       detail = paste(c(paste("data through", entry$data_current_through), notes), collapse = "; "))
}
manifest$health <- list(
  status = if (preview) "warn" else "ok", last_success_at = manifest$generated_at, expect_every = "1d",
  detail = if (preview) "preview build, not for deployment" else "site built",
  checks = list(`311` = pipeline_health(d311, "^validation_311_.*\\.json$", manifest$pipelines[["311"]]),
                permits = pipeline_health(dper, "^validation_permits_.*\\.json$", manifest$pipelines[["permits"]])))

write_json_min(manifest, file.path(out, "manifest.json"))
message("site data written to ", out)
