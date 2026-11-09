# Get metadata for a GDAL format driver

`gdal_get_driver_md()` returns metadata for a driver.

## Usage

``` r
gdal_get_driver_md(format, mdi_name = "")
```

## Arguments

- format:

  Character string giving a format driver short name (e.g., `"GTiff"`).

- mdi_name:

  Optional character string giving the name of a specific metadata item.
  Defaults to empty string (`""`) meaning fetch all metadata items.

## Value

Either a named list of metadata items and their values as character
strings, or a single character string if `mdi_name` is specified.
Returns `NULL` if no metadata items are found for the given inputs.

## See also

[`getCreationOptions()`](https://firelab.github.io/gdalraster/reference/getCreationOptions.md)

## Examples

``` r
dmd <- gdal_get_driver_md("GTiff")
str(dmd)
#> List of 23
#>  $ DCAP_RASTER                           : chr "YES"
#>  $ DMD_LONGNAME                          : chr "GeoTIFF"
#>  $ DMD_HELPTOPIC                         : chr "drivers/raster/gtiff.html"
#>  $ DMD_MIMETYPE                          : chr "image/tiff"
#>  $ DMD_EXTENSIONS                        : chr "tif tiff"
#>  $ DMD_EXTENSION                         : chr "tif"
#>  $ DMD_CREATIONDATATYPES                 : chr "Byte Int8 UInt16 Int16 UInt32 Int32 Float32 Float64 CInt16 CInt32 CFloat32 CFloat64"
#>  $ DMD_CREATIONOPTIONLIST                : chr "<CreationOptionList>   <Option name='COMPRESS' type='string-select'>       <Value>NONE</Value>       <Value>LZW"| __truncated__
#>  $ DMD_OVERVIEW_CREATIONOPTIONLIST       : chr "<OverviewCreationOptionList>   <Option name='LOCATION' type='string-select'>       <Value>INTERNAL</Value>     "| __truncated__
#>  $ DMD_OPENOPTIONLIST                    : chr "<OpenOptionList>   <Option name='NUM_THREADS' type='string' description='Number of worker threads for compressi"| __truncated__
#>  $ DMD_SUBDATASETS                       : chr "YES"
#>  $ DCAP_CREATE_SUBDATASETS               : chr "YES"
#>  $ DCAP_VIRTUALIO                        : chr "YES"
#>  $ DCAP_CREATE_ONLY_VISIBLE_AT_CLOSE_TIME: chr "YES"
#>  $ DCAP_CAN_READ_AFTER_DELETE            : chr "YES"
#>  $ DCAP_UPDATE                           : chr "YES"
#>  $ DMD_UPDATE_ITEMS                      : chr "GeoTransform SRS GCPs NoData ColorInterpretation RasterValues DatasetMetadata BandMetadata"
#>  $ LIBTIFF                               : chr "LIBTIFF, Version 4.7.0\nCopyright (c) 1988-1996 Sam Leffler\nCopyright (c) 1991-1996 Silicon Graphics, Inc."
#>  $ LIBGEOTIFF                            : chr "1740"
#>  $ DCAP_COORDINATE_EPOCH                 : chr "YES"
#>  $ DCAP_OPEN                             : chr "YES"
#>  $ DCAP_CREATE                           : chr "YES"
#>  $ DCAP_CREATECOPY                       : chr "YES"
```
