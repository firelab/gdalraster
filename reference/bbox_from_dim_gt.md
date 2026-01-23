# Bounding box from dimensions and geotransform

`bbox_from_dim_gt()` computes the bounding box from raster dimensions
and geotransform coefficients. For rotated rasters, returns the
axis-aligned envelope of the four corner coordinates.

## Usage

``` r
bbox_from_dim_gt(dim, gt)
```

## Arguments

- dim:

  Integer vector of length two containing the raster dimensions (xsize,
  ysize) in pixels.

- gt:

  Numeric vector of length six containing the geotransform coefficients.

## Value

Numeric vector of length four containing the bounding box (xmin, ymin,
xmax, ymax) in georeferenced coordinates.

## See also

[`GDALRaster$getGeoTransform()`](https://firelab.github.io/gdalraster/reference/GDALRaster-class.md),
[`GDALRaster$bbox()`](https://firelab.github.io/gdalraster/reference/GDALRaster-class.md),
[`gt_from_dim_bbox()`](https://firelab.github.io/gdalraster/reference/gt_from_dim_bbox.md),
[`inv_geotransform()`](https://firelab.github.io/gdalraster/reference/inv_geotransform.md)

## Examples

``` r
elev_file <- system.file("extdata/storml_elev.tif", package="gdalraster")
ds <- new(GDALRaster, elev_file)
gt <- ds$getGeoTransform()
dim <- ds$dim()

# should match ds$bbox()
bbox_from_dim_gt(dim, gt)
#> [1]  323476.1 5101872.0  327766.1 5105082.0
ds$bbox()
#> [1]  323476.1 5101872.0  327766.1 5105082.0

ds$close()
```
