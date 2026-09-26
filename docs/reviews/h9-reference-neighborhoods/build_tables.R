# Evidence tables for the reference-neighborhood decision (DECISIONS.md H9).
# Nothing here changes geography/reference_neighborhoods.csv.
#
# Usage (from the repository root, after a 311 run):
#   Rscript docs/reviews/h9-reference-neighborhoods/build_tables.R [published_311_dir]

suppressPackageStartupMessages({
  library(memequity)
  library(sf)
})
args <- commandArgs(trailingOnly = TRUE)
d311 <- if (length(args)) args[1] else file.path("data", "published", "311")
out <- file.path("docs", "reviews", "h9-reference-neighborhoods")
UA <- "memphis-service-equity (https://github.com/jpbranson/mem-service-equity)"

rn <- reference_neighborhoods(geography_dir())
measures <- c("population", "pct_black_nh", "pct_white_nh", "pct_hispanic", "pct_poverty",
              "per_capita_income", "pct_renter", "pct_no_vehicle")
wide <- function(geo_type) {
  d <- load_demographics(geo_type)
  d <- d[d$measure %in% measures, ]
  w <- reshape(d[, c("geo_id", "measure", "value")], idvar = "geo_id", timevar = "measure",
               direction = "wide")
  names(w) <- sub("^value\\.", "", names(w))
  moe <- d[d$measure == "population", c("geo_id", "moe")]
  w$population_moe <- moe$moe[match(w$geo_id, moe$geo_id)]
  comp <- load_demographic_components(geo_type)
  pop <- comp[comp$variable == "POP100", ]; all <- comp[comp$variable == "POP100_all", ]
  w$share_2020_pop_in_city <- round(pop$estimate[match(w$geo_id, pop$geo_id)] /
                                      all$estimate[match(w$geo_id, all$geo_id)], 3)
  w
}
requests <- function(geo_type) {
  m <- utils::read.csv(file.path(d311, sprintf("metrics_311_by_%s.csv", geo_type)),
                       stringsAsFactors = FALSE, colClasses = c(geo_id = "character"))
  m <- m[m$metric == "requests_per_1000" & m$variant == "primary", ]
  m <- m[as.Date(m$window_end) - as.Date(m$window_start) + 1 == 365, ]
  if (!nrow(m)) stop("no 12-month requests_per_1000 rows in ", d311, call. = FALSE)
  r <- aggregate(list(requests_12m = m$n), list(geo_id = m$geo_id), sum)
  attr(r, "window") <- paste(m$window_start[1], "to", m$window_end[1])
  r
}
fmt <- function(w) {
  for (v in c("pct_black_nh", "pct_white_nh", "pct_hispanic", "pct_poverty", "pct_renter", "pct_no_vehicle"))
    w[[v]] <- round(100 * w[[v]], 1)
  w$per_capita_income <- round(w$per_capita_income, -2)
  w$population <- round(w$population, -1); w$population_moe <- round(w$population_moe, -1)
  w
}

# ---- ZIP codes ------------------------------------------------------------------
z <- wide("zcta")
rz <- requests("zcta")
z$requests_12m <- rz$requests_12m[match(z$geo_id, rz$geo_id)]
z$requests_per_1000 <- round(1000 * z$requests_12m / z$population, 1)
z$draft_neighborhood <- rn$neighborhood[match(z$geo_id, rn$zip)]
z <- fmt(z)
z <- z[order(-z$population), c("geo_id", "draft_neighborhood", "population", "population_moe",
                                "share_2020_pop_in_city", "pct_black_nh", "pct_white_nh", "pct_hispanic",
                                "pct_poverty", "per_capita_income", "pct_renter", "pct_no_vehicle",
                                "requests_12m", "requests_per_1000")]
names(z)[1] <- "zip"
utils::write.csv(z, file.path(out, "zip_table.csv"), row.names = FALSE, na = "")

# ---- draft neighborhoods and the city as a whole ------------------------------------
n <- wide("reference_neighborhood")
rr <- requests("reference_neighborhood")
n$requests_12m <- rr$requests_12m[match(n$geo_id, rr$geo_id)]
n$requests_per_1000 <- round(1000 * n$requests_12m / n$population, 1)
n$zips <- vapply(n$geo_id, function(g) paste(rn$zip[rn$neighborhood == g], collapse = " "), "")
city <- wide("citywide")
rc <- requests("citywide")
city$requests_12m <- rc$requests_12m[match(city$geo_id, rc$geo_id)]
city$requests_per_1000 <- round(1000 * city$requests_12m / city$population, 1)
city$zips <- "(all)"; city$geo_id <- "City of Memphis"
n <- fmt(rbind(n, city[, names(n)]))
n <- n[, c("geo_id", "zips", "population", "population_moe", "share_2020_pop_in_city", "pct_black_nh",
           "pct_white_nh", "pct_hispanic", "pct_poverty", "per_capita_income", "pct_renter",
           "pct_no_vehicle", "requests_12m", "requests_per_1000")]
names(n)[1] <- "neighborhood"
utils::write.csv(n, file.path(out, "neighborhood_table.csv"), row.names = FALSE, na = "")

# ---- CDC service areas (City layer) against ZIP codes --------------------------
url <- paste0("https://311.memphistn.gov/server/rest/services/City_of_Memphis_Neighborhoods_MIL1/",
              "MapServer/0/query?where=1%3D1&outFields=name&outSR=4326&f=geojson")
tmp <- tempfile(fileext = ".geojson")
resp <- httr2::request(url) |> httr2::req_user_agent(UA) |> httr2::req_perform()
writeBin(httr2::resp_body_raw(resp), tmp)
cdc <- st_make_valid(st_read(tmp, quiet = TRUE))
zc <- load_boundaries("zcta")
cdc_m <- st_transform(cdc, MSE_CRS_METERS); zc_m <- st_transform(zc, MSE_CRS_METERS)
cdc_m$area <- as.numeric(st_area(cdc_m))
ix <- suppressWarnings(st_intersection(cdc_m[, c("name", "area")], zc_m[, "geo_id"]))
ix$share <- as.numeric(st_area(ix)) / ix$area
ix <- st_drop_geometry(ix)
ix <- ix[ix$share >= 0.02, ]
ix <- ix[order(ix$name, -ix$share), ]
cw <- do.call(rbind, lapply(split(ix, ix$name), function(x) data.frame(
  cdc_service_area = x$name[1], area_km2 = round(x$area[1] / 1e6, 2),
  zips_by_area_share = paste(sprintf("%s %.0f%%", x$geo_id, 100 * x$share), collapse = "; "),
  draft_neighborhoods_touched = paste(sort(unique(na.omit(rn$neighborhood[match(x$geo_id, rn$zip)]))),
                                      collapse = "; "))))
utils::write.csv(cw, file.path(out, "cdc_service_areas_by_zip.csv"), row.names = FALSE)

cov <- sum(z$population[!is.na(z$draft_neighborhood)]) / sum(z$population)
message(sprintf("draft anchors cover %.0f%% of in-city residents; 311 window %s",
                100 * cov, attr(rz, "window")))
