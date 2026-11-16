skip_if(gdal_version_num() < gdal_compute_version(3, 2, 0))
skip_if(nrow(gdal_formats("netCDF")) == 0 ||
            isFALSE(gdal_formats("netCDF")$multidim_raster))

# inst/extdata/mdim_small.nc is created by data-raw/mdim_small.R

test_that("open, close and dataset-level methods work", {
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")

    ds <- new(GDALMultiDimRaster, f)
    expect_true(ds$isOpen())
    expect_true(ds$isReadOnly())
    expect_equal(ds$getFilename(), f)
    expect_equal(ds$getDriverShortName(), "netCDF")
    expect_equal(ds$getDriverLongName(), "Network Common Data Format")
    expect_equal(basename(ds$getFileList()), "mdim_small.nc")
    expect_no_error(show(ds))

    ds$close()
    expect_false(ds$isOpen())
    expect_error(ds$getGroupNames("/"), "not open")
    expect_no_error(show(ds))

    ds$open(TRUE)
    expect_true(ds$isOpen())
    expect_equal(ds$getGroupNames("/"), "ocean")
    ds$close()

    # other constructors
    ds <- new(GDALMultiDimRaster, f, TRUE)
    expect_true(ds$isReadOnly())
    ds$close()

    ds <- new(GDALMultiDimRaster, f, TRUE, "")
    expect_true(ds$isOpen())
    ds$close()

    ds <- new(GDALMultiDimRaster, f, TRUE, NULL, FALSE, "netCDF")
    expect_equal(ds$getDriverShortName(), "netCDF")
    ds$close()

    expect_error(new(GDALMultiDimRaster, f, TRUE, NULL, FALSE, "GTiff"))

    # a classic raster cannot be opened in multidimensional mode
    f_tif <- system.file("extdata/storml_elev.tif", package="gdalraster")
    expect_error(new(GDALMultiDimRaster, f_tif))
})

test_that("group and array names work", {
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    ds <- new(GDALMultiDimRaster, f)

    expect_equal(ds$getGroupNames("/"), "ocean")
    expect_equal(ds$getGroupNames("/ocean"), character(0))
    expect_setequal(ds$getMDArrayNames("/"), c("lat", "lon", "time", "t2m"))
    expect_equal(ds$getMDArrayNames("/ocean"), "sst")

    # path normalization
    expect_equal(ds$getMDArrayNames(""), ds$getMDArrayNames("/"))
    expect_equal(ds$getMDArrayNames("ocean"), "sst")
    expect_equal(ds$getMDArrayNames("/ocean/"), "sst")

    expect_error(ds$getGroupNames("/nope"), "group not found")
    # an array is not a group
    expect_error(ds$getMDArrayNames("/t2m"), "group not found")

    ds$close()
})

test_that("getDimensions works for groups and arrays", {
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    ds <- new(GDALMultiDimRaster, f)

    cols <- c("name", "full_name", "size", "type", "direction",
              "indexing_variable")

    dims <- ds$getDimensions("/")
    expect_true(is.data.frame(dims))
    expect_equal(names(dims), cols)
    expect_equal(nrow(dims), 3)
    dims <- dims[order(dims$name), ]
    expect_equal(dims$name, c("lat", "lon", "time"))
    expect_equal(dims$size, c(5, 6, 4))
    expect_equal(dims$type, c("HORIZONTAL_Y", "HORIZONTAL_X", "TEMPORAL"))
    expect_equal(dims$indexing_variable, c("/lat", "/lon", "/time"))

    # array dimensions in the array's own order (slowest varying first)
    dims <- ds$getDimensions("/t2m")
    expect_equal(names(dims), cols)
    expect_equal(dims$name, c("time", "lat", "lon"))
    expect_equal(dims$full_name, c("/time", "/lat", "/lon"))
    expect_equal(dims$size, c(4, 5, 6))
    expect_equal(dims$direction, c("", "NORTH", "EAST"))

    # array in a sub-group referencing dimensions of the root group
    dims <- ds$getDimensions("/ocean/sst")
    expect_equal(dims$full_name, c("/time", "/lat", "/lon"))

    # a group with no dimensions of its own
    dims <- ds$getDimensions("/ocean")
    expect_equal(names(dims), cols)
    expect_equal(nrow(dims), 0)

    expect_error(ds$getDimensions("/nope"), "no group or array found")

    ds$close()
})

test_that("getAttributes converts by data type", {
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    ds <- new(GDALMultiDimRaster, f)

    attrs <- ds$getAttributes("/")
    expect_type(attrs, "list")
    expect_setequal(names(attrs),
                    c("Conventions", "title", "version", "resolution"))
    expect_identical(attrs$Conventions, "CF-1.8")
    expect_identical(attrs$version, 1L)
    expect_identical(attrs$resolution, 0.25)

    attrs <- ds$getAttributes("/t2m")
    expect_identical(attrs$long_name, "2 metre temperature")
    expect_identical(attrs$valid_range, c(-5000L, 5000L))

    attrs <- ds$getAttributes("/time")
    expect_identical(attrs$calendar, "standard")

    attrs <- ds$getAttributes("/ocean")
    expect_identical(attrs, list(source = "synthetic"))

    attrs <- ds$getAttributes("/ocean/sst")
    expect_identical(attrs$long_name, "sea surface temperature")

    expect_error(ds$getAttributes("/nope"), "no group or array found")

    ds$close()
})

test_that("getGroupInfo works", {
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    ds <- new(GDALMultiDimRaster, f)

    info <- ds$getGroupInfo("/")
    expect_equal(names(info), c("name", "full_name", "group_names",
                                "array_names", "dimensions", "attributes"))
    expect_equal(info$name, "/")
    expect_equal(info$full_name, "/")
    expect_equal(info$group_names, "ocean")
    expect_setequal(info$array_names, c("lat", "lon", "time", "t2m"))
    expect_equal(nrow(info$dimensions), 3)
    expect_identical(info$attributes$version, 1L)

    info <- ds$getGroupInfo("/ocean")
    expect_equal(info$name, "ocean")
    expect_equal(info$full_name, "/ocean")
    expect_equal(info$array_names, "sst")

    expect_error(ds$getGroupInfo("/t2m"), "group not found")

    ds$close()
})

test_that("info prints JSON from gdalmdiminfo", {
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    ds <- new(GDALMultiDimRaster, f)

    expect_output(ds$info(), "\"driver\": \"netCDF\"")

    ds$infoOptions <- c("-array", "t2m")
    expect_output(ds$info(), "\"type\": \"array\"")

    ds$infoOptions <- "--not-an-option"
    expect_error(ds$info())

    ds$close()
})

test_that("Zarr copy of the test dataset gives the same structure", {
    skip_if(nrow(gdal_formats("Zarr")) == 0 ||
                isFALSE(gdal_formats("Zarr")$multidim_raster))

    f <- system.file("extdata/mdim_small.nc", package="gdalraster")
    zarr_dir <- file.path(tempdir(), "mdim_small.zarr")
    on.exit(unlink(zarr_dir, recursive = TRUE))
    mdim_translate(f, zarr_dir, output_format = "Zarr", quiet = TRUE)

    ds <- new(GDALMultiDimRaster, zarr_dir)
    expect_equal(ds$getDriverShortName(), "Zarr")
    expect_equal(ds$getGroupNames("/"), "ocean")
    ## true in GDAL 3.8.4 (but not in 3.14)
    #expect_equal(ds$getMDArrayNames("/ocean"), "sst")
    expect_true("sst" %in% ds$getMDArrayNames("/ocean"))
    expect_equal(ds$getDimensions("/t2m")$size, c(4, 5, 6))
    expect_identical(ds$getAttributes("/ocean/sst")$long_name,
                     "sea surface temperature")
    ds$close()
})
