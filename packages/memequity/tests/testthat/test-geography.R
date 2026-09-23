test_that("points_from_lonlat flags unlocated rows", {
  df <- data.frame(id = 1:4, longitude = c(-90.05, NA, 0, "-90.03"), latitude = c(35.14, 35.14, 0, "35.14"))
  p <- points_from_lonlat(df)
  expect_equal(p$located, c(TRUE, FALSE, FALSE, TRUE))
  expect_equal(sum(sf::st_is_empty(p)), 2)
})

test_that("assign_geography handles interior, edge and outside points", {
  polys <- fixture_polygons()
  df <- data.frame(id = 1:5,
                   longitude = c(-90.05, -90.03, -90.04, -89.90, NA),
                   latitude = c(35.14, 35.14, 35.14, 35.14, NA))
  p <- assign_geography(points_from_lonlat(df), polys, "zcta")
  expect_equal(p$zcta, c("A", "B", "A", NA, NA))
  expect_equal(p$zcta_on_boundary, c(FALSE, FALSE, TRUE, FALSE, FALSE))
  s <- assignment_summary(p, "zcta")
  expect_equal(s$unlocated, 1)
  expect_equal(s$unassigned, 1)
  expect_equal(s$on_boundary, 1)
})

test_that("boundary assignment is invariant to polygon order", {
  polys <- fixture_polygons()
  df <- data.frame(id = 1, longitude = -90.04, latitude = 35.14)
  a <- assign_geography(points_from_lonlat(df), polys, "z")$z
  b <- assign_geography(points_from_lonlat(df), polys[2:1, ], "z")$z
  expect_equal(a, b)
})

test_that("points_within_radius uses true distance in meters", {
  # 0.01 degrees of latitude is ~1,110 m.
  df <- data.frame(id = 1:3, longitude = c(-90.05, -90.05, -90.05),
                   latitude = c(35.140, 35.149, 35.160))
  p <- points_from_lonlat(df)
  near <- points_within_radius(p, c(-90.05, 35.14), 1200)
  expect_equal(near$id, c(1, 2))
  expect_equal(nrow(points_within_radius(p, c(-90.05, 35.14), miles_to_m(0.25))), 1)
  expect_equal(miles_to_m(1), 1609.344)
})

test_that("load_boundaries reads the registry and standardises geo_id", {
  d <- fixture_geography_dir()
  b <- load_boundaries("zcta", d)
  expect_true("geo_id" %in% names(b))
  expect_setequal(b$geo_id, c("A", "B"))
  expect_error(load_boundaries("nope", d), "Unknown")
  expect_equal(reference_neighborhoods(d)$zip, "38103")
})

test_that("h3 cells are assigned and empty points stay NA", {
  skip_if_not_installed("h3jsr")
  df <- data.frame(id = 1:2, longitude = c(-90.05, NA), latitude = c(35.14, NA))
  cells <- h3_cell(points_from_lonlat(df), res = 8)
  expect_true(grepl("^88", cells[1]))
  expect_true(is.na(cells[2]))
})
