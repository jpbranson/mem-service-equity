# Fast spatial / spatio-temporal pair finding with a grid hash.
#
# GEOS distance queries are slow when many points share a few very detailed
# polygons, or when hundreds of records sit at one address. Hashing
# projected coordinates into `meters`-sized cells (and optionally time into
# `lag`-sized bins) turns neighbor search into equality joins.

#' Find pairs (i in A, j in B) with the same group, within `meters`
#' (projected coordinates), and, if times are given, with
#' `lag_min < t_b - t_a <= lag_max`.
#'
#' @return data.table with columns i, j, dist, and lag (if times given).
#' @export
grid_pairs <- function(ax, ay, bx, by, meters, ag = NULL, bg = NULL,
                       at = NULL, bt = NULL, lag_min = NULL, lag_max = NULL) {
  timed <- !is.null(at)
  A <- data.table::data.table(i = seq_along(ax), ax = ax, ay = ay,
                              g = if (is.null(ag)) 1L else ag,
                              cx = floor(ax / meters), cy = floor(ay / meters))
  B <- data.table::data.table(j = seq_along(bx), bx = bx, by = by,
                              g = if (is.null(bg)) 1L else bg,
                              cx = floor(bx / meters), cy = floor(by / meters))
  keys <- c("g", "cx", "cy")
  if (timed) {
    width <- lag_max - lag_min
    A[, at := at]; B[, bt := bt]
    B[, tb := floor(bt / width)]
    A[, tb0 := floor((at + lag_min) / width)]
    keys <- c(keys, "tb")
  }
  A <- A[!is.na(ax) & !is.na(ay)]
  B <- B[!is.na(bx) & !is.na(by)]
  out <- list()
  for (dx in -1:1) for (dy in -1:1) for (dt in if (timed) 0:1 else 0L) {
    q <- data.table::copy(A)
    q[, `:=`(cx = cx + dx, cy = cy + dy)]
    if (timed) q[, tb := tb0 + dt]
    m <- B[q, on = keys, nomatch = NULL, allow.cartesian = TRUE]
    if (!nrow(m)) next
    m[, dist := sqrt((bx - ax)^2 + (by - ay)^2)]
    m <- m[dist <= meters]
    if (timed) {
      m[, lag := bt - at]
      m <- m[lag > lag_min & lag <= lag_max]
      out[[length(out) + 1]] <- m[, list(i, j, dist, lag)]
    } else {
      out[[length(out) + 1]] <- m[, list(i, j, dist)]
    }
  }
  res <- data.table::rbindlist(out)
  if (!nrow(res)) {
    res <- data.table::data.table(i = integer(), j = integer(), dist = numeric())
    if (timed) res[, lag := numeric()]
  }
  unique(res, by = c("i", "j"))
}

#' Projected (meter) coordinates of an sf/sfc point layer; NA for empty points.
#' @export
xy_meters <- function(points) {
  g <- sf::st_transform(sf::st_geometry(points), MSE_CRS_METERS)
  empty <- sf::st_is_empty(g)
  out <- matrix(NA_real_, length(g), 2)
  if (any(!empty)) out[!empty, ] <- sf::st_coordinates(g[!empty])[, 1:2]
  out
}
