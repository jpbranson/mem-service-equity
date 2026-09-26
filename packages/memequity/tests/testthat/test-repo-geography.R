# Integration tests against the committed boundary files in geography/.
repo_geo <- function() {
  d <- normalizePath(file.path(testthat::test_path(), "..", "..", "..", "..", "geography"),
                     mustWork = FALSE)
  if (!file.exists(file.path(d, "boundaries", "registry.csv"))) testthat::skip("no geography/ dir")
  d
}

test_that("every registered boundary set loads with unique, non-missing ids", {
  d <- repo_geo()
  reg <- boundary_registry(d)
  for (g in reg$geo_type) {
    b <- load_boundaries(g, d)
    expect_gt(nrow(b), 0)
    expect_false(anyNA(b$geo_id), info = g)
    expect_false(anyDuplicated(b$geo_id) > 0, info = g)
    expect_true(all(sf::st_is_valid(b)), info = g)
  }
})

test_that("a known address lands in the right ZCTA, tract and city", {
  d <- repo_geo()
  # 125 N Main St, Memphis TN 38103, as geocoded by the Census geocoder:
  # ZCTA 38103, tract 47157004200.
  p <- points_from_lonlat(data.frame(id = 1, longitude = -90.051553690438, latitude = 35.148558377868))
  p <- assign_geography(p, load_boundaries("zcta", d), "zcta")
  p <- assign_geography(p, load_boundaries("tract", d), "tract")
  p <- assign_geography(p, load_boundaries("citywide", d), "city")
  expect_equal(p$zcta, "38103")
  expect_equal(p$tract, "47157004200")
  expect_equal(p$city, "4748000")
})

test_that("parcel counts cover every area and add up to the city total", {
  d <- repo_geo()
  skip_if_not(file.exists(file.path(d, "parcels", "registry.csv")), "no parcel counts yet")
  reg <- parcels_registry(d)
  expect_true(file.exists(file.path(d, "parcels", reg$file[1])))
  city <- area_parcels("citywide", d)
  expect_equal(nrow(city), 1)
  expect_equal(city$parcels, reg$parcels_in_city[1])
  for (g in c("zcta", "council_district", "super_district")) {
    a <- area_parcels(g, d)
    expect_false(anyDuplicated(a$geo_id) > 0, info = g)
    expect_true(all(a$geo_id %in% load_boundaries(g, d)$geo_id), info = g)
    # Each in-city parcel falls in at most one area of each set (D8). The
    # 2026 city line and the 2023 district map disagree on a few slivers, so
    # a handful can fall in none.
    expect_lte(sum(a$parcels), city$parcels)
    expect_gte(sum(a$parcels) / city$parcels, 0.9999)
  }
  expect_error(area_parcels("tract", d), "No parcel counts")
})

test_that("reference neighborhoods only use ZCTAs that exist", {
  d <- repo_geo()
  rn <- reference_neighborhoods(d)
  expect_true(all(rn$zip %in% load_boundaries("zcta", d)$geo_id))
  expect_gte(length(unique(rn$neighborhood)), 6)
  expect_lte(length(unique(rn$neighborhood)), 8)
})
