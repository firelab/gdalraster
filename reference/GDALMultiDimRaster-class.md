# Class encapsulating a multidimensional raster dataset (experimental)

`GDALMultiDimRaster` provides an interface for accessing a dataset in
the GDAL Multidimensional Raster Data Model
(<https://gdal.org/en/stable/user/multidim_raster_data_model.html>),
such as netCDF, HDF5 or Zarr. An object of class `GDALMultiDimRaster`
persists an open connection to the dataset and its root group, and
exposes methods to:

- retrieve dataset information

- list the groups and arrays in a group

- describe the dimensions of a group or an array

- read the attributes of a group or an array

- open an array as an object of class
  [`GDALMDArray`](https://firelab.github.io/gdalraster/reference/GDALMDArray-class.md).

Groups, arrays and dimensions are addressed by their full path from the
root group, e.g., `"/"`, `"/group/subgroup"` or `"/group/temperature"`.
A path without a leading `"/"` is taken from the root. Groups and
dimensions are returned as plain R lists and data frames. Arrays are
opened as objects of class
[`GDALMDArray`](https://firelab.github.io/gdalraster/reference/GDALMDArray-class.md).

**This class is experimental**. Its interface may change in future
releases. Requires GDAL \>= 3.2.

`GDALMultiDimRaster` is a C++ class exposed directly to R (via
`RCPP_EXPOSED_CLASS`). Fields and methods of the class are accessed
using the `$` operator. **Note that all arguments to class methods are
required and must be given in the order documented.** Naming the
arguments is optional but may be preferred for readability.

In this documentation, "attributes" always means GDAL attributes, i.e.,
metadata stored on groups and arrays in the dataset, not R object
attributes.

## Usage (see Details)

    ## Constructors
    # read-only by default:
    ds <- new(GDALMultiDimRaster, filename)
    # for update access:
    ds <- new(GDALMultiDimRaster, filename, read_only = FALSE)
    # to use dataset open options:
    ds <- new(GDALMultiDimRaster, filename, read_only, open_options)
    # to open in shared mode, or restrict the candidate drivers:
    ds <- new(GDALMultiDimRaster, filename, read_only, open_options, shared,
              allowed_drivers)

    ## Read/write fields
    ds$infoOptions
    ds$quiet

    ## Methods
    ds$getFilename()
    ds$open(read_only)
    ds$isOpen()
    ds$isReadOnly()
    ds$getDriverShortName()
    ds$getDriverLongName()
    ds$getFileList()
    ds$info()

    ds$getGroupNames(path)
    ds$getMDArrayNames(path)
    ds$getDimensions(path)
    ds$getAttributes(path)
    ds$getGroupInfo(path)
    ds$openMDArray(path)

    ds$close()

## Details

### Constructors

`new(GDALMultiDimRaster, filename)`  
Constructor for read-only access. `filename` is a character string
containing the file name or other data source name (DSN) of a
multidimensional raster, e.g., a netCDF file, a Zarr store given as
`ZARR:"/vsicurl/https://..."`, or a multidimensional VRT. Returns an
object of class `GDALMultiDimRaster`, or an error is raised if the
dataset cannot be opened in multidimensional mode.

`new(GDALMultiDimRaster, filename, read_only)`  
Constructor specifying read/write access (`read_only = TRUE|FALSE`).

`new(GDALMultiDimRaster, filename, read_only, open_options)`  
Constructor specifying dataset `open_options` as a character vector of
`NAME=VALUE` pairs.

`new(GDALMultiDimRaster, filename, read_only, open_options, shared, allowed_drivers)`  
Constructor to open the dataset in shared mode (`shared = TRUE`), and/or
to give `allowed_drivers` as a character vector of driver short names
that must be considered when opening `filename`. All arguments are
required in this form of the constructor, but `open_options` and
`allowed_drivers` may be `NULL`.

### Read/write fields

`$infoOptions`  
A character vector of command-line arguments for `gdalmdiminfo` used by
the `$info()` method (see below), e.g., `c("-detailed", "-limit", "5")`.
Defaults to an empty vector (no options).

`$quiet`  
A logical value, `TRUE` to suppress progress reporting and other console
output from class methods. Defaults to `FALSE`. Reserved for methods
added in later releases.

### Methods

`$getFilename()`  
Returns a character string containing the `filename` associated with
this `GDALMultiDimRaster` object.

`$open(read_only)`  
(Re-)opens the dataset on the existing filename. Use this method to open
a dataset that has been closed using `$close()`. May be used to re-open
a dataset with a different read/write access (`read_only` set to `TRUE`
or `FALSE`). The method will first close an open dataset, so it is not
required to call `$close()` explicitly in this case. No return value,
called for side effects.

`$isOpen()`  
Returns logical `TRUE` if the dataset is open, otherwise `FALSE`.

`$isReadOnly()`  
Returns logical `TRUE` if the dataset is open read-only, or `FALSE` if
opened for update.

`$getDriverShortName()`  
Returns the short name of the GDAL driver used to open the dataset
(e.g., `"netCDF"`, `"Zarr"`).

`$getDriverLongName()`  
Returns the long name of the GDAL driver used to open the dataset.

`$getFileList()`  
Returns a character vector of files believed to be part of the dataset.
If it returns an empty string (`""`) it means there is believed to be no
local file system files associated with the dataset (e.g., a virtual
file system).

`$info()`  
Prints various information about the dataset to the console, as JSON
output from the `gdalmdiminfo` utility, using the options given in
`$infoOptions`. No return value, called for that side effect. See also
[`mdim_info()`](https://firelab.github.io/gdalraster/reference/mdim_info.md),
which returns the information as a character string.

`$getGroupNames(path)`  
Returns a character vector containing the names of the sub-groups
directly under the group at `path` (a character string giving the full
path of a group, e.g., `"/"` for the root group). Returns an empty
vector if there are no sub-groups. An error is raised if no group is
found at `path`.

`$getMDArrayNames(path)`  
Returns a character vector containing the names of the arrays in the
group at `path`. Coordinate variables (indexing variables of dimensions)
are included. An error is raised if no group is found at `path`.

`$getDimensions(path)`  
Returns a data frame describing the dimensions of the group or the array
at `path`. For an array, rows are in the array's own dimension order
(slowest varying first). For a group, rows are the dimensions defined in
that group, in the order returned by the driver. The data frame has
columns:

- `name`: the dimension name

- `full_name`: the full path of the dimension

- `size`: the dimension size (numeric)

- `type`: the dimension type, e.g., `"HORIZONTAL_X"`, `"HORIZONTAL_Y"`,
  `"VERTICAL"`, `"TEMPORAL"`, or `""` if unknown

- `direction`: the dimension direction, e.g., `"EAST"`, `"NORTH"`,
  `"FUTURE"`, or `""` if unknown

- `indexing_variable`: the full path of the array holding the coordinate
  values of the dimension, or `""` if there is none.

A `path` is first looked up as a group, then as an array. An error is
raised if neither is found.

`$getAttributes(path)`  
Returns a named list of the attributes of the group or the array at
`path`. Values are converted by attribute data type: string attributes
are returned as `character`, integer attributes that fit in 32 bits as
`integer`, other numeric attributes as `double`, and attributes of
compound or complex data type as `raw` (the bytes as stored).
Multi-valued attributes are returned as vectors. Returns an empty list
if there are no attributes. Note that some drivers report certain
attributes through dedicated properties of an array instead (e.g., the
netCDF driver hides `units`, `_FillValue`, `scale_factor` and
`add_offset`, which will be available from methods of class
`GDALMDArray`). A `path` is first looked up as a group, then as an
array. An error is raised if neither is found.

`$getGroupInfo(path)`  
Returns a named list describing the group at `path`, with elements
`name`, `full_name`, `group_names`, `array_names`, `dimensions` (a data
frame as returned by `$getDimensions()`), and `attributes` (a list as
returned by `$getAttributes()`). An error is raised if no group is found
at `path`.

`$openMDArray(path)`  
Opens the array at `path` (a character string giving the full path of an
array, e.g., `"/temperature"` or `"/group/temperature"`) and returns an
object of class
[`GDALMDArray`](https://firelab.github.io/gdalraster/reference/GDALMDArray-class.md).
The array holds a reference to the dataset, so it remains valid after
`$close()` is called on this object. An error is raised if no array is
found at `path`.

`$close()`  
Closes the dataset and the root group. No return value, called for side
effects.

## See also

[GDALMDArray](https://firelab.github.io/gdalraster/reference/GDALMDArray-class.md),
[`mdim_read()`](https://firelab.github.io/gdalraster/reference/mdim_read.md),
[`mdim_info()`](https://firelab.github.io/gdalraster/reference/mdim_info.md),
[`mdim_translate()`](https://firelab.github.io/gdalraster/reference/mdim_translate.md),
[`mdim_as_classic()`](https://firelab.github.io/gdalraster/reference/mdim_as_classic.md)

GDAL Multidimensional Raster Data Model:  
<https://gdal.org/en/stable/user/multidim_raster_data_model.html>

## Examples

``` r
f <- system.file("extdata/mdim_small.nc", package="gdalraster")
ds <- new(GDALMultiDimRaster, f)
ds
#> C++ object of class <GDALMultiDimRaster>
#>   • Driver: Network Common Data Format (netCDF)
#>   • Filename:
#>   "/home/runner/work/_temp/Library/gdalraster/extdata/mdim_small.nc"
#>   • Access: read-only
#>   • Groups in root: 1
#>   • Arrays in root: 4 (lat, lon, time, t2m)

ds$getGroupNames("/")
#> [1] "ocean"
ds$getMDArrayNames("/")
#> [1] "lat"  "lon"  "time" "t2m" 
ds$getMDArrayNames("/ocean")
#> [1] "sst"

ds$getDimensions("/")
#>   name full_name size         type direction indexing_variable
#> 1  lat      /lat    5 HORIZONTAL_Y     NORTH              /lat
#> 2  lon      /lon    6 HORIZONTAL_X      EAST              /lon
#> 3 time     /time    4     TEMPORAL                       /time
ds$getDimensions("/t2m")
#>   name full_name size         type direction indexing_variable
#> 1 time     /time    4     TEMPORAL                       /time
#> 2  lat      /lat    5 HORIZONTAL_Y     NORTH              /lat
#> 3  lon      /lon    6 HORIZONTAL_X      EAST              /lon

ds$getAttributes("/")
#> $Conventions
#> [1] "CF-1.8"
#> 
#> $resolution
#> [1] 0.25
#> 
#> $title
#> [1] "gdalraster multidim test dataset"
#> 
#> $version
#> [1] 1
#> 
ds$getAttributes("/time")
#> $calendar
#> [1] "standard"
#> 
#> $standard_name
#> [1] "time"
#> 

str(ds$getGroupInfo("/ocean"))
#> List of 6
#>  $ name       : chr "ocean"
#>  $ full_name  : chr "/ocean"
#>  $ group_names: chr(0) 
#>  $ array_names: chr "sst"
#>  $ dimensions :'data.frame': 0 obs. of  6 variables:
#>   ..$ name             : chr(0) 
#>   ..$ full_name        : chr(0) 
#>   ..$ size             : num(0) 
#>   ..$ type             : chr(0) 
#>   ..$ direction        : chr(0) 
#>   ..$ indexing_variable: chr(0) 
#>  $ attributes :List of 1
#>   ..$ source: chr "synthetic"

arr <- ds$openMDArray("/ocean/sst")
arr$getDimensions()
#>   name full_name size         type direction indexing_variable
#> 1 time     /time    4     TEMPORAL                       /time
#> 2  lat      /lat    5 HORIZONTAL_Y     NORTH              /lat
#> 3  lon      /lon    6 HORIZONTAL_X      EAST              /lon
arr$close()

ds$infoOptions <- c("-array", "t2m", "-detailed", "-limit", "2")
ds$info()
#> {
#>   "type": "array",
#>   "name": "t2m",
#>   "datatype": "Int16",
#>   "dimensions": [
#>     {
#>       "name": "time",
#>       "full_name": "/time",
#>       "size": 4,
#>       "type": "TEMPORAL",
#>       "indexing_variable": {
#>         "time": {
#>           "datatype": "Float64",
#>           "dimensions": [
#>             "/time"
#>           ],
#>           "dimension_size": [
#>             4
#>           ],
#>           "attributes": {
#>             "calendar": {
#>               "datatype": "String",
#>               "value": "standard"
#>             },
#>             "standard_name": {
#>               "datatype": "String",
#>               "value": "time"
#>             },
#>             "units": {
#>               "datatype": "String",
#>               "value": "hours since 2000-01-01 00:00:00"
#>             }
#>           },
#>           "unit": "hours since 2000-01-01 00:00:00",
#>           "values": [0, "[...]", 18]
#>         }
#>       }
#>     },
#>     {
#>       "name": "lat",
#>       "full_name": "/lat",
#>       "size": 5,
#>       "type": "HORIZONTAL_Y",
#>       "direction": "NORTH",
#>       "indexing_variable": {
#>         "lat": {
#>           "datatype": "Float64",
#>           "dimensions": [
#>             "/lat"
#>           ],
#>           "dimension_size": [
#>             5
#>           ],
#>           "attributes": {
#>             "standard_name": {
#>               "datatype": "String",
#>               "value": "latitude"
#>             },
#>             "units": {
#>               "datatype": "String",
#>               "value": "degrees_north"
#>             }
#>           },
#>           "unit": "degrees_north",
#>           "values": [-41, "[...]", -42]
#>         }
#>       }
#>     },
#>     {
#>       "name": "lon",
#>       "full_name": "/lon",
#>       "size": 6,
#>       "type": "HORIZONTAL_X",
#>       "direction": "EAST",
#>       "indexing_variable": {
#>         "lon": {
#>           "datatype": "Float64",
#>           "dimensions": [
#>             "/lon"
#>           ],
#>           "dimension_size": [
#>             6
#>           ],
#>           "attributes": {
#>             "standard_name": {
#>               "datatype": "String",
#>               "value": "longitude"
#>             },
#>             "units": {
#>               "datatype": "String",
#>               "value": "degrees_east"
#>             }
#>           },
#>           "unit": "degrees_east",
#>           "values": [145, "[...]", 146.25]
#>         }
#>       }
#>     }
#>   ],
#>   "dimension_size": [
#>     4,
#>     5,
#>     6
#>   ],
#>   "attributes": {
#>     "_FillValue": {
#>       "datatype": "Int16",
#>       "value": -32767
#>     },
#>     "long_name": {
#>       "datatype": "String",
#>       "value": "2 metre temperature"
#>     },
#>     "valid_range": {
#>       "datatype": "Int16",
#>       "value": [-5000, 5000]
#>     },
#>     "units": {
#>       "datatype": "String",
#>       "value": "degC"
#>     },
#>     "add_offset": {
#>       "datatype": "Float64",
#>       "value": 0
#>     },
#>     "scale_factor": {
#>       "datatype": "Float64",
#>       "value": 0.01
#>     }
#>   },
#>   "unit": "degC",
#>   "nodata_value": -32767,
#>   "offset": 0,
#>   "scale": 0.01,
#>   "values": [
#>     [
#>       [1295, "[...]", 1345],
#>       "[...]",
#>       [1535, "[...]", 1585]
#>     ],
#>     "[...]",
#>     [
#>       [1595, "[...]", 1645],
#>       "[...]",
#>       [1835, "[...]", 1885]
#>     ]
#>   ]
#> }

ds$close()
```
