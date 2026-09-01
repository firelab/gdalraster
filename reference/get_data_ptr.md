# Get pointer address of an R vector as a character string

`get_data_ptr()` returns a character string representation of the
address of the first value in the C array underlying a given R vector of
`raw`, `integer`, `double` or `complex`. The returned string is suitable
for use as a DATAPOINTER for a GDAL MEM dataset
(<https://gdal.org/en/stable/drivers/raster/mem.html>).

## Usage

``` r
get_data_ptr(x)
```

## Arguments

- x:

  Vector of type `double`, `integer`, `raw` or `complex`.

## Value

Character string pointer address with format suitable as DATAPOINTER for
a GDAL MEM dataset.

## See also

[`rvector_to_MEM()`](https://firelab.github.io/gdalraster/reference/rvector_to_MEM.md)

## Examples

``` r
v <- sample(0:255, 20, replace = TRUE)
get_data_ptr(v)
#> [1] "0x5597a0df02c8"
```
