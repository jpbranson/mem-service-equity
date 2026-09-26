skip_if_not_installed("httr2")

fake_perform <- function(bodies) {
  i <- 0
  function(req) {
    i <<- i + 1
    b <- bodies[[min(i, length(bodies))]]
    if (inherits(b, "error")) stop(b)
    httr2::response(status_code = 200, body = charToRaw(b))
  }
}
req <- httr2::request("https://example.invalid/query")

test_that("an ArcGIS error in a 200 body is retried, then the good page is returned", {
  waits <- integer()
  perform <- fake_perform(list(
    '{"error":{"code":400,"message":"User couldn\'t access this resource"}}',
    '{"count":408375}'))
  out <- arcgis_json(req, perform = perform, wait = function(i) waits <<- c(waits, i))
  expect_equal(out$count, 408375)
  expect_equal(waits, 1L)
})

test_that("dropped connections are retried too", {
  perform <- fake_perform(list(simpleError("Failure when receiving data from the peer"), '{"ok":true}'))
  expect_true(arcgis_json(req, perform = perform, wait = function(i) NULL)$ok)
})

test_that("persistent errors are raised after the last try", {
  perform <- fake_perform(list('{"error":{"message":"Failed to execute query."}}'))
  n <- 0
  expect_error(arcgis_json(req, tries = 3, perform = perform, wait = function(i) n <<- n + 1),
               "ArcGIS error: Failed to execute query.")
  expect_equal(n, 2)
})
