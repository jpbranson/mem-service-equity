# Fetch ACS 5-year demographics and apportion them to every geography the
# pipelines report on (design plan section 7 "Denominators"; DECISIONS D20).
#
# ACS block groups do not nest in ZIP codes or council districts, so each
# block group's estimates are split across its 2020 Census blocks in
# proportion to the blocks' 2020 population (or housing units, for
# household and housing variables), and the blocks are assigned to areas by
# their internal points. Only blocks inside the City of Memphis are counted,
# matching the 311 pipeline, which counts only requests inside the city.
#
# Run from the repository root, about once a year when a new ACS 5-year
# release comes out (each December):
#   CENSUS_API_KEY=... Rscript geography/fetch_demographics.R [acs_year]
#
# Writes to geography/demographics/:
#   components_census-acs5-<year>_blocks-2020.csv  long: geo_type, geo_id,
#       variable, estimate, moe (ACS variables, plus 2020 block counts
#       POP100 / POP100_all for the share of each area inside the city)
#   registry.csv                                   the current file and vintages
#   validation_demographics_<date>.json            checks, in the plan 8 format

suppressPackageStartupMessages({
  library(memequity)
  library(httr2)
})

args <- commandArgs(trailingOnly = TRUE)
acs_year <- if (length(args)) as.integer(args[1]) else 2024L
key <- Sys.getenv("CENSUS_API_KEY")
if (!nzchar(key)) stop("Set CENSUS_API_KEY (DECISIONS.md H12)", call. = FALSE)

geo_dir <- "geography"
out_dir <- file.path(geo_dir, "demographics")
STATE <- "47"; COUNTY <- "157"
SHELBY_POP_2020 <- 929744  # 2020 Census, Shelby County (P1_001N)
MEMPHIS_PLACE <- "48000"
# Tables whose universe is households or housing units: apportioned by 2020
# housing units instead of population.
HU_TABLES <- c("B11001", "B25002", "B25003", "B25044", "B28002")

log <- function(...) message(format(Sys.time(), "%H:%M:%S"), "  ", ...)
measures <- demographic_measures(geo_dir)
vars <- sort(unique(unlist(strsplit(c(measures$numerator, measures$denominator), "+", fixed = TRUE))))
vars <- vars[nzchar(vars)]
hu_vars <- vars[substr(vars, 1, 6) %in% HU_TABLES]

# ---- ACS -----------------------------------------------------------------------

acs_get <- function(geo_for, geo_in = NULL) {
  get <- paste(c(paste0(vars, "E"), paste0(vars, "M")), collapse = ",")
  req <- request(sprintf("https://api.census.gov/data/%d/acs/acs5", acs_year)) |>
    req_url_query(get = get, `for` = geo_for, key = key) |>
    req_retry(max_tries = 4) |>
    req_timeout(120)
  if (!is.null(geo_in)) req <- req_url_query(req, `in` = geo_in)
  j <- jsonlite::fromJSON(resp_body_string(req_perform(req)))
  d <- as.data.frame(j[-1, , drop = FALSE], stringsAsFactors = FALSE)
  names(d) <- j[1, ]
  d
}

# Long format with the Census annotation codes resolved: a negative estimate
# means "not available"; MOE -555555555 means the estimate is controlled
# (exact, MOE 0); other negative MOEs mean no MOE could be computed.
acs_long <- function(d, id) {
  do.call(rbind, lapply(vars, function(v) {
    e <- as.numeric(d[[paste0(v, "E")]])
    m <- as.numeric(d[[paste0(v, "M")]])
    e[e < 0] <- NA
    m[m == -555555555] <- 0
    m[m < 0] <- NA
    data.frame(id = id, variable = v, estimate = e, moe = m, stringsAsFactors = FALSE)
  }))
}

log("fetching ACS ", acs_year, " 5-year block groups")
bg_raw <- acs_get("block group:*", sprintf("state:%s county:%s", STATE, COUNTY))
bg_raw$GEOID <- paste0(bg_raw$state, bg_raw$county, bg_raw$tract, bg_raw$`block group`)
bg <- acs_long(bg_raw, bg_raw$GEOID)
names(bg)[1] <- "bg"
# Aggregates such as income are "not available" in block groups with no
# residents (airport, parks); there the true value is 0. Any other missing
# value is left missing and fails the checks below.
empty_bg <- bg$bg[bg$variable == "B01003_001" & bg$estimate %in% 0]
fill <- is.na(bg$estimate) & bg$bg %in% empty_bg
bg$estimate[fill] <- 0
bg$moe[fill] <- 0
log(nrow(bg_raw), " block groups; ", sum(fill), " values set to 0 in ", length(empty_bg),
    " block groups with no residents")

log("fetching ACS reference totals (county, city, tracts)")
county_ref <- acs_long(acs_get(sprintf("county:%s", COUNTY), sprintf("state:%s", STATE)), "county")
place_ref <- acs_long(acs_get(sprintf("place:%s", MEMPHIS_PLACE), sprintf("state:%s", STATE)), "city")
tr <- acs_get("tract:*", sprintf("state:%s county:%s", STATE, COUNTY))
tract_ref <- acs_long(tr, paste0(tr$state, tr$county, tr$tract))

# ---- 2020 blocks ------------------------------------------------------------------

log("fetching 2020 Census blocks")
blocks <- local({
  url <- "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_Census2020/MapServer/10/query"
  parts <- list(); offset <- 0; page <- 5000
  repeat {
    j <- request(url) |>
      req_url_query(where = sprintf("STATE='%s' AND COUNTY='%s'", STATE, COUNTY),
                    outFields = "GEOID,POP100,HU100,INTPTLAT,INTPTLON", returnGeometry = "false",
                    orderByFields = "GEOID", f = "json", resultOffset = offset,
                    resultRecordCount = page) |>
      req_retry(max_tries = 4) |> req_timeout(300) |> req_perform() |>
      resp_body_string() |> jsonlite::fromJSON()
    a <- j$features$attributes
    if (is.null(a) || !nrow(a)) break
    parts[[length(parts) + 1]] <- a
    if (nrow(a) < page) break
    offset <- offset + page
  }
  b <- do.call(rbind, parts)
  data.frame(block = b$GEOID, bg = substr(b$GEOID, 1, 12), tract = substr(b$GEOID, 1, 11),
             pop = as.numeric(b$POP100), hu = as.numeric(b$HU100),
             longitude = as.numeric(b$INTPTLON), latitude = as.numeric(b$INTPTLAT),
             stringsAsFactors = FALSE)
})
log(nrow(blocks), " blocks, 2020 population ", format(sum(blocks$pop), big.mark = ","))

# Each block's share of its block group. A block group with no 2020
# population (or housing) is split evenly across its blocks.
share <- function(x, g) {
  tot <- ave(x, g, FUN = sum)
  cnt <- ave(rep(1, length(x)), g, FUN = sum)
  ifelse(tot > 0, x / tot, 1 / cnt)
}
blocks$weight_pop <- share(blocks$pop, blocks$bg)
blocks$weight_hu <- share(blocks$hu, blocks$bg)

# ---- assign blocks to areas ---------------------------------------------------------

log("assigning blocks to areas")
pts <- points_from_lonlat(blocks)
for (g in c("citywide", "zcta", "council_district", "super_district", "commission_district"))
  pts <- assign_geography(pts, load_boundaries(g, geo_dir), g)
blk <- sf::st_drop_geometry(pts)
rn <- reference_neighborhoods(geo_dir)
blk$reference_neighborhood <- rn$neighborhood[match(blk$zcta, rn$zip)]
in_city <- !is.na(blk$citywide)

# Areas are restricted to the part inside the city; tracts and ZIP codes can
# extend past the city limits.
geo_cols <- c("citywide", "zcta", "tract", "council_district", "super_district",
              "commission_district", "reference_neighborhood")
city_blk <- blk
for (g in geo_cols) city_blk[[g]][!in_city] <- NA
components <- apportion_block_groups(bg, city_blk, geo_cols, hu_vars)
# Whole-area apportionment, used only for the checks below.
all_blk <- blk; all_blk$county <- "county"
whole <- apportion_block_groups(bg, all_blk, c("county", "tract"), hu_vars)

# 2020 population inside the city and in the whole area, so each area's
# coverage (e.g. a ZIP code mostly outside the city) is visible.
pop_rows <- do.call(rbind, lapply(geo_cols, function(g) {
  a <- tapply(blk$pop[in_city], blk[[g]][in_city], sum)
  all <- tapply(blk$pop, blk[[g]], sum)
  rbind(data.frame(geo_type = g, geo_id = names(a), variable = "POP100", estimate = as.numeric(a), moe = 0),
        data.frame(geo_type = g, geo_id = names(a), variable = "POP100_all",
                   estimate = as.numeric(all[names(a)]), moe = 0))
}))
components <- rbind(components, pop_rows)
components <- components[order(components$geo_type, components$geo_id, components$variable), ]

# ---- checks ------------------------------------------------------------------------------

rep <- validation_report("demographics", Sys.Date(),
                         source = sprintf("Census ACS %d 5-year block groups; 2020 Census blocks (TIGERweb)", acs_year))
rep <- add_count(rep, "block_groups", nrow(bg_raw))
rep <- add_count(rep, "blocks", nrow(blocks))
rep <- add_count(rep, "blocks_in_city", sum(in_city))
rep <- add_count(rep, "values_zeroed_in_empty_block_groups", sum(fill))
rep <- add_check(rep, "no block-group estimate is missing", "completeness",
                 !anyNA(bg$estimate) && !anyNA(bg$moe),
                 list(missing = unique(bg$variable[is.na(bg$estimate) | is.na(bg$moe)])))
rep <- add_check(rep, "2020 block population matches the 2020 Census county total", "reconciliation",
                 sum(blocks$pop) == SHELBY_POP_2020,
                 list(blocks = sum(blocks$pop), census = SHELBY_POP_2020))
rep <- add_check(rep, "every ACS block group has 2020 blocks", "referential",
                 all(bg_raw$GEOID %in% blocks$bg),
                 list(missing = setdiff(bg_raw$GEOID, blocks$bg)))
rep <- add_check(rep, "every block's block group is in the ACS", "referential",
                 all(blocks$bg %in% bg_raw$GEOID),
                 list(missing = head(setdiff(blocks$bg, bg_raw$GEOID), 20)))
wsum <- tapply(blocks$weight_pop, blocks$bg, sum)
rep <- add_check(rep, "block weights sum to 1 in every block group", "consistency",
                 all(abs(wsum - 1) < 1e-9))

# Block groups nest exactly in counties and tracts, so whole-area
# apportionment must reproduce the published county and tract estimates.
# Aggregate income is published rounded (to the nearest $100), so its sums
# may differ by rounding; counts must match exactly.
cmp <- function(ours, ref) {
  m <- merge(ours, ref, by = c("id", "variable"), suffixes = c("_ours", "_ref"))
  m <- m[!is.na(m$estimate_ref), ]
  m$ok <- abs(m$estimate_ours - m$estimate_ref) <= 0.5 |
    (m$variable == "B19313_001" & abs(m$estimate_ours / m$estimate_ref - 1) <= 1e-5)
  m
}
wc <- whole[whole$geo_type == "county", ]
cc <- cmp(data.frame(id = "county", variable = wc$variable, estimate = wc$estimate), county_ref)
rep <- add_check(rep, "block-group sums reproduce the county estimates", "reconciliation",
                 all(cc$ok), list(variables_off = unique(cc$variable[!cc$ok])))
wt <- whole[whole$geo_type == "tract", ]
tc <- cmp(data.frame(id = wt$geo_id, variable = wt$variable, estimate = wt$estimate), tract_ref)
rep <- add_check(rep, "block-group sums reproduce every tract estimate", "reconciliation",
                 all(tc$ok), list(tracts = length(unique(tc$id)), variables_off = unique(tc$variable[!tc$ok]),
                                  max_income_gap = max(abs(tc$estimate_ours - tc$estimate_ref)[tc$variable == "B19313_001"])))

# The city is not built from block groups, so its total can differ from the
# published place estimate: 2020 blocks vs the current city boundary, and
# population change inside split block groups.
city_pop <- components$estimate[components$geo_type == "citywide" & components$variable == "B01003_001"]
place_pop <- place_ref$estimate[place_ref$variable == "B01003_001"]
gap <- city_pop / place_pop - 1
rep <- add_check(rep, "city population within 2% of the published Memphis estimate", "reconciliation",
                 abs(gap) <= 0.02,
                 list(apportioned = round(city_pop), published = place_pop, relative_gap = round(gap, 4)))
for (g in c("council_district", "super_district")) {
  tot <- sum(components$estimate[components$geo_type == g & components$variable == "B01003_001"])
  rep <- add_check(rep, sprintf("%s populations sum to the city total (within 0.5%%)", g), "consistency",
                   abs(tot / city_pop - 1) <= 0.005,
                   list(sum = round(tot), city = round(city_pop)))
}
rep <- add_check(rep, "no block inside the city is left without a council district", "referential",
                 !any(in_city & is.na(blk$council_district) & blk$pop > 0),
                 list(blocks = sum(in_city & is.na(blk$council_district) & blk$pop > 0)),
                 severity = "warning")

rep <- finalize_report(rep)
path <- write_validation_report(rep, out_dir)
log("validation: ", rep$status, " -> ", path)
stop_if_failed(rep)

# ---- write ---------------------------------------------------------------------------------

file <- sprintf("components_census-acs5-%d_blocks-2020.csv", acs_year)
old <- setdiff(list.files(out_dir, pattern = "^components_.*\\.csv$"), file)
unlink(file.path(out_dir, old))  # superseded vintages stay in git history
components$estimate <- round(components$estimate, 3)
components$moe <- round(components$moe, 3)
utils::write.csv(components, file.path(out_dir, file), row.names = FALSE)
utils::write.csv(data.frame(
  file = file,
  source = sprintf("Census ACS %d 5-year (%d-%d) block groups, api.census.gov", acs_year, acs_year - 4, acs_year),
  acs_vintage = sprintf("%d-%d", acs_year - 4, acs_year),
  weights = "2020 Census blocks POP100/HU100, TIGERweb tigerWMS_Census2020 layer 10",
  universe = "Part of each area inside the City of Memphis",
  fetched = format(Sys.Date())), file.path(out_dir, "registry.csv"), row.names = FALSE)
log("wrote ", file.path(out_dir, file), " (", nrow(components), " rows)")
