# Geotransform from dimensions and bounding box

`gt_from_dim_bbox()` computes geotransform coefficients from raster
dimensions and a bounding box. The resulting geotransform will always be
north-up (no rotation).

## Usage

``` r
gt_from_dim_bbox(dim, bbox)
```

## Arguments

- dim:

  Integer vector of length two containing the raster dimensions (xsize,
  ysize) in pixels.

- bbox:

  Numeric vector of length four containing the bounding box (xmin, ymin,
  xmax, ymax) in georeferenced coordinates.

## Value

Numeric vector of length six containing the geotransform coefficients.

## See also

[`GDALRaster$getGeoTransform()`](https://firelab.github.io/gdalraster/reference/GDALRaster-class.md),
[`GDALRaster$setGeoTransform()`](https://firelab.github.io/gdalraster/reference/GDALRaster-class.md),
[`GDALRaster$setBbox()`](https://firelab.github.io/gdalraster/reference/GDALRaster-class.md),
[`bbox_from_dim_gt()`](https://firelab.github.io/gdalraster/reference/bbox_from_dim_gt.md),
[`inv_geotransform()`](https://firelab.github.io/gdalraster/reference/inv_geotransform.md)

## Examples

``` r
# 1-degree global grid
gt <- gt_from_dim_bbox(c(360, 180), c(-180, -90, 180, 90))
gt
#> [1] -180    1    0   90    0   -1

# verify round-trip
bbox_from_dim_gt(c(360, 180), gt)
#> [1] -180  -90  180   90
```
