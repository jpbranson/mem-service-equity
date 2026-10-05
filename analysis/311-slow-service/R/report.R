# Report assembly: the figure model, the exported SVGs, and one
# self-contained HTML page. Every number in the text is computed here from
# the results, never typed in.

report_model <- function(res, tg, x) {
  crs <- memequity::MSE_CRS_METERS
  t <- res$prim$tracts[match(tg$geo_id, res$prim$tracts$geo_id), ]
  geo <- sf::st_simplify(tg, preserveTopology = TRUE, dTolerance = 15)
  city <- sf::st_simplify(sf::st_union(sf::st_transform(memequity::load_boundaries("citywide"), crs)),
                          preserveTopology = TRUE, dTolerance = 15)
  city <- sf::st_sf(geometry = city)
  bbox <- sf::st_bbox(city)
  fr <- map_frame(bbox, 460)
  ti <- tract_info(x, tg$geo_id)
  ti$council <- majority_of(x, "council_district")[tg$geo_id]
  # Reference-neighborhood labels at a point inside their in-city ZIP area
  rn <- memequity::reference_neighborhoods()
  z <- sf::st_transform(memequity::load_boundaries("zcta"), crs)
  lab <- do.call(rbind, lapply(unique(rn$neighborhood), function(nm) {
    g <- suppressWarnings(sf::st_intersection(sf::st_union(z[z$geo_id %in% rn$zip[rn$neighborhood == nm], ]),
                                              sf::st_geometry(city)))
    if (!length(g) || sf::st_is_empty(g)) return(NULL)
    parts <- suppressWarnings(sf::st_cast(sf::st_collection_extract(sf::st_sf(geometry = g), "POLYGON"), "POLYGON"))
    big <- parts[which.max(sf::st_area(parts)), ]
    p <- sf::st_coordinates(sf::st_point_on_surface(sf::st_geometry(big)))
    data.frame(x = p[1, 1], y = p[1, 2], label = nm, cls = "lbl", stringsAsFactors = FALSE)
  }))
  list(t = t, geo = geo, outline = city, bbox = bbox, fr = fr, ti = ti, tips = tract_tip(ti, t),
       labels = lab, cluster_labels = lab, group_ratios = res$group_ratios, type_groups = res$type_groups,
       top_types = res$top_types, thresholds = res$prim$thresholds, codes = res$codes, context = res$context)
}

majority_of <- function(x, col) {
  sr <- x$sr[is.na(x$sr$exclusion) & x$sr$in_city %in% TRUE & !is.na(x$sr$tract), ]
  tapply(sr[[col]], sr$tract, function(v) { v <- v[!is.na(v)]; if (!length(v)) NA else names(sort(table(v), decreasing = TRUE))[1] })
}

# Where a set of tracts sits: north/south/east/west of the city's middle,
# the ZIPs holding most of them, and the reference neighborhoods among those.
where_of <- function(M, ids) {
  g <- M$geo[M$geo$geo_id %in% ids, ]
  c0 <- sf::st_coordinates(sf::st_centroid(sf::st_union(g)))
  bb <- M$bbox
  ny <- (c0[2] - bb[["ymin"]]) / (bb[["ymax"]] - bb[["ymin"]])
  nx <- (c0[1] - bb[["xmin"]]) / (bb[["xmax"]] - bb[["xmin"]])
  ns <- if (ny > 0.6) "north" else if (ny < 0.4) "south" else ""
  ew <- if (nx > 0.62) "east" else if (nx < 0.38) "west" else ""
  dir <- if (nzchar(ns) && nzchar(ew)) paste0(ns, ew) else if (nzchar(ns)) ns else if (nzchar(ew)) ew else "center"
  ti <- M$ti[M$ti$geo_id %in% ids, ]
  zt <- sort(table(ti$zip), decreasing = TRUE)
  zips <- names(zt)[cumsum(zt) / sum(zt) <= 0.75 | seq_along(zt) == 1]
  nb <- unique(stats::na.omit(ti$nbhd[ti$zip %in% zips]))
  ct <- sort(table(ti$council), decreasing = TRUE)
  list(dir = dir, zips = zips, nbhds = nb, council = names(ct)[ct >= 2 | seq_along(ct) == 1], n = nrow(ti))
}
and_list <- function(v) if (length(v) <= 1) paste(v, collapse = "") else paste(paste(v[-length(v)], collapse = ", "), "and", v[length(v)])

theme_css <- function() {
  "
:root{--page:#f6f6f3;--surface:#fcfcfb;--surface-2:#efeeea;--text-1:#141413;--text-2:#4f4e4a;--muted:#7d7b75;
--grid:#e3e2dc;--baseline:#b9b8b0;--rule:#dcdbd4;--hatch:#bdbcb4;--accent:#1c5cab;
--slow-3:#892b2a;--slow-2:#d75853;--slow-1:#f1aea8;--neutral:#e9e8e3;--fast-1:#9ec5f4;--fast-2:#3987e5;--fast-3:#184f95;
--c-slow:#d75853;--c-fast:#3987e5;--on-3:#ffffff;--on-2:#141413;--on-1:#141413;--on-0:#141413;
--c1:#1baf7a;--c2:#4a3aa7;--c3:#eda100;--c-other:#c9c8c0;--on-c1:#141413;--on-c2:#ffffff;--on-c3:#141413;--on-c-other:#141413;}
@media (prefers-color-scheme:dark){:root:not([data-theme=\"light\"]){color-scheme:dark;--page:#111110;--surface:#1a1a19;--surface-2:#242422;
--text-1:#f4f3ee;--text-2:#c3c2b7;--muted:#8f8d86;--grid:#2c2c2a;--baseline:#4a4a46;--rule:#33332f;--hatch:#55544f;--accent:#86b6ef;
--slow-3:#ea9a93;--slow-2:#c74845;--slow-1:#892b2a;--neutral:#383835;--fast-1:#184f95;--fast-2:#2a78d6;--fast-3:#86b6ef;
--c-slow:#c74845;--c-fast:#2a78d6;--on-3:#141413;--on-2:#ffffff;--on-1:#ffffff;--on-0:#f4f3ee;
--c1:#199e70;--c2:#9085e9;--c3:#c98500;--c-other:#55544f;--on-c1:#141413;--on-c2:#141413;--on-c3:#141413;--on-c-other:#f4f3ee;}}
:root[data-theme=\"dark\"]{color-scheme:dark;--page:#111110;--surface:#1a1a19;--surface-2:#242422;
--text-1:#f4f3ee;--text-2:#c3c2b7;--muted:#8f8d86;--grid:#2c2c2a;--baseline:#4a4a46;--rule:#33332f;--hatch:#55544f;--accent:#86b6ef;
--slow-3:#ea9a93;--slow-2:#c74845;--slow-1:#892b2a;--neutral:#383835;--fast-1:#184f95;--fast-2:#2a78d6;--fast-3:#86b6ef;
--c-slow:#c74845;--c-fast:#2a78d6;--on-3:#141413;--on-2:#ffffff;--on-1:#ffffff;--on-0:#f4f3ee;
--c1:#199e70;--c2:#9085e9;--c3:#c98500;--c-other:#55544f;--on-c1:#141413;--on-c2:#141413;--on-c3:#141413;--on-c-other:#f4f3ee;}
"
}

svg_css <- function() {
  "
.fig-svg{font-family:inherit;display:block;width:100%;height:auto;overflow:visible}
.fig-svg text{font-family:\"Public Sans\",system-ui,-apple-system,\"Segoe UI\",sans-serif}
.tr{stroke:var(--surface);stroke-width:.6}
.tr.hot,.dot.hot{stroke:var(--text-1);stroke-width:1.8}
.f3{fill:var(--fast-3)}.f2{fill:var(--fast-2)}.f1{fill:var(--fast-1)}.n0{fill:var(--neutral)}
.s1{fill:var(--slow-1)}.s2{fill:var(--slow-2)}.s3{fill:var(--slow-3)}
.l-hh{fill:var(--slow-3)}.l-ll{fill:var(--fast-3)}.l-hl{fill:var(--slow-2)}.l-lh{fill:var(--fast-2)}
.l-hu{fill:var(--slow-1)}.l-lu{fill:var(--fast-1)}.l-ns{fill:var(--neutral)}
.hatch-bg{fill:var(--surface)}.hatch-ln{stroke:var(--hatch);stroke-width:1.4}
.city{fill:none;stroke:var(--text-2);stroke-width:1}
.nores{fill:var(--surface-2);stroke:none}
.lbl{font-size:11px;font-weight:600;fill:var(--text-1);stroke:var(--surface);stroke-width:3px;paint-order:stroke;stroke-linejoin:round}
.leg{font-size:11px;fill:var(--text-2)}
.ax{font-size:10.5px;fill:var(--muted)}
.lab{font-size:11.5px;fill:var(--text-1)}
.val{font-size:11px;fill:var(--text-2);font-variant-numeric:tabular-nums}
.val.muted{fill:var(--muted)}
.panel-t{font-size:12.5px;font-weight:600;fill:var(--text-1)}
.fig-title{font-size:15px;font-weight:600;fill:var(--text-1)}
.src{font-size:10px;fill:var(--muted)}
.grid{stroke:var(--grid);stroke-width:1}
.base{stroke:var(--baseline);stroke-width:1.2}
.ref{stroke:var(--text-2);stroke-width:1.2;stroke-dasharray:3 3;fill:none}
.bracket{stroke:var(--baseline);stroke-width:1.5}
.dot-slow_core{fill:var(--c-slow)}.dot-fast_core{fill:var(--c-fast)}
.dot-other{fill:var(--surface);stroke:var(--muted);stroke-width:1.1}
.ci{stroke-width:1.2;stroke-linecap:round}.ci.thick{stroke-width:2.5}
.ci-slow_core{stroke:var(--c-slow)}.ci-fast_core{stroke:var(--c-fast)}.ci-other{stroke:var(--baseline)}
.cell-t{font-size:11.5px;font-weight:600;font-variant-numeric:tabular-nums}
.on-3{fill:var(--on-3)}.on-2{fill:var(--on-2)}.on-1{fill:var(--on-1)}.on-0{fill:var(--on-0)}
.c1{fill:var(--c1)}.c2{fill:var(--c2)}.c3{fill:var(--c3)}.c-other{fill:var(--c-other)}
.seg-t{font-size:11px;font-weight:600}
.on-c1{fill:var(--on-c1)}.on-c2{fill:var(--on-c2)}.on-c3{fill:var(--on-c3)}.on-c-other{fill:var(--on-c-other)}
.hd-slow_core{fill:var(--c-slow);font-weight:600}.hd-fast_core{fill:var(--c-fast);font-weight:600}
"
}

# Light theme only, as plain values, for the exported SVG files.
export_css <- function() {
  light <- sub("@media.*$", "", theme_css())
  paste0(light, svg_css(), ".fig-svg{background:var(--surface)} text{font-family:system-ui,-apple-system,\"Segoe UI\",sans-serif}")
}

page_css <- function() {
  paste0(theme_css(), svg_css(), "
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--page);color:var(--text-1);font:15.5px/1.6 \"Public Sans\",system-ui,-apple-system,\"Segoe UI\",sans-serif;padding-inline:16px;padding-block:0 64px}
.wrap{max-width:1000px;margin:0 auto}
.col{max-width:68ch}
header.top{padding-block:44px 8px;border-bottom:1px solid var(--rule);margin-bottom:28px}
.eyebrow{font:600 11.5px/1.2 \"IBM Plex Mono\",ui-monospace,Menlo,monospace;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);margin:0 0 14px}
h1{font-size:clamp(30px,4.6vw,44px);line-height:1.08;letter-spacing:-.015em;margin:0 0 14px;text-wrap:balance;font-weight:700}
.dek{font-size:18px;line-height:1.5;color:var(--text-2);margin:0 0 18px;max-width:62ch;text-wrap:pretty}
.meta{font:12px/1.5 \"IBM Plex Mono\",ui-monospace,Menlo,monospace;color:var(--muted);margin:0 0 20px;display:flex;flex-wrap:wrap;gap:4px 18px}
h2{font-size:22px;line-height:1.25;margin:48px 0 12px;text-wrap:balance;letter-spacing:-.005em}
h3{font-size:17px;line-height:1.3;margin:0 0 6px;text-wrap:balance}
h4{font-size:14px;margin:18px 0 6px}
p{margin:0 0 14px}
.lead{font-size:17px;line-height:1.62}
.lead strong{font-weight:650}
ul.keys{margin:0 0 18px;padding-left:20px;font-size:16.5px;line-height:1.55}ul.keys li{margin:6px 0}
figure .interp p{margin:0 0 6px}figure .interp ul{margin:0}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;margin:22px 0 8px}
.tile{background:var(--surface);border:1px solid var(--rule);border-radius:6px;padding:14px 16px}
.tile .num{font-size:30px;font-weight:700;line-height:1.1;letter-spacing:-.01em}
.tile .num.slow{color:var(--c-slow)}.tile .num.fast{color:var(--c-fast)}
.tile .cap{font-size:13px;color:var(--text-2);line-height:1.4;margin-top:4px}
figure{margin:34px 0 10px;background:var(--surface);border:1px solid var(--rule);border-radius:8px;padding:20px 20px 14px}
figure .interp{color:var(--text-2);margin:0 0 16px;max-width:75ch}
.panels{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:22px 28px;align-items:start}
.scroll{overflow-x:auto;-webkit-overflow-scrolling:touch}
.scroll>.fig-svg{min-width:560px}
figcaption,.notes{font-size:12.5px;line-height:1.5;color:var(--muted);margin-top:12px;border-top:1px solid var(--rule);padding-top:10px}
.scatter{max-width:440px;margin-top:18px}
ul.tight{margin:0 0 14px;padding-left:20px}ul.tight li{margin:3px 0}
.kv{display:grid;grid-template-columns:max-content 1fr;gap:4px 16px;font-size:14px;margin:0 0 16px}
.kv dt{color:var(--muted);font:12.5px/1.6 \"IBM Plex Mono\",ui-monospace,Menlo,monospace}
.kv dd{margin:0}
table{border-collapse:collapse;width:100%;font-size:13px;font-variant-numeric:tabular-nums}
th,td{text-align:left;padding:6px 10px 6px 0;border-bottom:1px solid var(--rule);vertical-align:top}
th{font-weight:600;color:var(--text-2);font-size:12px}
td.n,th.n{text-align:right}
.tablewrap{overflow-x:auto;margin:10px 0 16px}
details{margin:14px 0;background:var(--surface);border:1px solid var(--rule);border-radius:8px;padding:12px 16px}
summary{cursor:pointer;font-weight:600}
summary:focus-visible,a:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
code,pre{font-family:\"IBM Plex Mono\",ui-monospace,Menlo,monospace;font-size:12.5px}
code{background:var(--surface-2);padding:1px 5px;border-radius:3px}
pre{background:var(--surface-2);padding:12px 14px;border-radius:6px;overflow-x:auto;line-height:1.5}
a{color:var(--accent)}
.pill{display:inline-block;font:600 11px/1 \"IBM Plex Mono\",ui-monospace,monospace;padding:4px 7px;border-radius:999px;background:var(--surface-2);color:var(--text-2)}
.pill.slow{background:var(--slow-1);color:var(--on-1)}.pill.fast{background:var(--fast-1);color:var(--on-1)}
#tip{position:fixed;z-index:10;pointer-events:none;max-width:300px;background:var(--text-1);color:var(--page);font:12px/1.45 \"Public Sans\",system-ui,sans-serif;padding:8px 10px;border-radius:6px;white-space:pre-line;box-shadow:0 4px 16px rgba(0,0,0,.18)}
footer{margin-top:48px;padding-top:16px;border-top:1px solid var(--rule);font-size:12.5px;color:var(--muted)}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
")
}

page_js <- function() {
  "
(function(){var tip=document.getElementById('tip');var hot=[];
function clear(){hot.forEach(function(e){e.classList.remove('hot')});hot=[];tip.hidden=true;}
function show(t,x,y){tip.textContent=t.getAttribute('data-tip');tip.hidden=false;place(x,y);
var id=t.getAttribute('data-tract');if(id){document.querySelectorAll('[data-tract=\"'+id+'\"]').forEach(function(e){e.classList.add('hot');hot.push(e);});}else{t.classList.add('hot');hot.push(t);}}
function place(x,y){var w=tip.offsetWidth,h=tip.offsetHeight;var nx=x+14,ny=y+14;if(nx+w>innerWidth-8)nx=x-w-14;if(ny+h>innerHeight-8)ny=y-h-14;tip.style.left=Math.max(8,nx)+'px';tip.style.top=Math.max(8,ny)+'px';}
document.addEventListener('pointerover',function(e){var t=e.target.closest&&e.target.closest('[data-tip]');clear();if(t)show(t,e.clientX,e.clientY);});
document.addEventListener('pointermove',function(e){if(!tip.hidden)place(e.clientX,e.clientY);});
document.addEventListener('pointerleave',clear);window.addEventListener('scroll',clear,{passive:true});})();
"
}

td <- function(x, cls = NULL) sprintf("<td%s>%s</td>", if (is.null(cls)) "" else sprintf(" class=\"%s\"", cls), x)

build_report <- function(res, tg, x, out_dir) {
  M <- report_model(res, tg, x)
  P <- res$params
  sl <- spec_list(res)
  ss <- spec_summary(res)
  prim <- res$prim
  gr <- res$group_ratios; rownames(gr) <- gr$group
  tt <- res$type_groups
  bt <- function(g) tt$median_days[tt$request_type == "SWM-Missed Bulk Trash" & tt$group == g]
  thr_bulk <- prim$thresholds$threshold[prim$thresholds$request_type == "SWM-Missed Bulk Trash"]
  cc <- res$codes
  code_share <- function(code, g) { v <- cc$share[cc$code == code & cc$group == g]; if (length(v)) v else 0 }
  top_code <- function(g) { s <- cc[cc$group == g & cc$code != "other codes", ]; s[which.max(s$share), ] }
  slow_ids <- prim$tracts$geo_id[prim$tracts$class == "HH"]
  fast_ids <- prim$tracts$geo_id[prim$tracts$class == "LL"]
  wf <- where_of(M, fast_ids); ws <- where_of(M, slow_ids)
  pt <- prim$tracts
  other_fast <- pt$geo_id[!pt$suppressed & pt$ratio < 1 / 1.2 & pt$class != "LL" &
                            !M$ti$zip[match(pt$geo_id, M$ti$geo_id)] %in% wf$zips]
  s25 <- ss[ss$spec == "y2025", ]; sk <- ss[ss$spec == "knn6", ]; sn <- ss[ss$spec == "no_swm", ]; sp <- ss[ss$spec == "primary", ]
  w25s <- where_of(M, res$y25$tracts$geo_id[res$y25$tracts$class == "HH"])
  sc <- fig4_scatter(M, res$prim, res$y25, "Jun-Jul 2025 ratio", "Jun-Aug 2026 ratio")
  flow <- prim$flow
  thr <- prim$thresholds
  excl_types <- thr[thr$status == "median_not_reached", ]
  excl_types <- excl_types[order(-excl_types$n), ]
  weeds <- excl_types[excl_types$request_type %in% c("CW-Weeds Vacant Lots", "CW-Weeds Vacant Houses"), ]
  still_open <- function(types) { d <- prim$requests[prim$requests$request_type %in% types, ]; mean(!d$closed) }
  wq <- prim$requests[prim$requests$request_type %in% weeds$request_type, ]
  wq$group <- res$groups[wq$tract]
  weeds_open_by_group <- tapply(!wq$closed, wq$group, mean)
  cx <- res$context
  cval <- function(m, g) cx$value[cx$measure == m & cx$group == g]
  win_txt <- function(a, b) sprintf("%s to %s", dmy(a), dmy(b))
  src_line <- sprintf("Source: City of Memphis 311 service requests (copy of %s); 2020 census tracts and city limits, Census TIGERweb. Analysis: analysis/311-slow-service.",
                      dmy(P$as_of, "%b"))

  # ---- figures -----------------------------------------------------------------
  fig1p <- fig1_panels(M)
  f1a <- fig1p$a; f1b <- fig1p$b
  f2a <- fig2_caterpillar(M); f2b <- fig2_groups(M)
  f3a <- fig3_heatmap(M); f3b <- fig3_codes(M); f3c <- fig3_context(M)
  specs4 <- lapply(sl, function(s) list(tracts = s$s$tracts, title = s$title, sub = sprintf("%s · Moran's I = %s", s$sub, f2(s$s$moran$I)), label = s$label))
  f4a <- fig4_minimaps(M, specs4)
  inline <- list(
    f1a = finish(f1a, "fig1a", "Map of the slow-request ratio by census tract"),
    f1b = finish(f1b, "fig1b", "Map of local Moran's I cluster cores"),
    f2a = finish(f2a, "fig2a", "Each tract's slow-request ratio with its 95 percent interval"),
    f2b = finish(f2b, "fig2b", "Pooled slow-request ratio for each group of tracts"),
    f3a = finish(f3a, "fig3a", "Median business days and slow-request ratio by request type and group"),
    f3b = finish(f3b, "fig3b", "Resolution codes on closed bulk-trash requests by group"),
    f3c = finish(f3c, "fig3c", "Neighborhood context by group"),
    f4a = finish(f4a, "fig4a", "Cluster cores under four specifications"),
    f4b = finish(sc, "fig4b", "Tract ratios in 2025 against 2026"))
  titles <- c(
    fig1 = "Figure 1. The north closes requests fast; the southwest, slow",
    fig2 = "Figure 2. The two clusters sit at the ends of the range; most tracts are near average",
    fig3 = "Figure 3. The difference is in trash pickup, and in how it is recorded",
    fig4 = "Figure 4. The fast cluster holds up; the slow cluster moves between years")
  ex <- export_css()
  exports <- list(
    fig1_map = finish(side_by_side(list(f1a, f1b), 28), "e1", titles[["fig1"]], titles[["fig1"]], src_line),
    fig2_ratios = finish(stacked(list(f2a, f2b), 22), "e2", titles[["fig2"]], titles[["fig2"]], src_line),
    fig3_profile = finish(stacked(list(f3a, f3b, f3c), 26), "e3", titles[["fig3"]], titles[["fig3"]],
                          paste(src_line, "Context: ACS 2020-2024 5-year; City DPD permits; Data Midsouth demolitions snapshot.")),
    fig4_robustness = finish(side_by_side(list(f4a, sc), 36), "e4", titles[["fig4"]], titles[["fig4"]], src_line))
  for (nm in names(exports))
    writeLines(svg_standalone(exports[[nm]], ex), file.path(out_dir, "figures", paste0(nm, ".svg")), useBytes = TRUE)

  # ---- text pieces ---------------------------------------------------------------
  n_an <- sum(!prim$tracts$suppressed)
  fast_less <- 1 - gr["fast_core", "ratio"]; slow_more <- gr["slow_core", "ratio"] - 1
  # "ZIPs 38127 (Frayser) and 38128 (Raleigh)": each ZIP with its reference-neighborhood name, if any.
  zips_txt <- function(w) {
    rn <- memequity::reference_neighborhoods()
    lab <- vapply(w$zips, function(z) { n <- rn$neighborhood[rn$zip == z]; if (length(n)) sprintf("%s (%s)", z, n[1]) else z }, "")
    sprintf("ZIP%s %s", if (length(w$zips) > 1) "s" else "", and_list(lab))
  }
  where_txt <- function(w) paste("mostly in", zips_txt(w))
  kept <- function(s, which) s[[paste0("primary_", which, "_cores_any")]] / sp[[paste0(which, "_cores")]]
  dname <- function(d) c(north = "north", south = "south", east = "east", west = "west", northwest = "northwest",
                         northeast = "northeast", southwest = "southwest", southeast = "southeast", center = "middle")[[d]]
  daysw <- function(d) sprintf("%s business day%s", formatC(d, format = "fg"), if (d == 1) "" else "s")
  tc_fast <- top_code("fast_core"); tc_slow <- top_code("slow_core")
  codename <- function(cd) if (cd == "(no code)") "no resolution code" else sprintf("code <code>%s</code>", cd)
  swm_share <- mean(startsWith(prim$eligible$request_type, "SWM"))
  bulk_share <- mean(prim$eligible$request_type == "SWM-Missed Bulk Trash")

  cap1 <- function(s) paste0(toupper(substr(s, 1, 1)), substring(s, 2))
  lead <- sprintf(paste0(
    "<p class=\"lead\">From June to August 2026, 311 requests in some parts of Memphis closed much faster or slower than ",
    "the same kinds of request elsewhere. These places sit together in two large clusters.</p><ul class=\"keys\">",
    "<li><strong>Fast cluster, %s:</strong> %d tracts, %s. %s fewer requests than expected ran past the citywide typical time for their type.</li>",
    "<li><strong>Slow cluster, %s:</strong> %d tracts, %s. %s more did.</li>",
    "<li><strong>The gap is mostly trash pickup.</strong> A bulk-trash request closed in a median of %s in the fast cluster, %s citywide and %s in the slow cluster.</li>",
    "<li><strong>Part of the gap may be record-keeping.</strong> The two clusters close these requests with different codes in the City's system (Figure 3B), so faster closing may not mean faster pickup.</li>",
    "<li>%s</li></ul>"),
    dname(wf$dir), length(fast_ids), where_txt(wf), cap1(pct(fast_less)),
    dname(ws$dir), length(slow_ids), where_txt(ws), cap1(pct(slow_more)),
    daysw(bt("fast_core")), daysw(thr_bulk), daysw(bt("slow_core")),
    if (kept(s25, "fast") >= 0.6 && kept(s25, "slow") < 0.5)
      sprintf("<strong>The fast cluster is stable; the slow one moves.</strong> A year earlier the fast cluster was in the same place, while the slow cluster was %s.", where_txt(w25s))
    else if (kept(s25, "fast") >= 0.6 && kept(s25, "slow") >= 0.6) "<strong>Both clusters are stable.</strong> A year earlier they were in the same places."
    else sprintf("<strong>The clusters shift over time.</strong> A year earlier, %d of the %d fast and %d of the %d slow cores were again at least nominally significant.",
                 s25$primary_fast_cores_any, sp$fast_cores, s25$primary_slow_cores_any, sp$slow_cores))

  tiles <- sprintf(paste0(
    "<div class=\"tiles\">",
    "<div class=\"tile\"><div class=\"num\">%s</div><div class=\"cap\">Moran's I across %d tracts: how alike neighboring tracts are (0 means no pattern). %s</div></div>",
    "<div class=\"tile\"><div class=\"num slow\">%s</div><div class=\"cap\">Slow requests vs expected in the slow cluster: %s ran past the typical time, against %s expected.</div></div>",
    "<div class=\"tile\"><div class=\"num fast\">%s</div><div class=\"cap\">The same in the fast cluster: %s, against %s expected.</div></div>",
    "</div>"),
    f2(sp$moran_I), n_an,
    if (sp$p_perm <= 1 / (P$nsim_global + 1)) sprintf("None of %s random shuffles of the tracts came this high.", fmt_n(P$nsim_global))
    else sprintf("Permutation p = %s.", formatC(sp$p_perm, format = "g")),
    fmt_ratio(gr["slow_core", "ratio"]), pct(gr["slow_core", "observed_share"]), pct(gr["slow_core", "expected_share"]),
    fmt_ratio(gr["fast_core", "ratio"]), pct(gr["fast_core", "observed_share"]), pct(gr["fast_core", "expected_share"]))

  question <- sprintf(paste0(
    "<h2 id=\"question\">The question</h2><div class=\"col\">",
    "<p><strong>Does how long the City takes to close a 311 request depend on where it was filed, when each request is compared only with requests of the same type?</strong></p>",
    "<dl class=\"kv\"><dt>Slow request</dt><dd>Not closed within the citywide median time for its type, counted in City business days (D10). A request still open counts as slow once that time has passed.</dd>",
    "<dt>Eligible request</dt><dd>Opened in the period and old enough to judge: its type's typical time has passed.</dd>",
    "<dt>Expected</dt><dd>The number of slow requests a tract would have if each of its requests fared like the city average for its type.</dd>",
    "<dt>Ratio</dt><dd>Slow ÷ expected. 1.0 is average; 1.3 means 30%% more slow requests than expected.</dd>",
    "<dt>Areas</dt><dd>2020 census tracts, clipped to the city limits. %d overlap the city; %d have at least %d eligible requests and are analysed.</dd>",
    "<dt>Period</dt><dd>Requests opened %s; data through %s. %s eligible requests of %d types.</dd></dl>",
    "<p>Comparing like with like matters because types differ a lot: a pothole typically closes in %s, a weeds case in %s. Without this, an area would look slow just because it reports more weeds cases.</p>",
    "<h4>Why this question</h4><ul class=\"tight\">",
    "<li><strong>Chosen.</strong> It measures something residents experience, uses %s requests with exact locations, and needs no population denominator.</li>",
    "<li><strong>Not chosen: profiles combining 311, permits and inspections.</strong> The sources cover different periods (3 months, 5 years, 21 months), inspections are too sparse per tract, and the result would be a composite score.</li>",
    "<li><strong>Not chosen: requests per resident.</strong> Volume mixes how many problems an area has with how often people report them. It appears only as context.</li></ul></div>"),
    nrow(tg), n_an, P$min_tract_n, win_txt(prim$from, prim$to), dmy(P$as_of - 1),
    fmt_n(flow[["analysed"]]), sum(thr$status == "ok"),
    daysw(thr$threshold[thr$request_type == "PW (SM)-Potholes"]),
    daysw(thr$threshold[thr$request_type == "CE-Weeds Occupied Property"]), fmt_n(flow[["analysed"]]))

  fig1 <- sprintf(paste0(
    "<figure id=\"fig1\"><h3>%s</h3>",
    "<p class=\"interp\">Map A shows each tract's ratio. Map B shows where the pattern is statistically supported. ",
    "A <em>cluster core</em> is a slow (or fast) tract whose neighbors are also slow (or fast), more than chance would produce. ",
    "The test compares each tract with %s random shuffles of the tract values and corrects for testing %d tracts at once. %s</p>",
    "<div class=\"panels\"><div>%s</div><div>%s</div></div>",
    "<figcaption>Requests opened %s. Colors are symmetric, so 40%% more and 40%% fewer look equally strong. ",
    "B: local Moran's I on smoothed ratios (see Methods), with touching tracts as neighbors and a 5%% false discovery rate. Gray: no residents. Hover a tract to see its numbers in both maps. %s</figcaption></figure>"),
    titles[["fig1"]], fmt_n(P$nsim_local), n_an,
    if (length(other_fast)) sprintf(paste0("Another %d tracts have at least 20%% fewer slow requests than expected, %s. ",
                                           "They are less extreme and mixed with average tracts, so none is a cluster core."),
                                    length(other_fast), where_txt(where_of(M, other_fast))) else "",
    inline$f1a, inline$f1b,
    win_txt(prim$from, prim$to), src_line)

  n_ci_hi <- sum(!prim$tracts$suppressed & prim$tracts$ci_low > 1)
  n_ci_lo <- sum(!prim$tracts$suppressed & prim$tracts$ci_high < 1)
  fig2 <- sprintf(paste0(
    "<figure id=\"fig2\"><h3>%s</h3>",
    "<p class=\"interp\">Pooled, the slow cluster had %s the expected number of slow requests, the fast cluster %s, and the other %d tracts %s. ",
    "Tract ratios run from %s to %s. Judged one at a time, %d tracts are clearly above 1.0 and %d clearly below. These intervals are too narrow, though, because requests on one route are often closed together.</p>",
    "<div class=\"scroll\">%s</div><div class=\"scroll\" style=\"margin-top:14px\">%s</div>",
    "<figcaption>Requests opened %s; %d tracts with at least %d eligible requests. 95%% intervals: Wilson interval on the slow share, divided by the expected share. %s</figcaption></figure>"),
    titles[["fig2"]], fmt_ratio(gr["slow_core", "ratio"]), fmt_ratio(gr["fast_core", "ratio"]), gr["other", "tracts"],
    fmt_ratio(gr["other", "ratio"]),
    f2(min(prim$tracts$ratio[!prim$tracts$suppressed])), f2(max(prim$tracts$ratio[!prim$tracts$suppressed])),
    n_ci_hi, n_ci_lo, inline$f2a, inline$f2b, win_txt(prim$from, prim$to), n_an, P$min_tract_n, src_line)

  nonswm_types <- res$top_types[!startsWith(res$top_types, "SWM")]
  rng <- function(g) { v <- tt$ratio[tt$group == g & tt$request_type %in% nonswm_types]; sprintf("%s–%s×", f2(min(v)), f2(max(v))) }
  pick <- function(ty, g) tt$ratio[tt$request_type == ty & tt$group == g]
  fig3 <- sprintf(paste0(
    "<figure id=\"fig3\"><h3>%s</h3>",
    "<p class=\"interp\"><strong>A. Three collection services make the clusters.</strong> Slow bulk-trash, missed-garbage and missed-recycling requests ran at %s, %s and %s the expected rate in the fast cluster, and %s, %s and %s in the slow cluster. ",
    "Other request types differ much less (%s in the fast cluster, %s in the slow). Solid waste is %s of requests; bulk trash alone is %s.</p>",
    "<div class=\"scroll\">%s</div>",
    "<p class=\"interp\" style=\"margin-top:18px\"><strong>B. The clusters close bulk-trash requests differently.</strong> In the fast cluster, %s close with %s; in the slow cluster, %s close with %s. ",
    "The City does not publish what the codes mean, so the data cannot tell whether the fast cluster collects faster or only closes requests faster. The project's disposition audit (H4) would answer this.</p>",
    "<div class=\"scroll\">%s</div>",
    "<p class=\"interp\" style=\"margin-top:18px\"><strong>C. Demographics do not separate the two clusters.</strong> Both are majority-Black and poorer than the rest of the city (fast / slow: %s / %s Black, not Hispanic; %s / %s in poverty, against %s and %s elsewhere). ",
    "The slow cluster reports more per resident (%s requests per 1,000 in three months, against %s). Over five years, per 1,000 homes (fast / slow): renovation permits %s / %s, demolitions %s / %s, new-home permits %s / %s. ",
    "These describe areas; they are not causes.</p>",
    "<div class=\"scroll\">%s</div>",
    "<figcaption>A: requests opened %s; Kaplan-Meier median business days (open requests censored). B: closed <code>SWM-Missed Bulk Trash</code> requests; codes under 5%% in every group are pooled. ",
    "C: ACS 2020-2024 with 90%% margins of error; permits (City DPD, Sep 2021 to Aug 2026) and demolitions (Data Midsouth snapshot, Aug 2021 to Jul 2026) per 1,000 housing units, with 95%% Poisson intervals. Dashed tick: citywide. %s</figcaption></figure>"),
    titles[["fig3"]],
    fmt_ratio(pick("SWM-Missed Bulk Trash", "fast_core")), fmt_ratio(pick("SWM-Garbage Missed", "fast_core")), fmt_ratio(pick("SWM-Recycling Missed", "fast_core")),
    fmt_ratio(pick("SWM-Missed Bulk Trash", "slow_core")), fmt_ratio(pick("SWM-Garbage Missed", "slow_core")), fmt_ratio(pick("SWM-Recycling Missed", "slow_core")),
    rng("fast_core"), rng("slow_core"), pct(swm_share), pct(bulk_share), inline$f3a,
    pct(tc_fast$share), codename(tc_fast$code), pct(tc_slow$share), codename(tc_slow$code), inline$f3b,
    pct(cval("pct_black_nh", "fast_core")), pct(cval("pct_black_nh", "slow_core")), pct(cval("pct_poverty", "fast_core")),
    pct(cval("pct_poverty", "slow_core")), pct(cval("pct_black_nh", "other")), pct(cval("pct_poverty", "other")),
    formatC(cval("requests_per_1000_residents", "slow_core"), format = "f", digits = 0),
    formatC(cval("requests_per_1000_residents", "fast_core"), format = "f", digits = 0),
    f1(cval("renovation_permits_per_1000_hu", "fast_core")), f1(cval("renovation_permits_per_1000_hu", "slow_core")),
    f1(cval("demolitions_per_1000_hu", "fast_core")), f1(cval("demolitions_per_1000_hu", "slow_core")),
    f1(cval("new_home_permits_per_1000_hu", "fast_core")), f1(cval("new_home_permits_per_1000_hu", "slow_core")), inline$f3c,
    win_txt(prim$from, prim$to), src_line)

  spec_rows <- paste(vapply(seq_len(nrow(ss)), function(i) {
    r <- ss[i, ]
    paste0("<tr>", td(esc(r$label)), td(sprintf("%s (z = %s)", f2(r$moran_I), formatC(r$z, format = "f", digits = 1)), "n"),
           td(r$slow_cores, "n"), td(r$fast_cores, "n"),
           td(if (r$spec == "primary") "&ndash;" else sprintf("%d of %d (%d)", r$primary_slow_cores_kept, sp$slow_cores, r$primary_slow_cores_any), "n"),
           td(if (r$spec == "primary") "&ndash;" else sprintf("%d of %d (%d)", r$primary_fast_cores_kept, sp$fast_cores, r$primary_fast_cores_any), "n"),
           td(r$tracts, "n"), td(fmt_n(r$requests), "n"), "</tr>")
  }, ""), collapse = "")
  fig4 <- sprintf(paste0(
    "<figure id=\"fig4\"><h3>%s</h3>",
    "<div class=\"interp\"><p>Three checks. The first two were set before seeing any results; the third was added after Figure 3.</p><ul class=\"tight\">",
    "<li><strong>Six nearest tracts as neighbors</strong>, instead of touching tracts: almost no change. %d of %d slow and %d of %d fast cores remain.</li>",
    "<li><strong>Same season a year earlier</strong> (June–July 2025): the fast cluster is largely the same (%d of %d cores; %d counting those significant only before correction). Only %d of the %d slow cores were slow cores then (%d counting before correction); the 2025 slow cluster was mostly in %s.</li>",
    "<li><strong>Without solid-waste requests</strong>: Moran's I falls from %s to %s, and only %d slow and %d fast cores remain.</li></ul></div>",
    "<div class=\"scroll\">%s</div><div class=\"scatter\">%s</div>",
    "<div class=\"tablewrap\"><table><thead><tr><th>Check</th><th class=\"n\">Moran's I</th><th class=\"n\">Slow cores</th><th class=\"n\">Fast cores</th><th class=\"n\">Slow cores kept (incl. before correction)</th><th class=\"n\">Fast cores kept (incl. before correction)</th><th class=\"n\">Tracts</th><th class=\"n\">Requests</th></tr></thead><tbody>%s</tbody></table></div>",
    "<figcaption>Each check recomputes the typical times, expected counts, smoothing and tests from scratch. z: how far Moran's I is above what chance would give. Scatter: tracts analysed in both periods, log scales. %s</figcaption></figure>"),
    titles[["fig4"]], sk$primary_slow_cores_kept, sp$slow_cores, sk$primary_fast_cores_kept, sp$fast_cores,
    s25$primary_fast_cores_kept, sp$fast_cores, s25$primary_fast_cores_any, s25$primary_slow_cores_kept, sp$slow_cores,
    s25$primary_slow_cores_any, zips_txt(w25s), f2(sp$moran_I), f2(sn$moran_I), sn$slow_cores, sn$fast_cores,
    inline$f4a, inline$f4b, spec_rows, src_line)

  holds <- sprintf(paste0(
    "<h2 id=\"holds\">What the results mean</h2><div class=\"col\">",
    "<p><strong>Solid.</strong> With all request types, closing times cluster strongly under every check (Moran's I %s to %s). The fast cluster in the north shows up every time.</p>",
    "<p><strong>Less solid.</strong> The slow cluster moves: in 2025 it was mostly in %s; in 2026, mostly in %s. Tract ratios in the two years are only moderately related (rank correlation %s, %d tracts). Without solid waste, clustering is weaker (Moran's I %s) and only %d slow and %d fast cores remain, so the two big clusters are a solid-waste pattern.</p>",
    "<p><strong>How much it matters.</strong> The pattern is not chance (z = %s), and the gap is large: a median bulk-trash wait of %s in the slow cluster against %s in the fast cluster. ",
    "What that means for residents depends on the records. If closure dates track pickups, the gap is real. If one area closes requests at pickup and another closes them later in batches, much of the gap is paperwork. The City, or the H4 audit, could settle this.</p></div>"),
    f2(min(ss$moran_I[ss$spec != "no_swm"])), f2(max(ss$moran_I)), zips_txt(w25s), zips_txt(ws), f2(sc$rho), sc$n,
    f2(sn$moran_I), sn$slow_cores, sn$fast_cores,
    formatC(sp$z, format = "f", digits = 1), daysw(bt("slow_core")), daysw(bt("fast_core")))

  methods <- sprintf(paste0(
    "<h2 id=\"methods\">Methods</h2><div class=\"col\">",
    "<p><strong>Records.</strong> Requests are prepared with the 311 pipeline's own code. City-marked duplicates, records from before the October 2023 migration, and requests with no type or an unknown status are removed. Near-duplicates (same type, within 50 m and 7 days; D6) are dropped. ",
    "Of %s requests opened in the period inside the city, %s with a bad close date are excluded.</p>",
    "<p><strong>Typical time.</strong> For each type, the citywide median business days to close, estimated with Kaplan-Meier so that open requests count at their current age (D9). ",
    "Types are left out if they have fewer than %d requests (%d types, %s requests) or if fewer than half had closed (%d types, %s requests). ",
    "Most of the latter are weed cutting on vacant lots and houses (%s requests, %s still open, %s to %s in each group). Dropping them hides slow service but does not change the map. ",
    "A request counts only once its type's typical time has passed (%s recent requests do not yet). This depends on the open date, not the outcome.</p>",
    "<p><strong>Tract ratio.</strong> Slow ÷ expected. Tracts with fewer than %d eligible requests are not shown (%d tracts, %s requests).</p>",
    "<p><strong>Smoothing small tracts.</strong> Small tracts give noisy ratios. For the spatial tests only, each ratio is standardized with the empirical-Bayes method of Assunção and Reis (1999), using the variance of a yes/no outcome. Maps and charts show the raw ratio.</p>",
    "<p><strong>Neighbors.</strong> Tracts whose boundaries come within %s m of each other (queen contiguity), weighted equally: %s neighbors on average, none isolated. Tracts on the city edge have fewer neighbors; the six-nearest check gives every tract the same number.</p>",
    "<p><strong>Tests.</strong> Global Moran's I with %s random shuffles of the tract values (p = %s; the analytic z of %s agrees). Local Moran's I (Anselin 1995) with %s shuffles per tract, holding the tract's own value fixed; two-sided p-values; Benjamini-Hochberg false discovery rate of %s across %d tracts. Null hypothesis: tract values are unrelated to location. Seed %d.</p>",
    "<p><strong>Context.</strong> ACS 2020-2024 estimates for the in-city part of each tract (D20), pooled by group with margins of error. Permits and demolitions per 1,000 ACS housing units.</p></div>"),
    fmt_n(flow[["in_window"]]), fmt_n(flow[["close_problem"]]),
    P$min_type_n, sum(thr$status == "too_few"), fmt_n(sum(thr$n[thr$status == "too_few"])),
    sum(thr$status == "median_not_reached"), fmt_n(sum(thr$n[thr$status == "median_not_reached"])),
    fmt_n(sum(weeds$n)), pct(still_open(weeds$request_type)), pct(min(weeds_open_by_group)), pct(max(weeds_open_by_group)),
    fmt_n(flow[["not_yet_observable"]]),
    P$min_tract_n, sum(prim$tracts$suppressed), fmt_n(flow[["in_suppressed_tracts"]]),
    P$contiguity_tol_m, formatC(sp$mean_neighbors, format = "f", digits = 1),
    fmt_n(P$nsim_global), formatC(sp$p_perm, format = "g"), formatC(sp$z, format = "f", digits = 1),
    fmt_n(P$nsim_local), pct(P$alpha), n_an, P$seed)

  limits <- sprintf(paste0(
    "<h2 id=\"limits\">Limitations</h2><div class=\"col\"><ul class=\"tight\">",
    "<li><strong>A closure is a record, not a pickup.</strong> The two clusters use different resolution codes, and the codes are undocumented.</li>",
    "<li><strong>The slowest services are left out.</strong> Most weed-cutting requests on vacant property were still open, so they have no typical time. They are open at similar rates everywhere, so the map is unaffected, but the service is slow everywhere.</li>",
    "<li><strong>Only reported problems count.</strong> The slow cluster reports more per resident, and requests of the same type can differ between areas.</li>",
    "<li><strong>One season.</strong> The main period is three months, and the slow cluster moved between 2025 and 2026.</li>",
    "<li><strong>Requests are not independent.</strong> Requests on one route are often closed together, so Figure 2's intervals are too narrow. The permutation tests do not rely on them.</li>",
    "<li><strong>Tract boundaries are one choice.</strong> Other boundaries could shift a cluster's edge.</li>",
    "<li><strong>Areas, not people.</strong> Demographics describe areas, not individuals, and are not causes.</li>",
    "<li><strong>Calendar and later edits.</strong> Business days before 2026 use a reconstructed holiday calendar (H13), and the City can edit closure dates later.</li>",
    "<li><strong>Not a project metric.</strong> The 311 specs are drafts (H10) and the manual audit (H3) is not done, so none of this is publishable under the project's rules.</li>",
    "</ul></div>"))

  inv <- res$inventory
  inv_rows <- paste(vapply(seq_len(nrow(inv)), function(i) paste0("<tr>",
    td(sprintf("<strong>%s</strong><br><span style=\"color:var(--muted)\">%s</span>", esc(inv$source[i]), esc(inv$origin[i]))),
    td(sprintf("%s<br><span style=\"color:var(--muted)\">%s</span>", esc(inv$unit[i]), esc(inv$kind[i]))),
    td(sprintf("%s<br>%s", esc(inv$time[i]), esc(inv$volume[i]))), td(esc(inv$denominator[i])), td(esc(inv$quality[i])),
    td(esc(inv$used[i])), "</tr>"), ""), collapse = "")
  inventory <- sprintf(paste0(
    "<h2 id=\"data\">The data available</h2><div class=\"col\"><p>Before choosing the question, each source was checked for what a record represents, its coverage, its denominator and the problems that could distort a map.</p></div>",
    "<div class=\"tablewrap\"><table><thead><tr><th>Source</th><th>One record is</th><th>Coverage</th><th>Denominator</th><th>Problems that matter here</th><th>Use</th></tr></thead><tbody>%s</tbody></table></div>",
    "<div class=\"col\"><p><strong>Checks on the 311 records.</strong> Missing close dates are the main risk: %s of closed requests opened in December 2025 and %s in January 2026 have none, so those months were avoided (June to August 2026: %s). Requests do not pile up on default locations (at most %d at one point since October 2023). %s ",
    "Open requests are kept and count as slow once their typical time passes. Tracts with no requests are shown as no data, not zero.</p></div>"),
    inv_rows, pct(res$data_checks$missing_dec2025), pct(res$data_checks$missing_jan2026),
    pct(res$data_checks$missing_window, 1), res$data_checks$max_stack,
    if (res$data_checks$no_tract == 0) "Every in-city request falls in a tract."
    else sprintf("%s in-city requests fall in no tract.", fmt_n(res$data_checks$no_tract)))

  reproduce <- sprintf(paste0(
    "<h2 id=\"reproduce\">Reproduce</h2><div class=\"col\"><p>From the repository root, with R 4.3 or newer and the project's packages installed:</p>",
    "<pre>R CMD INSTALL packages/memequity\nRscript analysis/311-slow-service/run.R                 # reuses the prep cache\nRscript analysis/311-slow-service/run.R --rebuild-prep  # rebuilds it (about 3 minutes)</pre>",
    "<p><strong>Inputs</strong> (offline, not committed): <code>%s</code>, <code>%s</code>, the demolition snapshot <code>%s</code> and the inspection data <code>%s</code> with its geocode cache. Boundaries and ACS estimates come from <code>geography/</code>.</p>",
    "<p><strong>Outputs:</strong> this page, <code>output/figures/*.svg</code> and <code>output/results/*.csv</code> (every tract under every check, plus the group tables). All parameters are in <code>PARAMS</code> at the top of <code>run.R</code>; seed %d. The same inputs give identical numbers. The statistics are coded in <code>R/spatial.R</code>, so no spatial package is needed.</p></div>"),
    P$raw_311, P$raw_permits, P$demolitions_file, P$inspections_dir, P$seed)

  tr <- merge(M$ti, prim$tracts, by = "geo_id")
  tr <- tr[order(tr$suppressed, -tr$ratio), ]
  trows <- paste(vapply(seq_len(nrow(tr)), function(i) {
    r <- tr[i, ]
    paste0("<tr>", td(esc(sub("Census Tract ", "", r$name))), td(esc(r$zip)), td(esc(r$nbhd %||% "")),
           td(fmt_n(round(r$residents)), "n"), td(fmt_n(r$n), "n"),
           td(if (r$suppressed) "&ndash;" else pct(r$observed / r$n), "n"),
           td(if (r$suppressed) "&ndash;" else pct(r$expected / r$n), "n"),
           td(if (r$suppressed) "&ndash;" else sprintf("%s (%s&ndash;%s)", f2(r$ratio), f2(r$ci_low), f2(r$ci_high)), "n"),
           td(esc(class_words(r$class, NA))), td(if (is.na(r$q)) "&ndash;" else formatC(r$q, format = "g", digits = 2), "n"), "</tr>")
  }, ""), collapse = "")
  table_view <- sprintf(paste0(
    "<details id=\"tracts\"><summary>Every tract's numbers (%d tracts)</summary><div class=\"tablewrap\"><table><thead><tr>",
    "<th>Tract</th><th>ZIP</th><th>Area</th><th class=\"n\">Residents</th><th class=\"n\">Eligible requests</th><th class=\"n\">Slow</th><th class=\"n\">Expected</th><th class=\"n\">Ratio (95%% CI)</th><th>Local result</th><th class=\"n\">q</th>",
    "</tr></thead><tbody>%s</tbody></table></div></details>"), nrow(tr), trows)

  head <- paste0(
    "<title>Where 311 Runs Slow</title>\n<meta name=\"description\" content=\"Where Memphis 311 requests close slower or faster than the same request types citywide, and whether those places cluster.\">\n",
    "<link rel=\"preconnect\" href=\"https://fonts.googleapis.com\"><link rel=\"preconnect\" href=\"https://fonts.gstatic.com\" crossorigin>",
    "<link rel=\"stylesheet\" href=\"https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@500;600&family=Public+Sans:ital,wght@0,400;0,600;0,700;1,400&display=swap\">\n",
    "<style>", page_css(), "</style>\n")
  body <- paste0(
    "<div class=\"wrap\"><header class=\"top\"><p class=\"eyebrow\">Memphis Service Equity · spatial analysis · 311 city services</p>",
    "<h1>Where 311 runs slow</h1>",
    "<p class=\"dek\">Which parts of Memphis wait longer than the rest of the city for the same kind of 311 request, and whether those places cluster.</p>",
    sprintf("<p class=\"meta\"><span>Requests opened %s</span><span>Data through %s</span><span>%s requests · %d census tracts</span><span>Built %s</span></p></header>",
            win_txt(prim$from, prim$to), dmy(P$as_of - 1, "%b"), fmt_n(flow[["analysed"]]), n_an, dmy(Sys.Date(), "%b")),
    "<section class=\"col\">", lead, "</section>", tiles,
    question, fig1, fig2, fig3, fig4, holds, methods, limits, inventory, reproduce, table_view,
    "<footer><p>City of Memphis 311 data are public records; only the pipeline's fields are used (no contact details). ",
    "ACS 2020-2024 5-year estimates, U.S. Census Bureau. Boundaries: Census TIGERweb (2020 tracts, 2026 city limits). ",
    "Codes such as D6 or H4 refer to DECISIONS.md in the project repository.</p></footer></div>",
    "<div id=\"tip\" hidden role=\"tooltip\"></div><script>", page_js(), "</script>")
  full <- paste0("<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1,viewport-fit=cover\">\n",
                 head, "</head><body>", body, "</body></html>\n")
  writeLines(full, file.path(out_dir, "report.html"), useBytes = TRUE)
  writeLines(paste0(head, body), file.path(out_dir, "report_artifact.html"), useBytes = TRUE)
  invisible(M)
}

# "1 June 2026" (strftime's %-d is not portable to Windows).
dmy <- function(d, month = "%B") paste(as.integer(format(d, "%d")), format(d, paste(month, "%Y")))
