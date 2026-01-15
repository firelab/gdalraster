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
if (FALSE) { # gdal_version_num() >= gdal_compute_version(3, 12, 0)
# Requires GDAL >= 3.12
vsi_uri_to_vsi_path("gs://cmip6/")
}
```
