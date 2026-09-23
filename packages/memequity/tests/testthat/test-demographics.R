test_that("ACS margin-of-error formulas give the Census approximations", {
  expect_equal(acs_moe_sum(c(3, 4)), 5)
  # Proportion: p = 0.2, sqrt(5^2 - 0.2^2 * 10^2) / 100
  expect_equal(acs_moe_prop(20, 100, 5, 10), sqrt(21) / 100)
  # Negative radicand falls back to the ratio formula.
  expect_equal(acs_moe_prop(50, 100, 2, 10), sqrt(4 + 0.25 * 100) / 100)
  expect_equal(acs_moe_ratio(50, 100, 2, 10), sqrt(4 + 0.25 * 100) / 100)
})

test_that("reliability classes follow the CV thresholds", {
  expect_equal(acs_reliability(c(100, 100, 100, 100, 0), c(10, 50, 100, 0, 5)),
               c("high", "medium", "low", "high", NA))
})

test_that("apportionment sums correlated pieces before combining block groups", {
  bg <- data.frame(bg = c("1", "2", "1", "2"), variable = c("P", "P", "H", "H"),
                   estimate = c(100, 50, 40, 20), moe = c(30, 40, 10, 10))
  blocks <- data.frame(bg = c("1", "1", "2", "2"),
                       weight_pop = c(0.5, 0.5, 0.2, 0.8), weight_hu = c(0.5, 0.5, 0.5, 0.5),
                       area = c("X", "X", "X", "Y"))
  a <- apportion_block_groups(bg, blocks, "area", hu_vars = "H")
  get <- function(id, v, col) a[[col]][a$geo_id == id & a$variable == v]
  # Both halves of block group 1 are in X: its full MOE counts once.
  expect_equal(get("X", "P", "estimate"), 110)
  expect_equal(get("X", "P", "moe"), sqrt(30^2 + 8^2))
  expect_equal(get("Y", "P", "estimate"), 40)
  expect_equal(get("Y", "P", "moe"), 32)
  # Housing variables use housing-unit weights.
  expect_equal(get("X", "H", "estimate"), 40 + 10)
  expect_equal(get("Y", "H", "estimate"), 10)
  # A missing estimate propagates instead of shrinking the total.
  bg$estimate[2] <- NA
  a <- apportion_block_groups(bg, blocks, "area", hu_vars = "H")
  expect_true(is.na(get("X", "P", "estimate")))
})

test_that("measures are derived from components with their margins of error", {
  comp <- data.frame(geo_type = "zcta", geo_id = "38103",
                     variable = c("T", "A", "B"), estimate = c(100, 15, 5), moe = c(10, 3, 4))
  ms <- data.frame(id = c("total", "share"), label = "", unit = c("count", "proportion"),
                   numerator = c("T", "A+B"), denominator = c("", "T"), note = "")
  d <- derive_demographics(comp, ms)
  expect_equal(d$value[d$measure == "total"], 100)
  expect_equal(d$moe[d$measure == "total"], 10)
  expect_equal(d$value[d$measure == "share"], 0.2)
  expect_equal(d$moe[d$measure == "share"], acs_moe_prop(20, 100, 5, 10))
  expect_error(derive_demographics(rbind(comp, comp), ms), "one row per area")
})

# ---- committed demographics (geography/demographics/) ---------------------------

repo_demo <- function() {
  d <- normalizePath(file.path(testthat::test_path(), "..", "..", "..", "..", "geography"),
                     mustWork = FALSE)
  if (!file.exists(file.path(d, "demographics", "registry.csv"))) testthat::skip("no demographics")
  d
}

test_that("committed demographics load for every geography with every measure", {
  d <- repo_demo()
  comp <- load_demographic_components(dir = d)
  ms <- demographic_measures(d)
  for (g in c("citywide", "zcta", "tract", "council_district", "super_district",
              "commission_district", "reference_neighborhood")) {
    x <- load_demographics(g, d)
    expect_setequal(unique(x$measure), ms$id)
    expect_false(anyNA(x$value[x$measure == "population"]), info = g)
  }
  expect_setequal(load_demographics("council_district", d)$geo_id, as.character(1:7))
  pop <- comp[comp$variable %in% c("POP100", "POP100_all"), ]
  w <- reshape(pop[, c("geo_type", "geo_id", "variable", "estimate")], direction = "wide",
               idvar = c("geo_type", "geo_id"), timevar = "variable")
  expect_true(all(w$estimate.POP100 <= w$estimate.POP100_all))
})

test_that("reference neighborhoods in the demographics match the current ZIP groupings", {
  # If this fails, geography/reference_neighborhoods.csv changed (H9): rerun
  # geography/fetch_demographics.R.
  d <- repo_demo()
  rn <- reference_neighborhoods(d)
  comp <- load_demographic_components(dir = d)
  pop <- function(g, ids) sum(comp$estimate[comp$geo_type == g & comp$geo_id %in% ids &
                                              comp$variable == "POP100"])
  for (n in unique(rn$neighborhood))
    expect_equal(pop("reference_neighborhood", n), pop("zcta", rn$zip[rn$neighborhood == n]), info = n)
})
