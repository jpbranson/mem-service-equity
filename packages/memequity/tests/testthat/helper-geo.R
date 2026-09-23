# Synthetic geography near downtown Memphis: two adjacent squares sharing an
# edge at longitude -90.04.
square <- function(x0, y0, x1, y1) {
  sf::st_polygon(list(matrix(c(x0, y0, x1, y0, x1, y1, x0, y1, x0, y0), ncol = 2, byrow = TRUE)))
}

fixture_polygons <- function() {
  sf::st_sf(geo_id = c("B", "A"),
            geometry = sf::st_sfc(square(-90.04, 35.13, -90.02, 35.15),
                                  square(-90.06, 35.13, -90.04, 35.15), crs = 4326))
}

fixture_geography_dir <- function() {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  dir.create(file.path(d, "boundaries"))
  polys <- fixture_polygons()
  names(polys)[1] <- "ZCTA5CE20"
  sf::st_write(polys, file.path(d, "boundaries", "zcta_test.geojson"), quiet = TRUE)
  writeLines(c("geo_type,file,id_field,source,vintage",
               "zcta,zcta_test.geojson,ZCTA5CE20,test,2020"),
             file.path(d, "boundaries", "registry.csv"))
  writeLines(c("neighborhood,zip", "Downtown,38103"), file.path(d, "reference_neighborhoods.csv"))
  d
}
