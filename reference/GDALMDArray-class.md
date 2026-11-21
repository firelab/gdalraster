# Class encapsulating an array in a multidimensional dataset (experimental)

`GDALMDArray` provides an interface for an array (an MDArray) in a
dataset of the GDAL Multidimensional Raster Data Model
(<https://gdal.org/en/stable/user/multidim_raster_data_model.html>). An
object of class `GDALMDArray` is returned by
`GDALMultiDimRaster$openMDArray()`, and exposes methods to:

- describe the array, its dimensions, data type and attributes

- get the nodata value, scale, offset, unit, spatial reference and block
  (chunk) size

- read coordinate values of a dimension

- read a hyperslab of the array (start, count and optional step per
  dimension)

- derive new arrays without copying data: a view given a slicing
  expression, a transposed view, an unscaled view and a mask

- expose a 2D view of the array as a classic raster, an object of class
  [`GDALRaster`](https://firelab.github.io/gdalraster/reference/GDALRaster-class.md).

An object of class `GDALMDArray` holds a reference to the dataset that
contains it, so the array remains valid after the `GDALMultiDimRaster`
object is closed or garbage collected.

**This class is experimental**. Its interface may change in future
releases. Requires GDAL \>= 3.2.

`GDALMDArray` is a C++ class exposed directly to R (via
`RCPP_EXPOSED_CLASS`). Fields and methods of the class are accessed
using the `$` operator. **Note that all arguments to class methods are
required and must be given in the order documented.**

Dimension indexes and offsets are 0-based, as in other **gdalraster**
class methods. Dimensions are always given in the array's own order,
slowest varying first (e.g., `time, lat, lon`).

## Usage (see Details)

    ## Obtain an object of class GDALMDArray
    ds <- new(GDALMultiDimRaster, filename)
    arr <- ds$openMDArray(path)

    ## Read/write fields
    arr$readByteAsRaw
    arr$quiet

    ## Methods
    arr$isOpen()
    arr$getName()
    arr$getFullName()
    arr$getDimensionCount()
    arr$getDimensions()
    arr$getDataType()
    arr$getAttributes()
    arr$getNoDataValue()
    arr$getScale()
    arr$getOffset()
    arr$getUnit()
    arr$getSpatialRef()
    arr$getBlockSize()
    arr$getInfo()
    arr$getCoordinateValues(dim)

    arr$read(start, count, step)

    arr$getView(view_expr)
    arr$transpose(axes)
    arr$getUnscaled()
    arr$getMask(options)
    arr$asClassicDataset(idx_xdim, idx_ydim, options)

    arr$close()

## Details

### Obtaining an object

`GDALMultiDimRaster$openMDArray(path)`  
Opens the array at `path`, a character string giving the full path of
the array from the root group, e.g., `"/temperature"` or
`"/group/temperature"`. Returns an object of class `GDALMDArray`. An
error is raised if no array is found at `path`.

### Read/write fields

`$readByteAsRaw`  
A logical value, `TRUE` to read arrays of data type Byte as R `raw`
vectors. Defaults to `FALSE` (Byte is read as `integer`).

`$quiet`  
A logical value, `TRUE` to suppress console output from class methods.
Defaults to `FALSE`. Reserved for methods added in later releases.

### Methods

`$isOpen()`  
Returns logical `TRUE` if the array is open, otherwise `FALSE`.

`$getName()`  
Returns the name of the array.

`$getFullName()`  
Returns the full path of the array.

`$getDimensionCount()`  
Returns the number of dimensions of the array (`0` for a scalar array).

`$getDimensions()`  
Returns a data frame describing the dimensions of the array in its own
order, with columns `name`, `full_name`, `size`, `type`, `direction` and
`indexing_variable`, as described for
`GDALMultiDimRaster$getDimensions()`.

`$getDataType()`  
Returns a list describing the data type of the array, with elements
`class` (`"NUMERIC"`, `"STRING"` or `"COMPOUND"`), `numeric_type` (the
GDAL data type name such as `"Int16"` or `"Float32"`, or `""` if not
numeric), `name` (the data type name, used for compound types) and
`size` (in bytes).

`$getAttributes()`  
Returns a named list of the attributes of the array, converted as
described for `GDALMultiDimRaster$getAttributes()`.

`$getNoDataValue()`  
Returns the nodata value of the array as a numeric value, or `NA` if no
nodata value is set.

`$getScale()`  
Returns the scale value of the array (e.g., from the `scale_factor`
attribute in netCDF), or `NA` if not set. Values returned by `$read()`
are not scaled. The unscaled value is `raw_value * scale + offset`.

`$getOffset()`  
Returns the offset value of the array (e.g., from the `add_offset`
attribute in netCDF), or `NA` if not set.

`$getUnit()`  
Returns the unit of the array values as a character string (e.g., `"K"`,
`"degC"`, or `"hours since 1900-01-01"` for a time coordinate), or `""`
if not set.

`$getSpatialRef()`  
Returns the spatial reference system of the array as a WKT string, or
`""` if not known.

`$getBlockSize()`  
Returns a numeric vector with the block (chunk) size of the array along
each dimension. A value of `0` means that no block size is known for
that dimension. Reading whole blocks is the most efficient access
pattern for chunked formats such as Zarr, netCDF-4 and HDF5.

`$getInfo()`  
Returns a named list with elements `name`, `full_name`, `dimensions`,
`datatype`, `block_size`, `nodata`, `scale`, `offset`, `unit`, `srs` and
`attributes`, combining the methods above in one call.

`$getCoordinateValues(dim)`  
Returns the values of the indexing variable (coordinate array) of the
dimension at 0-based index `dim`, or `NULL` if the dimension has no
indexing variable.

`$read(start, count, step)`  
Reads the whole array, or a hyperslab of it. `start` is a numeric vector
of 0-based start indexes and `count` a numeric vector of the number of
values to read, each with one value per dimension of the array. `step`
is a numeric vector giving the step between indexes for each dimension
(e.g., `2` to read every second value, or a negative value to read in
reverse order), or `NULL` for a step of `1`. Use `start = NULL` and
`count = NULL` to read the whole array, i.e., `$read(NULL, NULL, NULL)`.
All three arguments are required (see Description), but
[`mdim_read()`](https://firelab.github.io/gdalraster/reference/mdim_read.md)
provides defaults for them.

The value returned by `$read()` is a plain vector, with the last
dimension varying fastest (C order, the same layout as data returned by
`GDALRaster$read()`), and with no R attributes. See
[`mdim_read()`](https://firelab.github.io/gdalraster/reference/mdim_read.md)
for a reader that also returns dimension and coordinate information.
Data types follow `GDALRaster$read()`: integer types that fit in 32 bits
are returned as `integer` (or Byte as `raw` if `$readByteAsRaw` is
`TRUE`), other numeric types as `double` (64-bit integer values are
exact up to 2^53), complex types as `complex`, and string arrays as
`character`. The nodata value is returned as `NA`, as is `NaN` for
floating point types. Arrays of compound data type are not supported.

### Derived arrays

The methods below return a new object of class `GDALMDArray` that is a
view of this array. No data are read or copied until the new array is
read. The new array holds its own reference to the dataset, so it
remains valid after this array or the dataset is closed. Its fields
(`$readByteAsRaw`, `$quiet`) start with the values of this array.

`$getView(view_expr)`  
Returns a view of the array given a character string `view_expr`, using
the same syntax as NumPy basic slicing and indexing (0-based), or field
access by name, as described in section "View Expressions" of
[`mdim_as_classic()`](https://firelab.github.io/gdalraster/reference/mdim_as_classic.md).
For example, `"[0,...]"` selects the first index of the first dimension
(removing that dimension), `"[1:3,:,::2]"` takes indexes 1 and 2 of the
first dimension and every second index of the third, and `"[::-1,...]"`
reverses the first dimension. Note that GDAL renames the sliced
dimensions of a view (e.g., `"subset_lat_2_1_2"`), and they then have no
indexing variable.

`$transpose(axes)`  
Returns a view of the array with its dimensions reordered. `axes` is an
integer vector of 0-based dimension indexes of this array, giving for
each dimension of the new array the dimension of this array that it
comes from. For example, for an array with dimensions `time, lat, lon`,
`axes = c(2, 1, 0)` gives an array with dimensions `lon, lat, time`. A
value of `-1` inserts a new dimension of size 1.

`$getUnscaled()`  
Returns a view of the array with the scale and offset applied
(`raw_value * scale + offset`). The new array has data type `Float64`
(or `CFloat64` for a complex array), no scale or offset, and the nodata
value `NaN` if this array has a nodata value (read as `NA`).

`$getMask(options)`  
Returns a view of the array of data type Byte, with the value `1` where
a value of this array is valid and `0` where it is not, as determined
from the nodata value, and the attributes `_FillValue`, `missing_value`,
`valid_min`, `valid_max` and `valid_range`, if present (and `NaN` for
floating point types). `options` is a character vector of `NAME=VALUE`
pairs, or `NULL` (see `GDALMDArray::GetMask()` in the GDAL API
documentation).

### Classic raster view

`$asClassicDataset(idx_xdim, idx_ydim, options)`  
Returns a view of the array as a classic (2D) raster, an object of class
[`GDALRaster`](https://firelab.github.io/gdalraster/reference/GDALRaster-class.md).
`idx_xdim` and `idx_ydim` are the 0-based indexes of the dimensions to
use as the X (width) and Y (height) axes. Any other dimensions become
raster bands. `idx_ydim` is ignored for a 1D array. `options` is a
character vector of `NAME=VALUE` pairs, or `NULL` (see
`GDALMDArray::AsClassicDataset()` in the GDAL API documentation; it
requires GDAL \>= 3.8 when not empty). The geotransform is taken from
regularly spaced indexing variables of the X and Y dimensions. No data
are copied: the raster reads from the array, so a view from `$getView()`
can be used to take, e.g., one time step of a 4D array as a
`GDALRaster`, which can be passed to any function that works on a
`GDALRaster` (e.g.,
[`warp()`](https://firelab.github.io/gdalraster/reference/warp.md),
[`plot_raster()`](https://firelab.github.io/gdalraster/reference/plot_raster.md)).
The `GDALRaster` remains valid after the array is closed. See also
[`mdim_as_classic()`](https://firelab.github.io/gdalraster/reference/mdim_as_classic.md),
which opens a dataset and returns the same raster in one call.

`$close()`  
Closes the array and releases the reference to its dataset.

## See also

[GDALMultiDimRaster](https://firelab.github.io/gdalraster/reference/GDALMultiDimRaster-class.md),
[GDALRaster](https://firelab.github.io/gdalraster/reference/GDALRaster-class.md),
[`mdim_read()`](https://firelab.github.io/gdalraster/reference/mdim_read.md),
[`mdim_info()`](https://firelab.github.io/gdalraster/reference/mdim_info.md),
[`mdim_as_classic()`](https://firelab.github.io/gdalraster/reference/mdim_as_classic.md)

## Examples

``` r
f <- system.file("extdata/mdim_small.nc", package="gdalraster")
ds <- new(GDALMultiDimRaster, f)
arr <- ds$openMDArray("/t2m")
arr
#> C++ object of class <GDALMDArray>
#>   • Name: /t2m
#>   • Data type: Int16
#>   • Dimensions: time=4, lat=5, lon=6
#>   • Unit: degC

arr$getDimensions()
#>   name full_name size         type direction indexing_variable
#> 1 time     /time    4     TEMPORAL                       /time
#> 2  lat      /lat    5 HORIZONTAL_Y     NORTH              /lat
#> 3  lon      /lon    6 HORIZONTAL_X      EAST              /lon
arr$getDataType()
#> $class
#> [1] "NUMERIC"
#> 
#> $numeric_type
#> [1] "Int16"
#> 
#> $name
#> [1] ""
#> 
#> $size
#> [1] 2
#> 
arr$getBlockSize()
#> [1] 0 0 0
c(arr$getScale(), arr$getOffset())
#> [1] 0.01 0.00
arr$getUnit()
#> [1] "degC"

# coordinate values of the first dimension (time)
arr$getCoordinateValues(0)
#> [1]  0  6 12 18

# the first time step, as stored (not scaled)
v <- arr$read(start = c(0, 0, 0), count = c(1, 5, 6), step = NULL)
v
#>  [1] 1295 1305   NA 1325 1335 1345 1355 1365 1375 1385 1395 1405 1415 1425 1435
#> [16] 1445 1455 1465 1475 1485 1495 1505 1515 1525 1535 1545 1555 1565 1575 1585

# one grid cell, all time steps, scaled to degC
arr$read(c(0, 2, 3), c(4, 1, 1), NULL) * arr$getScale() + arr$getOffset()
#> [1] 14.45 15.45 16.45 17.45

# the same, from a view with the scale and offset applied
arr$getUnscaled()$read(c(0, 2, 3), c(4, 1, 1), NULL)
#> [1] 14.45 15.45 16.45 17.45

# the first time step as a view, and its mask of valid values
v1 <- arr$getView("[0,...]")
v1$getDimensions()$size
#> [1] 5 6
v1$getMask(NULL)$read(NULL, NULL, NULL)
#>  [1] 1 1 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1

# lon, lat, time order
arr$transpose(c(2, 1, 0))$getDimensions()$name
#> [1] "lon"  "lat"  "time"

# the first time step as a classic raster (lon is X, lat is Y)
r <- v1$asClassicDataset(1, 0, NULL)
r
#> C++ object of class <GDALRaster>
#>   • Driver: (driverless dataset)
#>   • DSN: ""
#>   • Dimensions: 6, 5, 1
#>   • CRS: not set
#>   • Pixel resolution: 0.250000, 0.250000
#>   • Bbox: 144.875000, -42.125000, 146.375000, -40.875000
r$getGeoTransform()
#> [1] 144.875   0.250   0.000 -40.875   0.000  -0.250
r$close()

arr$close()
ds$close()
```
