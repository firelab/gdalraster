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

At the time of writing (GDAL 3.9 through 3.12.1), a point exactly on the
surface of the DEM is never visible with `GDALIsLineOfSightVisible()`,
even if viewed from a point directly above. For a detailed description,
see <https://github.com/OSGeo/gdal/issues/12458>. A workaround for that
case could be to set a small but negligible postive Z value (if using
`"RELATIVE_TO_DEM"`) for points that are intended to be on the DEM
surface, if appropriate for the use case.

## See also

<https://www.researchgate.net/publication/2411280_Efficient_Line-of-Sight_Algorithms_for_Real_Terrain_Data>

## Examples

``` r
if (FALSE) { # gdal_version_num() >= gdal_compute_version(3, 9, 0)
dem <- system.file("extdata/storml_elev.tif", package="gdalraster")

## no reprojection, the point coordinates are in the same projection as DEM

## one-to-many
ptA <- c(324625.0, 5104724.0, 1.7)
ptsB <-c(324803.0, 5104517.0, 10,
         325286.0, 5102923.0, 10,
         323847.0, 5104538.0, 10)
ptsB <- matrix(ptsB, nrow = 3, ncol = 3, byrow = TRUE)

is_los_visible(dem, ptA, ptsB)

## pairwise, same ptA location with varying height
ptsA <- c(324625.0, 5104724.0, 1,
          324625.0, 5104724.0, 10,
          324625.0, 5104724.0, 1000)
ptsA <- matrix(ptsA, nrow = 3, ncol = 3, byrow = TRUE)

is_los_visible(dem, ptsA, ptsB)

## WKB points
(ptsA_wkb <- g_create("POINT", ptsA))

# as WKT
g_wk2wk(ptsA_wkb)

# or as ISO WKT
g_wk2wk(ptsA_wkb, as_iso = TRUE)

is_los_visible(dem, ptsA_wkb, ptsB)

## reprojecting ptsA, and the DEM given as a dataset object
(ds <- new(GDALRaster, dem))

ptsA_wkb_wgs84 <- g_transform(ptsA_wkb, ds$getSpatialRef(), "WGS84")
g_wk2wk(ptsA_wkb_wgs84)

is_los_visible(ds, ptsA_wkb_wgs84, ptsB, srsA = "WGS84")

## read ptsB from a vector dataset, use original ptA

dsn <- system.file("extdata/storml_los_pts_b.geojson", package="gdalraster")
(lyr <- new(GDALVector, dsn))

(features <- lyr$fetch(-1))

is_los_visible(ds, ptA, features$geom, srsB = lyr$getSpatialRef(),
               ZinterpB = "ACTUAL")

ds$close()
lyr$close()
}
```
