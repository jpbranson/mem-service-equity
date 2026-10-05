# The report's figures. Each builder returns list(body, w, h, defs); finish()
# turns it into an inline SVG (the HTML supplies title and source) or an
# export SVG (title and source drawn in).

finish <- function(parts, id, label, title = NULL, source = NULL) {
  top <- if (is.null(title)) 0 else 30
  bot <- if (is.null(source)) 0 else 24
  h <- parts$h + top + bot
  paste0(svg_open(parts$w, h, label, id), parts$defs %||% "",
         if (!is.null(title)) txt(0, 18, title, "fig-title") else "",
         sprintf("<g transform=\"translate(0,%d)\">", top), parts$body, "</g>",
         if (!is.null(source)) txt(0, h - 7, source, "src") else "", "</svg>")
}

# Put several panels side by side (for export).
side_by_side <- function(panels, gap = 24) {
  x <- 0; body <- character(); defs <- character()
  for (p in panels) {
    body <- c(body, sprintf("<g transform=\"translate(%s,0)\">%s</g>", f1(x), p$body))
    defs <- c(defs, p$defs %||% "")
    x <- x + p$w + gap
  }
  list(body = paste(body, collapse = ""), defs = paste(unique(defs), collapse = ""),
       w = x - gap, h = max(vapply(panels, function(p) p$h, 1)))
}
stacked <- function(panels, gap = 18) {
  y <- 0; body <- character(); defs <- character()
  for (p in panels) {
    body <- c(body, sprintf("<g transform=\"translate(0,%s)\">%s</g>", f1(y), p$body))
    defs <- c(defs, p$defs %||% "")
    y <- y + p$h + gap
  }
  list(body = paste(body, collapse = ""), defs = paste(unique(defs), collapse = ""),
       w = max(vapply(panels, function(p) p$w, 1)), h = y - gap)
}

tract_tip <- function(ti, t) {
  loc <- ifelse(is.na(ti$nbhd), sprintf("ZIP %s", ti$zip), sprintf("ZIP %s, %s", ti$zip, ti$nbhd))
  base <- sprintf("%s (%s)\n%s residents in the city", ti$name, loc, fmt_n(round(ti$residents)))
  ifelse(t$suppressed,
         sprintf("%s\n%s eligible requests: too few to estimate", base, fmt_n(t$n)),
         sprintf("%s\n%s eligible requests\n%s slow vs %s expected\nRatio %s (95%% CI %s to %s)\nLocal result: %s",
                 base, fmt_n(t$n), pct(t$observed / t$n), pct(t$expected / t$n), fmt_ratio(t$ratio),
                 f2(t$ci_low), f2(t$ci_high), class_words(t$class, t$q)))
}
class_words <- function(cls, q) {
  w <- c(HH = "slow cluster core", LL = "fast cluster core", HL = "slow outlier among fast tracts",
         LH = "fast outlier among slow tracts", HH_unadj = "slower (significant before correction only)",
         LL_unadj = "faster (significant before correction only)",
         HL_unadj = "slow outlier (before correction only)", LH_unadj = "fast outlier (before correction only)",
         ns = "no significant local pattern", suppressed = "too few requests")[cls]
  ifelse(is.na(q), w, sprintf("%s (q = %s)", w, formatC(q, format = "g", digits = 2)))
}

# ---- Figure 1: the two maps -------------------------------------------------------
map_panel <- function(geo, classes, tips, outline, labels, fr, subtitle, legend, hatch_id, ids, ncol = 2,
                      byrow = TRUE) {
  top <- 22
  body <- paste0(txt(0, 14, subtitle, "panel-t"),
                 sprintf("<g transform=\"translate(0,%d)\">", top),
                 map_body(geo, classes, tips, fr, outline, labels, hatch_id, tract_ids = ids), "</g>")
  ly <- top + fr$h + 10
  nrow_leg <- ceiling(length(legend) / ncol)
  body <- paste0(body, legend_rows(legend, 0, ly, fr$w / ncol, ncol, hatch_id, byrow = byrow))
  list(body = body, w = fr$w, h = ly + nrow_leg * 20, defs = hatch_def(hatch_id))
}

fig1_panels <- function(M) {
  t <- M$t
  cls_a <- ifelse(t$suppressed, "sup", ratio_class(t$ratio))
  # Left column: more slow requests than expected; right column: fewer.
  leg_a <- c(lapply(7:4, function(i) c(RATIO_CLASSES[i], RATIO_LABELS[i])),
             lapply(1:3, function(i) c(RATIO_CLASSES[i], RATIO_LABELS[i])),
             list(c("sup", "Too few requests (under 30)")))
  a <- map_panel(M$geo, cls_a, M$tips, M$outline, M$labels, M$fr,
                 "A  Slow requests vs expected, by tract", leg_a, "hatch-1a", t$geo_id,
                 byrow = FALSE)
  cls_b <- unname(LISA_CLASS[t$class])
  present <- unique(cls_b)
  leg_b <- Filter(function(z) z[1] %in% present, LISA_LEGEND)
  b <- map_panel(M$geo, cls_b, M$tips, M$outline, M$cluster_labels, M$fr,
                 "B  Where the pattern is statistically supported", leg_b, "hatch-1b", t$geo_id)
  list(a = a, b = b)
}

# ---- Figure 2: how far each tract is from expected ------------------------------------
GROUP_LAB <- c(slow_core = "Slow cluster", other = "Other tracts", fast_core = "Fast cluster",
               citywide = "Citywide")
group_of_class <- function(cls) ifelse(cls == "HH", "slow_core", ifelse(cls == "LL", "fast_core", "other"))

fig2_caterpillar <- function(M) {
  t <- M$t[!M$t$suppressed, ]
  t <- t[order(t$ratio), ]
  w <- 640; h <- 300; ml <- 44; mr <- 12; mt <- 30; mb <- 34
  lo <- min(0.25, min(t$ci_low)); hi <- max(2.2, max(t$ci_high))
  y <- logsc(lo, hi, h - mb, mt)
  x <- lin(1, nrow(t), ml + 4, w - mr - 4)
  ticks <- c(0.25, 0.33, 0.5, 0.67, 1, 1.5, 2)
  ticks <- ticks[ticks >= lo & ticks <= hi]
  grid <- paste(vapply(ticks, function(v) paste0(
    tag("line", x1 = ml, x2 = w - mr, y1 = f1(y(v)), y2 = f1(y(v)), class = if (v == 1) "base" else "grid"),
    txt(ml - 6, y(v) + 4, if (v == 1) "1.0" else formatC(v, format = "fg", digits = 2), "ax", "end")), ""), collapse = "")
  g <- group_of_class(t$class)
  ci <- paste(sprintf("<line x1=\"%s\" x2=\"%s\" y1=\"%s\" y2=\"%s\" class=\"ci ci-%s\"/>",
                      f1(x(seq_len(nrow(t)))), f1(x(seq_len(nrow(t)))), f1(y(t$ci_low)), f1(y(t$ci_high)), g), collapse = "")
  tips <- M$tips[match(t$geo_id, M$t$geo_id)]
  dots <- paste(sprintf("<circle cx=\"%s\" cy=\"%s\" r=\"%s\" class=\"dot dot-%s\" data-tip=\"%s\" data-tract=\"%s\"/>",
                        f1(x(seq_len(nrow(t)))), f1(y(t$ratio)), ifelse(g == "other", "2.2", "3"), g,
                        vapply(tips, esc, ""), t$geo_id), collapse = "")
  leg <- paste0(
    "<circle cx=\"", ml + 6, "\" cy=\"12\" r=\"4\" class=\"dot dot-slow_core\"/>", txt(ml + 16, 16, "Slow cluster core", "leg"),
    "<circle cx=\"", ml + 146, "\" cy=\"12\" r=\"4\" class=\"dot dot-fast_core\"/>", txt(ml + 156, 16, "Fast cluster core", "leg"),
    "<circle cx=\"", ml + 282, "\" cy=\"12\" r=\"3\" class=\"dot dot-other\"/>", txt(ml + 292, 16, "Other tract", "leg"),
    txt(w - mr, 16, "Vertical lines: 95% interval", "leg", "end"))
  ann <- paste0(txt(ml + 8, y(1) - 6, "1.0 = as expected", "ax"),
                txt(ml, h - 8, sprintf("%d tracts, from fastest to slowest", nrow(t)), "ax"),
                txt(12, (mt + h - mb) / 2, "Slow vs expected (log scale)", "ax", "middle",
                    transform = sprintf("rotate(-90 12 %s)", f1((mt + h - mb) / 2))))
  list(body = paste0(leg, grid, ci, dots, ann), w = w, h = h)
}

fig2_groups <- function(M) {
  gr <- M$group_ratios
  gr <- gr[match(c("fast_core", "other", "slow_core"), gr$group), ]
  w <- 640; row <- 34; mt <- 8; ml <- 150; mr <- 230
  h <- mt + 3 * row + 26
  x <- logsc(0.45, 1.6, ml, w - mr)
  ticks <- c(0.5, 0.67, 1, 1.5)
  body <- paste(vapply(ticks, function(v) paste0(
    tag("line", x1 = f1(x(v)), x2 = f1(x(v)), y1 = mt, y2 = mt + 3 * row, class = if (v == 1) "base" else "grid"),
    txt(x(v), mt + 3 * row + 14, if (v == 1) "1.0" else formatC(v, format = "fg", digits = 2), "ax", "middle")), ""), collapse = "")
  for (i in seq_len(nrow(gr))) {
    yy <- mt + (i - 0.5) * row
    g <- gr$group[i]
    body <- paste0(body, txt(ml - 10, yy + 4, sprintf("%s (%d)", GROUP_LAB[[g]], gr$tracts[i]), "lab", "end"),
                   tag("line", x1 = f1(x(gr$ci_low[i])), x2 = f1(x(gr$ci_high[i])), y1 = f1(yy), y2 = f1(yy),
                       class = sprintf("ci ci-%s thick", g)),
                   sprintf("<circle cx=\"%s\" cy=\"%s\" r=\"5\" class=\"dot dot-%s\" data-tip=\"%s\"/>",
                           f1(x(gr$ratio[i])), f1(yy), g,
                           esc(sprintf("%s: %s requests\n%s slow vs %s expected\nRatio %s (95%% CI %s to %s)",
                                       GROUP_LAB[[g]], fmt_n(gr$n[i]), pct(gr$observed_share[i]),
                                       pct(gr$expected_share[i]), fmt_ratio(gr$ratio[i]), f2(gr$ci_low[i]),
                                       f2(gr$ci_high[i])))),
                   txt(w - mr + 12, yy + 4, sprintf("%s: %s slow vs %s expected", fmt_ratio(gr$ratio[i]),
                                                    pct(gr$observed_share[i]), pct(gr$expected_share[i])), "val"))
  }
  body <- paste0(body, txt(x(1), h - 2, "Slow requests vs expected, all of a group's tracts pooled (log scale)", "ax", "middle"))
  list(body = body, w = w, h = h)
}

# ---- Figure 3: what distinguishes the groups -------------------------------------------
TYPE_LABELS <- c(
  "SWM-Missed Bulk Trash" = "Bulk trash not picked up", "SWM-Garbage Missed" = "Garbage pickup missed",
  "SWM-Recycling Missed" = "Recycling pickup missed", "SWM-Cart Repair" = "Garbage cart repair",
  "SWM-Missing Cart" = "Garbage cart missing", "SWM-New Start Garbage Request" = "New garbage service",
  "CE-Weeds Occupied Property" = "Weeds, occupied property", "CE-Code Miscellaneous" = "Code violation, other",
  "CE-Vehicle Violations" = "Vehicle code violation", "PW (SM)-Potholes" = "Pothole",
  "SWM-Dead Animal Collection" = "Dead animal pickup", "SWM-Service Quality" = "Sanitation service complaint",
  "CE-Substandard,Derelict Struc" = "Derelict structure")
type_label <- function(t) ifelse(t %in% names(TYPE_LABELS), TYPE_LABELS[t], t)
DEPT_OF <- function(t) ifelse(startsWith(t, "SWM"), "Solid waste", ifelse(startsWith(t, "CE"), "Code enforcement",
                        ifelse(startsWith(t, "PW"), "Public works", "Other")))

fig3_heatmap <- function(M) {
  tt <- M$type_groups
  types <- M$top_types
  dept_order <- c("Solid waste", "Code enforcement", "Public works", "Other")
  types <- types[order(match(DEPT_OF(types), dept_order), match(types, M$top_types))]
  cols <- c("fast_core", "other", "slow_core")
  w <- 640; ml <- 270; mt <- 40; rh <- 28; cw <- (w - ml - 110) / 3
  h <- mt + length(types) * rh + 30
  body <- paste0(
    paste(vapply(seq_along(cols), function(j) txt(ml + (j - 0.5) * cw, mt - 12, GROUP_LAB[[cols[j]]], "lab", "middle"), ""), collapse = ""),
    txt(ml + 3 * cw + 55, mt - 12, "Citywide", "lab", "middle"),
    txt(ml + 3 * cw + 55, mt - 26, "typical days", "ax", "middle"))
  for (i in seq_along(types)) {
    ty <- types[i]; yy <- mt + (i - 1) * rh
    body <- paste0(body, txt(ml - 10, yy + rh / 2 + 4, type_label(ty), "lab", "end"))
    for (j in seq_along(cols)) {
      r <- tt[tt$request_type == ty & tt$group == cols[j], ]
      cl <- ratio_class(r$ratio)
      tone <- sub("^[fs]", "", cl); tone <- ifelse(cl == "n0", "0", tone)
      days <- if (is.na(r$median_days)) "–" else sprintf("%s d", formatC(r$median_days, format = "fg"))
      tip <- sprintf("%s, %s\n%s requests; median %s business days\n%s slow requests vs expected (95%% CI %s to %s)",
                     type_label(ty), GROUP_LAB[[cols[j]]], fmt_n(r$n),
                     if (is.na(r$median_days)) "n/a" else formatC(r$median_days, format = "fg"),
                     fmt_ratio(r$ratio), f2(r$ci_low), f2(r$ci_high))
      body <- paste0(body,
        sprintf("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" rx=\"3\" class=\"tr %s\" data-tip=\"%s\"/>",
                f1(ml + (j - 1) * cw + 1), f1(yy + 1), f1(cw - 2), f1(rh - 2), cl, esc(tip)),
        txt(ml + (j - 0.5) * cw, yy + rh / 2 + 4, sprintf("%s  ·  %s", days, fmt_ratio(r$ratio)),
            paste0("cell-t on-", tone), "middle", pointer_events = "none"))
    }
    cw_ <- tt[tt$request_type == ty & tt$group == "citywide", ]
    thr <- M$thresholds$threshold[M$thresholds$request_type == ty]
    body <- paste0(body, txt(ml + 3 * cw + 55, yy + rh / 2 + 4, sprintf("%s d", formatC(thr, format = "fg")), "val", "middle"))
  }
  # department brackets
  depts <- DEPT_OF(types)
  for (dname in unique(depts)) {
    ix <- which(depts == dname)
    y0 <- mt + (min(ix) - 1) * rh + 3; y1 <- mt + max(ix) * rh - 3
    body <- paste0(body, tag("line", x1 = 4, x2 = 4, y1 = f1(y0), y2 = f1(y1), class = "bracket"),
                   txt(10, y0 + 9, dname, "ax"))
  }
  body <- paste0(body, txt(ml, h - 6, "Cell: median business days · slow requests vs expected. Colors as in Figure 1A.", "ax"))
  list(body = body, w = w, h = h)
}

CODE_CLASS <- c("c1", "c2", "c3", "c4", "c5")
fig3_codes <- function(M) {
  cc <- M$codes
  groups <- c("fast_core", "other", "slow_core")
  codes <- unique(cc$code[order(-cc$share)])
  codes <- c(setdiff(codes, "other codes"), intersect("other codes", codes))
  w <- 640; ml <- 150; mr <- 16; mt <- 30; bh <- 22; gap <- 12
  h <- mt + 3 * (bh + gap) + 8
  x <- lin(0, 1, ml, w - mr)
  body <- ""
  # legend
  lx <- ml
  for (k in seq_along(codes)) {
    cl <- if (codes[k] == "other codes") "c-other" else CODE_CLASS[k]
    lab <- if (codes[k] == "(no code)") "No resolution code" else if (codes[k] == "other codes") "Other codes" else codes[k]
    body <- paste0(body, sprintf("<rect x=\"%s\" y=\"6\" width=\"12\" height=\"10\" rx=\"2\" class=\"%s\"/>", f1(lx), cl),
                   txt(lx + 17, 15, lab, "leg"))
    lx <- lx + 36 + 6.2 * nchar(lab)
  }
  for (i in seq_along(groups)) {
    yy <- mt + (i - 1) * (bh + gap)
    s <- cc[cc$group == groups[i], ]
    s <- s[match(codes, s$code), ]; s$share[is.na(s$share)] <- 0
    x0 <- 0
    body <- paste0(body, txt(ml - 10, yy + bh / 2 + 4, sprintf("%s (%s)", GROUP_LAB[[groups[i]]], fmt_n(s$n_group[!is.na(s$n_group)][1])), "lab", "end"))
    for (k in seq_along(codes)) {
      if (s$share[k] <= 0) next
      cl <- if (codes[k] == "other codes") "c-other" else CODE_CLASS[k]
      x1 <- x0 + s$share[k]
      body <- paste0(body, sprintf("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%d\" class=\"seg %s\" data-tip=\"%s\"/>",
                                   f1(x(x0) + 1), f1(yy), f1(max(0.5, x(x1) - x(x0) - 2)), bh, cl,
                                   esc(sprintf("%s: %s of closed bulk-trash requests closed with %s",
                                               GROUP_LAB[[groups[i]]], pct(s$share[k]),
                                               if (codes[k] == "(no code)") "no resolution code" else codes[k]))))
      if (s$share[k] >= 0.08)
        body <- paste0(body, txt((x(x0) + x(x1)) / 2, yy + bh / 2 + 4, pct(s$share[k]), paste0("seg-t on-", cl), "middle",
                                 pointer_events = "none"))
      x0 <- x1
    }
  }
  list(body = body, w = w, h = h)
}

CONTEXT_ROWS <- list(
  c("pct_black_nh", "Black, not Hispanic", "pct"), c("pct_poverty", "Below the poverty line", "pct"),
  c("pct_renter", "Households that rent", "pct"), c("pct_vacant", "Vacant homes", "pct"),
  c("pct_no_vehicle", "Households without a vehicle", "pct"),
  c("requests_per_1000_residents", "311 requests per 1,000 residents", "num"),
  c("renovation_permits_per_1000_hu", "Home renovation permits per 1,000 homes", "num"),
  c("new_home_permits_per_1000_hu", "New-home permits per 1,000 homes", "num"),
  c("demolitions_per_1000_hu", "Demolitions per 1,000 homes", "num"))

fig3_context <- function(M) {
  cx <- M$context
  rows <- Filter(function(r) r[1] %in% cx$measure, CONTEXT_ROWS)
  groups <- c("fast_core", "other", "slow_core")
  w <- 640; ml <- 232; pw <- 190; rh <- 30; mt <- 36
  cols_x <- ml + pw + 30 + c(0, 1, 2, 3) * 50
  h <- mt + length(rows) * rh + 8
  fmtv <- function(v, kind) if (kind == "pct") pct(v) else formatC(v, format = "f", digits = if (v < 20) 1 else 0)
  body <- paste0(paste(vapply(seq_along(groups), function(j)
    txt(cols_x[j] + 20, mt - 14, c("Fast", "Other", "Slow")[j], paste0("lab hd-", groups[j]), "middle"), ""), collapse = ""),
    txt(cols_x[4] + 20, mt - 14, "City", "lab", "middle"),
    txt(ml, mt - 14, "Each row has its own scale, from zero", "ax"))
  for (i in seq_along(rows)) {
    m <- rows[[i]]; yy <- mt + (i - 0.5) * rh
    s <- cx[cx$measure == m[1], ]
    top <- max(s$ci_high, na.rm = TRUE) * 1.08
    x <- lin(0, top, ml, ml + pw)
    city <- s[s$group == "citywide", ]
    body <- paste0(body, txt(ml - 12, yy + 4, m[2], "lab", "end"),
                   tag("line", x1 = ml, x2 = ml + pw, y1 = f1(yy), y2 = f1(yy), class = "grid"),
                   tag("line", x1 = f1(x(city$value)), x2 = f1(x(city$value)), y1 = f1(yy - 9), y2 = f1(yy + 9), class = "ref"))
    for (j in seq_along(groups)) {
      r <- s[s$group == groups[j], ]
      body <- paste0(body,
        tag("line", x1 = f1(x(r$ci_low)), x2 = f1(x(r$ci_high)), y1 = f1(yy), y2 = f1(yy), class = sprintf("ci ci-%s", groups[j])),
        sprintf("<circle cx=\"%s\" cy=\"%s\" r=\"%s\" class=\"dot dot-%s\" data-tip=\"%s\"/>", f1(x(r$value)), f1(yy),
                if (groups[j] == "other") "3.2" else "4.5", groups[j],
                esc(sprintf("%s, %s: %s (%s %s to %s)%s", m[2], GROUP_LAB[[groups[j]]], fmtv(r$value, m[3]),
                            r$interval, fmtv(r$ci_low, m[3]), fmtv(r$ci_high, m[3]),
                            if (is.na(r$count)) "" else sprintf("; %s counted", fmt_n(r$count))))),
        txt(cols_x[j] + 20, yy + 4, fmtv(r$value, m[3]), "val", "middle"))
    }
    body <- paste0(body, txt(cols_x[4] + 20, yy + 4, fmtv(city$value, m[3]), "val muted", "middle"))
  }
  list(body = body, w = w, h = h)
}

# ---- Figure 4: robustness ----------------------------------------------------------------
fig4_minimaps <- function(M, specs) {
  w1 <- 300
  fr <- map_frame(M$bbox, w1, pad = 4)
  panels <- lapply(seq_along(specs), function(k) {
    s <- specs[[k]]
    t <- s$tracts[match(M$t$geo_id, s$tracts$geo_id), ]
    cls <- unname(LISA_CLASS[t$class])
    tips <- sprintf("%s\n%s: %s", M$ti$name, s$label, class_words(t$class, t$q))
    body <- paste0(txt(0, 14, s$title, "panel-t"), txt(0, 30, s$sub, "ax"),
                   "<g transform=\"translate(0,38)\">",
                   map_body(M$geo, cls, tips, fr, M$outline, NULL, sprintf("hatch-4-%d", k), tract_ids = M$t$geo_id), "</g>")
    list(body = body, w = w1, h = fr$h + 40, defs = hatch_def(sprintf("hatch-4-%d", k)))
  })
  rows <- list(side_by_side(panels[1:2], 40), side_by_side(panels[3:4], 40))
  g <- stacked(rows, 14)
  items <- Filter(function(z) z[1] %in% c("l-hh", "l-ll", "l-hu", "l-lu", "l-ns", "sup"), LISA_LEGEND)
  g$body <- paste0(g$body, legend_rows(items, 0, g$h + 12, g$w / 3, 3, "hatch-4-1"))
  g$h <- g$h + 12 + 2 * 20
  g
}

fig4_scatter <- function(M, a, b, xlab, ylab) {
  m <- merge(a$tracts[, c("geo_id", "ratio", "suppressed", "class")], b$tracts[, c("geo_id", "ratio", "suppressed")],
             by = "geo_id", suffixes = c("", ".b"))
  m <- m[!m$suppressed & !m$suppressed.b, ]
  w <- 400; h <- 360; ml <- 46; mb <- 40; mt <- 12; mr <- 12
  lo <- 0.25; hi <- 2.2
  x <- logsc(lo, hi, ml, w - mr); y <- logsc(lo, hi, h - mb, mt)
  ticks <- c(0.25, 0.5, 1, 2)
  body <- paste(vapply(ticks, function(v) paste0(
    tag("line", x1 = f1(x(v)), x2 = f1(x(v)), y1 = mt, y2 = h - mb, class = if (v == 1) "base" else "grid"),
    tag("line", x1 = ml, x2 = w - mr, y1 = f1(y(v)), y2 = f1(y(v)), class = if (v == 1) "base" else "grid"),
    txt(x(v), h - mb + 15, formatC(v, format = "fg"), "ax", "middle"),
    txt(ml - 6, y(v) + 4, formatC(v, format = "fg"), "ax", "end")), ""), collapse = "")
  body <- paste0(body, tag("line", x1 = f1(x(lo)), y1 = f1(y(lo)), x2 = f1(x(hi)), y2 = f1(y(hi)), class = "ref"))
  g <- group_of_class(m$class)
  o <- order(g != "other")
  m <- m[o, ]; g <- g[o]
  cl <- function(v) pmin(hi, pmax(lo, v))
  body <- paste0(body, paste(sprintf("<circle cx=\"%s\" cy=\"%s\" r=\"%s\" class=\"dot dot-%s\" data-tip=\"%s\" data-tract=\"%s\"/>",
    f1(x(cl(m$ratio.b))), f1(y(cl(m$ratio))), ifelse(g == "other", "2.4", "3.2"), g,
    vapply(sprintf("%s\n%s: %s\n%s: %s", M$ti$name[match(m$geo_id, M$ti$geo_id)], ylab, fmt_ratio(m$ratio), xlab,
                   fmt_ratio(m$ratio.b)), esc, ""), m$geo_id), collapse = ""))
  rho <- stats::cor(m$ratio, m$ratio.b, method = "spearman")
  body <- paste0(body, txt(x(1.75), y(1.75) - 8, "same in both periods", "ax", "end"),
                 txt(w - mr - 4, h - mb - 10, sprintf("Spearman rank correlation %s (%d tracts)", f2(rho), nrow(m)), "val", "end"),
                 txt((ml + w - mr) / 2, h - 6, xlab, "ax", "middle"),
                 txt(12, (mt + h - mb) / 2, ylab, "ax", "middle", transform = sprintf("rotate(-90 12 %s)", f1((mt + h - mb) / 2))))
  list(body = body, w = w, h = h, rho = rho, n = nrow(m))
}
