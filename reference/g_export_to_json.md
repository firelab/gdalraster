# Convert WKB/WKT geometries into GeoJSON-style format

`g_export_to_json()` exports input geometries to GeoJSON strings.
Interface to `OGR_G_ExportToJsonEx()` in the GDAL API.

## Usage

``` r
g_export_to_json(geom, srs = NULL, options = NULL)
```

## Arguments

- geom:

  Either a raw vector of WKB or list of raw vectors, or a character
  vector containing one or more WKT strings.

- srs:

  Optional character string specifying the spatial reference system for
  the geometries given in `geom`. May be in WKT format or any of the
  formats supported by
  [`srs_to_wkt()`](https://firelab.github.io/gdalraster/reference/srs_convert.md).

- options:

  Optional character vector of `NAME=VALE` pairs. May include any of the
  options supported by `OGR_G_ExportToJsonEx()` in the GDAL API (see
  Details).

## Value

A character vector of GeoJSON strings the same length as the number of
input geometries.

## Details

Available `options` are the ones supported by `OGR_G_ExportToJsonEx()`.
See <https://gdal.org/en/latest/api/vector_c_api.html>.

If there is a SRS attached to the geometry, and the geometry is aimed at
being stored in the "place" member of JSON-FG features, then
`COORDINATE_ORDER=AUTHORITY_COMPLIANT` option must be set (added in GDAL
3.12.1). When a SRS is attached to the geometry, and
`AUTHORITY_COMPLIANT` is used, the coordinates will be emitted in the
order of the official SRS definition. When using `TRADITIONAL_GIS_ORDER`
(the default), coordinates are emitted in longitude/easting first, then
latitude/northing second. When no SRS is attached, coordinates are
emitted in the order they are set in the geometry.

## Examples

``` r
g_export_to_json("POINT (-114.0 47.0)")
#> [1] "{ \"type\": \"Point\", \"coordinates\": [ -114.0, 47.0 ] }"
```
