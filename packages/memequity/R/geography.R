# Shared geography layer (design plan section 7).

#' Projected CRS used for all distance work: NAD83 / Tennessee (meters).
#' @export
MSE_CRS_METERS <- 32136L

#' Geographic CRS for storage and display.
#' @export
MSE_CRS_LONLAT <- 4326L

METERS_PER_MILE <- 1609.344

#' Convert miles to meters.
#' @export
miles_to_m <- function(miles) miles * METERS_PER_MILE

#' Locate the repository's geography directory.
#'
#' Uses the MSE_GEOGRAPHY_DIR environment variable if set, otherwise walks up
#' from the working directory looking for `geography/boundaries`.
#' @export
geography_dir <- function() {
  env <- Sys.getenv("MSE_GEOGRAPHY_DIR")
  if (nzchar(env)) return(normalizePath(env, mustWork = TRUE))
  d <- normalizePath(getwd())
  repeat {
    cand <- file.path(d, "geography")
    if (dir.exists(file.path(cand, "boundaries"))) return(cand)
    parent <- dirname(d)
    if (parent == d) stop("Could not find geography/ directory; set MSE_GEOGRAPHY_DIR", call. = FALSE)
    d <- parent
  }
}

#' The boundary registry: one row per boundary set with its file, id field,
#' source and vintage.
#' @export
boundary_registry <- function(dir = geography_dir()) {
  path <- file.path(dir, "boundaries", "registry.csv")
  utils::read.csv(path, stringsAsFactors = FALSE)
}

#' Load one boundary set as an sf object with a standard `geo_id` column.
#' @export
load_boundaries <- function(geo_type, dir = geography_dir()) {
  reg <- boundary_registry(dir)
  row <- reg[reg$geo_type == geo_type, ]
  if (nrow(row) != 1) stop("Unknown or ambiguous geo_type: ", geo_type, call. = FALSE)
  b <- sf::st_read(file.path(dir, "boundaries", row$file), quiet = TRUE)
  b$geo_id <- as.character(b[[row$id_field]])
  b <- b[, c("geo_id", setdiff(names(b), c("geo_id", attr(b, "sf_column"))))]
  # Coordinate rounding on write can introduce slivers; repair on read.
  sf::st_make_valid(sf::st_transform(b, MSE_CRS_LONLAT))
}

#' Build an sf point layer from longitude/latitude columns.
#'
#' Rows with missing or zero coordinates are kept as empty geometries and
#' flagged `located = FALSE`, so the unlocated count can be published.
#' @export
points_from_lonlat <- function(df, lon = "longitude", lat = "latitude") {
  x <- suppressWarnings(as.numeric(df[[lon]]))
  y <- suppressWarnings(as.numeric(df[[lat]]))
  located <- !is.na(x) & !is.na(y) & x != 0 & y != 0
  geoms <- lapply(seq_along(x), function(i)
    if (located[i]) sf::st_point(c(x[i], y[i])) else sf::st_point())
  df$located <- located
  sf::st_sf(df, geometry = sf::st_sfc(geoms, crs = MSE_CRS_LONLAT))
}

#' Assign each point to a polygon of one boundary set.
#'
#' Adds `<prefix>` (the geo_id) and `<prefix>_on_boundary`.
#'
#' Rule: a point within `tolerance_m` of more than one polygon is "on the
#' boundary"; it is assigned deterministically to the lowest geo_id among
#' those polygons and flagged. A point outside every polygon but within the
#' tolerance of one (a sliver gap between generalized boundaries) is assigned
#' to it and flagged. Otherwise the containing polygon is used; points in no
#' polygon get NA ("unassigned").
#' @export
assign_geography <- function(points, polygons, prefix, tolerance_m = 1) {
  pts <- sf::st_transform(sf::st_geometry(points), MSE_CRS_METERS)
  polys <- sf::st_transform(sf::st_geometry(polygons), MSE_CRS_METERS)
  n <- length(pts)
  empty <- sf::st_is_empty(pts)
  # Containment: polygons as the first argument are prepared once, which is
  # far faster than testing each point against detailed boundaries.
  inside <- invert_index(sf::st_intersects(polys, pts), n)
  # Points near a boundary: densify boundaries so vertices are at most
  # `spacing` apart, grid-join points to vertices, then run the exact
  # distance test only on those few candidates.
  spacing <- 20
  bnd <- sf::st_segmentize(sf::st_boundary(sf::st_cast(polys, "MULTIPOLYGON")), spacing)
  v <- sf::st_coordinates(bnd)
  xy <- xy_meters(pts)
  pr <- grid_pairs(xy[, 1], xy[, 2], v[, 1], v[, 2], meters = tolerance_m + spacing)
  cand <- sort(unique(pr$i))
  near <- inside
  if (length(cand)) {
    close <- sf::st_is_within_distance(pts[cand], polys, dist = tolerance_m)
    near[cand] <- mapply(function(a, b) sort(unique(c(a, b))), inside[cand], close,
                         SIMPLIFY = FALSE)
  }
  inside[empty] <- list(integer())
  near[empty] <- list(integer())
  ids <- polygons$geo_id
  pick <- function(i) {
    c <- if (length(near[[i]]) > 1 || !length(inside[[i]])) near[[i]] else inside[[i]]
    if (length(c)) sort(ids[c])[1] else NA_character_
  }
  points[[prefix]] <- vapply(seq_len(n), pick, character(1))
  points[[paste0(prefix, "_on_boundary")]] <- lengths(near) > 1 |
    (lengths(inside) == 0 & lengths(near) > 0)
  points
}

# Turn a polygon -> points sparse index into a point -> polygons list.
invert_index <- function(idx, n) {
  poly <- rep(seq_along(idx), lengths(idx))
  pt <- unlist(idx)
  out <- vector("list", n)
  out[] <- list(integer())
  if (length(pt)) {
    s <- split(poly, pt)
    out[as.integer(names(s))] <- s
  }
  out
}

#' Summarise assignment coverage: counts assigned, unassigned, unlocated and
#' on-boundary, for publication in the validation report.
#' @export
assignment_summary <- function(points, prefix) {
  located <- if ("located" %in% names(points)) points$located else rep(TRUE, nrow(points))
  list(
    geo_type = prefix,
    total = nrow(points),
    unlocated = sum(!located),
    unassigned = sum(located & is.na(points[[prefix]])),
    on_boundary = sum(points[[paste0(prefix, "_on_boundary")]], na.rm = TRUE)
  )
}

#' Select points within a straight-line radius of an origin.
#'
#' @param origin an sf/sfc point (any CRS) or c(lon, lat).
#' @param meters radius in meters.
#' @export
points_within_radius <- function(points, origin, meters) {
  if (is.numeric(origin)) origin <- sf::st_sfc(sf::st_point(origin), crs = MSE_CRS_LONLAT)
  o <- sf::st_transform(sf::st_geometry(origin), MSE_CRS_METERS)
  p <- sf::st_transform(points, MSE_CRS_METERS)
  keep <- as.vector(sf::st_is_within_distance(p, o, dist = meters, sparse = FALSE)[, 1])
  keep[sf::st_is_empty(p)] <- FALSE
  points[keep, ]
}

#' H3 cell index for each point (resolution 8 by default).
#' @export
h3_cell <- function(points, res = 8L) {
  if (!requireNamespace("h3jsr", quietly = TRUE))
    stop("Package h3jsr is required for hex indexing", call. = FALSE)
  out <- rep(NA_character_, nrow(points))
  ok <- !sf::st_is_empty(points)
  if (any(ok)) out[ok] <- h3jsr::point_to_cell(sf::st_transform(points[ok, ], MSE_CRS_LONLAT),
                                               res = res, simple = TRUE)
  out
}

#' Reference neighborhoods (design plan section 7): named ZIP groupings used
#' as comparison anchors in every view.
#' @export
reference_neighborhoods <- function(dir = geography_dir()) {
  utils::read.csv(file.path(dir, "reference_neighborhoods.csv"),
                  stringsAsFactors = FALSE, colClasses = "character")
}
