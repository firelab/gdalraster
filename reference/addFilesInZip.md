# Create/append to a potentially Seek-Optimized ZIP file (SOZip)

`addFilesInZip()` will create new or open existing ZIP file, and add one
or more compressed files potentially using the seek optimization
extension. This function is basically a wrapper for `CPLAddFileInZip()`
in the GDAL Common Portability Library, but optionally creates a new ZIP
file first (with `CPLCreateZip()`). It provides a subset of
functionality in the GDAL `sozip` command-line utility
(<https://gdal.org/en/stable/programs/sozip.html>). Requires GDAL \>=
3.7.

## Usage

``` r
addFilesInZip(
  zip_file,
  add_files,
  overwrite = FALSE,
  full_paths = TRUE,
  sozip_enabled = NULL,
  sozip_chunk_size = NULL,
  sozip_min_file_size = NULL,
  num_threads = NULL,
  content_type = NULL,
  quiet = FALSE
)
```

## Arguments

- zip_file:

  Filename of the ZIP file. Will be created if it does not exist or if
  `overwrite = TRUE`. Otherwise will append to an existing file.

- add_files:

  Character vector of one or more input filenames to add.

- overwrite:

  Logical scalar. Overwrite the target zip file if it already exists.

- full_paths:

  Logical scalar. By default, the full path will be stored (relative to
  the current directory). `FALSE` to store just the name of a saved file
  (drop the path).

- sozip_enabled:

  String. Whether to generate a SOZip index for the file. One of
  `"AUTO"` (the default), `"YES"` or `"NO"` (see Details).

- sozip_chunk_size:

  The chunk size for a seek-optimized file. Defaults to 32768 bytes. The
  value is specified in bytes, or K and M suffix can be used
  respectively to specify a value in kilo-bytes or mega-bytes. Will be
  coerced to string.

- sozip_min_file_size:

  The minimum file size to decide if a file should be seek-optimized, in
  `sozip_enabled="AUTO"` mode. Defaults to 1 MB byte. The value is
  specified in bytes, or K, M or G suffix can be used respectively to
  specify a value in kilo-bytes, mega-bytes or giga-bytes. Will be
  coerced to string.

- num_threads:

  Number of threads used for SOZip generation. Defaults to `"ALL_CPUS"`
  or specify an integer value (coerced to string).

- content_type:

  String Content-Type value for the file. This is stored as a key-value
  pair in the extra field extension 'KV' (0x564b) dedicated to storing
  key-value pair metadata.

- quiet:

  Logical scalar. `TRUE` for quiet mode, no progress messages emitted.
  Defaults to `FALSE`.

## Value

Logical indicating success (invisible `TRUE`). An error is raised if the
operation fails.

## Details

A Seek-Optimized ZIP file (SOZip) contains one or more compressed files
organized and annotated such that a SOZip-aware reader can perform very
fast random access within the .zip file (see
<https://github.com/sozip/sozip-spec>). Large compressed files can be
accessed directly from SOZip without prior decompression. The .zip file
is otherwise fully backward compatible.

If `sozip_enabled="AUTO"` (the default), a file is seek-optimized only
if its size is above the values of `sozip_min_file_size` (default 1 MB)
and `sozip_chunk_size` (default `32768`). In `"YES"` mode, all input
files will be seek-optimized. In `"NO"` mode, no input files will be
seek-optimized. The default can be changed with the `CPL_SOZIP_ENABLED`
configuration option.

## Note

The `GDAL_NUM_THREADS` configuration option can be set to `ALL_CPUS` or
an integer value to specify the number of threads to use for
SOZip-compressed files (see
[`set_config_option()`](https://firelab.github.io/gdalraster/reference/set_config_option.md)).

SOZip can be validated with:

    vsi_get_file_metadata(zip_file, domain="ZIP")

where `zip_file` uses the /vsizip/ prefix.

## See also

[`vsi_get_file_metadata()`](https://firelab.github.io/gdalraster/reference/vsi_get_file_metadata.md)

## Examples

``` r
f <- system.file("extdata/ynp_fires_1984_2022.gpkg", package = "gdalraster")
zip_file <- file.path(tempdir(), "ynp_fires.zip")

# Requires GDAL >= 3.7
if (gdal_version_num() >= gdal_compute_version(3, 7, 0)) {
  addFilesInZip(zip_file, f, full_paths = FALSE, sozip_enabled = "YES",
                num_threads = 1)

  print("Files in zip archive:")
  print(unzip(zip_file, list = TRUE))

  # Open with GDAL using Virtual File System handler '/vsizip/'
  # https://gdal.org/en/stable/user/virtual_file_systems.html#vsizip-zip-archives
  vsi_f <- file.path("/vsizip", zip_file, "ynp_fires_1984_2022.gpkg")
  print("SOZip metadata:")
  print(vsi_get_file_metadata(vsi_f, domain = "ZIP"))

  lyr <- new(GDALVector, vsi_f)
  lyr$info()
  lyr$close()
  DONTSHOW({vsi_unlink(zip_file)})
}
#> ℹ Adding "ynp_fires_1984_2022.gpkg"
#> ✔ Adding "ynp_fires_1984_2022.gpkg" [20ms]
#> 
#> [1] "Files in zip archive:"
#>                       Name Length                Date
#> 1 ynp_fires_1984_2022.gpkg 307200 2026-05-17 17:24:00
#> [1] "SOZip metadata:"
#> $START_DATA_OFFSET
#> [1] "54"
#> 
#> $COMPRESSION_METHOD
#> [1] "8 (DEFLATE)"
#> 
#> $COMPRESSED_SIZE
#> [1] "164729"
#> 
#> $UNCOMPRESSED_SIZE
#> [1] "307200"
#> 
#> $SOZIP_FOUND
#> [1] "YES"
#> 
#> $SOZIP_VERSION
#> [1] "1"
#> 
#> $SOZIP_OFFSET_SIZE
#> [1] "8"
#> 
#> $SOZIP_CHUNK_SIZE
#> [1] "32768"
#> 
#> $SOZIP_START_DATA_OFFSET
#> [1] "164848"
#> 
#> $SOZIP_VALID
#> [1] "YES"
#> 
#> INFO: Open of `/vsizip//tmp/Rtmpr2QnNr/ynp_fires.zip/ynp_fires_1984_2022.gpkg'
#>       using driver `GPKG' successful.
#> 
#> Layer name: mtbs_perims
#> Geometry: Multi Polygon
#> Feature Count: 61
#> Extent: (469685.726682, -12917.756287) - (573531.719643, 96577.336358)
#> Layer SRS WKT:
#> PROJCRS["NAD83 / Montana",
#>     BASEGEOGCRS["NAD83",
#>         DATUM["North American Datum 1983",
#>             ELLIPSOID["GRS 1980",6378137,298.257222101,
#>                 LENGTHUNIT["metre",1]]],
#>         PRIMEM["Greenwich",0,
#>             ANGLEUNIT["degree",0.0174532925199433]],
#>         ID["EPSG",4269]],
#>     CONVERSION["SPCS83 Montana zone (meter)",
#>         METHOD["Lambert Conic Conformal (2SP)",
#>             ID["EPSG",9802]],
#>         PARAMETER["Latitude of false origin",44.25,
#>             ANGLEUNIT["degree",0.0174532925199433],
#>             ID["EPSG",8821]],
#>         PARAMETER["Longitude of false origin",-109.5,
#>             ANGLEUNIT["degree",0.0174532925199433],
#>             ID["EPSG",8822]],
#>         PARAMETER["Latitude of 1st standard parallel",49,
#>             ANGLEUNIT["degree",0.0174532925199433],
#>             ID["EPSG",8823]],
#>         PARAMETER["Latitude of 2nd standard parallel",45,
#>             ANGLEUNIT["degree",0.0174532925199433],
#>             ID["EPSG",8824]],
#>         PARAMETER["Easting at false origin",600000,
#>             LENGTHUNIT["metre",1],
#>             ID["EPSG",8826]],
#>         PARAMETER["Northing at false origin",0,
#>             LENGTHUNIT["metre",1],
#>             ID["EPSG",8827]]],
#>     CS[Cartesian,2],
#>         AXIS["easting (X)",east,
#>             ORDER[1],
#>             LENGTHUNIT["metre",1]],
#>         AXIS["northing (Y)",north,
#>             ORDER[2],
#>             LENGTHUNIT["metre",1]],
#>     USAGE[
#>         SCOPE["Engineering survey, topographic mapping."],
#>         AREA["United States (USA) - Montana - counties of Beaverhead; Big Horn; Blaine; Broadwater; Carbon; Carter; Cascade; Chouteau; Custer; Daniels; Dawson; Deer Lodge; Fallon; Fergus; Flathead; Gallatin; Garfield; Glacier; Golden Valley; Granite; Hill; Jefferson; Judith Basin; Lake; Lewis and Clark; Liberty; Lincoln; Madison; McCone; Meagher; Mineral; Missoula; Musselshell; Park; Petroleum; Phillips; Pondera; Powder River; Powell; Prairie; Ravalli; Richland; Roosevelt; Rosebud; Sanders; Sheridan; Silver Bow; Stillwater; Sweet Grass; Teton; Toole; Treasure; Valley; Wheatland; Wibaux; Yellowstone."],
#>         BBOX[44.35,-116.07,49.01,-104.04]],
#>     ID["EPSG",32100]]
#> Data axis to CRS axis mapping: 1,2
#> FID Column = fid
#> Geometry Column = geom
#> event_id: String (254.0)
#> incid_name: String (254.0)
#> incid_type: String (254.0)
#> map_id: Integer64 (0.0)
#> burn_bnd_ac: Integer64 (0.0)
#> burn_bnd_lat: String (10.0)
#> burn_bnd_lon: String (10.0)
#> ig_date: Date
#> ig_year: Integer (0.0)
```
