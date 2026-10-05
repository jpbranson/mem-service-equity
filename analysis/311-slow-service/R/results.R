# Tables written next to the report, and the model the figures are drawn from.

spec_list <- function(res) {
  list(primary = list(s = res$prim, title = "Main analysis", label = "Main analysis (Jun-Aug 2026, touching tracts)",
                      sub = "Jun-Aug 2026 · touching tracts"),
       knn6 = list(s = res$knn, title = "Six nearest tracts", label = "Six nearest tracts as neighbors",
                   sub = "Jun-Aug 2026 · 6 nearest tracts"),
       y2025 = list(s = res$y25, title = "One year earlier", label = "Jun-Jul 2025",
                    sub = "Jun-Jul 2025 · touching tracts"),
       no_swm = list(s = res$noswm, title = "Without solid waste", label = "Excluding solid-waste types",
                     sub = "Jun-Aug 2026 · no solid-waste types"))
}

spec_summary <- function(res) {
  sl <- spec_list(res)
  ph <- res$prim$tracts$geo_id[res$prim$tracts$class == "HH"]
  pl <- res$prim$tracts$geo_id[res$prim$tracts$class == "LL"]
  do.call(rbind, lapply(names(sl), function(k) {
    s <- sl[[k]]$s; t <- s$tracts
    cnt <- function(v) sum(t$class %in% v)
    data.frame(spec = k, label = sl[[k]]$label, window = paste(format(s$from), "to", format(s$to)),
               neighbors = s$neighbors, tracts = sum(!t$suppressed), requests = s$flow[["analysed"]],
               moran_I = s$moran$I, expected_I = s$moran$expected, sd_I = s$moran$sd, z = s$moran$z,
               p_perm = s$moran$p_perm, mean_neighbors = s$moran$mean_neighbors,
               slow_cores = cnt("HH"), fast_cores = cnt("LL"), slow_unadj = cnt("HH_unadj"),
               fast_unadj = cnt("LL_unadj"), outliers = cnt(c("HL", "LH", "HL_unadj", "LH_unadj")),
               primary_slow_cores_kept = sum(t$class[match(ph, t$geo_id)] %in% "HH"),
               primary_fast_cores_kept = sum(t$class[match(pl, t$geo_id)] %in% "LL"),
               primary_slow_cores_any = sum(t$class[match(ph, t$geo_id)] %in% c("HH", "HH_unadj")),
               primary_fast_cores_any = sum(t$class[match(pl, t$geo_id)] %in% c("LL", "LL_unadj")),
               stringsAsFactors = FALSE)
  }))
}

# Tract names, the ZIP holding most of each tract's requests, and residents.
tract_info <- function(x, ids) {
  tr <- memequity::load_boundaries("tract")
  sr <- x$sr[is.na(x$sr$exclusion) & x$sr$in_city %in% TRUE & !is.na(x$sr$tract), ]
  z <- tapply(sr$zcta, sr$tract, function(v) names(sort(table(v), decreasing = TRUE))[1])
  rn <- memequity::reference_neighborhoods()
  pop <- memequity::area_population("tract")
  data.frame(geo_id = ids, name = tr$NAME[match(ids, tr$geo_id)], zip = as.character(z[ids]),
             nbhd = rn$neighborhood[match(as.character(z[ids]), rn$zip)],
             residents = pop$population[match(ids, pop$geo_id)], stringsAsFactors = FALSE)
}

write_results <- function(res, tg, x, dir) {
  ti <- tract_info(x, tg$geo_id)
  sl <- spec_list(res)
  t <- res$prim$tracts
  out <- merge(ti, t[, c("geo_id", "n", "observed", "expected", "ratio", "ci_low", "ci_high", "eb_smoothed",
                         "eb_z", "Ii", "p", "q", "class")], by = "geo_id")
  names(out)[names(out) == "class"] <- "class_primary"
  for (k in c("knn6", "y2025", "no_swm")) {
    s <- sl[[k]]$s$tracts
    out[[paste0("class_", k)]] <- s$class[match(out$geo_id, s$geo_id)]
    out[[paste0("ratio_", k)]] <- s$ratio[match(out$geo_id, s$geo_id)]
  }
  out$observed_share <- out$observed / out$n
  out$expected_share <- out$expected / out$n
  names(out)[names(out) == "n"] <- "eligible_requests"
  utils::write.csv(out[order(out$geo_id), ], file.path(dir, "tract_results.csv"), row.names = FALSE)
  utils::write.csv(spec_summary(res), file.path(dir, "specifications.csv"), row.names = FALSE)
  thr <- rbind(cbind(window = "2026-06-01 to 2026-08-31", res$prim$thresholds),
               cbind(window = "2025-06-01 to 2025-07-31", res$y25$thresholds))
  utils::write.csv(thr, file.path(dir, "type_thresholds.csv"), row.names = FALSE)
  utils::write.csv(res$type_groups, file.path(dir, "type_by_group.csv"), row.names = FALSE)
  utils::write.csv(res$group_ratios, file.path(dir, "group_ratios.csv"), row.names = FALSE)
  utils::write.csv(res$context, file.path(dir, "group_context.csv"), row.names = FALSE)
  utils::write.csv(res$codes, file.path(dir, "bulk_trash_closure_codes.csv"), row.names = FALSE)
  utils::write.csv(res$inventory, file.path(dir, "data_inventory.csv"), row.names = FALSE)
  fl <- do.call(rbind, lapply(names(sl), function(k) data.frame(spec = k, step = names(sl[[k]]$s$flow),
                                                               requests = as.numeric(sl[[k]]$s$flow))))
  utils::write.csv(fl, file.path(dir, "request_flow.csv"), row.names = FALSE)
  invisible(out)
}
