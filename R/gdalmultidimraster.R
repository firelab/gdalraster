#' @name GDALMultiDimRaster-class
#'
#' @aliases
#' Rcpp_GDALMultiDimRaster Rcpp_GDALMultiDimRaster-class GDALMultiDimRaster
#'
#' @title Class encapsulating a multidimensional raster dataset (experimental)
#'
#' @description
#' `GDALMultiDimRaster` provides an interface for accessing a dataset in the
#' GDAL Multidimensional Raster Data Model
#' (\url{https://gdal.org/en/stable/user/multidim_raster_data_model.html}),
#' such as netCDF, HDF5 or Zarr. An object of class `GDALMultiDimRaster`
#' persists an open connection to the dataset and its root group, and exposes
#' methods to:
#' * retrieve dataset information
#' * list the groups and arrays in a group
#' * describe the dimensions of a group or an array
#' * read the attributes of a group or an array
#' * open an array as an object of class [`GDALMDArray`][GDALMDArray]
#' * create groups, dimensions, arrays and attributes in a dataset opened for
#' update, or in a new dataset (see [mdim_create()]).
#'
#' Groups, arrays and dimensions are addressed by their full path from the
#' root group, e.g., `"/"`, `"/group/subgroup"` or `"/group/temperature"`. A
#' path without a leading `"/"` is taken from the root. Groups and dimensions
#' are returned as plain \R lists and data frames. Arrays are opened as
#' objects of class [`GDALMDArray`][GDALMDArray].
#'
#' **This class is experimental**. Its interface may change in future releases.
#' Requires GDAL >= 3.2.
#'
#' `GDALMultiDimRaster` is a C++ class exposed directly to \R (via
#' `RCPP_EXPOSED_CLASS`). Fields and methods of the class are accessed using
#' the `$` operator. **Note that all arguments to class methods are required
#' and must be given in the order documented.** Naming the arguments is
#' optional but may be preferred for readability.
#'
#' In this documentation, "attributes" always means GDAL attributes, i.e.,
#' metadata stored on groups and arrays in the dataset, not \R object
#' attributes.
#'
#' @section Usage (see Details):
#' ```
#' ## Constructors
#' # read-only by default:
#' ds <- new(GDALMultiDimRaster, filename)
#' # for update access:
#' ds <- new(GDALMultiDimRaster, filename, read_only = FALSE)
#' # to use dataset open options:
#' ds <- new(GDALMultiDimRaster, filename, read_only, open_options)
#' # to open in shared mode, or restrict the candidate drivers:
#' ds <- new(GDALMultiDimRaster, filename, read_only, open_options, shared,
#'           allowed_drivers)
#'
#' ## Read/write fields
#' ds$infoOptions
#' ds$quiet
#'
#' ## Methods
#' ds$getFilename()
#' ds$open(read_only)
#' ds$isOpen()
#' ds$isReadOnly()
#' ds$getDriverShortName()
#' ds$getDriverLongName()
#' ds$getFileList()
#' ds$info()
#'
#' ds$getGroupNames(path)
#' ds$getMDArrayNames(path)
#' ds$getDimensions(path)
#' ds$getAttributes(path)
#' ds$getGroupInfo(path)
#' ds$openMDArray(path)
#'
#' ds$createGroup(path, options)
#' ds$createDimension(path, name, type, direction, size, options)
#' ds$createMDArray(path, dim_paths, data_type, options)
#' ds$setAttribute(path, name, value, data_type)
#' ds$deleteAttribute(path, name)
#'
#' ds$close()
#' ```
#' @section Details:
#' ## Constructors
#'
#' \code{new(GDALMultiDimRaster, filename)}\cr
#' Constructor for read-only access. `filename` is a character string
#' containing the file name or other data source name (DSN) of a
#' multidimensional raster, e.g., a netCDF file, a Zarr store given as
#' `ZARR:"/vsicurl/https://..."`, or a multidimensional VRT. Returns an
#' object of class `GDALMultiDimRaster`, or an error is raised if the dataset
#' cannot be opened in multidimensional mode.
#'
#' \code{new(GDALMultiDimRaster, filename, read_only)}\cr
#' Constructor specifying read/write access (`read_only = TRUE|FALSE`).
#'
#' \code{new(GDALMultiDimRaster, filename, read_only, open_options)}\cr
#' Constructor specifying dataset `open_options` as a character vector of
#' `NAME=VALUE` pairs.
#'
#' \code{new(GDALMultiDimRaster, filename, read_only, open_options, shared, allowed_drivers)}\cr
#' Constructor to open the dataset in shared mode (`shared = TRUE`), and/or to
#' give `allowed_drivers` as a character vector of driver short names that
#' must be considered when opening `filename`. All arguments are required in
#' this form of the constructor, but `open_options` and `allowed_drivers` may
#' be `NULL`.
#'
#' ## Read/write fields
#'
#' \code{$infoOptions}\cr
#' A character vector of command-line arguments for \command{gdalmdiminfo}
#' used by the \code{$info()} method (see below), e.g.,
#' `c("-detailed", "-limit", "5")`. Defaults to an empty vector (no options).
#'
#' \code{$quiet}\cr
#' A logical value, `TRUE` to suppress progress reporting and other console
#' output from class methods. Defaults to `FALSE`. Reserved for methods
#' added in later releases.
#'
#' ## Methods
#'
#' \code{$getFilename()}\cr
#' Returns a character string containing the `filename` associated with this
#' `GDALMultiDimRaster` object.
#'
#' \code{$open(read_only)}\cr
#' (Re-)opens the dataset on the existing filename. Use this method to
#' open a dataset that has been closed using \code{$close()}. May be used to
#' re-open a dataset with a different read/write access (`read_only` set to
#' `TRUE` or `FALSE`). The method will first close an open dataset, so it is
#' not required to call \code{$close()} explicitly in this case.
#' No return value, called for side effects.
#'
#' \code{$isOpen()}\cr
#' Returns logical `TRUE` if the dataset is open, otherwise `FALSE`.
#'
#' \code{$isReadOnly()}\cr
#' Returns logical `TRUE` if the dataset is open read-only, or `FALSE` if
#' opened for update.
#'
#' \code{$getDriverShortName()}\cr
#' Returns the short name of the GDAL driver used to open the dataset
#' (e.g., `"netCDF"`, `"Zarr"`).
#'
#' \code{$getDriverLongName()}\cr
#' Returns the long name of the GDAL driver used to open the dataset.
#'
#' \code{$getFileList()}\cr
#' Returns a character vector of files believed to be part of the dataset.
#' If it returns an empty string (`""`) it means there is believed to be no
#' local file system files associated with the dataset (e.g., a virtual file
#' system).
#'
#' \code{$info()}\cr
#' Prints various information about the dataset to the console, as JSON
#' output from the \command{gdalmdiminfo} utility, using the options given in
#' \code{$infoOptions}. No return value, called for that side effect. See also
#' [mdim_info()], which returns the information as a character string.
#'
#' \code{$getGroupNames(path)}\cr
#' Returns a character vector containing the names of the sub-groups directly
#' under the group at `path` (a character string giving the full path of a
#' group, e.g., `"/"` for the root group). Returns an empty vector if there
#' are no sub-groups. An error is raised if no group is found at `path`.
#'
#' \code{$getMDArrayNames(path)}\cr
#' Returns a character vector containing the names of the arrays in the group
#' at `path`. Coordinate variables (indexing variables of dimensions) are
#' included. An error is raised if no group is found at `path`.
#'
#' \code{$getDimensions(path)}\cr
#' Returns a data frame describing the dimensions of the group or the array at
#' `path`. For an array, rows are in the array's own dimension order (slowest
#' varying first). For a group, rows are the dimensions defined in that group,
#' in the order returned by the driver. The data frame has columns:
#' * `name`: the dimension name
#' * `full_name`: the full path of the dimension
#' * `size`: the dimension size (numeric)
#' * `type`: the dimension type, e.g., `"HORIZONTAL_X"`, `"HORIZONTAL_Y"`,
#' `"VERTICAL"`, `"TEMPORAL"`, or `""` if unknown
#' * `direction`: the dimension direction, e.g., `"EAST"`, `"NORTH"`,
#' `"FUTURE"`, or `""` if unknown
#' * `indexing_variable`: the full path of the array holding the coordinate
#' values of the dimension, or `""` if there is none.
#'
#' A `path` is first looked up as a group, then as an array. An error is
#' raised if neither is found.
#'
#' \code{$getAttributes(path)}\cr
#' Returns a named list of the attributes of the group or the array at `path`.
#' Values are converted by attribute data type: string attributes are returned
#' as `character`, integer attributes that fit in 32 bits as `integer`, other
#' numeric attributes as `double`, and attributes of compound or complex data
#' type as `raw` (the bytes as stored). Multi-valued attributes are returned
#' as vectors. Returns an empty list if there are no attributes. Note that
#' some drivers report certain attributes through dedicated properties of an
#' array instead (e.g., the netCDF driver hides `units`, `_FillValue`,
#' `scale_factor` and `add_offset`, which will be available from methods of
#' class `GDALMDArray`). A `path` is first looked up as a group, then as an
#' array. An error is raised if neither is found.
#'
#' \code{$getGroupInfo(path)}\cr
#' Returns a named list describing the group at `path`, with elements
#' `name`, `full_name`, `group_names`, `array_names`, `dimensions` (a data
#' frame as returned by \code{$getDimensions()}), and `attributes` (a list as
#' returned by \code{$getAttributes()}). An error is raised if no group is
#' found at `path`.
#'
#' \code{$openMDArray(path)}\cr
#' Opens the array at `path` (a character string giving the full path of an
#' array, e.g., `"/temperature"` or `"/group/temperature"`) and returns an
#' object of class [`GDALMDArray`][GDALMDArray]. The array holds a reference to
#' the dataset, so it remains valid after \code{$close()} is called on this
#' object. An error is raised if no array is found at `path`.
#'
#' ## Creating groups, dimensions, arrays and attributes
#'
#' The methods below require a dataset open for update, i.e., opened with
#' `read_only = FALSE` or created with [mdim_create()], and a format driver
#' that supports the operation. An error is raised if the operation fails.
#' They have no return value unless stated otherwise. Changes may not be
#' written to the file until the dataset is closed, which happens when
#' \code{$close()} has been called on this object and on every array object
#' obtained from it. That includes arrays that were not assigned a name, as
#' in `ds$openMDArray("/x")$read(NULL, NULL, NULL)`, which stay open until
#' garbage collected (see [gc()]). For the same reason, a file may fail to
#' re-open for update while array objects from an earlier open still exist.
#'
#' \code{$createGroup(path, options)}\cr
#' Creates a group. `path` is the full path of the new group, e.g.,
#' `"/ocean"` or `"/ocean/surface"`. Its parent group must exist. `options`
#' is a character vector of driver-specific `NAME=VALUE` group creation
#' options, or `NULL`.
#'
#' \code{$createDimension(path, name, type, direction, size, options)}\cr
#' Creates a dimension in the group at `path` (`"/"` for the root group).
#' `name` is the name of the dimension, so that its full path is, e.g.,
#' `"/time"` for `path = "/"` and `name = "time"`. `type` is a character
#' string, generally one of `"HORIZONTAL_X"`, `"HORIZONTAL_Y"`, `"VERTICAL"`,
#' `"TEMPORAL"`, `"PARAMETRIC"` or `""` (no type). `direction` is a character
#' string, generally one of `"EAST"`, `"WEST"`, `"SOUTH"`, `"NORTH"`, `"UP"`,
#' `"DOWN"`, `"FUTURE"`, `"PAST"` or `""`. `size` is the number of values
#' along the dimension. How `type` and `direction` are stored depends on the
#' format, and they may read back differently after the dataset is re-opened
#' (e.g., netCDF does not store them, and derives them from CF attributes of
#' the indexing variable such as its unit). `options` is a character vector
#' of driver-specific `NAME=VALUE` dimension creation options, or `NULL`,
#' e.g., `"UNLIMITED=YES"` for netCDF.
#'
#' \code{$createMDArray(path, dim_paths, data_type, options)}\cr
#' Creates an array and returns it as an object of class
#' [`GDALMDArray`][GDALMDArray]. `path` is the
#' full path of the new array, e.g., `"/temperature"`. Its parent group must
#' exist. `dim_paths` is a character vector of the full paths of its
#' dimensions, in order, e.g., `c("/time", "/lat", "/lon")` (see
#' \code{$createDimension()}), or `NULL` (or `character(0)`) for an array
#' with no dimensions (a single value). `data_type` is a character string
#' giving a GDAL data type name (e.g., `"Byte"`, `"Int16"`, `"Int32"`,
#' `"Float32"`, `"Float64"`, see [`DEFAULT_NODATA`] for the full list), or
#' `"String"` for an array of variable-length strings (not supported by all
#' formats).
#' `options` is a character vector of driver-specific `NAME=VALUE` array
#' creation options, or `NULL`, e.g., `"BLOCKSIZE=1,180,360"` and
#' `"COMPRESS=DEFLATE"` for netCDF (see the documentation of the format
#' driver). A 1D array with the same full path as its dimension (the same
#' group and the same name, e.g., array `"/time"` on dimension `"/time"`) is
#' set as the indexing variable of that dimension, i.e., it holds the
#' coordinate values of the dimension.
#'
#' \code{$setAttribute(path, name, value, data_type)}\cr
#' Sets the attribute `name` of the group or array at `path`. `value` is a
#' character, numeric, integer or logical vector, of length `1` or more and
#' with no `NA` values (`NaN` is accepted in a numeric vector). `data_type`
#' is the data type of the attribute. With `""` it follows `value`: String
#' for character, Float64 for numeric, and Int32 for integer or logical.
#' Otherwise give a GDAL data type name for numeric, integer or logical
#' values (e.g., `"Int16"`, `"Float32"`), which are converted to that type,
#' or `"String"` for character values. This matters for attributes that, by
#' convention, have the data type of their array (e.g., `valid_range`,
#' `valid_min` and `valid_max` in the CF conventions). Factors and
#' `integer64` vectors are not accepted, convert them first. An attribute
#' that already exists is replaced by deleting it and creating it again, so
#' that its type and length may change (requires GDAL >= 3.8, otherwise the
#' result depends on the format driver). The replacement is not atomic: if
#' the new value cannot be written, the previous attribute is not restored.
#' Some formats restrict certain attributes, e.g., netCDF requires
#' `_FillValue` to have the data type of its array.
#'
#' \code{$deleteAttribute(path, name)}\cr
#' Deletes the attribute `name` of the group or array at `path`. Requires
#' GDAL >= 3.8.
#'
#' \code{$close()}\cr
#' Closes the dataset and the root group. No return value, called for side
#' effects.
#'
#' @seealso
#' [GDALMDArray], [mdim_create()], [mdim_read()], [mdim_info()],
#' [mdim_translate()], [mdim_as_classic()]
#'
#' GDAL Multidimensional Raster Data Model:\cr
#' \url{https://gdal.org/en/stable/user/multidim_raster_data_model.html}
#'
#' @examplesIf gdal_version_num() >= gdal_compute_version(3, 2, 0) && isTRUE(gdal_formats("netCDF")$multidim_raster)
#' f <- system.file("extdata/mdim_small.nc", package="gdalraster")
#' ds <- new(GDALMultiDimRaster, f)
#' ds
#'
#' ds$getGroupNames("/")
#' ds$getMDArrayNames("/")
#' ds$getMDArrayNames("/ocean")
#'
#' ds$getDimensions("/")
#' ds$getDimensions("/t2m")
#'
#' ds$getAttributes("/")
#' ds$getAttributes("/time")
#'
#' str(ds$getGroupInfo("/ocean"))
#'
#' arr <- ds$openMDArray("/ocean/sst")
#' arr$getDimensions()
#' arr$close()
#'
#' ds$infoOptions <- c("-array", "t2m", "-detailed", "-limit", "2")
#' ds$info()
#'
#' ds$close()
#'
#' ## create a new dataset, see also mdim_create()
#' f_new <- tempfile(fileext = ".nc")
#' ds <- mdim_create("netCDF", f_new)
#' ds$createDimension("/", "x", "HORIZONTAL_X", "EAST", 3, NULL)
#' x <- ds$createMDArray("/x", "/x", "Float64", NULL)
#' ds$setAttribute("/", "title", "a new dataset", "")
#' ds$setAttribute("/x", "units", "degrees_east", "")
#' x$close()
#' ds$close()
#'
#' ds <- new(GDALMultiDimRaster, f_new)
#' ds$getAttributes("/")$title
#' ds$getDimensions("/")
#' ds$close()
#' \dontshow{unlink(f_new)}
NULL

Rcpp::loadModule("mod_GDALMultiDimRaster", TRUE)
