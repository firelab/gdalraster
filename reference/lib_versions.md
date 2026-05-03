# Return library version information for GDAL and its dependencies

`lib_versions()` returns a named list of library version information for
GDAL and its major dependencies, currently PROJ and GEOS. It provides
library versions in a consistent format, as an alternative to the
separate
[`gdal_version()`](https://firelab.github.io/gdalraster/reference/gdal_version.md),
[`proj_version()`](https://firelab.github.io/gdalraster/reference/proj_version.md)
and
[`geos_version()`](https://firelab.github.io/gdalraster/reference/geos_version.md).

## Usage

``` r
lib_versions()
```

## Value

A named list with elements `"gdal"`, `"proj"` and `"geos"`, each
containing a named list with the following elements:

- `"name"`: character string version as `"major.minor.patch"`

- `"major"`: integer major version number

- `"minor"`: integer minor version number

- `"patch"`: integer patch version number

## See also

[`gdal_version()`](https://firelab.github.io/gdalraster/reference/gdal_version.md),
[`proj_version()`](https://firelab.github.io/gdalraster/reference/proj_version.md),
[`geos_version()`](https://firelab.github.io/gdalraster/reference/geos_version.md)

## Examples

``` r
lib_versions()
#> $gdal
#> $gdal$name
#> [1] "3.8.4"
#> 
#> $gdal$major
#> [1] 3
#> 
#> $gdal$minor
#> [1] 8
#> 
#> $gdal$patch
#> [1] 4
#> 
#> 
#> $proj
#> $proj$name
#> [1] "9.4.0"
#> 
#> $proj$major
#> [1] 9
#> 
#> $proj$minor
#> [1] 4
#> 
#> $proj$patch
#> [1] 0
#> 
#> 
#> $geos
#> $geos$name
#> [1] "3.12.1"
#> 
#> $geos$major
#> [1] 3
#> 
#> $geos$minor
#> [1] 12
#> 
#> $geos$patch
#> [1] 1
#> 
#> 
```
