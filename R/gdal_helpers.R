# Miscellaneous helper functions for working with the GDAL API
# Chris Toney <chris.toney at usda.gov>

#' @noRd
#' @export
.get_crs_name <- function(wkt) {
    # name of form "<srs name> [(EPSG:####[, confidence ##])]"
    # include EPSG code if confidence > 50
    # include the confidence value if < 100

    crs_name <- srs_get_name(wkt)
    epsg <- srs_find_epsg(wkt, all_matches = TRUE)
    if (!is.null(epsg)) {
        if (nrow(epsg) >= 1 && epsg$confidence[1] > 50) {
            crs_name <- paste0(crs_name, " (", epsg$authority_name[1], ":",
                               epsg$authority_code[1])
            if (epsg$confidence[1] < 100) {
                crs_name <- paste0(crs_name, ", confidence ",
                                   epsg$confidence[1])
            }
            crs_name <- paste0(crs_name, ")")
        }
    }
    return(crs_name)
}


#' Compute a GDAL integer version number from major, minor, revision
#'
#' `gdal_compute_version()` computes a full integer version number
#' (GDAL_VERSION_NUM) from individual components (major, minor, revision).
#' Convenience function for checking a GDAL version requirement using
#' `gdal_version_num()`.
#'
#' @param maj Numeric value, major version component (coerced to integer by
#' truncation).
#' @param min Numeric value, min version component (coerced to integer by
#' truncation).
#' @param rev Numeric value, revision version component (coerced to integer by
#' truncation).
#' @returns Integer version number compatible with `gdal_version_num()`.
#'
#' @seealso
#' [gdal_version_num()]
#'
#' @examples
#' (gdal_version_num() >= gdal_compute_version(3, 7, 0))
#' @export
gdal_compute_version <- function(maj, min, rev) {
    if (!is.numeric(maj) || length(maj) != 1)
        stop("'maj' must be a single numeric value", call. = FALSE)
    else
        maj <- as.integer(maj)
    if (!is.numeric(min) || length(min) != 1)
        stop("'min' must be a single numeric value", call. = FALSE)
    else
        min <- as.integer(min)
    if (!is.numeric(rev) || length(rev) != 1)
        stop("'rev' must be a single numeric value", call. = FALSE)
    else
        rev <- as.integer(rev)

    return(as.integer(maj * 1000000 + min * 10000 + rev * 100))
}


#' Return library version information for GDAL and its dependencies
#'
#' `lib_versions()` returns a named list of library version information for
#' GDAL and its major dependencies, currently PROJ and GEOS. It provides library
#' versions in a consistent format, as an alternative to the separate
#' `gdal_version()`, `proj_version()` and `geos_version()`.
#'
#' @returns
#' A named list with elements `"gdal"`, `"proj"` and `"geos"`, each
#' containing a named list with the following elements:
#' * `"name"`: character string version as `"major.minor.patch"`
#' * `"major"`: integer major version number
#' * `"minor"`: integer minor version number
#' * `"patch"`: integer patch version number
#'
#' @seealso
#' [gdal_version()], [proj_version()], [geos_version()]
#'
#' @examples
#' lib_versions()
#' @export
lib_versions <- function() {
    out <- vector("list", 3)
    names(out) <- c("gdal", "proj", "geos")

    gdal_parts <- gdal_version()[4] |> strsplit(".", fixed = TRUE) |> unlist()
    out$gdal <- list(name = gdal_version()[4],
                     major = as.integer(gdal_parts[1]),
                     minor = as.integer(gdal_parts[2]),
                     patch = as.integer(gdal_parts[3]))
    out$proj <- proj_version()
    out$geos <- geos_version()

    return(out)
}


#' Create/append to a potentially Seek-Optimized ZIP file (SOZip)
#'
#' `addFilesInZip()` will create new or open existing ZIP file, and
#' add one or more compressed files potentially using the seek optimization
#' extension. This function is basically a wrapper for `CPLAddFileInZip()`
#' in the GDAL Common Portability Library, but optionally creates a new ZIP
#' file first (with `CPLCreateZip()`). It provides a subset of functionality
#' in the GDAL `sozip` command-line utility
#' (\url{https://gdal.org/en/stable/programs/sozip.html}). Requires GDAL >= 3.7.
#'
#' @details
#' A Seek-Optimized ZIP file (SOZip) contains one or more compressed files
#' organized and annotated such that a SOZip-aware reader can perform very
#' fast random access within the .zip file
#' (see \url{https://github.com/sozip/sozip-spec}).
#' Large compressed files can be accessed directly from SOZip without prior
#' decompression. The .zip file is otherwise fully backward compatible.
#'
#' If `sozip_enabled="AUTO"` (the default), a file is seek-optimized only if
#' its size is above the values of `sozip_min_file_size` (default 1 MB) and
#' `sozip_chunk_size` (default `32768`).
#' In `"YES"` mode, all input files will be seek-optimized. In `"NO"` mode, no
#' input files will be seek-optimized. The default can be changed with the
#' `CPL_SOZIP_ENABLED` configuration option.
#'
#' @param zip_file Filename of the ZIP file. Will be created if it does not
#' exist or if `overwrite = TRUE`. Otherwise will append to an existing file.
#' @param add_files Character vector of one or more input filenames to add.
#' @param overwrite Logical scalar. Overwrite the target zip file if it already
#' exists.
#' @param full_paths Logical scalar. By default, the full path will be stored
#' (relative to the current directory). `FALSE` to store just the name of a
#' saved file (drop the path).
#' @param sozip_enabled String. Whether to generate a SOZip index for the file.
#' One of `"AUTO"` (the default), `"YES"` or `"NO"` (see Details).
#' @param sozip_chunk_size The chunk size for a seek-optimized file.
#' Defaults to 32768 bytes. The value is specified in bytes, or K and M
#' suffix can be used respectively to specify a value in kilo-bytes or
#' mega-bytes. Will be coerced to string.
#' @param sozip_min_file_size The minimum file size to decide if a file
#' should be seek-optimized, in `sozip_enabled="AUTO"` mode. Defaults to
#' 1 MB byte. The value is specified in bytes, or K, M or G suffix can be used
#' respectively to specify a value in kilo-bytes, mega-bytes or giga-bytes.
#' Will be coerced to string.
#' @param num_threads Number of threads used for SOZip generation. Defaults to
#' `"ALL_CPUS"` or specify an integer value (coerced to string).
#' @param content_type String Content-Type value for the file. This is stored
#' as a key-value pair in the extra field extension 'KV' (0x564b) dedicated to
#' storing key-value pair metadata.
#' @param quiet Logical scalar. `TRUE` for quiet mode, no progress messages
#' emitted. Defaults to `FALSE`.
#' @returns Logical indicating success (invisible \code{TRUE}).
#' An error is raised if the operation fails.
#'
#' @note
#' The `GDAL_NUM_THREADS` configuration option can be set to `ALL_CPUS` or an
#' integer value to specify the number of threads to use for SOZip-compressed
#' files (see [set_config_option()]).
#'
#' SOZip can be validated with:
#' ```
#' vsi_get_file_metadata(zip_file, domain="ZIP")
#' ```
#'
#' where `zip_file` uses the /vsizip/ prefix.
#'
#' @seealso
#' [vsi_get_file_metadata()]
#'
#' @examples
#' f <- system.file("extdata/ynp_fires_1984_2022.gpkg", package = "gdalraster")
#' zip_file <- file.path(tempdir(), "ynp_fires.zip")
#'
#' # Requires GDAL >= 3.7
#' if (gdal_version_num() >= gdal_compute_version(3, 7, 0)) {
#'   addFilesInZip(zip_file, f, full_paths = FALSE, sozip_enabled = "YES",
#'                 num_threads = 1)
#'
#'   print("Files in zip archive:")
#'   print(unzip(zip_file, list = TRUE))
#'
#'   # Open with GDAL using Virtual File System handler '/vsizip/'
#'   # https://gdal.org/en/stable/user/virtual_file_systems.html#vsizip-zip-archives
#'   vsi_f <- file.path("/vsizip", zip_file, "ynp_fires_1984_2022.gpkg")
#'   print("SOZip metadata:")
#'   print(vsi_get_file_metadata(vsi_f, domain = "ZIP"))
#'
#'   lyr <- new(GDALVector, vsi_f)
#'   lyr$info()
#'   lyr$close()
#'   \dontshow{vsi_unlink(zip_file)}
#' }
#' @export
addFilesInZip <- function(
        zip_file,
        add_files,
        overwrite = FALSE,
        full_paths = TRUE,
        sozip_enabled = NULL,
        sozip_chunk_size = NULL,
        sozip_min_file_size = NULL,
        num_threads = NULL,
        content_type = NULL,
        quiet = FALSE) {

    if (gdal_version_num() < gdal_compute_version(3, 7, 0))
        stop("addFilesInZip() requires GDAL >= 3.7", call. = FALSE)

    if (!is.character(zip_file) || length(zip_file) > 1)
        stop("'zip_file' must be a single character string", call. = FALSE)
    else
        zip_file <- .check_gdal_filename(zip_file)

    if (!is.character(add_files))
        stop("'add_files' must be a character vector of filenames",
             call. = FALSE)

    if (!is.null(overwrite)) {
        if (!is.logical(overwrite) || length(overwrite) > 1)
            stop("'overwrite' must be a logical scalar", call. = FALSE)
    } else {
        overwrite <- FALSE
    }

    if (!is.null(full_paths)) {
        if (!is.logical(full_paths) || length(full_paths) > 1)
            stop("'full_paths' must be a logical scalar", call. = FALSE)
    } else {
        full_paths <- FALSE
    }

    if (!is.null(quiet)) {
        if (!is.logical(quiet) || length(quiet) > 1)
            stop("'quiet' must be a logical scalar", call. = FALSE)
    } else {
        quiet <- FALSE
    }

    opt <- NULL
    if (!is.null(sozip_enabled)) {
        if (!is.character(sozip_enabled) || length(sozip_enabled) > 1) {
            stop("'sozip_enabled' must be a single character string",
                 call. = FALSE)
        }
        sozip_enabled <- toupper(sozip_enabled)
        if (!(sozip_enabled %in% c("AUTO", "YES", "NO"))) {
            stop("'sozip_enabled' must be one of \"AUTO\", \"YES\" or \"NO\"",
                 call. = FALSE)
        } else {
            opt <- c(opt, paste0("SOZIP_ENABLED=", sozip_enabled))
        }
    }
    if (!is.null(sozip_chunk_size)) {
        if (length(sozip_chunk_size) > 1)
            stop("'sozip_chunk_size' must be a single value", call. = FALSE)
        opt <- c(opt, paste0("SOZIP_CHUNK_SIZE=", sozip_chunk_size))
    }
    if (!is.null(sozip_min_file_size)) {
        if (length(sozip_min_file_size) > 1)
            stop("'sozip_min_file_size' must be a single value", call. = FALSE)
        opt <- c(opt, paste0("SOZIP_MIN_FILE_SIZE=", sozip_min_file_size))
    }
    if (!is.null(num_threads)) {
        if (length(num_threads) > 1)
            stop("'num_threads' must be a single value", call. = FALSE)
        opt <- c(opt, paste0("NUM_THREADS=", num_threads))
    }
    if (!is.null(content_type)) {
        if (!is.character(content_type) || length(content_type) > 1) {
            stop("'content_type' must be a single character string",
                 call. = FALSE)
        }
        opt <- c(opt, paste0("CONTENT_TYPE=", content_type))
    }

    if (overwrite) {
        if (vsi_stat_exists(zip_file) && vsi_unlink(zip_file) != 0)
            stop("cannot overwrite: ", zip_file, call. = FALSE)
    }

    ret <- FALSE
    for (f in add_files) {
        if (!(vsi_stat_exists(f) && vsi_stat_type(f) == "file"))
            stop("file not found: ", f, call. = FALSE)

        archive_fname <- f
        if (!full_paths || substr(f, 1, 4) == "/vsi") {
            archive_fname <- .cpl_get_filename(f)
        } else if (substr(f, 1, 1) == "/") {
            archive_fname <- substring(f, 2)
        } else if (nchar(f) > 3 && substr(f, 2, 2) == ":" &&
                   (substr(f, 3, 3) == "/" || substr(f, 3, 3) == "\\")) {
            archive_fname <- substring(f, 4)
        }
        archive_fname <- .check_gdal_filename(archive_fname)

        if (!quiet) {
            cli::cli_progress_step(
                "Adding {.val {archive_fname}}",
                msg_failed = "Failed to add {.val {archive_fname}}")
        }

        if (!.addFileInZip(zip_file,
                           overwrite = FALSE,
                           archive_fname,
                           f,
                           opt,
                           quiet = TRUE)) {
            ret <- FALSE
            if (!quiet)
                cli::cli_progress_done("failed")
            break
        } else {
            ret <- TRUE
        }
        if (!quiet)
            cli::cli_progress_done()
    }

    if (!ret)
        stop("failed to add file, error from CPLAddFileInZip()",
             call. = FALSE)

    return(invisible(ret))
}


#' Return the list of creation options for a GDAL driver
#'
#' `getCreationOptions()` returns the list of creation options supported by a
#' GDAL format driver.
#' This function is a wrapper of `GDALGetDriverCreationOptionList()` in the
#' GDAL API, parsing its XML output into a named list.
#'
#' @details
#' The output is a nested list with names matching the creation option names.
#' The information for each creation option is a named list with the following
#' elements:
#' * `type`: a character string describing the data type, e.g., `"int"`,
#' `"float"`, `"string"`. The type `"string-select"` denotes a list of allowed
#' string values which are returned as a character vector in the `values`
#' element (see below).
#' * `description`: a character string describing the option, or `NA` if no
#' description is provided by the GDAL driver.
#' * `default`: the default value of the option as either a character string
#' or numeric value, or `NA` if no description is provided by the GDAL driver.
#' * `values`: a character vector of allowed string values for the creation
#' option if `type` is `"string-select"`, otherwise `NULL` if the option is
#' not a `"string-select"` type.
#' * `min`: (GDAL >= 3.11) the minimum value of the valid range for the
#' option, or `NA` if not provided by the GDAL driver or the option is not a
#' numeric type.
#' * `max`: (GDAL >= 3.11) the maximum value of the valid range for the
#' option, or `NA` if not provided by the GDAL driver or the option is not a
#' numeric type.
#'
#' @param format Format short name (e.g., `"GTiff"`).
#' @param filter Optional character vector of creation option names.
#' @returns A named list with names matching the creation option names, and
#' each element a named list with elements `type`, `description`, `default`
#' and `values` (see Details).
#'
#' @seealso
#' [create()], [createCopy()], [translate()], [validateCreationOptions()],
#' [warp()]
#'
#' @examples
#' opt <- getCreationOptions("GTiff", "COMPRESS")
#' names(opt)
#'
#' (opt$COMPRESS$type == "string-select")  # TRUE
#' opt$COMPRESS$values
#'
#' all_opt <- getCreationOptions("GTiff")
#' names(all_opt)
#'
#' # $description and $default will be NA if no value is provided by the driver
#' # $values will be NULL if the option is not a 'string-select' type
#'
#' all_opt$PREDICTOR
#'
#' all_opt$BIGTIFF
#' @export
getCreationOptions <- function(format, filter = NULL) {

    if (!is.character(format) || length(format) > 1)
        stop("'format' must be a character string", call. = FALSE)

    if (is.null(filter) || filter == "") {
        filter <- "_all_"
    } else {
        filter <- toupper(filter)
    }

    if (.getCreationOptions(format) == "") {
        cli::cli_alert_warning("no creation options found for {.val {format}}")
        return(NULL)
    }

    xml <- xml2::read_xml(.getCreationOptions(format))
    el <- xml2::xml_children(xml)
    out <- list()
    if (length(el) == 0) {
        return(NULL)
    } else {
        for (i in seq_along(el)) {
            a <- xml_attrs(el[[i]])
            if (filter[1] == "_all_" || toupper(a["name"]) %in% filter) {
                type_name <- unname(a["type"])
                str_values <- xml_children(el[[i]]) |> as_list() |> unlist()
                default_val <- unname(a["default"])
                if (toupper(type_name) %in% c("INT", "INTEGER", "UNSIGNED INT",
                                              "FLOAT")) {
                    default_val <- as.numeric(default_val)
                }

                # The XML returned by GDAL < 3.11 does not include the
                # min/max attributes even though they are populated in the
                # driver code that builds the XML string.
                # (https://github.com/OSGeo/gdal/issues/11967)
                if (gdal_version_num() < 3110000) {
                    out[[unname(a["name"])]] <- list(
                        type = type_name,
                        description = unname(a["description"]),
                        default = default_val,
                        values = str_values)
                } else {
                    out[[unname(a["name"])]] <- list(
                        type = type_name,
                        description = unname(a["description"]),
                        default = default_val,
                        values = str_values,
                        min = as.numeric(unname(a["min"])),
                        max = as.numeric(unname(a["max"])))
                }
            }
        }
    }

    return(out)
}


#' Return the list of options associated with a virtual file system handler
#'
#' `vsi_get_fs_options()` returns the list of options associated with a virtual
#' file system handler. Those options may be set as configuration options with
#' `set_config_option()`.
#' Wrapper for `VSIGetFileSystemOptions()` in the GDAL API.
#'
#' @param filename Filename, or prefix of a virtual file system handler.
#' @param as_list Logical scalar. If `TRUE` (the default), the XML string
#' returned by GDAL will be coerced to list. `FALSE` to return the configuration
#' options as a serialized XML string.
#' @returns An XML string, or empty string (`""`) if no options are declared.
#' If `as_list = TRUE` (the default), the XML string will be coerced to list
#' with `xml2::as_list()`.
#'
#' @seealso
#' [set_config_option()], [vsi_get_fs_prefixes()]
#'
#' \url{https://gdal.org/en/stable/user/virtual_file_systems.html}
#'
#' @examples
#' vsi_get_fs_options("/vsimem/")
#'
#' vsi_get_fs_options("/vsizip/")
#'
#' vsi_get_fs_options("/vsizip/", as_list = FALSE)
#' @export
vsi_get_fs_options <- function(filename, as_list = TRUE) {

    if (!is.character(filename) || length(filename) > 1)
        stop("'filename' must be a length-1 character vector.", call.=FALSE)

    opts <- .vsi_get_fs_options(filename)

    if (opts == "")
        return(opts)
    else if (as_list)
        return(xml2::read_xml(opts) |> xml2::as_list())
    else
        return(opts)
}


#' Apply geotransform (raster column/row to geospatial x/y)
#'
#' `apply_geotransform()` applies geotransform coefficients to raster
#' coordinates in pixel/line space (column/row), converting into
#' georeferenced (x/y) coordinates. Wrapper of `GDALApplyGeoTransform()` in
#' the GDAL API, operating on matrix input.
#'
#' @param col_row Numeric matrix of raster column, row (pixel/line) coordinates
#' (or two-column data frame that will be coerced to numeric matrix, or a
#' vector of column, row for one coordinate).
#' @param gt Either a numeric vector of length six containing the affine
#' geotransform for the raster, or an object of class `GDALRaster` from
#' which the geotransform will be obtained.
#' @returns Numeric matrix of geospatial x/y coordinates.
#'
#' @note
#' Bounds checking on the input coordinates is done if `gt` is obtained from an
#' object of class `GDALRaster`. See Note for [get_pixel_line()].
#'
#' @seealso [`GDALRaster$getGeoTransform()`][GDALRaster], [get_pixel_line()]
#'
#' @examples
#' raster_file <- system.file("extdata/storm_lake.lcp", package="gdalraster")
#' ds <- new(GDALRaster, raster_file)
#'
#' # compute some raster coordinates in column/row space
#' set.seed(42)
#' col_coords <- runif(10, min = 0, max = ds$getRasterXSize() - 0.00001)
#' row_coords <- runif(10, min = 0, max = ds$getRasterYSize() - 0.00001)
#' col_row <- cbind(col_coords, row_coords)
#'
#' # convert to geospatial x/y coordinates
#' gt <- ds$getGeoTransform()
#' apply_geotransform(col_row, gt)
#'
#' # or, using the class method
#' ds$apply_geotransform(col_row)
#'
#' # bounds checking
#' col_row <- rbind(col_row, c(ds$getRasterXSize(), ds$getRasterYSize()))
#' ds$apply_geotransform(col_row)
#'
#' ds$close()
#' @export
apply_geotransform <- function(col_row, gt) {
    if (!(is.vector(col_row) || is.matrix(col_row) || is.data.frame(col_row)))
        stop("'col_row' must be a data frame or numeric matrix", call. = FALSE)

    if ((is.matrix(col_row) || is.data.frame(col_row)) && ncol(col_row) != 2)
        stop("'col_row' must have 2 columns", call. = FALSE)
    else if (is.vector(col_row) && length(col_row) != 2)
        stop("'col_row' as vector must have length 2", call. = FALSE)

    # allow for c(NA, NA) which is logical type, NA input should return NA out
    if ((is.vector(xy) || is.matrix(xy)) && !is.numeric(xy) && !is.logical(xy))
        stop("'col_row' must be numeric", call. = FALSE)

    if (is(gt, "Rcpp_GDALRaster")) {
        return(.apply_geotransform_ds(col_row, gt))
    } else if (is.numeric(gt) && length(gt) == 6) {
        return(.apply_geotransform_gt(col_row, gt))
    } else {
        stop("'gt' must be a numeric vector of length 6, or GDALRaster object",
             call. = FALSE)
    }
}


#' Raster pixel/line from geospatial x,y coordinates
#'
#' `get_pixel_line()` converts geospatial coordinates to pixel/line (raster
#' column, row numbers).
#' The upper left corner pixel is the raster origin (0,0) with column, row
#' increasing left to right, top to bottom.
#'
#' @param xy Numeric matrix of geospatial x, y coordinates in the same spatial
#' reference system as \code{gt} (or two-column data frame that will be coerced
#' to numeric matrix, or a vector x, y for one coordinate).
#' @param gt Either a numeric vector of length six containing the affine
#' geotransform for the raster, or an object of class `GDALRaster` from
#' which the geotransform will be obtained (see Note).
#' @returns Integer matrix of raster pixel/line.
#'
#' @note
#' This function applies the inverse geotransform to the input points. If `gt`
#' is given as the numeric vector, no bounds checking is done (i.e., min
#' pixel/line could be less than zero and max pixel/line could be greater than
#' the raster x/y size). If `gt` is obtained from an object of class
#' `GDALRaster`, then `NA` is returned for points that fall outside the
#' raster extent and a warning emitted giving the number points that were
#' outside. This latter case is equivalent to calling the
#' \code{$get_pixel_line()} class method on the `GDALRaster` object (see
#' Examples). Points exactly on the raster right or bottom edge are considered
#' inside as of \pkg{gdalraster} 2.7.0.
#'
#' @seealso [`GDALRaster$getGeoTransform()`][GDALRaster], [inv_geotransform()]
#'
#' @examples
#' pt_file <- system.file("extdata/storml_pts.csv", package="gdalraster")
#' # id, x, y in NAD83 / UTM zone 12N
#' pts <- read.csv(pt_file)
#' print(pts)
#'
#' raster_file <- system.file("extdata/storm_lake.lcp", package="gdalraster")
#' ds <- new(GDALRaster, raster_file)
#' gt <- ds$getGeoTransform()
#' get_pixel_line(pts[, -1], gt)
#'
#' # or, using the class method
#' ds$get_pixel_line(pts[, -1])
#'
#' # add a point outside the raster extent
#' pts[11, ] <- c(11, 323318, 5105104)
#' get_pixel_line(pts[, -1], gt)
#'
#' # with bounds checking on the raster extent
#' ds$get_pixel_line(pts[, -1])
#'
#' ds$close()
#' @export
get_pixel_line <- function(xy, gt) {
    if (!(is.vector(xy) || is.matrix(xy) || is.data.frame(xy)))
        stop("'xy' must be a data frame or numeric matrix", call. = FALSE)

    if ((is.matrix(xy) || is.data.frame(xy)) && ncol(xy) != 2)
        stop("'xy' must have 2 columns", call. = FALSE)
    else if (is.vector(xy) && length(xy) != 2)
        stop("'xy' as vector must have length 2", call. = FALSE)

    # allow for c(NA, NA) which is logical type, NA input should return NA out
    if ((is.vector(xy) || is.matrix(xy)) && !is.numeric(xy) && !is.logical(xy))
        stop("'xy' must be numeric", call. = FALSE)

    if (is(gt, "Rcpp_GDALRaster")) {
        return(.get_pixel_line_ds(xy, gt))
    } else if (is.numeric(gt) && length(gt) == 6) {
        return(.get_pixel_line_gt(xy, gt))
    } else {
        stop("'gt' must be a numeric vector of length 6, or GDALRaster object",
             call. = FALSE)
    }
}


#' Report open datasets
#'
#' `dump_open_datasets()` dumps a list of all open datasets (shared or not) to
#' the console. This function is primarily intended to assist in debugging
#' "dataset leaks" and reference counting issues. The information reported
#' includes the dataset name, referenced count, shared status, driver name,
#' size, and band count. This a wrapper for `GDALDumpOpenDatasets()` with
#' output to the console.
#'
#' @returns Number of open datasets.
#'
#' @examples
#' elev_file <- system.file("extdata/storml_elev.tif", package="gdalraster")
#' ds <- new(GDALRaster, elev_file)
#' dump_open_datasets()
#' ds2 <- new(GDALRaster, elev_file)
#' dump_open_datasets()
#' # open without using shared mode
#' ds3 <- new(GDALRaster, elev_file, read_only = TRUE,
#'            open_options = NULL, shared = FALSE)
#' dump_open_datasets()
#' ds$close()
#' dump_open_datasets()
#' ds2$close()
#' dump_open_datasets()
#' ds3$close()
#' dump_open_datasets()
#' @export
dump_open_datasets <- function() {
    f <- tempfile(fileext = ".txt")
    nopen <- .dump_open_datasets(f)
    if (nopen < 0)
        stop("failed to obtain the list of open datasets", call. = FALSE)

    out <- readLines(f)
    unlink(f)
    writeLines(out)
    return(nopen)
}


#' Obtain information about a GDAL raster or vector dataset
#'
#' `inspectDataset()` returns information about the format and content
#' of a dataset. The function first calls `identifyDriver()`, and then opens
#' the dataset as raster and/or vector to obtain information about its content.
#' The return value is a list with named elements.
#'
#' @param filename Character string containing the name of the file to access.
#' This may not refer to a physical file, but instead contain information for
#' the driver on how to access a dataset (e.g., connection string, URL, etc.)
#' @param ... Additional arguments passed to `identifyDriver()`.
#'
#' @returns
#' A list with the following named elements:
#' * `format`: character string, the format short name
#' * `supports_raster`: logical, `TRUE` if the format supports raster data
#' * `contains_raster`: logical, `TRUE` if this is a raster dataset or the
#' source contains raster subdatasets
#' * `supports_subdatasets`: logical, `TRUE` if the format supports raster
#' subdatasets
#' * `contains_subdatasets`: logical, `TRUE` if the source contains subdatasets
#' * `subdataset_names`: character vector containing the subdataset names, or
#' empty vector if subdatasets are not supported or not present
#' * `supports_vector`: logical, `TRUE` if the format supports vector data
#' * `contains_vector`: logical, `TRUE` if the source contains one or more
#' vector layers
#' * `layer_names`: character vector containing the vector layer names, or
#' empty vector if the format does not support vector or the source does not
#' contain any vector layers
#'
#'@note
#' Subdataset names are the character strings that can be used to
#' instantiate `GDALRaster` objects.
#' See https://gdal.org/en/stable/en/latest/user/raster_data_model.html#subdatasets-domain.
#'
#' PostgreSQL / PostGISRaster are handled as a special case. If additional
#' arguments `raster` or `vector` are not given for `identifyDriver()`, then
#' `raster = FALSE` is assumed.
#'
#' @seealso
#' [gdal_formats()], [identifyDriver()]
#'
#' @examples
#' f <- system.file("extdata/ynp_features.zip", package = "gdalraster")
#' ynp_dsn <- file.path("/vsizip", f, "ynp_features.gpkg")
#'
#' inspectDataset(ynp_dsn)
#' @export
inspectDataset <- function(filename, ...) {
    if (!is.character(filename))
        stop("'filename' must be a character string", call. = FALSE)

    filename_in <- .check_gdal_filename(filename)
    fmt <- identifyDriver(filename = filename_in, ...)
    if (is.null(fmt)) {
        warning("failed to identify a format driver", call. = FALSE)
        return(NULL)
    }

    if (!hasArg("raster") && !hasArg("vector")) {
        # check for possibly two different drivers
        fmt_rast <- identifyDriver(filename = filename_in, vector = FALSE, ...)
        fmt_vect <- identifyDriver(filename = filename_in, raster = FALSE, ...)
        if (!is.null(fmt_rast) && !is.null(fmt_vect)) {
            if (fmt_rast != fmt_vect) {
                if (fmt_vect == "PostgreSQL") {
                    # for PostGISRaster / PostgreSQL, assume vector is intended
                    fmt <- fmt_vect
                } else {
                    message("identified separate raster and vector drivers: ",
                            fmt_rast, ", ", fmt_vect)
                    stop("need additional arguments for `identifyDriver()`",
                         call. = FALSE)
                }
            }
        }
    }

    out <- list()
    out$format <- fmt
    fmt_info <- gdal_formats(fmt)
    if (nrow(fmt_info) == 0) {
        stop("failed to obtain format information", call. = FALSE)
    }

    out$supports_raster <- fmt_info$raster
    out$contains_raster <- FALSE
    if (out$supports_raster) {
        push_error_handler("quiet")
        ds <- try(new(GDALRaster, filename_in), silent = TRUE)
        pop_error_handler()
        if (is(ds, "Rcpp_GDALRaster"))
            out$contains_raster <- TRUE
    }

    out$supports_subdatasets <- fmt_info$subdatasets
    out$contains_subdatasets <- FALSE
    out$subdataset_names <- character(0)
    if (out$contains_raster) {
        md <- ds$getMetadata(band = 0, domain = "SUBDATASETS")
        if (length(md) > 1) {
            out$contains_subdatasets <- TRUE
            Encoding(md) <- "UTF-8"
            for (i in seq_along(md)) {
                mdi <- strsplit(md[i], "=", fixed = TRUE)
                if (grepl("_NAME", mdi[[1]][1], ignore.case = TRUE)) {
                    out$subdataset_names <- c(out$subdataset_names, mdi[[1]][2])
                }
            }
        }
    }

    if (out$supports_raster && is(ds, "Rcpp_GDALRaster")) {
        ds$close()
    }

    out$supports_vector <- fmt_info$vector
    out$contains_vector <- FALSE
    out$layer_names <- character(0)
    if (out$supports_vector) {
        if (ogr_ds_layer_count(filename_in) > 0) {
            out$contains_vector <- TRUE
            out$layer_names <- ogr_ds_layer_names(filename_in)
        }
    }

    return(out)
}


#' Generate an index of chunk offsets and sizes for iterating a raster
#'
#' `make_chunk_index()` returns a matrix of `xchunkoff`, `ychunkoff`, `xoff`,
#' `yoff`, `xsize`, `ysize`, `xmin`, `xmax`, `ymin` and `ymax`, i.e., indexing
#' of potentially multi-block chunks defined on block boundaries for iterating
#' I/O operations over a raster. The last four columns are geospatial
#' coordinates of the bounding box. Note that class `GDALRaster` provides a
#' method of the same name that is more convenient to use with a dataset object.
#'
#' @details
#' The stand-alone function here supports the general case of chunking/tiling a
#' raster layout without using a dataset object. If the `max_pixels` argument
#' is set to zero, the chunks are raster blocks (the internal tiles in the case
#' of a tiled format). Otherwise, chunks are defined as the maximum number of
#' consecutive whole blocks containing `<= max_pixels`, that may span one or
#' multiple whole rows of blocks.
#'
#' @param raster_xsize Integer value giving the number of raster columns.
#' @param raster_ysize Integer value giving the number of raster rows.
#' @param block_xsize Integer value giving the horizontal size of a raster block
#' in number of pixels.
#' @param block_ysize Integer value giving the vertical size of a raster block
#' in number of pixels.
#' @param gt A numeric vector of length six containing the affine geotransform
#' for the raster (defaults to `c(0, 1, 0, 0, 0, 1)`). Required only if
#' geospatial bounding boxes of the chunks are needed in the output.
#' @param max_pixels Numeric value (a whole number), optionally carrying the
#' `bit64::integer64` class attribute. Specifies the maximum number of pixels
#' per chunk. Can be set to zero to define chunks as the blocks.
#' @return A numeric matrix with number of rows equal to the number of chunks,
#' and named columns: `xchunkoff`, `ychunkoff`, `xoff`, `yoff`, `xsize`,
#' `ysize`, `xmin`, `xmax`, `ymin`, `ymax`. Offsets are 0-based.
#'
#' @seealso
#' Methods \code{make_chunk_index()}, \code{readChunk()} and
#' \code{writeChunk()} in class [GDALRaster].
#'
#' Usage example in the web article
#' [GDAL Block Cache](https://firelab.github.io/gdalraster/articles/gdal-block-cache.html).
#'
#' @examples
#' ## chunk as one block
#' blocks <- make_chunk_index(raster_xsize = 156335, raster_ysize = 101538,
#'                            block_xsize = 256, block_ysize = 256,
#'                            gt = c(-2362395, 30, 0, 3267405, 0, -30),
#'                            max_pixels = 0)
#'
#' nrow(blocks)
#'
#' head(blocks)
#'
#' tail(blocks)
#'
#' ## chunk as 16 consecutive blocks
#' chunks <- make_chunk_index(raster_xsize = 156335, raster_ysize = 101538,
#'                            block_xsize = 256, block_ysize = 256,
#'                            gt = c(-2362395, 30, 0, 3267405, 0, -30),
#'                            max_pixels = 256 * 256 * 16)
#'
#' nrow(chunks)
#'
#' head(chunks)
#'
#' tail(chunks)
#' @export
make_chunk_index <- function(raster_xsize, raster_ysize,
                             block_xsize, block_ysize,
                             gt = c(0, 1, 0, 0, 0, 1),
                             max_pixels = 0) {

    return(.make_chunk_index(raster_xsize, raster_ysize, block_xsize,
                             block_ysize, gt, max_pixels))
}


#' Create a GDAL in-memory dataset from R data without copying
#'
#' `rvector_to_MEM()` creates a GDAL MEM dataset that references pixel data in
#' an existing R vector. It returns an object of class `GDALRaster` for a
#' writable in-memory dataset without copying the source data. The underlying
#' R object is protected from garbage collection until the returned dataset is
#' closed. GDAL MEM datasets support most kinds of auxiliary information
#' including metadata, coordinate systems, georeferencing, color interpretation,
#' nodata, color tables and all pixel data types (see Details).
#'
#' @details
#' The returned dataset is open with write access. Methods of the `GDALRaster`
#' object can be called to modify dataset and band properties, e.g., to set
#' nodata values, metadata items, band descriptions, color tables, etc. The
#' original R vector will be modified in place if the object's `$write()`
#' method is used.
#'
#' The MEM dataset will have a GDAL data type matching the type of the
#' input vector:
#' \tabular{rl}{
#' **R vector type**  \tab  **GDAL raster type**\cr
#' double             \tab  Float64\cr
#' integer            \tab  Int32\cr
#' raw                \tab  UInt8 (Byte in GDAL < 3.13)\cr
#' complex            \tab  CFloat64
#' }
#'
#' `vector_to_MEM()` is an alias of `rvector_to_MEM()` for backward
#' compatibility. It is a deprecated name of the function that will be removed
#' in a future version. Please use `rvector_to_MEM()` instead.
#'
#' @param data An R vector of type `"double"`, `"integer"`, `"raw"` or
#' `"complex"`, containing pixel values to be exposed as a GDAL in-memory
#' raster. The pixels must be arranged in left-to-right, top-to-bottom order
#' interleaved by band. `length(data)` must equal `xsize * ysize * nbands`.
#' @param xsize Integer value giving the number of raster columns.
#' @param ysize Integer value giving the number of raster rows.
#' @param nbands Integer value giving the number of raster bands.
#' @param gt A numeric vector of length six containing the affine geotransform
#' for the raster. Defaults to `c(0, 1, 0, 0, 0, 1)` if neither `gt` nor `bbox`
#' are given.
#' @param bbox A numeric vector of length four containing the raster bounding
#' box geospatial coordinates (`c(xmin, ymin, xmax, ymax)`). Ignored if `gt` is
#' given.
#' @param srs Optional character string containing the raster spatial reference
#' coordinate system as a WKT string. [epsg_to_wkt()] or [srs_to_wkt()] can be
#' used to convert from other formats to WKT if necessary.
#' @return An object of class `GDALRaster` providing a GDAL MEM dataset with
#' write access pointing to the underlying C array for `data`. The R object
#' referenced by `data` is protected from garbage collection during the lifetime
#' of the returned dataset, i.e., until its `$close()` is called or the dataset
#' object itself is garbage collected. An error is raised if creation of the
#' MEM dataset fails.
#'
#' @note
#' MEM datasets also support `addBand()` from existing R data without copying
#' (see Examples).
#'
#' The `$close()` method should be called when the `GDALRaster` object is no
#' longer needed so that resources can be freed. MEM datasets cannot be
#' re-opened once the object's `$close()` method has been called.
#'
#' `vector_to_MEM()` is a deprecated name for the function, currently set as
#' an alias of `rvector_to_MEM()`. _The `vector_to_MEM()` alias will be removed
#' in a future version_.
#'
#' @seealso
#' [`GDALRaster-class`][GDALRaster]
#'
#' @examples
#' v <- sample(0:255, 20, replace = TRUE)
#' (ds_mem <- rvector_to_MEM(v, xsize = 5, ysize = 4))
#'
#' all((ds_mem$read(1, 0, 0, 5, 4, 5, 4) == v))
#'
#' ds_mem$write(1, 0, 0, 5, 4, (v * -1))
#' print(v)
#'
#' ds_mem$close()
#'
#' # MEM also supports no-copy addBand() from R data
#' xsize <- 400
#' ysize <- 300
#' r <- sample(0:255, xsize * ysize, replace = TRUE) |> as.raw()
#' ds_mem <- rvector_to_MEM(r, xsize, ysize)
#' ds_mem$setRasterColorInterp(1, "Red")
#'
#' g <- sample(0:255, xsize * ysize, replace = TRUE) |> as.raw()
#' ds_mem$addBand("Byte", g)
#' ds_mem$setRasterColorInterp(2, "Green")
#'
#' b <- sample(0:255, xsize * ysize, replace = TRUE) |> as.raw()
#' ds_mem$addBand("Byte", b)
#' ds_mem$setRasterColorInterp(3, "Blue")
#'
#' ds_mem$info()
#'
#' plot_raster(ds_mem, main = "random RGB")
#' ds_mem$close()
#' @export
#' @rdname rvector_to_MEM
rvector_to_MEM <- function(data, xsize, ysize, nbands = 1L, gt = NULL,
                           bbox = NULL, srs = NULL) {

    if (!is.vector(data) && !is.numeric(data) && !is.raw(data) &&
        !is.complex(data)) {

        stop("'data' must be a vector of raw, integer, double or complex",
             call. = FALSE)
    }

    if (!(is.numeric(xsize) && length(xsize) == 1))
        stop("'xsize' must be a single integer value", call. = FALSE)

    if (!(is.numeric(ysize) && length(ysize) == 1))
        stop("'ysize' must be a single integer value", call. = FALSE)

    if (!(is.numeric(nbands) && length(nbands) == 1))
        stop("'nbands' must be a single integer value", call. = FALSE)

    if (length(data) != as.double(xsize) * ysize * nbands) {
        stop("length of 'data' must equal 'xsize' * 'ysize' * 'nbands'",
             call. = FALSE)
    }

    if (!is.null(gt)) {
        if (!(is.numeric(gt) && length(gt) == 6))
            stop("'gt' must be a numeric vector of length 6", call. = FALSE)
    }

    if (!is.null(bbox)) {
        if (!is.null(gt))
            message("NOTE: 'bbox' ignored since 'gt' was given")
        else if (!(is.numeric(bbox) && length(bbox) == 4))
            stop("'bbox' must be a numeric vector of length 4", call. = FALSE)
    }

    if (is.null(gt)) {
        if (!is.null(bbox))
            gt <- gt_from_dim_bbox(c(xsize, ysize), bbox)
        else
            gt <- c(0, 1, 0, 0, 0, 1)
    }

    if (!is.null(srs)) {
        if (!(is.character(srs) && length(srs) == 1))
            stop("'srs' must be a single character string", call. = FALSE)
    }

    dt <- "Unknown"
    if (is.double(data)) {
        dt <- "Float64"
    } else if (is.integer(data)) {
        dt <- "Int32"
    } else if (is.raw(data)) {
        if (gdal_version_num() < gdal_compute_version(3, 13, 0))
            dt <- "Byte"
        else
            dt <- "UInt8"
    } else if (is.complex(data)) {
        dt <- "CFloat64"
    } else {
        stop("failed to determine a raster data type for 'data'", call. = FALSE)
    }

    gt_str <- paste(gt, collapse = "/")
    band_offset <- as.double(xsize) * ysize * dt_size(dt)
    ptr <- get_data_ptr(data)

    dsn_fmt <- "MEM:::DATAPOINTER=%s,PIXELS=%d,LINES=%d,BANDS=%d,DATATYPE=%s,GEOTRANSFORM=%s,BANDOFFSET=%d"
    dsn <- sprintf(dsn_fmt, ptr, xsize, ysize, nbands, dt, gt_str, band_offset)

    orig_opt <- ""
    reset_opt <- FALSE
    if (gdal_version_num() >= gdal_compute_version(3, 10, 0)) {
        reset_opt <- TRUE
        orig_opt <- get_config_option("GDAL_MEM_ENABLE_OPEN")
        set_config_option("GDAL_MEM_ENABLE_OPEN", "YES")
    }

    ds_mem <- new(GDALRaster, dsn, FALSE)

    if (!ds_mem$preserveRObject_(data)) {
        ds_mem$close()
        stop("failed to preserve the R object", call. = FALSE)
    }

    if (!is.null(srs)) {
        if (!ds_mem$setProjection(srs)) {
            warning("failed to set projection on the MEM dataset",
                    call. = FALSE)
        }
    }

    if (reset_opt)
        set_config_option("GDAL_MEM_ENABLE_OPEN", orig_opt)

    return(ds_mem)
}

#' @export
#' @rdname rvector_to_MEM
vector_to_MEM <- rvector_to_MEM

#' Clear progress bar
#'
#' `progress_bar_clear()` terminates any active \pkg{cli} progress bars and
#' resets the global progress bar in C++. Generally not needed unless a process
#' using a progress bar terminates abnormally, or with ctrl-c interrupt, and
#' a progress bar display anomaly results.
#'
#' @return
#' No return value, call for side effects.
progress_bar_clear <- function() {
    cli::cli_progress_cleanup()
    cli::cli_progress_message("")
    .progress_bar_cleanup()
    cli::cat_line()
}
