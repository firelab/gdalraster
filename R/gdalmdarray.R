#' @name GDALMDArray-class
#'
#' @aliases
#' Rcpp_GDALMDArray Rcpp_GDALMDArray-class GDALMDArray
#'
#' @title Class encapsulating an array in a multidimensional dataset (experimental)
#'
#' @description
#' `GDALMDArray` provides an interface for an array (an MDArray) in a dataset of
#' the GDAL Multidimensional Raster Data Model
#' (\url{https://gdal.org/en/stable/user/multidim_raster_data_model.html}).
#' An object of class `GDALMDArray` is returned by
#' \code{GDALMultiDimRaster$openMDArray()}, and exposes methods to:
#' * describe the array, its dimensions, data type and attributes
#' * get the nodata value, scale, offset, unit, spatial reference and block
#' (chunk) size
#' * read coordinate values of a dimension
#' * read a hyperslab of the array (start, count and optional step per
#' dimension).
#'
#' An object of class `GDALMDArray` holds a reference to the dataset that
#' contains it, so the array remains valid after the `GDALMultiDimRaster`
#' object is closed or garbage collected.
#'
#' **This class is experimental**. Its interface may change in future releases.
#' Requires GDAL >= 3.2.
#'
#' `GDALMDArray` is a C++ class exposed directly to \R (via
#' `RCPP_EXPOSED_CLASS`). Fields and methods of the class are accessed using
#' the `$` operator. **Note that all arguments to class methods are required
#' and must be given in the order documented.**
#'
#' Dimension indexes and offsets are 0-based, as in other **gdalraster** class
#' methods. Dimensions are always given in the array's own order, slowest
#' varying first (e.g., `time, lat, lon`).
#'
#' @section Usage (see Details):
#' ```
#' ## Obtain an object of class GDALMDArray
#' ds <- new(GDALMultiDimRaster, filename)
#' arr <- ds$openMDArray(path)
#'
#' ## Read/write fields
#' arr$readByteAsRaw
#' arr$quiet
#'
#' ## Methods
#' arr$isOpen()
#' arr$getName()
#' arr$getFullName()
#' arr$getDimensionCount()
#' arr$getDimensions()
#' arr$getDataType()
#' arr$getAttributes()
#' arr$getNoDataValue()
#' arr$getScale()
#' arr$getOffset()
#' arr$getUnit()
#' arr$getSpatialRef()
#' arr$getBlockSize()
#' arr$getInfo()
#' arr$getCoordinateValues(dim)
#'
#' arr$read()
#' arr$read(start, count)
#' arr$read(start, count, step)
#'
#' arr$close()
#' ```
#' @section Details:
#' ## Obtaining an object
#'
#' \code{GDALMultiDimRaster$openMDArray(path)}\cr
#' Opens the array at `path`, a character string giving the full path of the
#' array from the root group, e.g., `"/temperature"` or
#' `"/group/temperature"`. Returns an object of class `GDALMDArray`. An error
#' is raised if no array is found at `path`.
#'
#' ## Read/write fields
#'
#' \code{$readByteAsRaw}\cr
#' A logical value, `TRUE` to read arrays of data type Byte as \R `raw`
#' vectors. Defaults to `FALSE` (Byte is read as `integer`).
#'
#' \code{$quiet}\cr
#' A logical value, `TRUE` to suppress console output from class methods.
#' Defaults to `FALSE`. Reserved for methods added in later releases.
#'
#' ## Methods
#'
#' \code{$isOpen()}\cr
#' Returns logical `TRUE` if the array is open, otherwise `FALSE`.
#'
#' \code{$getName()}\cr
#' Returns the name of the array.
#'
#' \code{$getFullName()}\cr
#' Returns the full path of the array.
#'
#' \code{$getDimensionCount()}\cr
#' Returns the number of dimensions of the array (`0` for a scalar array).
#'
#' \code{$getDimensions()}\cr
#' Returns a data frame describing the dimensions of the array in its own
#' order, with columns `name`, `full_name`, `size`, `type`, `direction` and
#' `indexing_variable`, as described for
#' \code{GDALMultiDimRaster$getDimensions()}.
#'
#' \code{$getDataType()}\cr
#' Returns a list describing the data type of the array, with elements
#' `class` (`"NUMERIC"`, `"STRING"` or `"COMPOUND"`), `numeric_type` (the
#' GDAL data type name such as `"Int16"` or `"Float32"`, or `""` if not
#' numeric), `name` (the data type name, used for compound types) and `size`
#' (in bytes).
#'
#' \code{$getAttributes()}\cr
#' Returns a named list of the attributes of the array, converted as described
#' for \code{GDALMultiDimRaster$getAttributes()}.
#'
#' \code{$getNoDataValue()}\cr
#' Returns the nodata value of the array as a numeric value, or `NA` if no
#' nodata value is set.
#'
#' \code{$getScale()}\cr
#' Returns the scale value of the array (e.g., from the `scale_factor`
#' attribute in netCDF), or `NA` if not set. Values returned by
#' \code{$read()} are not scaled. The unscaled value is
#' `raw_value * scale + offset`.
#'
#' \code{$getOffset()}\cr
#' Returns the offset value of the array (e.g., from the `add_offset`
#' attribute in netCDF), or `NA` if not set.
#'
#' \code{$getUnit()}\cr
#' Returns the unit of the array values as a character string (e.g., `"K"`,
#' `"degC"`, or `"hours since 1900-01-01"` for a time coordinate), or `""` if
#' not set.
#'
#' \code{$getSpatialRef()}\cr
#' Returns the spatial reference system of the array as a WKT string, or `""`
#' if not known.
#'
#' \code{$getBlockSize()}\cr
#' Returns a numeric vector with the block (chunk) size of the array along
#' each dimension. A value of `0` means that no block size is known for that
#' dimension. Reading whole blocks is the most efficient access pattern for
#' chunked formats such as Zarr, netCDF-4 and HDF5.
#'
#' \code{$getInfo()}\cr
#' Returns a named list with elements `name`, `full_name`, `dimensions`,
#' `datatype`, `block_size`, `nodata`, `scale`, `offset`, `unit`, `srs` and
#' `attributes`, combining the methods above in one call.
#'
#' \code{$getCoordinateValues(dim)}\cr
#' Returns the values of the indexing variable (coordinate array) of the
#' dimension at 0-based index `dim`, or `NULL` if the dimension has no
#' indexing variable.
#'
#' \code{$read()}\cr
#' Reads the whole array.
#'
#' \code{$read(start, count)}\cr
#' Reads a hyperslab of the array. `start` is a numeric vector of 0-based
#' start indexes and `count` a numeric vector of the number of values to read,
#' each with one value per dimension of the array.
#'
#' \code{$read(start, count, step)}\cr
#' As above, with `step` a numeric vector giving the step between indexes for
#' each dimension (e.g., `2` to read every second value, or a negative value
#' to read in reverse order). `step` may also be `NULL` (step of `1`).
#'
#' The value returned by \code{$read()} is a plain vector, with the last
#' dimension varying fastest (C order, the same layout as data returned by
#' `GDALRaster$read()`), and with no \R attributes. See [mdim_read()] for a
#' reader that also returns dimension and coordinate information. Data types
#' follow `GDALRaster$read()`: integer types that fit in 32 bits are returned
#' as `integer` (or Byte as `raw` if \code{$readByteAsRaw} is `TRUE`), other
#' numeric types as `double` (64-bit integer values are exact up to 2^53),
#' complex types as `complex`, and string arrays as `character`. The nodata
#' value is returned as `NA`, as is `NaN` for floating point types. Arrays of
#' compound data type are not supported.
#'
#' \code{$close()}\cr
#' Closes the array and releases the reference to its dataset.
#'
#' @seealso
#' [GDALMultiDimRaster], [mdim_read()], [mdim_info()]
#'
#' @examplesIf gdal_version_num() >= gdal_compute_version(3, 2, 0) && isTRUE(gdal_formats("netCDF")$multidim_raster)
#' f <- system.file("extdata/mdim_small.nc", package="gdalraster")
#' ds <- new(GDALMultiDimRaster, f)
#' arr <- ds$openMDArray("/t2m")
#' arr
#'
#' arr$getDimensions()
#' arr$getDataType()
#' arr$getBlockSize()
#' c(arr$getScale(), arr$getOffset())
#' arr$getUnit()
#'
#' # coordinate values of the first dimension (time)
#' arr$getCoordinateValues(0)
#'
#' # the first time step, as stored (not scaled)
#' v <- arr$read(start = c(0, 0, 0), count = c(1, 5, 6))
#' v
#'
#' # one grid cell, all time steps, scaled to degC
#' arr$read(c(0, 2, 3), c(4, 1, 1)) * arr$getScale() + arr$getOffset()
#'
#' arr$close()
#' ds$close()
NULL

Rcpp::loadModule("mod_GDALMDArray", TRUE)
