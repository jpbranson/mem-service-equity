# Spatial statistics, written out here rather than taken from spdep so the
# analysis needs nothing beyond the project's own dependencies. Formulas
# follow Moran (1950), Cliff & Ord (1981) for the analytic moments, Anselin
# (1995) for local Moran's I with conditional permutation, and Assuncao &
# Reis (1999) for the empirical-Bayes standardization of rates.

#' In-city part of each tract, in the project's meter CRS.
city_tracts <- function(ids, gd = memequity::geography_dir()) {
  crs <- memequity::MSE_CRS_METERS
  tr <- sf::st_transform(memequity::load_boundaries("tract", gd), crs)
  city <- sf::st_union(sf::st_transform(memequity::load_boundaries("citywide", gd), crs))
  tr <- tr[tr$geo_id %in% ids, "geo_id"]
  cut <- suppressWarnings(sf::st_intersection(tr, sf::st_sf(geometry = city)))
  # Intersections can return collections (polygons plus stray lines); keep
  # the polygon parts and merge them back into one feature per tract.
  cut <- suppressWarnings(sf::st_collection_extract(sf::st_make_valid(cut), "POLYGON"))
  parts <- split(sf::st_geometry(cut), cut$geo_id)
  out <- sf::st_sf(geo_id = names(parts),
                   geometry = sf::st_sfc(lapply(parts, function(g) sf::st_union(g)[[1]]), crs = crs))
  out$area_km2 <- as.numeric(sf::st_area(out)) / 1e6
  out[!sf::st_is_empty(out), ]
}

#' Neighbors: areas whose boundaries come within `tol_m` meters of each
#' other (queen contiguity with a small tolerance for boundary slivers). An
#' area with no neighbor gets its nearest area by centroid, so none is dropped.
nb_contiguity <- function(geom, tol_m = 10) {
  nb <- sf::st_is_within_distance(geom, geom, dist = tol_m)
  nb <- lapply(seq_along(nb), function(i) setdiff(nb[[i]], i))
  iso <- which(lengths(nb) == 0)
  if (length(iso)) {
    cen <- sf::st_coordinates(sf::st_point_on_surface(sf::st_geometry(geom)))
    for (i in iso) {
      dd <- sqrt(colSums((t(cen) - cen[i, ])^2)); dd[i] <- Inf
      nb[[i]] <- which.min(dd)
    }
  }
  attr(nb, "islands_linked") <- iso
  nb
}

#' Neighbors: the k nearest areas by representative point.
nb_knn <- function(geom, k = 6L) {
  cen <- sf::st_coordinates(sf::st_point_on_surface(sf::st_geometry(geom)))
  d <- as.matrix(stats::dist(cen)); diag(d) <- Inf
  lapply(seq_len(nrow(d)), function(i) order(d[i, ])[seq_len(k)])
}

#' Empirical-Bayes standardized ratio (Assuncao & Reis 1999).
#'
#' r = O / E. Under no geographic variation, r has mean b and sampling
#' variance null_var / E^2 (the outcome is binary, so null_var = sum p(1-p)
#' rather than the Poisson E). The between-area variance a is estimated by
#' moments; z = (r - b) / sqrt(a + sampling variance) puts large and small
#' areas on one scale, so small areas do not dominate the extremes.
eb_standardize <- function(observed, expected, null_var) {
  r <- observed / expected
  b <- sum(observed) / sum(expected)
  w <- expected / sum(expected)
  s2 <- sum(w * (r - b)^2)
  samp <- null_var / expected^2
  a <- max(0, s2 - sum(w * samp))
  z <- (r - b) / sqrt(a + samp)
  shrunk <- b + (a / (a + samp)) * (r - b)   # EB-smoothed ratio, for display only
  list(z = z, smoothed = shrunk, b = b, a = a)
}

# Row-standardized weights: each neighbor of i gets 1 / (number of neighbors).
lag_of <- function(x, nb) vapply(nb, function(j) mean(x[j]), numeric(1))

#' Global Moran's I with a permutation test and the analytic moments under
#' randomization (row-standardized weights).
moran_global <- function(x, nb, nsim = 9999L, seed = memequity:::DEFAULT_SEED) {
  n <- length(x)
  z <- x - mean(x)
  I <- sum(z * lag_of(z, nb)) / sum(z^2)
  W <- matrix(0, n, n)
  for (i in seq_len(n)) W[i, nb[[i]]] <- 1 / length(nb[[i]])
  S0 <- sum(W); S1 <- 0.5 * sum((W + t(W))^2); S2 <- sum((rowSums(W) + colSums(W))^2)
  EI <- -1 / (n - 1)
  k <- n * sum(z^4) / sum(z^2)^2
  VI <- (n * ((n^2 - 3 * n + 3) * S1 - n * S2 + 3 * S0^2) -
           k * ((n^2 - n) * S1 - 2 * n * S2 + 6 * S0^2)) /
    ((n - 1) * (n - 2) * (n - 3) * S0^2) - EI^2
  set.seed(seed)
  sims <- vapply(seq_len(nsim), function(s) {
    zp <- sample(z)
    sum(zp * lag_of(zp, nb)) / sum(zp^2)
  }, numeric(1))
  list(I = I, expected = EI, sd = sqrt(VI), z = (I - EI) / sqrt(VI),
       p_perm = (sum(sims >= I) + 1) / (nsim + 1), nsim = nsim, n = n,
       mean_neighbors = mean(lengths(nb)))
}

# nsim draws of k distinct values from 1..N (rejection of rows with repeats,
# which leaves every ordered k-subset equally likely).
draw_distinct <- function(nsim, k, N) {
  m <- matrix(sample.int(N, nsim * k, replace = TRUE), nsim, k)
  repeat {
    bad <- rep(FALSE, nsim)
    if (k > 1) for (a in 1:(k - 1)) for (b in (a + 1):k) bad <- bad | m[, a] == m[, b]
    if (!any(bad)) return(m)
    m[bad, ] <- matrix(sample.int(N, sum(bad) * k, replace = TRUE), sum(bad), k)
  }
}

#' Local Moran's I (Anselin 1995) with conditional permutation inference.
#'
#' Null model: holding area i's value fixed, the other n - 1 values are
#' randomly re-assigned to its neighbors. p is two-sided (twice the smaller
#' tail, with the +1 correction) and q is the Benjamini-Hochberg adjustment
#' over all areas tested.
lisa <- function(x, nb, nsim = 99999L, seed = memequity:::DEFAULT_SEED, alpha = 0.05) {
  n <- length(x)
  z <- x - mean(x)
  m2 <- sum(z^2) / n
  lagz <- lag_of(z, nb)
  Ii <- z * lagz / m2
  set.seed(seed)
  p <- numeric(n)
  for (i in seq_len(n)) {
    others <- z[-i]
    idx <- draw_distinct(nsim, length(nb[[i]]), n - 1)
    Ip <- z[i] * rowMeans(matrix(others[idx], nsim)) / m2
    lo <- sum(Ip <= Ii[i]); hi <- sum(Ip >= Ii[i])
    p[i] <- min(1, 2 * (min(lo, hi) + 1) / (nsim + 1))
  }
  q <- stats::p.adjust(p, "BH")
  quad <- ifelse(z > 0 & lagz > 0, "HH", ifelse(z < 0 & lagz < 0, "LL",
                 ifelse(z > 0, "HL", "LH")))
  cls <- ifelse(q < alpha, quad, ifelse(p < alpha, paste0(quad, "_unadj"), "ns"))
  data.frame(Ii = Ii, lag = lagz, z = z, p = p, q = q, quadrant = quad, class = cls,
             stringsAsFactors = FALSE)
}
