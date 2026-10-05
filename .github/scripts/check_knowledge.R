# Check the knowledge bundle against Open Knowledge Format v0.2 and the
# conventions in CLAUDE.md ("Knowledge bundle").
#
# Errors (exit status 1):
# - a concept without parseable frontmatter, a `type`, `title` or `description`;
# - a bad `status`, or a timestamp without an explicit UTC offset;
# - a source without `resource`, a repo path that does not exist, a duplicate
#   source id, or a footnote that matches no source id;
# - a broken link to a file in the repo;
# - an `index.md` with frontmatter other than `okf_version` at the root, a
#   `log.md` with frontmatter or a date heading not in YYYY-MM-DD form;
# - a concept missing from its folder's `index.md`, or listed there with a
#   description different from its frontmatter.
# Warnings: a concept past its `stale_after`, a source no footnote cites.
#
# Usage: Rscript .github/scripts/check_knowledge.R [bundle dir, default knowledge]

`%||%` <- function(a, b) if (is.null(a)) b else a

args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(if (length(args)) args[1] else "knowledge", winslash = "/", mustWork = TRUE)
on_ci <- identical(Sys.getenv("GITHUB_ACTIONS"), "true")
errors <- 0L
warnings <- 0L

report <- function(level, file, ...) {
  msg <- paste0(...)
  rel <- file.path(basename(root), sub(paste0(root, "/"), "", file, fixed = TRUE))
  if (level == "error") errors <<- errors + 1L else warnings <<- warnings + 1L
  if (on_ci) cat(sprintf("::%s file=%s::%s\n", level, rel, msg))
  else cat(sprintf("%s: %s: %s\n", level, rel, msg))
}

split_frontmatter <- function(lines) {
  if (!length(lines) || lines[1] != "---") return(list(fm = NULL, body = lines))
  end <- which(lines[-1] == "---")[1] + 1L
  if (is.na(end)) return(list(fm = NA_character_, body = lines))
  list(fm = paste(lines[seq_len(end - 2L) + 1L], collapse = "\n"), body = lines[-seq_len(end)])
}

# Body text with fenced, indented and inline code removed, so that regexes
# and diagrams inside code are not read as links or footnotes.
prose <- function(body) {
  fence <- cumsum(grepl("^\\s*```", body)) %% 2 == 1 | grepl("^\\s*```", body)
  keep <- body[!fence & !grepl("^( {4}|\t)", body)]
  gsub("`[^`]*`", "", paste(keep, collapse = "\n"))
}

is_url <- function(x) grepl("^[a-z][a-z0-9+.-]*://", x)
# yaml may already have turned a timestamp into POSIXct, which keeps its offset.
timestamp_ok <- function(x) inherits(x, "POSIXt") || is.character(x) && length(x) == 1L &&
  grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?(Z|[+-]\\d{2}:\\d{2})$", x)
parse_time <- function(x) {
  if (inherits(x, "POSIXt")) return(x)
  x <- sub("Z$", "+00:00", sub("\\.\\d+", "", x))
  as.POSIXct(sub("([+-]\\d{2}):(\\d{2})$", "\\1\\2", x), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
}

check_links <- function(file, text) {
  targets <- regmatches(text, gregexpr("\\]\\(([^)\\s]+)\\)", text, perl = TRUE))[[1]]
  targets <- sub("#.*$", "", sub("^\\]\\(", "", sub("\\)$", "", targets)))
  for (t in unique(targets[nzchar(targets) & !is_url(targets) & !startsWith(targets, "mailto:")])) {
    path <- if (startsWith(t, "/")) file.path(root, sub("^/", "", t)) else file.path(dirname(file), t)
    if (!file.exists(path)) report("error", file, "broken link ", t)
  }
}

# Index entries: "* [Title](target) - description", keyed by resolved path.
index_entries <- function(index_file) {
  if (!file.exists(index_file)) return(list())
  lines <- readLines(index_file, encoding = "UTF-8", warn = FALSE)
  m <- regmatches(lines, regexec("^\\s*[*-]\\s+\\[[^]]*\\]\\(([^)]+)\\)\\s*(?:-\\s*(.*))?$", lines, perl = TRUE))
  out <- list()
  for (x in m[lengths(m) > 0]) {
    target <- x[2]
    if (is_url(target)) next
    path <- if (startsWith(target, "/")) file.path(root, sub("^/", "", target)) else file.path(dirname(index_file), target)
    out[[normalizePath(path, winslash = "/", mustWork = FALSE)]] <- trimws(x[3])
  }
  out
}

check_concept <- function(file, s) {
  if (is.null(s$fm) || identical(s$fm, NA_character_))
    return(report("error", file, "no YAML frontmatter"))
  fm <- tryCatch(yaml::yaml.load(s$fm), error = function(e) {
    report("error", file, "frontmatter is not valid YAML: ", conditionMessage(e)); NULL
  })
  if (is.null(fm)) return(invisible())
  if (!is.list(fm)) return(report("error", file, "frontmatter is not a YAML mapping"))
  for (k in c("type", "title", "description"))
    if (!is.character(fm[[k]]) || !nzchar(fm[[k]])) report("error", file, "missing `", k, "`")
  if (!is.null(fm$status) && !isTRUE(fm$status %in% c("draft", "stable", "deprecated")))
    report("error", file, "`status` must be draft, stable or deprecated")
  if (!is.null(fm$generated)) {
    if (is.null(fm$generated$by)) report("error", file, "`generated` has no `by`")
    if (!is.null(fm$generated$at) && !timestamp_ok(fm$generated$at))
      report("error", file, "`generated.at` needs an ISO 8601 time with a UTC offset")
  }
  verified <- if (!is.null(fm$verified$by)) list(fm$verified) else fm$verified
  for (v in verified)
    if (is.null(v$by) || !timestamp_ok(v$at %||% "")) report("error", file, "`verified` entries need `by` and an ISO `at`")
  if (!is.null(fm$stale_after)) {
    if (!timestamp_ok(fm$stale_after)) report("error", file, "`stale_after` needs an ISO 8601 time with a UTC offset")
    else if (parse_time(fm$stale_after) <= Sys.time()) report("warning", file, "stale since ", fm$stale_after)
  }
  if (is.character(fm$resource) && !is_url(fm$resource) && !file.exists(file.path(dirname(file), fm$resource)))
    report("error", file, "`resource` path does not exist: ", fm$resource)

  ids <- character()
  for (src in fm$sources) {
    if (!is.character(src$resource)) { report("error", file, "a source has no `resource`"); next }
    # A resource that looks like a path must exist; free text describes a scope.
    if (!is_url(src$resource) && !grepl("\\s", src$resource) &&
        !file.exists(file.path(dirname(file), src$resource)))
      report("error", file, "source path does not exist: ", src$resource)
    if (!is.null(src$last_modified) && !timestamp_ok(src$last_modified))
      report("error", file, "source `", src$id %||% src$resource, "` has a bad `last_modified`")
    if (!is.null(src$id)) ids <- c(ids, src$id)
  }
  if (anyDuplicated(ids)) report("error", file, "duplicate source ids: ", paste(unique(ids[duplicated(ids)]), collapse = ", "))

  text <- prose(s$body)
  cited <- unique(gsub("^\\[\\^|\\]:?$", "", regmatches(text, gregexpr("\\[\\^[^]\\s]+\\]", text, perl = TRUE))[[1]]))
  for (id in setdiff(cited, ids)) report("error", file, "footnote [^", id, "] matches no source id")
  for (id in setdiff(ids, cited)) report("warning", file, "source `", id, "` is never cited")
  check_links(file, text)

  entries <- index_entries(file.path(dirname(file), "index.md"))
  entry <- entries[[normalizePath(file, winslash = "/")]]
  if (is.null(entry)) report("error", file, "not listed in its folder's index.md")
  else if (is.character(fm$description) && !identical(entry, trimws(fm$description)))
    report("error", file, "index.md lists a different description")
}

files <- sort(list.files(root, "\\.md$", recursive = TRUE, full.names = TRUE))
for (file in files) {
  s <- split_frontmatter(readLines(file, encoding = "UTF-8", warn = FALSE))
  name <- basename(file)
  if (name == "index.md") {
    if (!is.null(s$fm)) {
      fm <- tryCatch(yaml::yaml.load(s$fm), error = function(e) NULL)
      if (dirname(file) != root || !identical(names(fm), "okf_version"))
        report("error", file, "index.md may carry frontmatter only at the bundle root, and only `okf_version`")
    }
    check_links(file, prose(s$body))
  } else if (name == "log.md") {
    if (!is.null(s$fm)) report("error", file, "log.md must not have frontmatter")
    dates <- grep("^##\\s", s$body, value = TRUE)
    for (d in dates[!grepl("^## \\d{4}-\\d{2}-\\d{2}$", dates)])
      report("error", file, "date heading not in YYYY-MM-DD form: ", d)
    check_links(file, prose(s$body))
  } else {
    check_concept(file, s)
  }
}

cat(sprintf("%d files checked: %d errors, %d warnings\n", length(files), errors, warnings))
if (errors > 0L) quit(status = 1L)
