# Metric specifications (design plan 5.1). Specs live in
# specs/<pipeline>/<metric>.md: YAML front matter for the machine-readable
# parts, Markdown prose for the rest. The methodology page is generated from
# them.

SPEC_REQUIRED <- c("id", "pipeline", "title", "version", "status", "unit", "formula",
                   "windows", "geographies", "min_n", "promise", "thresholds",
                   "inclusions", "exclusions", "confounders", "objections")

SPEC_STATUSES <- c("draft", "review", "frozen")

#' Read one spec file.
#' @export
read_spec <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  fences <- which(lines == "---")
  if (length(fences) < 2 || fences[1] != 1) stop("Spec has no YAML front matter: ", path, call. = FALSE)
  meta <- yaml::yaml.load(paste(lines[2:(fences[2] - 1)], collapse = "\n"))
  body <- if (fences[2] < length(lines)) lines[(fences[2] + 1):length(lines)] else character()
  meta$body <- paste(body, collapse = "\n")
  meta$path <- path
  structure(meta, class = "mse_spec")
}

#' Read all specs for a pipeline.
#' @export
read_specs <- function(pipeline, specs_dir) {
  files <- sort(list.files(file.path(specs_dir, pipeline), pattern = "\\.md$", full.names = TRUE))
  stats::setNames(lapply(files, read_spec), vapply(files, function(f)
    tools::file_path_sans_ext(basename(f)), character(1)))
}

#' Problems with a spec (empty when valid).
#'
#' A frozen spec must also have: a promise source URL (or be labelled a
#' comparison), at least three adversarial objections each with a response,
#' and at least two alternatives for every arbitrary threshold.
#' @export
spec_problems <- function(spec) {
  p <- character()
  missing <- setdiff(SPEC_REQUIRED, names(spec))
  if (length(missing)) p <- c(p, paste("missing fields:", paste(missing, collapse = ", ")))
  if (!is.null(spec$status) && !spec$status %in% SPEC_STATUSES)
    p <- c(p, paste("status must be one of", paste(SPEC_STATUSES, collapse = "/")))
  if (!is.null(spec$version) && !grepl("^\\d+\\.\\d+$", as.character(spec$version)))
    p <- c(p, "version must look like MAJOR.MINOR")
  if (!is.null(spec$promise) && !isTRUE(spec$promise$kind %in% c("official", "comparison")))
    p <- c(p, "promise.kind must be 'official' or 'comparison'")
  if (identical(spec$status, "frozen")) {
    if (identical(spec$promise$kind, "official") && !nzchar(spec$promise$source_url %||% ""))
      p <- c(p, "frozen official promise needs promise.source_url")
    obj <- spec$objections %||% list()
    answered <- vapply(obj, function(o) nzchar(o$objection %||% "") && nzchar(o$response %||% ""), logical(1))
    if (sum(answered) < 3) p <- c(p, "frozen spec needs >= 3 answered objections")
    for (t in spec$thresholds %||% list()) {
      if (isTRUE(t$arbitrary) && length(t$alternatives) < 2)
        p <- c(p, paste0("threshold '", t$name, "' needs >= 2 alternatives"))
    }
  }
  p
}

fmt_list <- function(x) if (!length(x)) "_None._" else paste0("- ", unlist(x), collapse = "\n")

#' Render methodology_<pipeline>.md from the pipeline's specs and the latest
#' reconciliation and audit records.
#'
#' @param reconciliation list with date, reference, reference_value,
#'   our_value, gap, note (or NULL).
#' @param audit list with date, path, records (or NULL).
#' @export
render_methodology <- function(pipeline, specs_dir, out_dir, reconciliation = NULL,
                               audit = NULL, title = pipeline) {
  specs <- read_specs(pipeline, specs_dir)
  out <- c(sprintf("# Methodology: %s", title), "",
           sprintf("_Generated from `specs/%s/` on %s. Do not edit by hand._", pipeline, format(Sys.Date())), "")
  out <- c(out, "## Reconciliation", "",
           if (is.null(reconciliation)) "_No reconciliation has been run yet. Metrics are not publishable until one is._"
           else c(sprintf("- **Date:** %s", reconciliation$date),
                  sprintf("- **Reference:** %s", reconciliation$reference),
                  sprintf("- **Reference value:** %s; **our value:** %s; **gap:** %s",
                          reconciliation$reference_value, reconciliation$our_value, reconciliation$gap),
                  sprintf("- **Note:** %s", reconciliation$note %||% "")), "")
  out <- c(out, "## Manual audit", "",
           if (is.null(audit)) "_No pre-launch audit has been committed yet._"
           else sprintf("- %s: %s records traced end to end (`%s`)", audit$date, audit$records, audit$path), "")
  for (s in specs) {
    th <- vapply(s$thresholds %||% list(), function(t) sprintf("- **%s:** %s (alternatives: %s)%s",
      t$name, t$primary, paste(unlist(t$alternatives), collapse = "; "),
      if (isTRUE(t$arbitrary)) " -- arbitrary; published under each alternative" else ""), "")
    obj <- vapply(s$objections %||% list(), function(o)
      sprintf("- **Objection:** %s\n  **Response:** %s", o$objection, o$response %||% "_Unanswered._"), "")
    out <- c(out,
      sprintf("## %s", s$title), "",
      sprintf("`%s` · version %s · status **%s**", s$id, s$version, s$status), "",
      sprintf("**Promise (%s):** %s%s", s$promise$kind, s$promise$text,
              if (nzchar(s$promise$source_url %||% "")) sprintf(" ([source](%s))", s$promise$source_url) else ""), "",
      sprintf("**Formula:** %s", s$formula), "",
      sprintf("**Unit:** %s · **Windows:** %s · **Geographies:** %s · **Minimum n:** %s",
              s$unit, paste(unlist(s$windows), collapse = ", "),
              paste(unlist(s$geographies), collapse = ", "), s$min_n), "",
      "**Included:**", fmt_list(s$inclusions), "",
      "**Excluded:**", fmt_list(s$exclusions), "",
      "**Thresholds:**", if (length(th)) th else "_None._", "",
      "**Known confounders:**", fmt_list(s$confounders), "",
      "**Adversarial read:**", if (length(obj)) obj else "_None recorded._", "",
      s$body, "")
  }
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(out_dir, sprintf("methodology_%s.md", pipeline))
  writeLines(out, path, useBytes = TRUE)
  invisible(path)
}
