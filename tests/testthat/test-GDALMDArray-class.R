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
    expect_error(arr$read(), "not open")
    expect_no_error(show(arr))

    ds$close()
})

test_that("read works for whole arrays and hyperslabs", {
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    ds <- new(GDALMultiDimRaster, f)
    arr <- ds$openMDArray("/t2m")
    expected <- t2m_values()

    v <- arr$read()
    expect_type(v, "integer")
    expect_null(attributes(v))
    expect_identical(v, expected)

    # C order: lon fastest, then lat, then time
    a <- array(expected, dim = c(6, 5, 4))
    expect_identical(arr$read(c(0, 0, 0), c(1, 1, 6)), a[, 1, 1])
    expect_identical(arr$read(c(2, 3, 1), c(1, 1, 2)), a[2:3, 4, 3])
    expect_identical(arr$read(c(0, 2, 4), c(4, 1, 1)), a[5, 3, ])
    expect_identical(arr$read(c(0, 0, 0), c(1, 5, 6)),
                     as.vector(a[, , 1]))

    # step, including NULL and negative step
    expect_identical(arr$read(c(0, 0, 0), c(4, 1, 1), NULL), a[1, 1, ])
    expect_identical(arr$read(c(0, 0, 0), c(2, 1, 3), c(2, 1, 2)),
                     as.vector(a[c(1, 3, 5), 1, c(1, 3)]))
    expect_identical(arr$read(c(3, 0, 0), c(4, 1, 1), c(-1, 1, 1)),
                     a[1, 1, 4:1])

    # argument checks
    expect_error(arr$read(c(0, 0), c(1, 1)), "one value per dimension")
    expect_error(arr$read(c(0, 0, 0), c(5, 1, 1)), "out of range")
    expect_error(arr$read(c(-1, 0, 0), c(1, 1, 1)), "out of range")
    expect_error(arr$read(c(0.5, 0, 0), c(1, 1, 1)), "out of range")
    expect_error(arr$read(c(3, 0, 0), c(2, 1, 1)), "out of range")
    expect_error(arr$read(c(0, 0, 0), c(1, 1, 1), c(0, 1, 1)), "non-zero")
    expect_error(arr$read(c(0, 0, 0), c(3, 1, 1), c(2, 1, 1)), "outside")

    # the array remains valid after the dataset is closed
    ds$close()
    expect_identical(arr$read(c(0, 0, 0), c(1, 1, 2)), a[1:2, 1, 1])
    arr$close()

    # float array with nodata
    ds <- new(GDALMultiDimRaster, f)
    sst <- ds$openMDArray("/ocean/sst")
    v <- sst$read()
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

    v <- arr$read()
    expect_type(v, "integer")
    expect_length(v, 400)
    # same values as the classic raster view
    ds_classic <- mdim_as_classic(f, "Band1", 1, 0)
    expect_equal(sum(v), sum(ds_classic$read(1, 0, 0, 20, 20, 20, 20)))
    ds_classic$close()

    arr$readByteAsRaw <- TRUE
    v_raw <- arr$read()
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
    expect_identical(arr$read(), t2m_values())
    arr$close()
    ds$close()
})
