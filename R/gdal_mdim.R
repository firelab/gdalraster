# GDAL Multidimensional Raster functions
# public interface to src/gdal_mdim.cpp
# Chris Toney <jctoney at gmail.com>

#' Return a view of an MDArray as a "classic" GDALDataset (i.e., 2D)
#'
#' `mdim_as_classic()` returns a 2D raster view on an MDArray in a GDAL
#' Multidimensional Raster dataset, as an object of class `GDALRaster`. Only 2D
#' or more arrays are supported. In the case of > 2D arrays, additional
#' dimensions will be represented as raster bands. Requires GDAL >= 3.2.
#'
#' @param dsn Character string giving the data source name of the
#' multidimensional raster (e.g., file, VSI path).
#' @param array_name Character string giving the name of the MDarray in
#' `dsn`.
#' @param idx_xdim Integer value giving the index of the dimension that will be
#' used as the X/width axis (0-based).
#' @param idx_ydim Integer value giving the index of the dimension that will be
#' used as the Y/height axis (0-based).
#' @param read_only Logical value, `TRUE` to open the dataset in read-only mode
#' (the default).
#' @param group_name Optional character string giving the fully qualified name
#' of a group containing `array_name`.
#' @param view_expr Optional character string giving an expression for basic
#' array slicing and indexing, or field access (see section `View Expressions`).
#' @param allowed_drivers Optional character vector of driver short names that
#' must be considered. By default, all known multidimensional raster drivers are
#' considered.
#' @param open_options Optional character vector of format-specific dataset open
#' options as `"NAME=VALUE"` pairs.
#' @returns An object of class `GDALRaster`.
#'
#' @section View Expressions:
#' A character string can be passed in argument `view_expr` to specify array
#' slicing or field access. The slice expression uses the same syntax as NumPy
#' basic slicing and indexing (0-based), or it can use field access by name.
#' See \url{https://numpy.org/doc/stable/user/basics.indexing.html}.
#'
#' GDAL support for view expression on an MDArray is documented for
#' `GDALMDArray::GetView()` (see
#' \url{https://gdal.org/en/stable/api/gdalmdarray_cpp.html}) and copied here:
#'
#' Multiple [] bracket elements can be concatenated, with a slice expression or
#' field name inside each.
#'
#' For basic slicing and indexing, inside each [] bracket element, a list of
#' indexes that apply to successive source dimensions, can be specified, using
#' integer indexing (e.g. 1), range indexing (start:stop:step), ellipsis (...)
#' or newaxis, using a comma separator.
#'
#' Example expressions with a 2-dimensional array whose content is
#' `[[0,1,2,3],[4,5,6,7]]`.
#' * `"[1][2]"`: returns a 0-dimensional/scalar array with the value at
#' index 1 in the first dimension, and index 2 in the second dimension from the
#' source array. That is, `5`.
#' * `"[1,2]"`: same as above, but a bit more performant.
#' * `"[1]"`: returns a 1-dimensional array, sliced at index `1` in the
#' first dimension. That is `[4,5,6,7]`.
#' * `"[:,2]"`: returns a 1-dimensional array, sliced at index `2` in the
#' second dimension. That is `[2,6]`.
#' * `"[:,2:3:]"`: returns a 2-dimensional array, sliced at index `2` in
#' the second dimension. That is `[[2],[6]]`.
#' * `"[::,2]"`: Same as above.
#' * `"[...,2]"`: same as above, in that case, since the ellipsis only
#' expands to one dimension here.
#' * `"[:,::2]"`: returns a 2-dimensional array, with even-indexed
#' elements of the second dimension. That is `[[0,2],[4,6]]`.
#' * `"[:,1::2]"`: returns a 2-dimensional array, with odd-indexed
#' elements of the second dimension. That is `[[1,3],[5,7]]`.
#' * `"[:,1:3:]"`: returns a 2-dimensional array, with elements of the
#' second dimension with index in the range `[1,3]`. That is `[[1,2],[5,6]]`.
#' * `"[::-1,:]"`: returns a 2-dimensional array, with the values in
#' first dimension reversed. That is `[[4,5,6,7],[0,1,2,3]]`.
#' * `"[newaxis,...]"`: returns a 3-dimensional array, with an additional
#' dimension of size `1` put at the beginning. That is
#' `[[[0,1,2,3],[4,5,6,7]]]`.
#'
#' One difference with NumPy behavior is that ranges that would result in zero
#' elements are not allowed (dimensions of size 0 not being allowed in the GDAL
#' multidimensional model).
#'
#' For field access, the syntax to use is `"['field_name']"`. Multiple field
#' specification is not supported currently. Both type of access can be
#' combined, e.g. `"[1]['field_name']"`.
#'
#' @note
#' The indexing of array dimensions is 0-based consistent with the
#' `<ARRAY-SPEC>` notation that may be used with GDAL CLI commands, e.g.,
#' `gdal_usage("mdim convert")` (CLI bindings require GDAL > 3.11.3).
#' See \url{https://gdal.org/en/stable/programs/gdal_mdim_convert.html}.
#'
#' Once the returned `GDALRaster` object has been closed, it cannot be re-opened
#' with its `$open()` method.
#'
#' @seealso
#' [`GDALRaster-class`][GDALRaster], [mdim_info()], [mdim_translate()]
#'
#' @examplesIf gdal_version_num() >= gdal_compute_version(3, 2, 0) && isTRUE(gdal_formats("netCDF")$multidim_raster)
#' f <- system.file("extdata/byte.nc", package="gdalraster")
#' # mdim_info(f)
#'
#' (ds <- mdim_as_classic(f, "Band1", 1, 0))
#'
#' plot_raster(ds, interpolate = FALSE, legend = TRUE, main = "Band1")
#'
#' ds$close()
#' @export
mdim_as_classic <- function(dsn, array_name, idx_xdim, idx_ydim,
                            read_only = TRUE, group_name = NULL,
                            view_expr = NULL, allowed_drivers = NULL,
                            open_options = NULL) {

    if (missing(dsn) || is.null(dsn) || all(is.na(dsn)))
        stop("'dsn' is required", call. = FALSE)
    if (!(is.character(dsn) && length(dsn) == 1))
        stop("'dsn' must be a character string", call. = FALSE)

    if (missing(array_name) || is.null(array_name) || all(is.na(array_name)))
        stop("'array_name' is required", call. = FALSE)
    if (!(is.character(array_name) && length(array_name) == 1))
        stop("'array_name' must be a character string", call. = FALSE)

    if (missing(idx_xdim) || is.null(idx_xdim) || all(is.na(idx_xdim)))
        stop("'idx_xdim' is required", call. = FALSE)
    if (!(is.numeric(idx_xdim) && length(idx_xdim) == 1))
        stop("'idx_xdim' must be a numeric value (integer)", call. = FALSE)

    if (missing(idx_ydim) || is.null(idx_ydim) || all(is.na(idx_ydim)))
        stop("'idx_ydim' is required", call. = FALSE)
    if (!(is.numeric(idx_ydim) && length(idx_ydim) == 1))
        stop("'idx_ydim' must be a numeric value (integer)", call. = FALSE)

    if (missing(read_only) || is.null(read_only) || all(is.na(read_only)))
        read_only <- TRUE
    if (!(is.logical(read_only) && length(read_only) == 1))
        stop("'read_only' must be a logical value", call. = FALSE)

    if (missing(group_name) || is.null(group_name) || all(is.na(group_name)))
        group_name <- ""
    if (!(is.character(group_name) && length(group_name) == 1))
        stop("'group_name' must be a character string", call. = FALSE)

    if (missing(view_expr) || is.null(view_expr) || all(is.na(view_expr)))
        view_expr <- ""
    if (!(is.character(view_expr) && length(view_expr) == 1))
        stop("'view_expr' must be a character string", call. = FALSE)

    if (missing(allowed_drivers) || all(is.na(allowed_drivers)))
        allowed_drivers <- NULL
    if (!is.null(allowed_drivers)) {
        if (!is.character(allowed_drivers))
            stop("'allowed_drivers' must be a character vector", call. = FALSE)
    }

    if (missing(open_options) || all(is.na(open_options)))
        open_options <- NULL
    if (!is.null(open_options)) {
        if (!is.character(open_options))
            stop("'open_options' must be a character vector", call. = FALSE)
    }

    # signature for mdim_as_classic() object factory
    ds <- new(GDALRaster, dsn, array_name, idx_xdim, idx_ydim, read_only,
              group_name, view_expr, allowed_drivers, open_options)

    return(ds);
}

#' Read an MDArray from a multidimensional raster, with dimension information
#'
#' `mdim_read()` reads all or part of an array in a GDAL Multidimensional
#' Raster dataset, and returns a vector with an attribute `"gis"` describing
#' the dimensions and coordinates of the values read. It is the
#' multidimensional counterpart of [read_ds()], and uses
#' [`GDALMDArray$read()`][GDALMDArray]. Requires GDAL >= 3.2.
#' **This function is experimental**. Its interface may change in future
#' releases.
#'
#' @details
#' Values are returned as stored, in the same order as returned by
#' [`GDALMDArray$read()`][GDALMDArray]: the last dimension of the array varies
#' fastest. Scale and offset are not applied (the unscaled value is
#' `value * gis$scale + gis$offset`), and the nodata value is returned as `NA`.
#'
#' The `"gis"` attribute is a list with elements:
#' * `type`: `"multidim"`
#' * `dim`: the number of values read along each dimension, fastest varying
#' first, i.e., the reverse of the array's dimension order (the same
#' convention as `c(xsize, ysize, nbands)` in the `"gis"` attribute from
#' [read_ds()])
#' * `dim_names`: the dimension names, in the same order as `dim`
#' * `coords`: a named list, in the same order as `dim`, with the coordinate
#' values of each dimension for the values read, or `NULL` for a dimension
#' without an indexing variable
#' * `bbox`: `c(xmin, ymin, xmax, ymax)` from the coordinates of the
#' horizontal dimensions (cell edges, assuming regular spacing), or `NA`
#' values if they cannot be determined
#' * `srs`: the spatial reference system as WKT, or `""`
#' * `datatype`: the data type name (e.g., `"Int16"`)
#' * `nodata`, `scale`, `offset`: numeric values, `NA` if not set
#' * `unit`: the unit of the array values, or `""`
#' * `dim_units`: the units of the dimension coordinates, in the same order as
#' `dim` (e.g., `"degrees_east"`, `"hours since 1900-01-01"`), `""` if not set
#' * `calendar`: the `calendar` attribute of the time coordinate if present
#' (e.g., `"standard"`, `"noleap"`), otherwise `NA`.
#'
#' Units and calendars are returned as stored, as character strings.
#'
#' The horizontal dimensions are those with type `HORIZONTAL_X` and
#' `HORIZONTAL_Y`, or otherwise the last and second last dimensions of the
#' array.
#'
#' @param x Either an object of class [`GDALMultiDimRaster`][GDALMultiDimRaster],
#' or a character string giving the data source name of a multidimensional
#' raster (which is opened read-only and closed on return).
#' @param array_name Character string giving the full path of the array in
#' the dataset, e.g., `"/temperature"` or `"/group/temperature"`.
#' @param start Optional numeric vector of 0-based start indexes, one value per
#' dimension of the array, in the array's own dimension order. Defaults to `0`
#' for each dimension.
#' @param count Optional numeric vector of the number of values to read along
#' each dimension. Defaults to the rest of each dimension after `start`
#' (taking `step` into account).
#' @param step Optional numeric vector of the step between indexes along each
#' dimension. Defaults to `1` for each dimension.
#' @param as_array Logical value. If `TRUE`, also set the `dim` attribute of
#' the returned vector to `gis$dim`, so that it can be used as an \R array
#' indexed as `[x, y, ...]`. Defaults to `FALSE`.
#' @param as_raw Logical value. If `TRUE` and the array data type is Byte,
#' return values as \R `raw`. Defaults to `FALSE`.
#' @returns A vector of values, with attribute `"gis"` (and `dim` if
#' `as_array = TRUE`). See Details.
#'
#' @seealso
#' [GDALMultiDimRaster], [GDALMDArray], [read_ds()]
#'
#' @examplesIf gdal_version_num() >= gdal_compute_version(3, 2, 0) && isTRUE(gdal_formats("netCDF")$multidim_raster)
#' f <- system.file("extdata/mdim_small.nc", package="gdalraster")
#'
#' v <- mdim_read(f, "/t2m")
#' str(attr(v, "gis"))
#'
#' # the first time step as an R matrix [lon, lat], in degC
#' ds <- new(GDALMultiDimRaster, f)
#' v <- mdim_read(ds, "/t2m", start = c(0, 0, 0), count = c(1, 5, 6),
#'                as_array = TRUE)
#' gis <- attr(v, "gis")
#' gis$dim
#' gis$coords
#' v[, , 1] * gis$scale + gis$offset
#' ds$close()
#' @export
mdim_read <- function(x, array_name, start = NULL, count = NULL, step = NULL,
                      as_array = FALSE, as_raw = FALSE) {

    if (is.character(x) && length(x) == 1) {
        ds <- new(GDALMultiDimRaster, x)
        on.exit(ds$close(), add = TRUE)
    } else if (is(x, "Rcpp_GDALMultiDimRaster")) {
        ds <- x
    } else {
        stop("'x' must be a GDALMultiDimRaster object or a character string",
             call. = FALSE)
    }

    if (missing(array_name) || !is.character(array_name) ||
            length(array_name) != 1) {
        stop("'array_name' must be a character string", call. = FALSE)
    }

    arr <- ds$openMDArray(array_name)
    on.exit(arr$close(), add = TRUE)
    arr$readByteAsRaw <- isTRUE(as_raw)

    dims <- arr$getDimensions()
    ndim <- nrow(dims)

    if (is.null(start))
        start <- rep(0, ndim)
    if (is.null(step))
        step <- rep(1, ndim)
    if (length(start) != ndim || length(step) != ndim) {
        stop("'start' and 'step' must have one value per dimension (",
             ndim, ")", call. = FALSE)
    }
    if (is.null(count)) {
        count <- ifelse(step > 0,
                        ceiling((dims$size - start) / step),
                        floor(start / abs(step)) + 1)
    }
    if (length(count) != ndim) {
        stop("'count' must have one value per dimension (", ndim, ")",
             call. = FALSE)
    }

    if (ndim == 0)
        v <- arr$read(NULL, NULL, NULL)
    else
        v <- arr$read(start, count, step)

    # coordinates, units and calendar of each dimension, in array order
    coords <- vector("list", ndim)
    dim_units <- rep("", ndim)
    calendar <- NA_character_
    for (i in seq_len(ndim)) {
        var_name <- dims$indexing_variable[i]
        if (is.na(var_name) || var_name == "")
            next
        var <- tryCatch(ds$openMDArray(var_name), error = function(e) NULL)
        if (is.null(var))
            next
        if (var$getDimensionCount() == 1) {
            coords[i] <- list(var$read(start[i], count[i], step[i]))
        }
        dim_units[i] <- var$getUnit()
        cal <- var$getAttributes()$calendar
        if (is.na(calendar) && is.character(cal) && length(cal) == 1)
            calendar <- cal
        var$close()
    }
    names(coords) <- dims$name

    # bbox from the coordinates of the horizontal dimensions
    bb <- rep(NA_real_, 4)
    ix <- which(dims$type == "HORIZONTAL_X")
    iy <- which(dims$type == "HORIZONTAL_Y")
    if (length(ix) != 1 || length(iy) != 1) {
        if (ndim >= 2) {
            ix <- ndim
            iy <- ndim - 1
        } else {
            ix <- iy <- integer(0)
        }
    }
    .edges <- function(cv) {
        if (!is.numeric(cv) || length(cv) < 2 || anyNA(cv))
            return(c(NA_real_, NA_real_))
        half <- abs(mean(diff(cv))) / 2
        c(min(cv) - half, max(cv) + half)
    }
    if (length(ix) == 1 && length(iy) == 1) {
        ex <- .edges(coords[[ix]])
        ey <- .edges(coords[[iy]])
        bb <- c(ex[1], ey[1], ex[2], ey[2])
    }

    dt <- arr$getDataType()
    datatype <- if (dt$numeric_type != "") dt$numeric_type else dt$class

    wkt_fmt_config <- get_config_option("OSR_WKT_FORMAT")
    if (wkt_fmt_config == "")
        set_config_option("OSR_WKT_FORMAT", "WKT2")
    srs <- arr$getSpatialRef()
    set_config_option("OSR_WKT_FORMAT", wkt_fmt_config)

    gis <- list(type = "multidim",
                dim = rev(as.numeric(count)),
                dim_names = rev(dims$name),
                coords = rev(coords),
                bbox = bb,
                srs = srs,
                datatype = datatype,
                nodata = arr$getNoDataValue(),
                scale = arr$getScale(),
                offset = arr$getOffset(),
                unit = arr$getUnit(),
                dim_units = rev(dim_units),
                calendar = calendar)

    if (isTRUE(as_array) && ndim > 0)
        dim(v) <- gis$dim

    attr(v, "gis") <- gis
    return(v)
}

#' Generate an index of chunk offsets and sizes for iterating an MDArray
#'
#' `mdim_chunk_index()` returns a matrix of chunk indexes, start offsets and
#' sizes for iterating I/O operations over an array of a GDAL Multidimensional
#' Raster dataset, one row per chunk. It is the multidimensional counterpart
#' of [make_chunk_index()]. **This function is experimental**. Its interface
#' may change in future releases.
#'
#' @details
#' The chunks tile the array exactly, on a regular grid of `chunk_size`
#' starting at index `0` of each dimension. Chunks at the end of a dimension
#' are clipped to the array. By default, the chunks are the blocks of the
#' array as stored (see \code{$getBlockSize()} of class
#' [`GDALMDArray`][GDALMDArray]), so that each row is a read of exactly one
#' stored block: one fetch and one decode, the natural unit of cost for
#' chunked formats such as Zarr, netCDF-4 and HDF5. A `chunk_size` from
#' \code{$getProcessingChunkSize()} gives larger chunks, aligned to the
#' blocks, that fit a memory limit.
#'
#' If `start` and `count` are given, only the chunks that intersect that
#' hyperslab are returned (as whole chunks, i.e., not clipped to the
#' hyperslab). This gives the stored blocks that a planned read would touch.
#'
#' @param x Either an object of class [`GDALMDArray`][GDALMDArray], or a
#' numeric vector of dimension sizes (in the array's own dimension order).
#' @param chunk_size Optional numeric vector with the chunk size along each
#' dimension. A value of `0` or `NA` means the whole dimension. By default,
#' the block size of the array if `x` is a `GDALMDArray` object. Required if
#' `x` is a vector of dimension sizes.
#' @param start Optional numeric vector of 0-based start indexes of a
#' hyperslab, one value per dimension.
#' @param count Optional numeric vector giving the number of values of a
#' hyperslab along each dimension. Required if `start` is given.
#' @returns A numeric matrix with one row per chunk and, for an array of `n`
#' dimensions, `3 * n` named columns: `chunkoff0`, ..., `off0`, ..., `size0`,
#' ..., where the suffix is the 0-based dimension index. `chunkoff` is the
#' 0-based index of the chunk along the dimension, `off` is its 0-based start
#' index and `size` is its size. Columns `off` and `size` of a row are the
#' `start` and `count` arguments for \code{GDALMDArray$read()}. Rows are
#' ordered with the last dimension varying fastest.
#'
#' @seealso
#' [GDALMDArray], [make_chunk_index()], [mdim_read()]
#'
#' @examplesIf gdal_version_num() >= gdal_compute_version(3, 2, 0) && isTRUE(gdal_formats("netCDF")$multidim_raster)
#' # dimension sizes and chunk sizes given directly
#' mdim_chunk_index(c(4, 5, 6), c(2, 5, 4))
#'
#' # the chunks that a hyperslab read would touch
#' mdim_chunk_index(c(4, 5, 6), c(2, 5, 4), start = c(1, 0, 3),
#'                  count = c(1, 5, 1))
#'
#' # iterate over an array in chunks that fit a memory limit (here 120 bytes,
#' # i.e., 60 values of Int16)
#' f <- system.file("extdata/mdim_small.nc", package="gdalraster")
#' ds <- new(GDALMultiDimRaster, f)
#' arr <- ds$openMDArray("/t2m")
#' idx <- mdim_chunk_index(arr, arr$getProcessingChunkSize(120))
#' idx
#'
#' off_cols <- startsWith(colnames(idx), "off")
#' size_cols <- startsWith(colnames(idx), "size")
#' chunk_max <- numeric(nrow(idx))
#' for (i in seq_len(nrow(idx))) {
#'   v <- arr$read(idx[i, off_cols], idx[i, size_cols], NULL)
#'   chunk_max[i] <- max(v, na.rm = TRUE)
#' }
#' chunk_max
#'
#' arr$close()
#' ds$close()
#' @export
mdim_chunk_index <- function(x, chunk_size = NULL, start = NULL,
                             count = NULL) {

    if (is(x, "Rcpp_GDALMDArray")) {
        dim_size <- x$getDimensions()$size
        if (is.null(chunk_size))
            chunk_size <- x$getBlockSize()
    } else if (is.numeric(x)) {
        dim_size <- as.numeric(x)
        if (is.null(chunk_size))
            stop("'chunk_size' is required for a vector of dimension sizes",
                 call. = FALSE)
    } else {
        stop("'x' must be a GDALMDArray object or a numeric vector",
             call. = FALSE)
    }

    ndim <- length(dim_size)
    if (ndim == 0)
        stop("an array of 1 or more dimensions is required", call. = FALSE)
    if (anyNA(dim_size) || any(dim_size < 1) ||
            any(dim_size != trunc(dim_size))) {
        stop("dimension sizes must be whole numbers >= 1", call. = FALSE)
    }

    if (!is.numeric(chunk_size) || length(chunk_size) != ndim) {
        stop("'chunk_size' must have one value per dimension (", ndim, ")",
             call. = FALSE)
    }
    chunk_size <- as.numeric(chunk_size)
    whole_dim <- is.na(chunk_size) | chunk_size == 0
    chunk_size[whole_dim] <- dim_size[whole_dim]
    if (any(chunk_size < 1) || any(chunk_size != trunc(chunk_size)))
        stop("'chunk_size' must be whole numbers >= 0", call. = FALSE)
    chunk_size <- pmin(chunk_size, dim_size)

    if (is.null(start) != is.null(count))
        stop("'start' and 'count' must both be given, or both NULL",
             call. = FALSE)
    if (is.null(start)) {
        start <- rep(0, ndim)
        count <- dim_size
    }
    if (!is.numeric(start) || !is.numeric(count) || length(start) != ndim ||
            length(count) != ndim) {
        stop("'start' and 'count' must have one value per dimension (", ndim,
             ")", call. = FALSE)
    }
    if (anyNA(start) || anyNA(count) || any(start < 0) || any(count < 1) ||
            any(start + count > dim_size) || any(start != trunc(start)) ||
            any(count != trunc(count))) {
        stop("'start' and 'count' are out of range", call. = FALSE)
    }

    # first and last chunk index along each dimension
    chunk_first <- start %/% chunk_size
    chunk_last <- (start + count - 1) %/% chunk_size
    num_chunks <- prod(chunk_last - chunk_first + 1)
    if (num_chunks > 1e7) {
        stop("too many chunks (", format(num_chunks, scientific = FALSE),
             "), use 'start' and 'count' or a larger 'chunk_size'",
             call. = FALSE)
    }

    # last dimension varies fastest
    chunkoff <- expand.grid(lapply(rev(seq_len(ndim)), function(i) {
        seq(chunk_first[i], chunk_last[i])
    }), KEEP.OUT.ATTRS = FALSE)
    chunkoff <- unname(as.matrix(chunkoff))[, rev(seq_len(ndim)), drop = FALSE]

    off <- sweep(chunkoff, 2, chunk_size, `*`)
    size <- pmin(sweep(off, 2, chunk_size, `+`),
                 matrix(dim_size, nrow = nrow(off), ncol = ndim,
                        byrow = TRUE)) - off

    out <- cbind(chunkoff, off, size)
    storage.mode(out) <- "double"
    dim_idx <- seq_len(ndim) - 1
    colnames(out) <- c(paste0("chunkoff", dim_idx), paste0("off", dim_idx),
                       paste0("size", dim_idx))
    return(out)
}

#' Raw block references of a multidimensional array
#'
#' `mdim_block_refs()` returns the location of the stored blocks (chunks) of
#' an array of a GDAL Multidimensional Raster dataset: for each block, the
#' file that contains it, and the byte offset and size of the block in that
#' file. The blocks are not read or decoded. This is the information needed
#' to fetch the raw bytes of a block directly (e.g., with a byte range
#' request), or to build a table of references to the blocks of a set of
#' files (a "virtual" dataset in the style of kerchunk or VirtualiZarr).
#' Requires GDAL >= 3.12. **This function is experimental**. Its interface
#' may change in future releases.
#'
#' @details
#' The blocks are those of [mdim_chunk_index()] with the block size of the
#' array as stored, optionally limited to the blocks that intersect a
#' hyperslab given by `start` and `count`. Their locations are obtained with
#' \code{$getRawBlockRefs()} of class [`GDALMDArray`][GDALMDArray] (see that
#' method for details of the values returned and the formats supported).
#'
#' The time needed depends on the format. For netCDF-4 and HDF5, the index of
#' blocks in the file is read once. For Zarr, each block is a file (or a part
#' of a file) that GDAL has to query, so a remote store takes one or more
#' network requests per block. Use `start` and `count` to limit the number of
#' blocks.
#'
#' @param x An object of class [`GDALMDArray`][GDALMDArray].
#' @param start Optional numeric vector of 0-based start indexes of a
#' hyperslab, one value per dimension.
#' @param count Optional numeric vector giving the number of values of a
#' hyperslab along each dimension. Required if `start` is given.
#' @returns A data frame with one row per block. For an array of `n`
#' dimensions, the first `3 * n` columns are those of [mdim_chunk_index()]
#' (`chunkoff0`, ..., `off0`, ..., `size0`, ...), followed by:
#'   * `filename`: the file that contains the block, or `NA`
#'   * `offset`: the offset in bytes of the block in that file, or `NA`
#'   * `size`: the size in bytes of the block as stored, or `NA`
#'   * `info`: list column of character vectors of driver-specific
#'   `NAME=VALUE` pairs that describe how the block is encoded
#'   * `inline_data`: list column with a `raw` vector for a block that the
#'   dataset holds inline (`filename` and `offset` are then `NA`), otherwise
#'   `NULL`
#'
#' A block that is missing in the dataset (all values are nodata) has `NA`
#' for `filename`, `offset` and `size`.
#'
#' @seealso
#' [GDALMDArray], [mdim_chunk_index()], [mdim_read()]
#'
#' @examplesIf gdal_version_num() >= gdal_compute_version(3, 12, 0) && isTRUE(gdal_formats("netCDF")$multidim_raster) && nrow(gdal_formats("HDF5")) > 0
#' f <- system.file("extdata/mdim_small.nc", package="gdalraster")
#' ds <- new(GDALMultiDimRaster, f)
#' arr <- ds$openMDArray("/t2m")
#'
#' # this array is stored as one block, not compressed
#' refs <- mdim_block_refs(arr)
#' refs[, c("filename", "offset", "size")]
#' refs$info[[1]]
#'
#' # the bytes of the block, read directly from the file and decoded
#' con <- file(refs$filename[1], "rb")
#' invisible(seek(con, refs$offset[1]))
#' b <- readBin(con, "raw", n = refs$size[1])
#' close(con)
#' v <- readBin(b, "integer", n = length(b) / 2, size = 2, endian = "little")
#' v[v == arr$getNoDataValue()] <- NA
#'
#' identical(v, arr$read(NULL, NULL, NULL))
#'
#' arr$close()
#' ds$close()
#' @export
mdim_block_refs <- function(x, start = NULL, count = NULL) {

    if (!is(x, "Rcpp_GDALMDArray"))
        stop("'x' must be a GDALMDArray object", call. = FALSE)

    if (gdal_version_num() < gdal_compute_version(3, 12, 0))
        stop("mdim_block_refs() requires GDAL >= 3.12", call. = FALSE)

    idx <- mdim_chunk_index(x, start = start, count = count)
    ndim <- ncol(idx) / 3
    refs <- x$getRawBlockRefs(idx[, seq_len(ndim), drop = FALSE])

    out <- as.data.frame(idx)
    out[names(refs)] <- refs
    return(out)
}

#' Create a new multidimensional raster dataset
#'
#' `mdim_create()` creates a new, empty dataset in a format that supports the
#' GDAL Multidimensional Raster Data Model (e.g., netCDF, Zarr, or the
#' in-memory MEM format), and returns it open for update as an object of class
#' [`GDALMultiDimRaster`][GDALMultiDimRaster]. Dimensions, arrays, groups and
#' attributes are then added with methods of that class.
#' Wrapper of `GDALCreateMultiDimensional()` in the GDAL API. Requires
#' GDAL >= 3.2. **This function is experimental**. Its interface may change
#' in future releases.
#'
#' @details
#' Data may not be written to the file until the dataset is closed, which
#' happens when \code{$close()} has been called on the returned object and on
#' every array object obtained from it.
#'
#' Only some of the formats with multidimensional support can be created
#' (currently netCDF, Zarr, TileDB, VRT and MEM, depending on the GDAL version
#' and build). A format driver can be checked with
#' `gdal_get_driver_md(format, "DCAP_CREATE_MULTIDIMENSIONAL")`, which returns
#' `"YES"` if it supports this. Note that the `rw_flag` column of
#' [gdal_formats()] describes the driver as a whole, including its classic
#' raster and vector support. To convert an existing dataset to another
#' format, or to subset it, see [mdim_translate()].
#'
#' @param format Character string giving a format driver short name
#' (e.g., `"netCDF"`, `"Zarr"`, `"MEM"`).
#' @param dst_filename Character string giving the filename to create (may be
#' an empty string for the MEM format).
#' @param root_group_options Optional character vector of driver-specific
#' `NAME=VALUE` options for the creation of the root group.
#' @param options Optional character vector of driver-specific `NAME=VALUE`
#' dataset creation options (e.g., `"FORMAT=NC4"` for netCDF).
#' @returns An object of class [`GDALMultiDimRaster`][GDALMultiDimRaster],
#' open for update.
#'
#' @seealso
#' [GDALMultiDimRaster], [GDALMDArray], [mdim_translate()], [mdim_read()]
#'
#' @examplesIf gdal_version_num() >= gdal_compute_version(3, 2, 0) && isTRUE(gdal_formats("netCDF")$multidim_raster)
#' f <- tempfile(fileext = ".nc")
#' ds <- mdim_create("netCDF", f)
#' ds
#'
#' ds$createDimension("/", "time", "TEMPORAL", "", 2, NULL)
#' ds$createDimension("/", "lat", "HORIZONTAL_Y", "NORTH", 2, NULL)
#' ds$createDimension("/", "lon", "HORIZONTAL_X", "EAST", 3, NULL)
#'
#' # coordinate arrays, named as their dimensions
#' time <- ds$createMDArray("/time", "/time", "Int32", NULL)
#' ds$setAttribute("/time", "units", "days since 2020-01-01", "")
#' lat <- ds$createMDArray("/lat", "/lat", "Float64", NULL)
#' ds$setAttribute("/lat", "units", "degrees_north", "")
#' lon <- ds$createMDArray("/lon", "/lon", "Float64", NULL)
#' ds$setAttribute("/lon", "units", "degrees_east", "")
#'
#' # a data array of Int16, one block per time step, compressed
#' sst <- ds$createMDArray("/sst", c("/time", "/lat", "/lon"), "Int16",
#'                         c("BLOCKSIZE=1,2,3", "COMPRESS=DEFLATE"))
#' ds$setAttribute("/sst", "long_name", "sea surface temperature", "")
#' ds$setAttribute("/sst", "valid_range", c(-200L, 4000L), "Int16")
#' ds$setAttribute("/", "title", "mdim_create() example", "")
#' sst
#'
#' # close the arrays and the dataset to write the file
#' time$close()
#' lat$close()
#' lon$close()
#' sst$close()
#' ds$close()
#'
#' ds <- new(GDALMultiDimRaster, f)
#' ds$getMDArrayNames("/")
#' ds$getDimensions("/sst")
#' ds$getAttributes("/sst")
#' ds$close()
#' \dontshow{unlink(f)}
#' @export
mdim_create <- function(format, dst_filename, root_group_options = NULL,
                        options = NULL) {

    if (missing(format) || !is.character(format) || length(format) != 1 ||
            is.na(format)) {
        stop("'format' must be a character string", call. = FALSE)
    }
    if (missing(dst_filename) || !is.character(dst_filename) ||
            length(dst_filename) != 1 || is.na(dst_filename)) {
        stop("'dst_filename' must be a character string", call. = FALSE)
    }
    if (!is.null(root_group_options) && !is.character(root_group_options))
        stop("'root_group_options' must be a character vector or NULL",
             call. = FALSE)
    if (!is.null(options) && !is.character(options))
        stop("'options' must be a character vector or NULL", call. = FALSE)

    # signature for the mdim_create() object factory
    ds <- new(GDALMultiDimRaster, format, dst_filename, root_group_options,
              options)
    return(ds)
}
