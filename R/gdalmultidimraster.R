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
#' * read the attributes of a group or an array.
#'
#' Groups, arrays and dimensions are addressed by their full path from the
#' root group, e.g., `"/"`, `"/group/subgroup"` or `"/group/temperature"`. A
#' path without a leading `"/"` is taken from the root. Groups and dimensions
#' are returned as plain \R lists and data frames. Methods to open and read
#' an array (class `GDALMDArray`) will be added in a later release.
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
#' \code{$close()}\cr
#' Closes the dataset and the root group. No return value, called for side
#' effects.
#'
#' @seealso
#' [mdim_info()], [mdim_translate()], [mdim_as_classic()]
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
#' ds$infoOptions <- c("-array", "t2m", "-detailed", "-limit", "2")
#' ds$info()
#'
#' ds$close()
NULL

Rcpp::loadModule("mod_GDALMultiDimRaster", TRUE)
