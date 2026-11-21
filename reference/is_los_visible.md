# Check line of sight between pairs of point locations

`is_los_visible()` is an interface to GDAL's line-of-sight algorithm
implemented by `GDALIsLineOfSightVisible()` in the Algorithms C API
(<https://gdal.org/en/stable/api/gdal_alg.html>). It checks line of
sight across a DEM surface using a Bresenham algorithm. The function can
operate pairwise on sets of input points, or one-to-many. Requires GDAL
\>= 3.9.

## Usage

``` r
is_los_visible(
  dem,
  ptsA,
  ptsB,
  band = 1L,
  srsA = NULL,
  srsB = NULL,
  ZinterpA = "RELATIVE_TO_DEM",
  ZinterpB = "RELATIVE_TO_DEM",
  quiet = FALSE
)
```

## Arguments

- dem:

  Either a character string giving the filename of the DEM raster, or an
  object of class `GDALRaster` for the DEM.

- ptsA:

  A data frame or numeric matrix containing geospatial point
  coordinates, or point geometries (with Z values) as a list of WKB raw
  vectors or character vector of WKT strings. If data frame or matrix,
  the number of columns must be three (x, y, z). May be also be given as
  a numeric vector for one point (`c(x, y, z)`). If this argument
  contains a single point, then line of sight will be checked between it
  and each point in `ptsB`, otherwise `length(ptsA)` must equal
  `length(ptsB)`, and line of sight will be checked pairwise.

- ptsB:

  The second set of points, as described above for `ptsA`.

- band:

  An integer value specifying the band number in `dem` to use. Defaults
  to `1L`.

- srsA:

  An optional character string specifying the spatial reference system
  for `ptsA`. May be in WKT format or any of the formats supported by
  [`srs_to_wkt()`](https://firelab.github.io/gdalraster/reference/srs_convert.md).
  If this argument is `NULL` (the default), then `ptsA` are assumed to
  be in the same coordinate reference system as `dem`. Otherwise, `ptsA`
  will be reprojected from `srsA` to the spatial reference of `dem`.

- srsB:

  An optional character string specifying the spatial reference system
  for `ptsB` (see above). Defaults to `NULL`. If not `NULL`, `ptsB` will
  be reprojected from `srsB` to the spatial reference of `dem`.

- ZinterpA:

  A character string specifying the interpretation of the Z values for
  `ptsA`. The default is `"RELATIVE_TO_DEM"`, in which case the location
  heights of `ptsA` are obtained by querying the DEM surface and adding
  the Z value given in `ptsA`. Alternatively, the Z values can be
  interpreted as absolute heights to be used unmodified by setting this
  argument to `"ACTUAL"`.

- ZinterpB:

  A character string specifying the interpretation of the Z values for
  `ptsB`. See the description above for `ZinterpA`.

- quiet:

  A logical value with default of `FALSE`. If set to `TRUE`, will
  suppress a progress bar and informational messages.

## Value

A logical vector of `length(ptsB)`, `TRUE` for each pair of points that
are within line of sight, otherwise `FALSE`. The checks are done
pairwise if `(length(ptsA) == length(ptsB))`, or one-to-many if
`length(ptsA) == 1` and multiple points are given in `ptsB`.

## Note

Input coordinates must be within the raster bounds. `NA` will be
returned if either coordinate is outside the raster extent, or is
missing a Z value.

The GDAL documentation notes that line of sight is computed in raster
coordinate space, and thus may not be appropriate for some applications.
For example, datasets referenced against geographic coordinates at high
latitudes may have issues.

In GDAL 3.9 through 3.12, a point exactly on the surface of the DEM is
never visible with `GDALIsLineOfSightVisible()`, even if viewed from a
point directly above. For a detailed description, see
<https://github.com/OSGeo/gdal/issues/12458>. A workaround for that case
is to set a small but negligible positive Z value (if using
`"RELATIVE_TO_DEM"`) for points that are intended to be on the DEM
surface, if appropriate for the use case. GDAL as of version 3.13 treats
a point exactly on the surface as visible
(<https://github.com/OSGeo/gdal/pull/14237>).

## References

Roberto de Beauclair Seixas, Maur Riguette Mediano and Marcelo Gattass.
1999. Efficient Line-of-Sight Algorithms for Real Terrain Data.

## Examples

``` r
dem <- system.file("extdata/storml_elev.tif", package="gdalraster")

## no reprojection, the point coordinates are in the same projection as DEM

## one-to-many
ptA <- c(324625.0, 5104724.0, 1.7)
ptsB <-c(324803.0, 5104517.0, 10,
         325286.0, 5102923.0, 10,
         323847.0, 5104538.0, 10)
ptsB <- matrix(ptsB, nrow = 3, ncol = 3, byrow = TRUE)

is_los_visible(dem, ptA, ptsB)
#> → checking line-of-sight...
#>  ■■■■■■■■■■■                       33% |  ETA:  0s
#> ✔ Done (6ms)
#> 
#> [1]  TRUE  TRUE FALSE

## pairwise, same ptA location with varying height
ptsA <- c(324625.0, 5104724.0, 1,
          324625.0, 5104724.0, 10,
          324625.0, 5104724.0, 1000)
ptsA <- matrix(ptsA, nrow = 3, ncol = 3, byrow = TRUE)

is_los_visible(dem, ptsA, ptsB)
#> → checking line-of-sight...
#> [1] TRUE TRUE TRUE

## WKB points
(ptsA_wkb <- g_create("POINT", ptsA))
#> [[1]]
#>  [1] 01 01 00 00 80 00 00 00 00 44 d0 13 41 00 00 00 00 15 79 53 41 00 00 00 00
#> [26] 00 00 f0 3f
#> 
#> [[2]]
#>  [1] 01 01 00 00 80 00 00 00 00 44 d0 13 41 00 00 00 00 15 79 53 41 00 00 00 00
#> [26] 00 00 24 40
#> 
#> [[3]]
#>  [1] 01 01 00 00 80 00 00 00 00 44 d0 13 41 00 00 00 00 15 79 53 41 00 00 00 00
#> [26] 00 40 8f 40
#> 

# as WKT
g_wk2wk(ptsA_wkb)
#> [1] "POINT (324625 5104724 1)"    "POINT (324625 5104724 10)"  
#> [3] "POINT (324625 5104724 1000)"

# or as ISO WKT
g_wk2wk(ptsA_wkb, as_iso = TRUE)
#> [1] "POINT Z (324625 5104724 1)"    "POINT Z (324625 5104724 10)"  
#> [3] "POINT Z (324625 5104724 1000)"

is_los_visible(dem, ptsA_wkb, ptsB)
#> → checking line-of-sight...
#> [1] TRUE TRUE TRUE

## reprojecting ptsA, and the DEM given as a dataset object
(ds <- new(GDALRaster, dem))
#> C++ object of class <GDALRaster>
#>   • Driver: GeoTIFF (GTiff)
#>   • DSN: "/home/runner/work/_temp/Library/gdalraster/extdata/storml_elev.tif"
#>   • Dimensions: 143, 107, 1
#>   • CRS: NAD83 / UTM zone 12N (EPSG:26912)
#>   • Pixel resolution: 30.000000, 30.000000
#>   • Bbox: 323476.071971, 5101871.983031, 327766.071971, 5105081.983031

ptsA_wkb_wgs84 <- g_transform(ptsA_wkb, ds$getSpatialRef(), "WGS84")
g_wk2wk(ptsA_wkb_wgs84)
#> [1] "POINT (-113.267911021074 46.0735865085109 1)"   
#> [2] "POINT (-113.267911021074 46.0735865085109 10)"  
#> [3] "POINT (-113.267911021074 46.0735865085109 1000)"

is_los_visible(ds, ptsA_wkb_wgs84, ptsB, srsA = "WGS84")
#> → transforming `ptsA`...
#> → checking line-of-sight...
#> [1] TRUE TRUE TRUE

## read ptsB from a vector dataset, use original ptA

dsn <- system.file("extdata/storml_los_pts_b.geojson", package="gdalraster")
(lyr <- new(GDALVector, dsn))
#> C++ object of class <GDALVector>
#>   • Driver: GeoJSON (GeoJSON)
#>   • DSN:
#>   "/home/runner/work/_temp/Library/gdalraster/extdata/storml_los_pts_b.geojson"
#>   • Layer: storml_los_pts_b
#>   • CRS: WGS 84 (EPSG:4326)
#>   • Geometry: POINT25D

(features <- lyr$fetch(-1))
#> OGR feature set
#>   FID                             desc                           geom
#> 1   0                    on Storm Lake WKB POINT: raw 01 01 00 00 ...
#> 2   1 south of lake, high on far ridge WKB POINT: raw 01 01 00 00 ...
#> 3   2    west of lake, over high ridge WKB POINT: raw 01 01 00 00 ...

is_los_visible(ds, ptA, features$geom, srsB = lyr$getSpatialRef(),
               ZinterpB = "ACTUAL")
#> → transforming `ptsB`...
#> → checking line-of-sight...
#> [1]  TRUE  TRUE FALSE

ds$close()
lyr$close()
```
