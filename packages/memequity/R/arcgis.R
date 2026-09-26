# Querying ArcGIS REST services (the City's 311 server, the Memphis Data Hub).

#' Perform an ArcGIS REST request and return the parsed JSON, retrying on
#' failure.
#'
#' Two kinds of failure are retried with exponential backoff:
#' - a dropped connection or HTTP error. httr2's req_retry covers only HTTP
#'   429 and 503;
#' - an ArcGIS error returned inside an HTTP 200 body. On 2026-09-26 the
#'   City's 311 server answered one page of an otherwise normal fetch with
#'   "User couldn't access this resource", and the daily run failed.
#'
#' @param req an httr2 request.
#' @param tries attempts before giving up; the last error is raised.
#' @param perform,wait injectable for tests.
#' @export
arcgis_json <- function(req, tries = 6L, simplify = TRUE, perform = httr2::req_perform,
                        wait = function(i) Sys.sleep(2^i)) {
  for (i in seq_len(tries)) {
    body <- tryCatch({
      b <- jsonlite::fromJSON(httr2::resp_body_string(perform(req)), simplifyVector = simplify)
      if (!is.null(b$error))
        stop("ArcGIS error: ", b$error$message %||% "unknown", call. = FALSE)
      b
    }, error = function(e) e)
    if (!inherits(body, "error")) return(body)
    if (i == tries) stop(body)
    wait(i)
  }
}
