# Arrival inference at timepoint stops (spec on_time_pct). Each report on a
# matched trip is projected onto the trip's shape. The arrival at a stop is
# the moment the vehicle's distance along the shape reaches the stop's,
# interpolated linearly between the two reports that bracket it. Reports
# come about every 30 s, so a bus passing a stop without stopping is still
# timed, to within the bracket.

MAX_OFF_SHAPE_M <- 60   # reports further than this from the shape are ignored
MAX_BRACKET_S <- 180    # bracketing reports further apart leave the arrival unobserved
BACKTRACK_M <- 300      # how far back along the shape a report may project (GPS noise)

project_xy <- function(lon, lat) {
  pts <- sf::st_as_sf(data.frame(lon = lon, lat = lat), coords = c("lon", "lat"),
                      crs = memequity::MSE_CRS_LONLAT)
  sf::st_coordinates(sf::st_transform(pts, memequity::MSE_CRS_METERS))
}

#' Shape vertices in projected metres with cumulative distance. GTFS
#' shape_dist_traveled is in metres but runs about 0.3% longer than the
#' projected length, so stop distances are rescaled to the projected length.
prepare_shape <- function(shape_pts) {
  s <- shape_pts[order(shape_pt_sequence)]
  xy <- project_xy(s$shape_pt_lon, s$shape_pt_lat)
  seg <- sqrt(diff(xy[, 1])^2 + diff(xy[, 2])^2)
  list(x = xy[, 1], y = xy[, 2], cum = c(0, cumsum(seg)),
       scale = sum(seg) / max(s$shape_dist_traveled, na.rm = TRUE))
}

#' Nearest point on the shape at or beyond `min_along` metres.
project_on_shape <- function(sh, px, py, min_along = -Inf) {
  n <- length(sh$x)
  x1 <- sh$x[-n]; y1 <- sh$y[-n]; dx <- sh$x[-1] - x1; dy <- sh$y[-1] - y1
  l2 <- dx^2 + dy^2
  u <- pmin(1, pmax(0, ((px - x1) * dx + (py - y1) * dy) / ifelse(l2 == 0, 1, l2)))
  along <- sh$cum[-n] + u * sqrt(l2)
  d <- sqrt((px - x1 - u * dx)^2 + (py - y1 - u * dy)^2)
  d[along < min_along] <- Inf
  k <- which.min(d)
  c(along = along[k], off = d[k])
}

#' Distance along the shape for each report of one trip (in time order).
#' Projection is sequential so a route that doubles back is not confused:
#' each report may not project more than BACKTRACK_M behind the furthest
#' point reached so far. Reports off the shape get NA.
trip_progress <- function(sh, x, y) {
  along <- rep(NA_real_, length(x))
  reached <- -Inf
  for (i in seq_along(x)) {
    r <- project_on_shape(sh, x[i], y[i], min_along = reached - BACKTRACK_M)
    if (r[["off"]] <= MAX_OFF_SHAPE_M) {
      reached <- max(reached, r[["along"]])
      along[i] <- reached          # progress never goes backwards
    }
  }
  along
}

NEAR_STOP_M <- 30       # a vehicle that stops this close short of a stop has reached it

#' Interpolated time (seconds) at which `progress` first reaches each of
#' `stop_along`; NA when unobserved. A vehicle can halt just short of a stop,
#' typically at a terminal at the end of the shape. If it never crosses the
#' stop but comes within NEAR_STOP_M, the first report that close is the
#' arrival (not interpolated, so accurate to one report interval).
crossing_times <- function(t, progress, stop_along) {
  ok <- !is.na(progress)
  t <- t[ok]; a <- progress[ok]
  vapply(stop_along, function(D) {
    j <- which(a >= D - 0.5)[1]                 # 0.5 m absorbs rounding at the shape's end
    if (is.na(j)) {
      near <- which(a >= D - NEAR_STOP_M)[1]
      if (is.na(near) || near == 1 || t[near] - t[near - 1] > MAX_BRACKET_S) return(NA_real_)
      return(t[near])
    }
    if (j == 1) return(NA_real_)                # first seen already past the stop
    i <- j - 1
    if (t[j] - t[i] > MAX_BRACKET_S) return(NA_real_)
    if (a[j] <= a[i]) return(t[j])
    t[i] + (min(D, a[j]) - a[i]) / (a[j] - a[i]) * (t[j] - t[i])
  }, numeric(1))
}

#' Inferred arrivals at the timepoint stops of every observed, measurable
#' trip. The first stop of a trip is left out: a bus waits there before it
#' departs, so an arrival time says nothing about punctuality.
infer_arrivals <- function(matched, sched_stop_times, pos, g) {
  trips <- matched[observed == TRUE & measurable == TRUE]
  if (!nrow(trips)) return(data.table())
  shapes <- split(g$shapes, by = "shape_id", keep.by = TRUE)
  prepared <- new.env()
  xy <- project_xy(pos$lon, pos$lat)
  pos <- copy(pos)[, `:=`(x = xy[, 1], y = xy[, 2])]
  tp <- sched_stop_times[timepoint == TRUE & trip_id %in% trips$trip_id]
  setorder(tp, trip_id, stop_sequence)
  tp <- tp[, .SD[-1], by = trip_id]
  out <- vector("list", nrow(trips))
  for (k in seq_len(nrow(trips))) {
    tr <- trips[k]
    stops <- tp[trip_id == tr$trip_id]
    if (!nrow(stops) || is.na(tr$shape_id) || is.null(shapes[[tr$shape_id]])) next
    if (is.null(prepared[[tr$shape_id]])) prepared[[tr$shape_id]] <- prepare_shape(shapes[[tr$shape_id]])
    sh <- prepared[[tr$shape_id]]
    p <- pos[service_date == tr$service_date & trip_id == tr$trip_id]
    setorder(p, timestamp)
    arr <- crossing_times(p$timestamp, trip_progress(sh, p$x, p$y), stops$shape_dist_traveled * sh$scale)
    out[[k]] <- data.table(service_date = tr$service_date, trip_id = tr$trip_id, route_id = tr$route_id,
                           direction_id = tr$direction_id, stop_id = stops$stop_id,
                           stop_sequence = stops$stop_sequence, scheduled = stops$sched,
                           arrival = as.POSIXct(arr, origin = "1970-01-01", tz = "UTC"))
  }
  a <- rbindlist(out)
  if (nrow(a)) a[, delay_s := as.numeric(arrival) - as.numeric(scheduled)]
  a[]
}
