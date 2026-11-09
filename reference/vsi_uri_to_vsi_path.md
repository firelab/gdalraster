# Return VSI compatible paths from URIs / URLs

`vsi_uri_to_vsi_path()` substitutes URIs / URLs starting with `s3://`,
`gs://`, etc. by their VSI prefix equivalents. If no known substitution
is found, the input string is returned unmodified. Wrapper of
`VSIURIToVSIPath()` in the GDAL API. Requires GDAL \>= 3.12.

## Usage

``` r
vsi_uri_to_vsi_path(uris)
```

## Arguments

- uris:

  Character vector of input URI strings.

## Value

Character vector of VSI paths.

## Examples

``` r
# Requires GDAL >= 3.12
vsi_uri_to_vsi_path("gs://cmip6/")
#> [1] "/vsigs/cmip6/"
```
