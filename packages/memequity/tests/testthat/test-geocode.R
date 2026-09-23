test_that("census batch responses parse into match qualities", {
  txt <- paste(
    '"1","125 N Main St, Memphis, TN, 38103","Match","Exact","125 N MAIN ST, MEMPHIS, TN, 38103","-90.05,35.14","123","L"',
    '"2","9999 Nowhere Rd, Memphis, TN, ","No_Match"',
    '"3","100 Poplar, Memphis, TN, ","Match","Non_Exact","100 POPLAR AVE, MEMPHIS, TN, 38103","-90.04,35.15","456","R"',
    '"4","1 Main, Memphis, TN, ","Tie"',
    sep = "\n")
  p <- parse_census_batch(txt)
  expect_equal(p$match_quality, c("exact", "no_match", "non_exact", "tie"))
  expect_equal(p$longitude[1], -90.05)
  expect_true(is.na(p$latitude[2]))
})

test_that("addresses normalise to stable cache keys", {
  expect_equal(normalize_address(" 125 n. Main St., Memphis,  TN "),
               normalize_address("125 N MAIN ST MEMPHIS TN"))
})

test_that("cached addresses are served without a network call", {
  d <- withr::local_tempdir()
  cache <- file.path(d, "cache.csv")
  write.csv(data.frame(address_key = normalize_address("125 N Main St Memphis TN 38103"),
                       longitude = -90.05, latitude = 35.14, match_quality = "exact",
                       matched_address = "125 N MAIN ST", geocoder = "census",
                       geocoded_at = "2026-09-23T00:00:00Z"), cache, row.names = FALSE)
  g <- geocode_addresses("125 N Main St", zip = "38103", cache_path = cache)
  expect_equal(g$match_quality, "exact")
  expect_equal(g$longitude, -90.05)
})
