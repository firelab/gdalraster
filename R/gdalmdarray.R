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
#' dimension)
#' * advise an upcoming read, get a chunk size for processing, and compute
#' statistics
#' * derive new arrays without copying data: a view given a slicing
#' expression, a transposed view, an unscaled view, a mask, a resampled or
#' reprojected view, and a gridded view of scattered points
#' * expose a 2D view of the array as a classic raster, an object of class
#' [`GDALRaster`][GDALRaster].
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
#' arr$read(start, count, step)
#'
#' arr$getView(view_expr)
#' arr$transpose(axes)
#' arr$getUnscaled()
#' arr$getMask(options)
#' arr$getResampled(new_dim_sizes, resample_alg, target_srs, options)
#' arr$getGridded(grid_options, x_array, y_array, options)
#'
#' arr$adviseRead(start, count, options)
#' arr$getProcessingChunkSize(max_chunk_memory)
#' arr$getStatistics(approx_ok, force)
#' arr$computeStatistics(approx_ok, options)
#' arr$cache(options)
#'
#' arr$getRawBlockInfo(block_coords)
#' arr$getRawBlockRefs(block_coords)
#'
#' arr$asClassicDataset(idx_xdim, idx_ydim, options)
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
#' Defaults to `FALSE` (e.g., a progress bar from
#' \code{$computeStatistics()}).
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
#' \code{$read(start, count, step)}\cr
#' Reads the whole array, or a hyperslab of it. `start` is a numeric vector of
#' 0-based start indexes and `count` a numeric vector of the number of values
#' to read, each with one value per dimension of the array. `step` is a
#' numeric vector giving the step between indexes for each dimension (e.g.,
#' `2` to read every second value, or a negative value to read in reverse
#' order), or `NULL` for a step of `1`. Use `start = NULL` and `count = NULL`
#' to read the whole array, i.e., \code{$read(NULL, NULL, NULL)}. All three
#' arguments are required (see Description), but [mdim_read()] provides
#' defaults for them.
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
#' ## Derived arrays
#'
#' The methods below return a new object of class `GDALMDArray` that is a
#' view of this array. No data are read or copied until the new array is
#' read. The new array holds its own reference to the dataset, so it remains
#' valid after this array or the dataset is closed. Its fields
#' (\code{$readByteAsRaw}, \code{$quiet}) start with the values of this
#' array.
#'
#' \code{$getView(view_expr)}\cr
#' Returns a view of the array given a character string `view_expr`, using
#' the same syntax as NumPy basic slicing and indexing (0-based), or field
#' access by name, as described in section "View Expressions" of
#' [mdim_as_classic()]. For example, `"[0,...]"` selects the first index of
#' the first dimension (removing that dimension), `"[1:3,:,::2]"` takes
#' indexes 1 and 2 of the first dimension and every second index of the
#' third, and `"[::-1,...]"` reverses the first dimension. Note that GDAL
#' renames the sliced dimensions of a view (e.g., `"subset_lat_2_1_2"`), and
#' they then have no indexing variable.
#'
#' \code{$transpose(axes)}\cr
#' Returns a view of the array with its dimensions reordered. `axes` is an
#' integer vector of 0-based dimension indexes of this array, giving for each
#' dimension of the new array the dimension of this array that it comes from.
#' For example, for an array with dimensions `time, lat, lon`, `axes = c(2,
#' 1, 0)` gives an array with dimensions `lon, lat, time`. A value of `-1`
#' inserts a new dimension of size 1.
#'
#' \code{$getUnscaled()}\cr
#' Returns a view of the array with the scale and offset applied
#' (`raw_value * scale + offset`). The new array has data type `Float64` (or
#' `CFloat64` for a complex array), no scale or offset, and the nodata value
#' `NaN` if this array has a nodata value (read as `NA`).
#'
#' \code{$getMask(options)}\cr
#' Returns a view of the array of data type Byte, with the value `1` where a
#' value of this array is valid and `0` where it is not, as determined from
#' the nodata value, and the attributes `_FillValue`, `missing_value`,
#' `valid_min`, `valid_max` and `valid_range`, if present (and `NaN` for
#' floating point types). `options` is a character vector of `NAME=VALUE`
#' pairs, or `NULL` (see `GDALMDArray::GetMask()` in the GDAL API
#' documentation).
#'
#' \code{$getResampled(new_dim_sizes, resample_alg, target_srs, options)}\cr
#' Returns a view of the array resampled to new dimension sizes, and
#' optionally reprojected, along its horizontal dimensions (types
#' `"HORIZONTAL_X"` and `"HORIZONTAL_Y"`). Values are computed when the new
#' array is read, using GDAL's warping engine, so reading a window of the new
#' array reads only the part of the source array that it needs.
#' Requires GDAL >= 3.4.
#' * `new_dim_sizes`: a numeric vector with one value per dimension giving
#' the new size, or `NA` to keep a dimension unchanged (or, for the
#' horizontal dimensions, to have GDAL compute the size). `NULL` is the same
#' as all `NA`. Dimensions that are not horizontal must be `NA`. The new
#' horizontal dimensions are evenly spaced over the extent of the source.
#' * `resample_alg`: a character string, one of `"nearest"`, `"bilinear"`,
#' `"cubic"`, `"cubicspline"`, `"lanczos"`, `"average"`, `"rms"` or
#' `"mode"`.
#' * `target_srs`: a character string giving the spatial reference system to
#' reproject to, in a format accepted by [srs_to_wkt()] (e.g.,
#' `"EPSG:3031"`), or `""` to keep the spatial reference of the array. An
#' error is raised if `target_srs` is given and the array has no spatial
#' reference (a multidimensional VRT can add one, see the examples).
#' * `options`: a character vector of `NAME=VALUE` pairs, or `NULL` (see
#' `GDALMDArray::GetResampled()` in the GDAL API documentation).
#'
#' The new horizontal dimensions are named `dimX` and `dimY`, with indexing
#' variables of the same names holding the coordinates of the cell centres
#' in the target spatial reference.
#'
#' \code{$getGridded(grid_options, x_array, y_array, options)}\cr
#' Returns a gridded view of an array of scattered points, i.e., an array
#' whose last dimension indexes the points, interpolated onto a regular grid
#' using the GDAL gridding algorithms (as for \command{gdal_grid}).
#' Requires GDAL >= 3.7.
#' * `grid_options`: a character string giving the gridding algorithm and its
#' parameters, as for the \command{gdal_grid} `-a` argument, e.g.,
#' `"invdist:power=2.0:smoothing=1.0"`, `"nearest"`, `"average"` or
#' `"linear"`.
#' * `x_array`, `y_array`: objects of class `GDALMDArray` with the X and Y
#' coordinates of the points (one dimension, the same as the last dimension
#' of this array), or `NULL` for both to use the arrays named in the
#' `coordinates` attribute of this array.
#' * `options`: a character vector of `NAME=VALUE` pairs, or `NULL`, e.g.,
#' `"RESOLUTION=0.5"` for the grid spacing, and `"XMIN=..."`, `"XMAX=..."`,
#' `"YMIN=..."`, `"YMAX=..."` for its extent (see `GDALMDArray::GetGridded()`
#' in the GDAL API documentation).
#'
#' The new dimensions are named `dimX` and `dimY`, with indexing variables of
#' the same names.
#'
#' ## Chunk-aware I/O and statistics
#'
#' \code{$adviseRead(start, count, options)}\cr
#' Advises the driver of an upcoming read of the hyperslab given by `start`
#' and `count` (as for \code{$read()}, both `NULL` for the whole array).
#' Many drivers ignore the advice, but it can greatly accelerate access with
#' some. The Zarr driver fetches and decodes the blocks that intersect the
#' hyperslab using multiple threads and keeps them in memory for the reads
#' that follow on this array object (the call returns when that is done).
#' `options` is a character vector of driver-specific `NAME=VALUE` pairs, or
#' `NULL` (requires GDAL >= 3.4 when not empty). For Zarr these are
#' `"CACHE_SIZE=<bytes>"`, the maximum memory to use (by default half of the
#' remaining GDAL block cache), and `"NUM_THREADS=<integer>|ALL_CPUS"` (by
#' default from the `GDAL_NUM_THREADS` configuration option). Returns logical
#' `TRUE` on success (ignoring the advice is a success).
#'
#' \code{$getProcessingChunkSize(max_chunk_memory)}\cr
#' Returns a numeric vector with a chunk size along each dimension, suitable
#' for processing the array piece by piece. The chunk is a multiple of the
#' block size (see \code{$getBlockSize()}) along each dimension, within
#' `max_chunk_memory` bytes, or one block if a block is larger than that. For
#' an array with no block size, the chunk is built up from the last
#' dimension. See [mdim_chunk_index()] for the index of chunks of a given
#' size.
#'
#' \code{$getStatistics(approx_ok, force)}\cr
#' Returns a named numeric vector of statistics of the array values: `min`,
#' `max`, `mean`, `sd` (standard deviation) and `valid_count` (the number of
#' values that are not nodata). Statistics already stored for the array are
#' returned if there are any. Otherwise, they are computed if `force` is
#' `TRUE`, or `NA` values are returned if `force` is `FALSE`. `approx_ok` is
#' a logical value, `TRUE` to allow statistics computed from a subset of the
#' values (currently ignored by GDAL, which always uses all of the values).
#' Statistics are of the values as stored (scale and offset not applied).
#'
#' \code{$computeStatistics(approx_ok, options)}\cr
#' Computes statistics of the array values and returns them as a named numeric
#' vector, as for \code{$getStatistics()}. The array is read one processing
#' chunk at a time, so memory use is bounded for arrays of any size. A
#' progress bar is shown unless \code{$quiet} is `TRUE`. `options` is a
#' character vector of `NAME=VALUE` pairs, or `NULL` (requires GDAL >= 3.8
#' when not empty, e.g., `"UPDATE_METADATA=YES"` to store the minimum and
#' maximum in the `actual_range` attribute of a netCDF or Zarr array opened
#' for update). Once computed, the statistics are generally saved by GDAL
#' for later calls to \code{$getStatistics()}, in a file `pam.aux.xml` or
#' `<filename>.aux.xml` next to the dataset, written when the dataset is
#' closed. If that location is not writable (e.g., a remote dataset), GDAL
#' reports a failure to write the file at that time, which can be ignored.
#'
#' \code{$cache(options)}\cr
#' Caches the content of the array in a file named as the dataset filename
#' with the extension `.gmac` added (a netCDF dataset), or in the directory
#' given by the `GDAL_PAM_PROXY_DIR` configuration option if that file cannot
#' be written. Reads of the array then use the cache automatically, also in
#' later sessions. The main purpose is to cache a view that is expensive to
#' compute, such as a transposed array. The cache is not checked against the
#' source: it must be deleted manually if the source array changes. `options`
#' is a character vector of `NAME=VALUE` pairs, or `NULL`. Currently the only
#' option is `"BLOCKSIZE=bs0,bs1,...,bsN"`, the block size of the cached
#' array. Returns logical `TRUE` on success. Requires GDAL >= 3.4.
#'
#' ## Raw block references
#'
#' \code{$getRawBlockInfo(block_coords)}\cr
#' Returns the location of one block (chunk) of the array as stored, without
#' reading or decoding it. `block_coords` is a numeric vector of 0-based
#' block coordinates, one value per dimension, i.e., the index of the block
#' along each dimension (columns `chunkoff` of [mdim_chunk_index()]). For a
#' dimension with a block size of `0` the only valid coordinate is `0`.
#' Returns a named list with elements:
#'   * `filename`: the file that contains the block (may be a `/vsi` path or,
#'   for virtual stores such as kerchunk or Icechunk references, the file the
#'   reference points to), or `NA`
#'   * `offset`: the offset in bytes of the start of the block in that file
#'   (numeric, exact up to 2^53), or `NA`
#'   * `size`: the size in bytes of the block as stored (i.e., compressed if
#'   compression is used), or `NA`
#'   * `info`: character vector of driver-specific `NAME=VALUE` pairs that
#'   describe how the block is encoded
#'   * `inline_data`: a `raw` vector with the content of the block if the
#'   dataset holds it inline and not in a file (in which case `filename` and
#'   `offset` are `NA`), otherwise `NULL`
#'
#' A block that has valid coordinates but is missing in the dataset (all
#' values are nodata) has `NA` for `filename`, `offset` and `size`. The
#' `info` values depend on the format. For multi-byte data types they should
#' include `ENDIANNESS` (`LITTLE` or `BIG`). For netCDF-4 and HDF5 they may
#' include `COMPRESSION` (`DEFLATE` or `SZIP`) and `FILTER` (e.g.,
#' `SHUFFLE`). For Zarr they may include `COMPRESSOR` and `FILTERS` (JSON
#' as in the array metadata) and `TRANSPOSE_ORDER`. An error is raised if
#' the block coordinates are out of range, or if the format driver does not
#' provide this information for the array (it is available for netCDF-4,
#' HDF5, Zarr and, under conditions, multidimensional VRT). Requires GDAL >=
#' 3.12. For netCDF-4, GDAL must also have the HDF5 driver.
#'
#' \code{$getRawBlockRefs(block_coords)}\cr
#' Returns the locations of a set of blocks as a data frame, with one row per
#' block. `block_coords` is a numeric matrix of 0-based block coordinates
#' with one row per block and one column per dimension (e.g., the `chunkoff`
#' columns of a matrix from [mdim_chunk_index()]). The data frame has columns
#' `filename`, `offset`, `size`, `info` and `inline_data`, as described for
#' \code{$getRawBlockInfo()}, of which `info` and `inline_data` are list
#' columns. Rows are in the order of `block_coords`, with `NA` values for
#' missing blocks. A progress bar is shown for more than one block unless
#' \code{$quiet} is `TRUE`. For Zarr, each block is a file (or a part of a
#' file) that GDAL has to query, so for a remote store this takes one or
#' more network requests per block. See [mdim_block_refs()], which returns
#' the references along with the chunk index for the whole array or for a
#' hyperslab. Requires GDAL >= 3.12.
#'
#' ## Classic raster view
#'
#' \code{$asClassicDataset(idx_xdim, idx_ydim, options)}\cr
#' Returns a view of the array as a classic (2D) raster, an object of class
#' [`GDALRaster`][GDALRaster]. `idx_xdim` and `idx_ydim` are the 0-based
#' indexes of the dimensions to use as the X (width) and Y (height) axes.
#' Any other dimensions become raster bands. `idx_ydim` is ignored for a 1D
#' array. `options` is a character vector of `NAME=VALUE` pairs, or `NULL`
#' (see `GDALMDArray::AsClassicDataset()` in the GDAL API documentation; it
#' requires GDAL >= 3.8 when not empty). The geotransform is taken from
#' regularly spaced indexing variables of the X and Y dimensions. No data are
#' copied: the raster reads from the array, so a view from
#' \code{$getView()} can be used to take, e.g., one time step of a 4D array
#' as a `GDALRaster`, which can be passed to any function that works on a
#' `GDALRaster` (e.g., [warp()], [plot_raster()]). The `GDALRaster` remains
#' valid after the array is closed. See also [mdim_as_classic()], which opens
#' a dataset and returns the same raster in one call.
#'
#' \code{$close()}\cr
#' Closes the array and releases the reference to its dataset.
#'
#' @seealso
#' [GDALMultiDimRaster], [GDALRaster], [mdim_read()], [mdim_chunk_index()],
#' [mdim_block_refs()], [mdim_info()],
#' [mdim_as_classic()]
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
#' v <- arr$read(start = c(0, 0, 0), count = c(1, 5, 6), step = NULL)
#' v
#'
#' # one grid cell, all time steps, scaled to degC
#' arr$read(c(0, 2, 3), c(4, 1, 1), NULL) * arr$getScale() + arr$getOffset()
#'
#' # the same, from a view with the scale and offset applied
#' arr$getUnscaled()$read(c(0, 2, 3), c(4, 1, 1), NULL)
#'
#' # a chunk size for processing within 120 bytes (60 values of Int16)
#' arr$getProcessingChunkSize(120)
#'
#' # the first time step as a view, and its mask of valid values
#' v1 <- arr$getView("[0,...]")
#' v1$getDimensions()$size
#' v1$getMask(NULL)$read(NULL, NULL, NULL)
#'
#' # lon, lat, time order
#' arr$transpose(c(2, 1, 0))$getDimensions()$name
#'
#' # the first time step as a classic raster (lon is X, lat is Y)
#' r <- v1$asClassicDataset(1, 0, NULL)
#' r
#' r$getGeoTransform()
#' r$close()
#'
#' arr$close()
#' ds$close()
#'
#' ## statistics of the stored values, read one processing chunk at a time
#' # (on a copy of the file, since GDAL saves the statistics next to it)
#' f_tmp <- file.path(tempdir(), "mdim_small.nc")
#' file.copy(f, f_tmp)
#' ds <- new(GDALMultiDimRaster, f_tmp)
#' arr <- ds$openMDArray("/t2m")
#' arr$quiet <- TRUE
#' arr$computeStatistics(FALSE, NULL)
#' arr$close()
#' ds$close()
#' \dontshow{unlink(c(f_tmp, paste0(f_tmp, ".aux.xml")))}
#'
#' ## resampling and reprojection (GDAL >= 3.4)
#' if (gdal_version_num() >= gdal_compute_version(3, 4, 0)) {
#'   # t2m has no spatial reference: add one with a multidimensional VRT,
#'   # which reads from the source file (nothing is copied)
#'   vrt <- '<VRTDataset><Group name="/">
#'     <Dimension name="time" size="4" indexingVariable="time"/>
#'     <Dimension name="lat" type="HORIZONTAL_Y" size="5" indexingVariable="lat"/>
#'     <Dimension name="lon" type="HORIZONTAL_X" size="6" indexingVariable="lon"/>
#'     <Array name="time"><DataType>Float64</DataType><DimensionRef ref="time"/>
#'       <Source><SourceFilename>SRC</SourceFilename>
#'       <SourceArray>/time</SourceArray></Source></Array>
#'     <Array name="lat"><DataType>Float64</DataType><DimensionRef ref="lat"/>
#'       <Source><SourceFilename>SRC</SourceFilename>
#'       <SourceArray>/lat</SourceArray></Source></Array>
#'     <Array name="lon"><DataType>Float64</DataType><DimensionRef ref="lon"/>
#'       <Source><SourceFilename>SRC</SourceFilename>
#'       <SourceArray>/lon</SourceArray></Source></Array>
#'     <Array name="t2m"><DataType>Int16</DataType>
#'       <DimensionRef ref="time"/><DimensionRef ref="lat"/>
#'       <DimensionRef ref="lon"/>
#'       <SRS dataAxisToSRSAxisMapping="2,1">EPSG:4326</SRS>
#'       <NoDataValue>-32767</NoDataValue>
#'       <Source><SourceFilename>SRC</SourceFilename>
#'       <SourceArray>/t2m</SourceArray></Source></Array>
#'   </Group></VRTDataset>'
#'   vrt <- gsub("SRC", f, vrt, fixed = TRUE)
#'
#'   ds <- new(GDALMultiDimRaster, vrt)
#'   arr <- ds$openMDArray("/t2m")
#'
#'   # twice the resolution, bilinear
#'   arr2 <- arr$getResampled(c(NA, 10, 12), "bilinear", "", NULL)
#'   print(arr2$getDimensions()[, c("name", "size")])
#'   print(arr2$getCoordinateValues(2))
#'
#'   # Antarctic polar stereographic, size computed by GDAL
#'   arr3 <- arr$getResampled(NULL, "nearest", "EPSG:3031", NULL)
#'   print(arr3$getDimensions()[, c("name", "size")])
#'
#'   arr3$close()
#'   arr2$close()
#'   arr$close()
#'   ds$close()
#' }
#'
#' ## gridding scattered points (GDAL >= 3.7)
#' if (gdal_version_num() >= gdal_compute_version(3, 7, 0)) {
#'   # four points as a multidimensional VRT with inline values
#'   pts <- '<VRTDataset><Group name="/">
#'     <Dimension name="n" size="4"/>
#'     <Array name="x"><DataType>Float64</DataType><DimensionRef ref="n"/>
#'       <InlineValuesWithValueElement><Value>0</Value><Value>10</Value>
#'       <Value>0</Value><Value>10</Value></InlineValuesWithValueElement>
#'     </Array>
#'     <Array name="y"><DataType>Float64</DataType><DimensionRef ref="n"/>
#'       <InlineValuesWithValueElement><Value>0</Value><Value>0</Value>
#'       <Value>10</Value><Value>10</Value></InlineValuesWithValueElement>
#'     </Array>
#'     <Array name="v"><DataType>Float64</DataType><DimensionRef ref="n"/>
#'       <InlineValuesWithValueElement><Value>1</Value><Value>2</Value>
#'       <Value>3</Value><Value>4</Value></InlineValuesWithValueElement>
#'     </Array>
#'   </Group></VRTDataset>'
#'
#'   ds <- new(GDALMultiDimRaster, pts)
#'   v <- ds$openMDArray("/v")
#'   x <- ds$openMDArray("/x")
#'   y <- ds$openMDArray("/y")
#'   g <- v$getGridded("invdist:power=2.0", x, y, "RESOLUTION=2.5")
#'   print(g$getDimensions()[, c("name", "size")])
#'   print(matrix(g$read(NULL, NULL, NULL), nrow = 5, byrow = TRUE))
#'
#'   g$close()
#'   x$close()
#'   y$close()
#'   v$close()
#'   ds$close()
#' }
NULL

Rcpp::loadModule("mod_GDALMDArray", TRUE)
