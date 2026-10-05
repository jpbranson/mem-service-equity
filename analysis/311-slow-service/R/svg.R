# Hand-built SVG figures. Colors are CSS classes and variables, so the report
# can switch light/dark and every mark can carry a hover tooltip (data-tip).
# svg_standalone() writes the same figure as a self-contained .svg file with
# the light theme inlined, for export.

esc <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub("\"", "&quot;", x, fixed = TRUE)
}
f1 <- function(x) formatC(x, format = "f", digits = 1)
f2 <- function(x) formatC(x, format = "f", digits = 2)
tag <- function(name, ..., .body = NULL) {
  a <- list(...)
  a <- a[!vapply(a, is.null, TRUE)]
  attrs <- if (length(a)) paste0(" ", paste0(gsub("_", "-", names(a)), "=\"", vapply(a, esc, ""), "\""), collapse = "") else ""
  if (is.null(.body)) paste0("<", name, attrs, "/>") else paste0("<", name, attrs, ">", paste(.body, collapse = ""), "</", name, ">")
}
txt <- function(x, y, label, cls = NULL, anchor = NULL, ...) {
  tag("text", x = f1(x), y = f1(y), class = cls, text_anchor = anchor, ..., .body = esc(label))
}
svg_open <- function(w, h, label, id) {
  sprintf("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 %s %s\" role=\"img\" aria-label=\"%s\" id=\"%s\" class=\"fig-svg\">",
          f1(w), f1(h), esc(label), id)
}
hatch_def <- function(id) {
  sprintf(paste0("<defs><pattern id=\"%s\" patternUnits=\"userSpaceOnUse\" width=\"5\" height=\"5\" patternTransform=\"rotate(45)\">",
                 "<rect width=\"5\" height=\"5\" class=\"hatch-bg\"/><line x1=\"0\" y1=\"0\" x2=\"0\" y2=\"5\" class=\"hatch-ln\"/></pattern></defs>"), id)
}

# ---- classes for the diverging ratio scale -----------------------------------
# Bins are symmetric on a log scale, so "40% more" and "40% fewer" get equally
# strong colors: [1/1.4, 1/1.2, 1/1.07, 1.07, 1.2, 1.4].
RATIO_BREAKS <- c(1 / 1.4, 1 / 1.2, 1 / 1.07, 1.07, 1.2, 1.4)
RATIO_CLASSES <- c("f3", "f2", "f1", "n0", "s1", "s2", "s3")
RATIO_LABELS <- c("40%+ fewer", "20-40% fewer", "7-20% fewer", "within 7%", "7-20% more", "20-40% more", "40%+ more")
ratio_class <- function(r) RATIO_CLASSES[findInterval(r, RATIO_BREAKS) + 1]

LISA_CLASS <- c(HH = "l-hh", LL = "l-ll", HL = "l-hl", LH = "l-lh", HH_unadj = "l-hu", LL_unadj = "l-lu",
                HL_unadj = "l-hu", LH_unadj = "l-lu", ns = "l-ns", suppressed = "sup")
LISA_LEGEND <- list(
  c("l-hh", "Slow cluster core"), c("l-ll", "Fast cluster core"),
  c("l-hl", "Slow tract among fast (outlier)"), c("l-lh", "Fast tract among slow (outlier)"),
  c("l-hu", "Slower, before correction only"), c("l-lu", "Faster, before correction only"),
  c("l-ns", "No significant local pattern"), c("sup", "Too few requests (under 30)"))

# ---- maps ----------------------------------------------------------------------
map_frame <- function(bbox, width, pad = 6) {
  s <- (width - 2 * pad) / (bbox[["xmax"]] - bbox[["xmin"]])
  list(x0 = bbox[["xmin"]], y1 = bbox[["ymax"]], s = s, pad = pad, w = width,
       h = (bbox[["ymax"]] - bbox[["ymin"]]) * s + 2 * pad)
}
proj_xy <- function(xy, fr) cbind((xy[, 1] - fr$x0) * fr$s + fr$pad, (fr$y1 - xy[, 2]) * fr$s + fr$pad)
path_d <- function(g, fr) {
  polys <- if (inherits(g, "MULTIPOLYGON")) unclass(g) else if (inherits(g, "POLYGON")) list(unclass(g)) else list()
  paste(vapply(polys, function(pl) paste(vapply(pl, function(ring) {
    p <- proj_xy(ring, fr)
    paste0("M", paste(f1(p[, 1]), f1(p[, 2]), sep = ",", collapse = "L"), "Z")
  }, ""), collapse = ""), ""), collapse = "")
}

#' One map panel: tracts filled by class, city outline, optional labels.
map_body <- function(geo, classes, tips, fr, outline, labels = NULL, hatch_id, pattern_classes = "sup",
                     tract_ids = NULL) {
  ds <- vapply(seq_len(nrow(geo)), function(i) path_d(sf::st_geometry(geo)[[i]], fr), "")
  paths <- vapply(seq_along(ds), function(i) {
    fill <- if (classes[i] %in% pattern_classes) sprintf(" style=\"fill:url(#%s)\"", hatch_id) else ""
    sprintf("<path d=\"%s\" class=\"tr %s\"%s data-tip=\"%s\"%s/>", ds[i], classes[i], fill, esc(tips[i]),
            if (is.null(tract_ids)) "" else sprintf(" data-tract=\"%s\"", tract_ids[i]))
  }, "")
  city_d <- path_d(sf::st_geometry(outline)[[1]], fr)
  # The whole city first, so tracts without residents read as a surface, not a hole.
  out <- paste0("<path class=\"nores\" d=\"", city_d, "\"/>",
                "<g class=\"tracts\">", paste(paths, collapse = ""), "</g>",
                "<path class=\"city\" d=\"", city_d, "\"/>")
  if (!is.null(labels) && nrow(labels)) {
    p <- proj_xy(as.matrix(labels[, c("x", "y")]), fr)
    out <- paste0(out, "<g class=\"map-labels\" aria-hidden=\"true\">",
                  paste(vapply(seq_len(nrow(labels)), function(i)
                    txt(p[i, 1], p[i, 2], labels$label[i], cls = labels$cls[i] %||% "lbl", anchor = "middle"), ""),
                    collapse = ""), "</g>")
  }
  out
}
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

legend_rows <- function(items, x, y, col_w, ncol, hatch_id, sw = 14, row_h = 20, byrow = TRUE) {
  out <- character()
  nr <- ceiling(length(items) / ncol)
  for (k in seq_along(items)) {
    if (byrow) { r <- (k - 1) %/% ncol; c <- (k - 1) %% ncol } else { c <- (k - 1) %/% nr; r <- (k - 1) %% nr }
    xx <- x + c * col_w; yy <- y + r * row_h
    cls <- items[[k]][1]
    fill <- if (cls == "sup") sprintf(" style=\"fill:url(#%s)\"", hatch_id) else ""
    out <- c(out, sprintf("<rect x=\"%s\" y=\"%s\" width=\"%d\" height=\"%d\" rx=\"2\" class=\"tr %s\"%s/>",
                          f1(xx), f1(yy), sw, sw - 4, cls, fill),
             txt(xx + sw + 6, yy + sw - 5, items[[k]][2], cls = "leg"))
  }
  paste(out, collapse = "")
}

# ---- axis helpers ------------------------------------------------------------------
lin <- function(d0, d1, r0, r1) function(v) r0 + (v - d0) / (d1 - d0) * (r1 - r0)
logsc <- function(d0, d1, r0, r1) { f <- lin(log(d0), log(d1), r0, r1); function(v) f(log(v)) }
fmt_ratio <- function(r) paste0(f2(r), "×")

#' Standalone SVG: the figure plus the light-theme stylesheet inlined.
svg_standalone <- function(svg, css) {
  sub("(<svg[^>]*>)", paste0("\\1<style>", gsub("\\\\", "\\\\\\\\", css), "</style>"), svg)
}
