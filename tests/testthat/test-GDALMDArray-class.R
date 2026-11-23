skip_if(gdal_version_num() < gdal_compute_version(3, 2, 0))
skip_if(nrow(gdal_formats("netCDF")) == 0 ||
            isFALSE(gdal_formats("netCDF")$multidim_raster))

# inst/extdata/mdim_small.nc is created by data-raw/mdim_small.R
# t2m stored values are 1185 + 100 * k + 10 * i (k: 1-based time index,
# i: 1-based cell index in C order), with element 3 set to nodata (-32767)
t2m_values <- function() {
    v <- as.integer(outer(1:30, 1:4, function(i, k) 1185 + 100 * k + 10 * i))
    v[3] <- NA_integer_
    v
}

test_that("openMDArray and description methods work", {
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    ds <- new(GDALMultiDimRaster, f)

    arr <- ds$openMDArray("/t2m")
    expect_true(is(arr, "Rcpp_GDALMDArray"))
    expect_true(arr$isOpen())
    expect_no_error(show(arr))
    expect_equal(arr$getName(), "t2m")
    expect_equal(arr$getFullName(), "/t2m")
    expect_equal(arr$getDimensionCount(), 3)

    dims <- arr$getDimensions()
    expect_equal(dims$name, c("time", "lat", "lon"))
    expect_equal(dims$size, c(4, 5, 6))

    dt <- arr$getDataType()
    expect_equal(dt$class, "NUMERIC")
    expect_equal(dt$numeric_type, "Int16")
    expect_equal(dt$size, 2)

    expect_equal(arr$getNoDataValue(), -32767)
    expect_equal(arr$getScale(), 0.01)
    expect_equal(arr$getOffset(), 0)
    expect_equal(arr$getUnit(), "degC")
    expect_identical(arr$getAttributes()$valid_range, c(-5000L, 5000L))
    expect_length(arr$getBlockSize(), 3)

    info <- arr$getInfo()
    expect_equal(names(info),
                 c("name", "full_name", "dimensions", "datatype",
                   "block_size", "nodata", "scale", "offset", "unit", "srs",
                   "attributes"))
    expect_equal(info$unit, "degC")

    expect_equal(arr$getCoordinateValues(0), c(0, 6, 12, 18))
    expect_equal(arr$getCoordinateValues(1), seq(-41, -42, by = -0.25))
    expect_equal(arr$getCoordinateValues(2), seq(145, 146.25, by = 0.25))
    expect_error(arr$getCoordinateValues(3), "0-based")

    # path forms and errors
    expect_equal(ds$openMDArray("ocean/sst")$getFullName(), "/ocean/sst")
    expect_error(ds$openMDArray("/nope"), "array not found")
    expect_error(ds$openMDArray("/ocean"), "array not found")

    sst <- ds$openMDArray("/ocean/sst")
    expect_equal(sst$getDataType()$numeric_type, "Float32")
    expect_equal(sst$getNoDataValue(), -999)
    expect_true(is.na(sst$getScale()))
    expect_true(is.na(sst$getOffset()))
    sst$close()

    # an array with no nodata, scale or unit
    tm <- ds$openMDArray("/time")
    expect_true(is.na(tm$getNoDataValue()))
    expect_equal(tm$getUnit(), "hours since 2000-01-01 00:00:00")
    expect_equal(tm$getCoordinateValues(0), c(0, 6, 12, 18))
    tm$close()

    arr$close()
    expect_false(arr$isOpen())
    expect_error(arr$read(NULL, NULL, NULL), "not open")
    expect_no_error(show(arr))

    ds$close()
})

test_that("read works for whole arrays and hyperslabs", {
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    ds <- new(GDALMultiDimRaster, f)
    arr <- ds$openMDArray("/t2m")
    expected <- t2m_values()

    v <- arr$read(NULL, NULL, NULL)
    expect_type(v, "integer")
    expect_null(attributes(v))
    expect_identical(v, expected)

    # C order: lon fastest, then lat, then time
    a <- array(expected, dim = c(6, 5, 4))
    expect_identical(arr$read(c(0, 0, 0), c(1, 1, 6), NULL), a[, 1, 1])
    expect_identical(arr$read(c(2, 3, 1), c(1, 1, 2), NULL), a[2:3, 4, 3])
    expect_identical(arr$read(c(0, 2, 4), c(4, 1, 1), NULL), a[5, 3, ])
    expect_identical(arr$read(c(0, 0, 0), c(1, 5, 6), NULL),
                     as.vector(a[, , 1]))

    # step, including NULL and negative step
    expect_identical(arr$read(c(0, 0, 0), c(4, 1, 1), NULL), a[1, 1, ])
    expect_identical(arr$read(c(0, 0, 0), c(2, 1, 3), c(2, 1, 2)),
                     as.vector(a[c(1, 3, 5), 1, c(1, 3)]))
    expect_identical(arr$read(c(3, 0, 0), c(4, 1, 1), c(-1, 1, 1)),
                     a[1, 1, 4:1])

    # argument checks
    expect_error(arr$read(c(0, 0), c(1, 1), NULL), "one value per dimension")
    expect_error(arr$read(c(0, 0, 0), c(5, 1, 1), NULL), "out of range")
    expect_error(arr$read(c(-1, 0, 0), c(1, 1, 1), NULL), "out of range")
    expect_error(arr$read(c(0.5, 0, 0), c(1, 1, 1), NULL), "out of range")
    expect_error(arr$read(c(3, 0, 0), c(2, 1, 1), NULL), "out of range")
    expect_error(arr$read(c(0, 0, 0), c(1, 1, 1), c(0, 1, 1)), "non-zero")
    expect_error(arr$read(c(0, 0, 0), c(3, 1, 1), c(2, 1, 1)), "outside")
    expect_error(arr$read(c(0, 0, 0), NULL, NULL), "both")
    expect_error(arr$read(NULL, c(1, 1, 1), NULL), "both")
    expect_error(arr$read(numeric(0), numeric(0), NULL), "one value per")

    # the array remains valid after the dataset is closed
    ds$close()
    expect_identical(arr$read(c(0, 0, 0), c(1, 1, 2), NULL), a[1:2, 1, 1])
    arr$close()

    # float array with nodata
    ds <- new(GDALMultiDimRaster, f)
    sst <- ds$openMDArray("/ocean/sst")
    v <- sst$read(NULL, NULL, NULL)
    expect_type(v, "double")
    expect_true(all(is.na(v[1:2])))
    expect_equal(v[4], 1325 * 0.01 + 1, tolerance = 1e-6)
    sst$close()
    ds$close()
})

test_that("read of a Byte array works, optionally as raw", {
    f <- system.file("extdata/byte.nc", package="gdalraster")
    ds <- new(GDALMultiDimRaster, f)
    arr <- ds$openMDArray("/Band1")
    expect_equal(arr$getDataType()$numeric_type, "Byte")

    v <- arr$read(NULL, NULL, NULL)
    expect_type(v, "integer")
    expect_length(v, 400)
    # same values as the classic raster view
    ds_classic <- mdim_as_classic(f, "Band1", 1, 0)
    expect_equal(sum(v), sum(ds_classic$read(1, 0, 0, 20, 20, 20, 20)))
    ds_classic$close()

    arr$readByteAsRaw <- TRUE
    v_raw <- arr$read(NULL, NULL, NULL)
    expect_type(v_raw, "raw")
    expect_equal(as.integer(v_raw), v)

    expect_true(nchar(arr$getSpatialRef()) > 0)

    arr$close()
    ds$close()
})

test_that("block size is reported for a chunked Zarr array", {
    skip_if(nrow(gdal_formats("Zarr")) == 0 ||
                isFALSE(gdal_formats("Zarr")$multidim_raster))

    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    zarr_dir <- file.path(tempdir(), "mdim_small_blocks.zarr")
    on.exit(unlink(zarr_dir, recursive = TRUE))
    mdim_translate(f, zarr_dir, output_format = "Zarr",
                   creation_options = "ARRAY:IF(DIM=3):BLOCKSIZE=1,5,6", quiet = TRUE)

    ds <- new(GDALMultiDimRaster, zarr_dir)
    arr <- ds$openMDArray("/t2m")
    expect_equal(arr$getBlockSize(), c(1, 5, 6))
    expect_identical(arr$read(NULL, NULL, NULL), t2m_values())
    arr$close()
    ds$close()
})

test_that("getView, transpose, getUnscaled and getMask work", {
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    ds <- new(GDALMultiDimRaster, f)
    arr <- ds$openMDArray("/t2m")
    expected <- t2m_values()
    a <- array(expected, dim = c(6, 5, 4))

    # a view gives the same values as the matching hyperslab read
    v <- arr$getView("[1,2:4,::2]")
    expect_true(is(v, "Rcpp_GDALMDArray"))
    expect_equal(v$getDimensionCount(), 2)
    expect_equal(v$getDimensions()$size, c(2, 3))
    expect_identical(v$read(NULL, NULL, NULL),
                     arr$read(c(1, 2, 0), c(1, 2, 3), c(1, 1, 2)))
    expect_identical(v$read(NULL, NULL, NULL),
                     as.vector(a[c(1, 3, 5), 3:4, 2]))
    expect_equal(v$getUnit(), "degC")

    # reversed dimension
    rv <- arr$getView("[::-1,...]")
    expect_identical(rv$read(c(0, 0, 0), c(4, 1, 1), NULL), a[1, 1, 4:1])
    rv$close()

    expect_error(arr$getView(""), "non-empty")
    expect_error(arr$getView("[9,...]"), "failed to get view")

    # views remain valid after the source array and dataset are closed
    tr <- arr$transpose(c(2, 1, 0))
    expect_equal(tr$getDimensions()$name, c("lon", "lat", "time"))
    expect_identical(tr$read(NULL, NULL, NULL),
                     as.vector(aperm(a, c(3, 2, 1))))
    expect_equal(arr$transpose(c(-1, 0, 1, 2))$getDimensions()$size,
                 c(1, 4, 5, 6))
    expect_error(arr$transpose(c(0, 1, 3)), "0-based")
    expect_error(arr$transpose(c(0, 0, 1)), "failed to get transposed")

    # unscaled values
    u <- arr$getUnscaled()
    expect_equal(u$getDataType()$numeric_type, "Float64")
    expect_true(is.na(u$getScale()))
    expect_equal(u$read(NULL, NULL, NULL), expected * 0.01)

    # mask of valid values
    m <- arr$getMask(NULL)
    expect_equal(m$getDataType()$numeric_type, "Byte")
    expect_identical(m$read(NULL, NULL, NULL),
                     as.integer(!is.na(expected)))
    expect_identical(v$getMask(character(0))$read(NULL, NULL, NULL),
                     rep(1L, 6))

    # fields are carried over
    arr$readByteAsRaw <- TRUE
    expect_type(arr$getMask(NULL)$read(NULL, NULL, NULL), "raw")
    arr$readByteAsRaw <- FALSE

    arr$close()
    ds$close()
    expect_identical(v$read(NULL, NULL, NULL),
                     as.vector(a[c(1, 3, 5), 3:4, 2]))
    expect_equal(tr$read(c(0, 0, 0), c(1, 1, 4), NULL), a[1, 1, ])
    expect_error(arr$getView("[0,...]"), "not open")
    v$close()
    tr$close()
    u$close()
    m$close()
})

test_that("asClassicDataset works", {
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    ds <- new(GDALMultiDimRaster, f)
    arr <- ds$openMDArray("/t2m")
    a <- array(t2m_values(), dim = c(6, 5, 4))

    r <- arr$asClassicDataset(2, 1, NULL)
    expect_true(is(r, "Rcpp_GDALRaster"))
    expect_equal(r$dim(), c(6, 5, 4))
    expect_equal(r$getGeoTransform(), c(144.875, 0.25, 0, -40.875, 0, -0.25))
    expect_identical(r$read(3, 0, 0, 6, 5, 6, 5), as.vector(a[, , 3]))

    # the same geotransform as mdim_as_classic(view_expr = )
    v <- arr$getView("[2,...]")
    r1 <- v$asClassicDataset(1, 0, NULL)
    expect_equal(r1$dim(), c(6, 5, 1))
    r2 <- mdim_as_classic(f, "t2m", 1, 0, view_expr = "[2,...]")
    expect_equal(r1$getGeoTransform(), r2$getGeoTransform())
    expect_equal(r1$read(1, 0, 0, 6, 5, 6, 5), r2$read(1, 0, 0, 6, 5, 6, 5))
    r2$close()

    expect_error(arr$asClassicDataset(3, 1, NULL), "idx_xdim")
    expect_error(arr$asClassicDataset(2, -1, NULL), "idx_ydim")
    expect_error(arr$asClassicDataset(2, 2, NULL), "different")

    # the raster remains valid after the array and dataset are closed
    arr$close()
    v$close()
    ds$close()
    expect_identical(r1$read(1, 0, 0, 6, 1, 6, 1), a[, 1, 3])
    r1$close()
    r$close()

    # statistics on a view of byte.nc, as for mdim_as_classic()
    # on a copy, since GDAL >= 3.8 saves statistics of a classic view in
    # <filename>.aux.xml next to the dataset
    f2 <- tempfile(fileext = ".nc")
    file.copy(system.file("extdata/byte.nc", package="gdalraster"), f2)
    on.exit(unlink(c(f2, paste0(f2, ".aux.xml"))), add = TRUE)
    ds <- new(GDALMultiDimRaster, f2)
    band1 <- ds$openMDArray("/Band1")
    v <- band1$getView("[0:10,...]")
    r <- v$asClassicDataset(1, 0, NULL)
    # https://github.com/OSGeo/gdal/blob/2b1c4d1fdb9377b62d821d70d022e7426940aec6/autotest/gdrivers/netcdf_multidim.py#L4036
    expect_equal(r$getStatistics(1, FALSE, TRUE),
                 c(74.0, 255.0, 126.82, 26.729713803182),
                 tolerance = 0.01)
    r$close()
    v$close()
    band1$close()
    ds$close()
})

# mdim_small.nc /t2m with a spatial reference and nodata value, as a
# multidimensional VRT reading from the file
t2m_vrt <- function() {
    vrt <- '<VRTDataset><Group name="/">
      <Dimension name="time" size="4" indexingVariable="time"/>
      <Dimension name="lat" type="HORIZONTAL_Y" size="5" indexingVariable="lat"/>
      <Dimension name="lon" type="HORIZONTAL_X" size="6" indexingVariable="lon"/>
      <Array name="time"><DataType>Float64</DataType><DimensionRef ref="time"/>
        <Source><SourceFilename>SRC</SourceFilename>
        <SourceArray>/time</SourceArray></Source></Array>
      <Array name="lat"><DataType>Float64</DataType><DimensionRef ref="lat"/>
        <Source><SourceFilename>SRC</SourceFilename>
        <SourceArray>/lat</SourceArray></Source></Array>
      <Array name="lon"><DataType>Float64</DataType><DimensionRef ref="lon"/>
        <Source><SourceFilename>SRC</SourceFilename>
        <SourceArray>/lon</SourceArray></Source></Array>
      <Array name="t2m"><DataType>Int16</DataType>
        <DimensionRef ref="time"/><DimensionRef ref="lat"/>
        <DimensionRef ref="lon"/>
        <SRS dataAxisToSRSAxisMapping="2,1">EPSG:4326</SRS>
        <NoDataValue>-32767</NoDataValue>
        <Source><SourceFilename>SRC</SourceFilename>
        <SourceArray>/t2m</SourceArray></Source></Array>
    </Group></VRTDataset>'
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    gsub("SRC", f, vrt, fixed = TRUE)
}

test_that("getResampled works", {
    skip_if(gdal_version_num() < gdal_compute_version(3, 4, 0))

    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    ds <- new(GDALMultiDimRaster, f)
    arr <- ds$openMDArray("/t2m")

    # resampling to the same grid is an identity
    r1 <- arr$getResampled(NULL, "nearest", "", NULL)
    expect_true(is(r1, "Rcpp_GDALMDArray"))
    expect_equal(r1$getDimensions()$size, c(4, 5, 6))
    expect_identical(r1$read(NULL, NULL, NULL), arr$read(NULL, NULL, NULL))
    expect_equal(r1$getCoordinateValues(1), arr$getCoordinateValues(1))
    expect_equal(r1$getCoordinateValues(2), arr$getCoordinateValues(2))
    r1$close()

    # twice the resolution over the same extent
    r2 <- arr$getResampled(c(NA, 10, 12), "nearest", "", NULL)
    expect_equal(r2$getDimensions()$size, c(4, 10, 12))
    expect_equal(r2$getDimensions()$name, c("time", "dimY", "dimX"))
    expect_equal(r2$getCoordinateValues(2),
                 seq(145 - 0.125 + 0.0625, by = 0.125, length.out = 12))
    expect_equal(r2$getCoordinateValues(0), c(0, 6, 12, 18))
    a <- array(t2m_values(), dim = c(6, 5, 4))
    v <- r2$read(c(1, 0, 0), c(1, 10, 12), NULL)
    expect_identical(v[c(2, 4)], a[1:2, 1, 2])
    expect_true(all(v %in% c(a[, , 2], NA)))
    r2$close()

    # argument checks
    expect_error(arr$getResampled(c(NA, 10), "nearest", "", NULL),
                 "one value per dimension")
    expect_error(arr$getResampled(c(NA, 0, 12), "nearest", "", NULL),
                 "whole numbers")
    expect_error(arr$getResampled(NULL, "nope", "", NULL), "not valid")
    # no spatial reference to reproject from
    expect_error(arr$getResampled(NULL, "nearest", "EPSG:3031", NULL),
                 "no spatial reference")
    arr$close()
    ds$close()

    # reprojection, with a spatial reference from a VRT
    ds <- new(GDALMultiDimRaster, t2m_vrt())
    arr <- ds$openMDArray("/t2m")
    expect_error(arr$getResampled(NULL, "nearest", "nope", NULL),
                 "not a valid spatial reference")
    r3 <- arr$getResampled(NULL, "nearest", "EPSG:3031", NULL)
    expect_equal(r3$getDimensionCount(), 3)
    expect_equal(r3$getDimensions()$name[1], "time")
    expect_equal(srs_get_name(r3$getSpatialRef()),
                 "WGS 84 / Antarctic Polar Stereographic")
    dims <- r3$getDimensions()
    v <- r3$read(c(0, 0, 0), c(1, dims$size[2], dims$size[3]), NULL)
    # nearest neighbour gives only source values, or nodata outside
    expect_true(all(v %in% c(a[, , 1], NA)))
    expect_true(sum(!is.na(v)) > 0)
    # x coordinates are in metres
    expect_true(all(r3$getCoordinateValues(2) > 1e6))

    # remains valid after the dataset is closed
    arr$close()
    ds$close()
    expect_identical(r3$read(c(0, 0, 0), c(1, dims$size[2], dims$size[3]),
                             NULL), v)
    r3$close()
})

test_that("getGridded works", {
    skip_if(gdal_version_num() < gdal_compute_version(3, 7, 0))

    pts <- '<VRTDataset><Group name="/">
      <Dimension name="n" size="4"/>
      <Array name="x"><DataType>Float64</DataType><DimensionRef ref="n"/>
        <InlineValuesWithValueElement><Value>0</Value><Value>10</Value>
        <Value>0</Value><Value>10</Value></InlineValuesWithValueElement>
      </Array>
      <Array name="y"><DataType>Float64</DataType><DimensionRef ref="n"/>
        <InlineValuesWithValueElement><Value>0</Value><Value>0</Value>
        <Value>10</Value><Value>10</Value></InlineValuesWithValueElement>
      </Array>
      <Array name="v"><DataType>Float64</DataType><DimensionRef ref="n"/>
        <InlineValuesWithValueElement><Value>1</Value><Value>2</Value>
        <Value>3</Value><Value>4</Value></InlineValuesWithValueElement>
      </Array>
    </Group></VRTDataset>'

    ds <- new(GDALMultiDimRaster, pts)
    v <- ds$openMDArray("/v")
    x <- ds$openMDArray("/x")
    y <- ds$openMDArray("/y")

    g <- v$getGridded("nearest", x, y, "RESOLUTION=10")
    expect_true(is(g, "Rcpp_GDALMDArray"))
    expect_equal(g$getDimensions()$name, c("dimY", "dimX"))
    expect_equal(g$getDimensions()$size, c(2, 2))
    expect_equal(g$getCoordinateValues(0), c(0, 10))
    expect_equal(g$getCoordinateValues(1), c(0, 10))
    # each grid node is on a point
    expect_equal(g$read(NULL, NULL, NULL), c(1, 2, 3, 4))

    g2 <- v$getGridded("invdist:power=2.0", x, y, "RESOLUTION=2.5")
    expect_equal(g2$getDimensions()$size, c(5, 5))
    gv <- g2$read(NULL, NULL, NULL)
    expect_equal(gv[c(1, 5, 21, 25)], c(1, 2, 3, 4))
    expect_true(all(gv >= 1 & gv <= 4))

    expect_error(v$getGridded("", x, y, NULL), "non-empty")
    expect_error(v$getGridded("nearest", x, NULL, NULL), "both")

    # remains valid after the source arrays and the dataset are closed
    x$close()
    y$close()
    v$close()
    ds$close()
    expect_equal(g$read(NULL, NULL, NULL), c(1, 2, 3, 4))
    g$close()
    g2$close()
})

test_that("adviseRead and getProcessingChunkSize work", {
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    ds <- new(GDALMultiDimRaster, f)
    arr <- ds$openMDArray("/t2m")

    expect_true(arr$adviseRead(NULL, NULL, NULL))
    expect_true(arr$adviseRead(c(1, 0, 0), c(2, 5, 6), NULL))
    # reads are unchanged after the advice
    expect_identical(arr$read(NULL, NULL, NULL), t2m_values())
    expect_error(arr$adviseRead(c(0, 0, 0), NULL, NULL), "both")
    expect_error(arr$adviseRead(c(0, 0), c(1, 1), NULL),
                 "one value per dimension")
    expect_error(arr$adviseRead(c(0, 0, 0), c(5, 5, 6), NULL),
                 "out of range")
    expect_error(arr$adviseRead(c(4, 0, 0), c(1, 5, 6), NULL),
                 "out of range")

    # Int16 values, the whole array is 240 bytes
    expect_equal(arr$getProcessingChunkSize(1e6), c(4, 5, 6))
    chunk <- arr$getProcessingChunkSize(24)
    expect_length(chunk, 3)
    expect_true(prod(chunk) * 2 <= 24)
    expect_true(all(chunk >= 1 & chunk <= c(4, 5, 6)))
    expect_error(arr$getProcessingChunkSize(0), "bytes")

    arr$close()
    expect_error(arr$adviseRead(NULL, NULL, NULL), "not open")
    ds$close()
})

test_that("statistics methods work", {
    # on a copy, since GDAL may save statistics next to the dataset
    f <- file.path(tempdir(), "mdim_small_stats.nc")
    unlink(paste0(f, ".aux.xml"))
    file.copy(system.file("extdata/mdim_small.nc", package="gdalraster"), f,
              overwrite = TRUE)
    on.exit(unlink(c(f, paste0(f, ".aux.xml"))), add = TRUE)

    ds <- new(GDALMultiDimRaster, f)
    arr <- ds$openMDArray("/t2m")
    arr$quiet <- TRUE
    v <- t2m_values()
    pop_sd <- function(x) {
        x <- x[!is.na(x)]
        sqrt(mean((x - mean(x))^2))
    }

    # not available without force
    st <- arr$getStatistics(FALSE, FALSE)
    expect_named(st, c("min", "max", "mean", "sd", "valid_count"))
    expect_true(all(is.na(st)))

    st <- arr$computeStatistics(FALSE, NULL)
    expect_named(st, c("min", "max", "mean", "sd", "valid_count"))
    expect_equal(unname(st),
                 c(range(v, na.rm = TRUE), mean(v, na.rm = TRUE), pop_sd(v),
                   sum(!is.na(v))))
    expect_equal(arr$getStatistics(FALSE, FALSE), st)

    # derived arrays
    expect_equal(unname(arr$getUnscaled()$computeStatistics(FALSE, NULL)),
                 c(range(v * 0.01, na.rm = TRUE), mean(v * 0.01, na.rm = TRUE),
                   pop_sd(v * 0.01), sum(!is.na(v))))
    v1 <- v[1:30]
    st1 <- arr$getView("[0,...]")$getStatistics(FALSE, TRUE)
    expect_equal(unname(st1),
                 c(range(v1, na.rm = TRUE), mean(v1, na.rm = TRUE),
                   pop_sd(v1), 29))

    arr$close()
    ds$close()
})

test_that("getRawBlockInfo and getRawBlockRefs work", {
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    ds <- new(GDALMultiDimRaster, f)
    arr <- ds$openMDArray("/t2m")
    arr$quiet <- TRUE

    if (gdal_version_num() < gdal_compute_version(3, 12, 0)) {
        expect_error(arr$getRawBlockInfo(c(0, 0, 0)), "requires GDAL >= 3.12")
        expect_error(arr$getRawBlockRefs(matrix(0, nrow = 1, ncol = 3)),
                     "requires GDAL >= 3.12")
        arr$close()
        ds$close()
        skip("GDAL < 3.12")
    }
    # the netCDF driver obtains this from the HDF5 driver
    if (nrow(gdal_formats("HDF5")) == 0) {
        arr$close()
        ds$close()
        skip("no HDF5 driver")
    }

    # one contiguous block of Int16, not compressed
    info <- arr$getRawBlockInfo(c(0, 0, 0))
    expect_named(info, c("filename", "offset", "size", "info", "inline_data"))
    expect_equal(normalizePath(info$filename), normalizePath(f))
    expect_equal(info$size, 240)
    expect_true(info$offset > 0)
    expect_true("ENDIANNESS=LITTLE" %in% info$info)
    expect_null(info$inline_data)

    con <- file(f, "rb")
    seek(con, info$offset)
    b <- readBin(con, "raw", n = info$size)
    close(con)
    v <- readBin(b, "integer", n = 120, size = 2, endian = "little")
    v[v == arr$getNoDataValue()] <- NA
    expect_identical(v, t2m_values())

    refs <- arr$getRawBlockRefs(matrix(0, nrow = 1, ncol = 3))
    expect_s3_class(refs, "data.frame")
    expect_named(refs, c("filename", "offset", "size", "info", "inline_data"))
    expect_equal(nrow(refs), 1)
    expect_equal(refs$filename, info$filename)
    expect_equal(refs$offset, info$offset)
    expect_equal(refs$size, info$size)
    expect_equal(refs$info[[1]], info$info)
    expect_null(refs$inline_data[[1]])

    # no rows
    refs0 <- arr$getRawBlockRefs(matrix(0, nrow = 0, ncol = 3))
    expect_s3_class(refs0, "data.frame")
    expect_equal(nrow(refs0), 0)

    # argument checks
    expect_error(arr$getRawBlockInfo(c(0, 0)), "one value per dimension")
    expect_error(arr$getRawBlockInfo(c(0, 0, -1)), "whole numbers")
    expect_error(arr$getRawBlockInfo(c(0, 0, 0.5)), "whole numbers")
    expect_error(arr$getRawBlockInfo(c(0, 0, NA)), "whole numbers")
    expect_error(arr$getRawBlockRefs(matrix(0, nrow = 1, ncol = 2)),
                 "one column per dimension")
    expect_error(arr$getRawBlockRefs(matrix(-1, nrow = 1, ncol = 3)),
                 "whole numbers")
    # out of range, reported by GDAL
    expect_error(arr$getRawBlockInfo(c(1, 0, 0)), "raw block info")
    expect_error(arr$getRawBlockRefs(rbind(c(0, 0, 0), c(1, 0, 0))),
                 "raw block info")

    arr$close()
    expect_error(arr$getRawBlockInfo(c(0, 0, 0)))
    ds$close()
})

test_that("cache works", {
    skip_if(gdal_version_num() < gdal_compute_version(3, 4, 0))

    f <- file.path(tempdir(), "mdim_small_cache.nc")
    file.copy(system.file("extdata/mdim_small.nc", package="gdalraster"), f,
              overwrite = TRUE)
    f_cache <- paste0(f, ".gmac")
    on.exit(unlink(c(f, f_cache, paste0(f, ".aux.xml"))), add = TRUE)

    ds <- new(GDALMultiDimRaster, f)
    arr <- ds$openMDArray("/t2m")
    tr <- arr$transpose(c(2, 1, 0))
    expected <- tr$read(NULL, NULL, NULL)
    expect_false(file.exists(f_cache))
    expect_true(tr$cache(NULL))
    expect_true(file.exists(f_cache))
    tr$close()
    arr$close()
    ds$close()

    # the cached array is used on a later open
    ds <- new(GDALMultiDimRaster, f)
    arr <- ds$openMDArray("/t2m")
    tr <- arr$transpose(c(2, 1, 0))
    expect_identical(tr$read(NULL, NULL, NULL), expected)
    tr$close()
    arr$close()
    ds$close()
})
