# Read an MDArray from a multidimensional raster, with dimension information

`mdim_read()` reads all or part of an array in a GDAL Multidimensional
Raster dataset, and returns a vector with an attribute `"gis"`
describing the dimensions and coordinates of the values read. It is the
multidimensional counterpart of
[`read_ds()`](https://firelab.github.io/gdalraster/reference/read_ds.md),
and uses
[`GDALMDArray$read()`](https://firelab.github.io/gdalraster/reference/GDALMDArray-class.md).
Requires GDAL \>= 3.2. **This function is experimental**. Its interface
may change in future releases.

## Usage

``` r
mdim_read(
  x,
  array_name,
  start = NULL,
  count = NULL,
  step = NULL,
  as_array = FALSE,
  as_raw = FALSE
)
```

## Arguments

- x:

  Either an object of class
  [`GDALMultiDimRaster`](https://firelab.github.io/gdalraster/reference/GDALMultiDimRaster-class.md),
  or a character string giving the data source name of a
  multidimensional raster (which is opened read-only and closed on
  return).

- array_name:

  Character string giving the full path of the array in the dataset,
  e.g., `"/temperature"` or `"/group/temperature"`.

- start:

  Optional numeric vector of 0-based start indexes, one value per
  dimension of the array, in the array's own dimension order. Defaults
  to `0` for each dimension.

- count:

  Optional numeric vector of the number of values to read along each
  dimension. Defaults to the rest of each dimension after `start`
  (taking `step` into account).

- step:

  Optional numeric vector of the step between indexes along each
  dimension. Defaults to `1` for each dimension.

- as_array:

  Logical value. If `TRUE`, also set the `dim` attribute of the returned
  vector to `gis$dim`, so that it can be used as an R array indexed as
  `[x, y, ...]`. Defaults to `FALSE`.

- as_raw:

  Logical value. If `TRUE` and the array data type is Byte, return
  values as R `raw`. Defaults to `FALSE`.

## Value

A vector of values, with attribute `"gis"` (and `dim` if
`as_array = TRUE`). See Details.

## Details

Values are returned as stored, in the same order as returned by
[`GDALMDArray$read()`](https://firelab.github.io/gdalraster/reference/GDALMDArray-class.md):
the last dimension of the array varies fastest. Scale and offset are not
applied (the unscaled value is `value * gis$scale + gis$offset`), and
the nodata value is returned as `NA`.

The `"gis"` attribute is a list with elements:

- `type`: `"multidim"`

- `dim`: the number of values read along each dimension, fastest varying
  first, i.e., the reverse of the array's dimension order (the same
  convention as `c(xsize, ysize, nbands)` in the `"gis"` attribute from
  [`read_ds()`](https://firelab.github.io/gdalraster/reference/read_ds.md))

- `dim_names`: the dimension names, in the same order as `dim`

- `coords`: a named list, in the same order as `dim`, with the
  coordinate values of each dimension for the values read, or `NULL` for
  a dimension without an indexing variable

- `bbox`: `c(xmin, ymin, xmax, ymax)` from the coordinates of the
  horizontal dimensions (cell edges, assuming regular spacing), or `NA`
  values if they cannot be determined

- `srs`: the spatial reference system as WKT, or `""`

- `datatype`: the data type name (e.g., `"Int16"`)

- `nodata`, `scale`, `offset`: numeric values, `NA` if not set

- `unit`: the unit of the array values, or `""`

- `dim_units`: the units of the dimension coordinates, in the same order
  as `dim` (e.g., `"degrees_east"`, `"hours since 1900-01-01"`), `""` if
  not set

- `calendar`: the `calendar` attribute of the time coordinate if present
  (e.g., `"standard"`, `"noleap"`), otherwise `NA`.

Units and calendars are returned as stored, as character strings.

The horizontal dimensions are those with type `HORIZONTAL_X` and
`HORIZONTAL_Y`, or otherwise the last and second last dimensions of the
array.

## See also

[GDALMultiDimRaster](https://firelab.github.io/gdalraster/reference/GDALMultiDimRaster-class.md),
[GDALMDArray](https://firelab.github.io/gdalraster/reference/GDALMDArray-class.md),
[`read_ds()`](https://firelab.github.io/gdalraster/reference/read_ds.md)

## Examples

``` r
f <- system.file("extdata/mdim_small.nc", package="gdalraster")

v <- mdim_read(f, "/t2m")
str(attr(v, "gis"))
#> List of 13
#>  $ type     : chr "multidim"
#>  $ dim      : num [1:3] 6 5 4
#>  $ dim_names: chr [1:3] "lon" "lat" "time"
#>  $ coords   :List of 3
#>   ..$ lon : num [1:6] 145 145 146 146 146 ...
#>   ..$ lat : num [1:5] -41 -41.2 -41.5 -41.8 -42
#>   ..$ time: num [1:4] 0 6 12 18
#>  $ bbox     : num [1:4] 144.9 -42.1 146.4 -40.9
#>  $ srs      : chr ""
#>  $ datatype : chr "Int16"
#>  $ nodata   : num -32767
#>  $ scale    : num 0.01
#>  $ offset   : num 0
#>  $ unit     : chr "degC"
#>  $ dim_units: chr [1:3] "degrees_east" "degrees_north" "hours since 2000-01-01 00:00:00"
#>  $ calendar : chr "standard"

# the first time step as an R matrix [lon, lat], in degC
ds <- new(GDALMultiDimRaster, f)
v <- mdim_read(ds, "/t2m", start = c(0, 0, 0), count = c(1, 5, 6),
               as_array = TRUE)
gis <- attr(v, "gis")
gis$dim
#> [1] 6 5 1
gis$coords
#> $lon
#> [1] 145.00 145.25 145.50 145.75 146.00 146.25
#> 
#> $lat
#> [1] -41.00 -41.25 -41.50 -41.75 -42.00
#> 
#> $time
#> [1] 0
#> 
v[, , 1] * gis$scale + gis$offset
#>       [,1]  [,2]  [,3]  [,4]  [,5]
#> [1,] 12.95 13.55 14.15 14.75 15.35
#> [2,] 13.05 13.65 14.25 14.85 15.45
#> [3,]    NA 13.75 14.35 14.95 15.55
#> [4,] 13.25 13.85 14.45 15.05 15.65
#> [5,] 13.35 13.95 14.55 15.15 15.75
#> [6,] 13.45 14.05 14.65 15.25 15.85
ds$close()
```
