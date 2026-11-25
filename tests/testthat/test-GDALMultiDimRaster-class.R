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

test_that("show() prints a placeholder for an inline VRT XML filename", {
    vrt <- paste0('<VRTDataset><Group name="/">',
                  '<Dimension name="x" size="3"/>',
                  '<Array name="a"><DataType>Float64</DataType>',
                  '<DimensionRef ref="x"/>',
                  '<ConstantValue>1</ConstantValue></Array>',
                  '</Group></VRTDataset>')
    ds <- new(GDALMultiDimRaster, vrt)
    expect_equal(ds$getDriverShortName(), "VRT")
    msg <- paste0("<inline VRTDataset XML, ", nchar(vrt), " chars>")
    out <- paste(capture_messages(show(ds)), collapse = "")
    expect_match(out, msg, fixed = TRUE)
    expect_no_match(out, "<Group", fixed = TRUE)
    ds$close()
    out <- paste(capture_messages(show(ds)), collapse = "")
    expect_match(out, msg, fixed = TRUE)
})

test_that("openMDArray reports the GDAL error for an array that fails", {
    skip_if(nrow(gdal_formats("Zarr")) == 0 ||
                isFALSE(gdal_formats("Zarr")$multidim_raster))

    # a Zarr v2 array with an unknown compressor: GDAL fails to open the
    # array with a specific error rather than not finding it
    zarr_dir <- file.path(tempdir(), "bad_codec.zarr")
    on.exit(unlink(zarr_dir, recursive = TRUE))
    dir.create(file.path(zarr_dir, "x"), recursive = TRUE)
    writeLines('{"zarr_format": 2}', file.path(zarr_dir, ".zgroup"))
    writeLines(paste0('{"zarr_format": 2, "shape": [4], "chunks": [2], ',
                      '"dtype": "<f4", "compressor": {"id": "bogus"}, ',
                      '"fill_value": 0, "order": "C", "filters": null}'),
               file.path(zarr_dir, "x", ".zarray"))

    ds <- new(GDALMultiDimRaster, zarr_dir)
    expect_error(ds$openMDArray("/x"), "failed to open array /x: .*bogus")
    expect_error(ds$openMDArray("/nope"), "array not found: /nope")
    ds$close()
})

test_that("mdim_create and creation methods work", {
    expect_error(mdim_create("not_a_format", ""), "driver")
    expect_error(mdim_create("GTiff", tempfile(fileext = ".tif")),
                 "multidimensional create")
    expect_error(mdim_create(1, ""), "'format'")
    expect_error(mdim_create("MEM"), "'dst_filename'")
    expect_error(mdim_create("MEM", "", options = 1), "'options'")

    f <- tempfile(fileext = ".nc")
    on.exit(unlink(f), add = TRUE)

    ds <- mdim_create("netCDF", f)
    expect_s4_class(ds, "Rcpp_GDALMultiDimRaster")
    expect_true(ds$isOpen())
    expect_false(ds$isReadOnly())
    expect_equal(ds$getDriverShortName(), "netCDF")
    expect_equal(normalizePath(ds$getFilename()), normalizePath(f))
    expect_length(ds$getMDArrayNames("/"), 0)

    ds$createDimension("/", "time", "TEMPORAL", "", 3, NULL)
    ds$createDimension("/", "lat", "HORIZONTAL_Y", "NORTH", 2, NULL)
    ds$createDimension("/", "lon", "HORIZONTAL_X", "EAST", 4, NULL)
    dims <- ds$getDimensions("/")
    expect_equal(dims$name, c("time", "lat", "lon"))
    expect_equal(dims$size, c(3, 2, 4))
    expect_error(ds$createDimension("/", "", "", "", 2, NULL), "'name'")
    expect_error(ds$createDimension("/", "bad", "", "", 0, NULL), "'size'")
    expect_error(ds$createDimension("/", "bad", "", "", 1.5, NULL), "'size'")
    expect_error(ds$createDimension("/nogroup", "bad", "", "", 2, NULL),
                 "group not found")

    lat <- ds$createMDArray("/lat", "/lat", "Float64", NULL)
    expect_s4_class(lat, "Rcpp_GDALMDArray")
    ds$setAttribute("/lat", "units", "degrees_north", "")
    # a 1D array named as its dimension is the indexing variable
    dims <- ds$getDimensions("/")
    expect_equal(dims$indexing_variable[dims$name == "lat"], "/lat")

    arr <- ds$createMDArray("/t2m", c("/time", "/lat", "/lon"), "Int16",
                            c("BLOCKSIZE=1,2,4", "COMPRESS=DEFLATE"))
    expect_equal(arr$getDimensions()$name, c("time", "lat", "lon"))
    expect_equal(arr$getDataType()$numeric_type, "Int16")
    expect_equal(arr$getBlockSize(), c(1, 2, 4))

    expect_error(ds$createMDArray("/", "/lat", "Int16", NULL), "'path'")
    expect_error(ds$createMDArray("/bad", "/nodim", "Int16", NULL),
                 "dimension not found")
    expect_error(ds$createMDArray("/bad", NA_character_, "Int16", NULL),
                 "NA")
    expect_error(ds$createMDArray("/bad", "/lat", "not_a_type", NULL),
                 "'data_type'")
    expect_error(ds$createMDArray("/nogroup/bad", "/lat", "Int16", NULL),
                 "group not found")

    # groups, with their own dimensions and arrays
    ds$createGroup("/ocean", NULL)
    expect_equal(ds$getGroupNames("/"), "ocean")
    ds$createDimension("/ocean", "depth", "VERTICAL", "DOWN", 2, NULL)
    depth <- ds$createMDArray("/ocean/depth", "/ocean/depth", "Float32", NULL)
    prof <- ds$createMDArray("/ocean/temp", c("/ocean/depth", "/lat"),
                             "Float32", NULL)
    expect_equal(ds$getMDArrayNames("/ocean"), c("depth", "temp"))
    expect_error(ds$createGroup("/", NULL), "'path'")
    expect_error(ds$createGroup("/nogroup/sub", NULL), "group not found")

    # attributes of groups and arrays
    ds$setAttribute("/", "title", "created", "")
    ds$setAttribute("/", "version", 2L, "")
    ds$setAttribute("/t2m", "valid_range", c(-100.5, 100.5), "")
    ds$setAttribute("/t2m", "flags", c("a", "b"), "")
    ds$setAttribute("/ocean", "note", "a group", "")
    expect_equal(ds$getAttributes("/")$title, "created")
    expect_identical(ds$getAttributes("/")$version, 2L)
    expect_equal(ds$getAttributes("/t2m")$valid_range, c(-100.5, 100.5))
    expect_equal(ds$getAttributes("/t2m")$flags, c("a", "b"))
    expect_error(ds$setAttribute("/", "", "x", ""), "'name'")
    expect_error(ds$setAttribute("/", "bad", NULL, ""), "'value'")
    expect_error(ds$setAttribute("/", "bad", character(0), ""), "'value'")
    expect_error(ds$setAttribute("/", "bad", list(1), ""), "'value'")
    expect_error(ds$setAttribute("/", "bad", c(1, NA), ""), "NA")
    expect_error(ds$setAttribute("/", "bad", NA_character_, ""), "NA")
    expect_error(ds$setAttribute("/nothing", "bad", 1, ""), "no group or array")

    if (gdal_version_num() >= gdal_compute_version(3, 8, 0)) {
        # replace, with another type and length
        ds$setAttribute("/", "title", "created again", "")
        expect_equal(ds$getAttributes("/")$title, "created again")
        ds$setAttribute("/t2m", "flags", c(1.5, 2.5, 3.5), "")
        expect_equal(ds$getAttributes("/t2m")$flags, c(1.5, 2.5, 3.5))
        ds$deleteAttribute("/", "version")
        expect_null(ds$getAttributes("/")$version)
        ds$deleteAttribute("/t2m", "flags")
        expect_null(ds$getAttributes("/t2m")$flags)
        expect_error(ds$deleteAttribute("/nothing", "x"), "no group or array")
    } else {
        expect_error(ds$deleteAttribute("/", "version"), "GDAL >= 3.8")
    }

    lat$close()
    arr$close()
    depth$close()
    prof$close()
    ds$close()
    expect_error(ds$createGroup("/x", NULL), "not open")

    # as written to the file
    ds <- new(GDALMultiDimRaster, f)
    expect_equal(sort(ds$getMDArrayNames("/")), c("lat", "t2m"))
    dims <- ds$getDimensions("/")
    # netCDF derives the dimension type from CF attributes (here the unit)
    expect_equal(dims$type[dims$name == "lat"], "HORIZONTAL_Y")
    expect_equal(dims$indexing_variable[dims$name == "lat"], "/lat")
    expect_equal(ds$getAttributes("/ocean")$note, "a group")
    expect_equal(ds$getAttributes("/t2m")$valid_range, c(-100.5, 100.5))
    arr <- ds$openMDArray("/t2m")
    expect_equal(arr$getDimensions()$size, c(3, 2, 4))
    expect_equal(arr$getDataType()$numeric_type, "Int16")
    expect_equal(arr$getBlockSize(), c(1, 2, 4))
    expect_length(arr$read(NULL, NULL, NULL), 24)
    arr$close()
    prof <- ds$openMDArray("/ocean/temp")
    expect_equal(prof$getDimensions()$full_name, c("/ocean/depth", "/lat"))
    expect_equal(prof$getDataType()$numeric_type, "Float32")
    prof$close()

    # read-only
    expect_error(ds$createGroup("/x", NULL), "read-only")
    expect_error(ds$createDimension("/", "x", "", "", 2, NULL), "read-only")
    expect_error(ds$createMDArray("/x", "/lat", "Int16", NULL), "read-only")
    expect_error(ds$setAttribute("/", "x", 1, ""), "read-only")
    expect_error(ds$deleteAttribute("/", "title"), "read-only")
    ds$close()

    # update an existing dataset
    ds <- new(GDALMultiDimRaster, f, read_only = FALSE)
    ds$setAttribute("/", "history", "updated", "")
    ds$createDimension("/", "level", "VERTICAL", "UP", 5, NULL)
    lev <- ds$createMDArray("/level", "/level", "Float32", NULL)
    lev$close()
    ds$close()
    ds <- new(GDALMultiDimRaster, f)
    expect_equal(ds$getAttributes("/")$history, "updated")
    expect_true("level" %in% ds$getMDArrayNames("/"))
    expect_equal(ds$getDimensions("/level")$size, 5)
    ds$close()
})

test_that("mdim_create works for MEM and Zarr", {
    ds <- mdim_create("MEM", "")
    ds$createDimension("/", "x", "HORIZONTAL_X", "EAST", 3, NULL)
    x <- ds$createMDArray("/x", "/x", "Float64", NULL)
    expect_equal(ds$getDimensions("/")$indexing_variable, "/x")
    expect_equal(ds$getDimensions("/")$type, "HORIZONTAL_X")
    s <- ds$createMDArray("/scalar", character(0), "Int32", NULL)
    expect_equal(s$getDimensionCount(), 0)
    expect_length(s$read(NULL, NULL, NULL), 1)
    x2 <- ds$openMDArray("/x")
    expect_equal(x2$getDimensions()$size, 3)
    x$close()
    x2$close()
    s$close()
    ds$close()

    skip_if(nrow(gdal_formats("Zarr")) == 0 ||
                isFALSE(gdal_formats("Zarr")$multidim_raster))

    f <- file.path(tempdir(), "mdim_create_test.zarr")
    unlink(f, recursive = TRUE)
    on.exit(unlink(f, recursive = TRUE), add = TRUE)

    ds <- mdim_create("Zarr", f)
    ds$createDimension("/", "y", "HORIZONTAL_Y", "NORTH", 2, NULL)
    ds$createDimension("/", "x", "HORIZONTAL_X", "EAST", 3, NULL)
    arr <- ds$createMDArray("/v", c("/y", "/x"), "Float32", "BLOCKSIZE=1,3")
    ds$setAttribute("/v", "long_name", "a variable", "")
    arr$close()
    ds$close()

    ds <- new(GDALMultiDimRaster, f)
    arr <- ds$openMDArray("/v")
    expect_equal(arr$getBlockSize(), c(1, 3))
    expect_equal(arr$getDimensions()$size, c(2, 3))
    expect_equal(arr$getDataType()$numeric_type, "Float32")
    expect_equal(arr$getAttributes()$long_name, "a variable")
    arr$close()
    ds$close()
})

test_that("indexing variable is set only for an array in the same group", {
    ds <- mdim_create("MEM", "")
    ds$createDimension("/", "x", "HORIZONTAL_X", "EAST", 3, NULL)
    ds$createGroup("/g", NULL)
    # same name as the dimension but in another group
    gx <- ds$createMDArray("/g/x", "/x", "Float64", NULL)
    expect_equal(ds$getDimensions("/")$indexing_variable, "")
    x <- ds$createMDArray("/x", "/x", "Float64", NULL)
    expect_equal(ds$getDimensions("/")$indexing_variable, "/x")
    gx$close()
    x$close()
    ds$close()
})

test_that("setAttribute checks its value and cleans up on failure", {
    ds <- mdim_create("MEM", "")
    ds$setAttribute("/", "nan_ok", c(1, NaN, Inf), "")
    expect_equal(ds$getAttributes("/")$nan_ok, c(1, NaN, Inf))
    expect_error(ds$setAttribute("/", "bad", c(1, NA), ""), "NA")
    expect_error(ds$setAttribute("/", "bad", NA, ""), "NA")
    expect_error(ds$setAttribute("/", "bad", factor("a"), ""), "factor")
    i64 <- structure(1, class = "integer64")
    expect_error(ds$setAttribute("/", "bad", i64, ""),
                 "integer64")
    expect_named(ds$getAttributes("/"), "nan_ok")
    expect_error(ds$setAttribute("/nothing", "bad", 1, ""), "/nothing")
    if (gdal_version_num() >= gdal_compute_version(3, 8, 0))
        expect_error(ds$deleteAttribute("/", ""), "'name'")
    ds$close()

    skip_if(gdal_version_num() < gdal_compute_version(3, 8, 0))

    # netCDF requires _FillValue to have the data type of its variable
    f <- tempfile(fileext = ".nc")
    on.exit(unlink(f), add = TRUE)
    ds <- mdim_create("netCDF", f)
    ds$createDimension("/", "x", "", "", 3, NULL)
    v <- ds$createMDArray("/v", "/x", "Int16", NULL)
    ds$setAttribute("/v", "keep", 5L, "")
    expect_error(ds$setAttribute("/v", "_FillValue", "abc", ""), "/v")
    expect_named(v$getAttributes(), "keep")
    v$close()
    ds$close()

    ds <- new(GDALMultiDimRaster, f)
    expect_named(ds$getAttributes("/v"), "keep")
    ds$close()
})

test_that("creation options, NULL dim_paths and attribute data types work", {
    ds <- mdim_create("MEM", "")
    s <- ds$createMDArray("/scalar", NULL, "Int32", NULL)
    expect_equal(s$getDimensionCount(), 0)
    s$close()
    ds$close()

    f <- tempfile(fileext = ".nc")
    on.exit(unlink(f), add = TRUE)
    ds <- mdim_create("netCDF", f)
    ds$createGroup("/g", NULL)
    # a driver-specific option is passed through (unlimited dimension)
    ds$createDimension("/", "time", "TEMPORAL", "", 2, "UNLIMITED=YES")
    ds$createDimension("/", "x", "HORIZONTAL_X", "EAST", 3, NULL)
    v <- ds$createMDArray("/v", c("/time", "/x"), "Int16", NULL)
    ds$setAttribute("/v", "valid_range", c(-200L, 4000L), "Int16")
    ds$setAttribute("/v", "scale", 0.5, "Float32")
    ds$setAttribute("/v", "count", 7, "")
    ds$setAttribute("/v", "note", "text", "String")
    expect_error(ds$setAttribute("/v", "bad", 1, "not_a_type"), "'data_type'")
    expect_error(ds$setAttribute("/v", "bad", 1, "String"), "'data_type'")
    expect_error(ds$setAttribute("/v", "bad", "a", "Int16"), "'data_type'")
    v$close()
    ds$close()

    json <- mdim_info(f, "v", pretty = FALSE, detailed = TRUE, cout = FALSE)
    expect_match(json, '"valid_range":{"datatype":"Int16"', fixed = TRUE)
    expect_match(json, '"scale":{"datatype":"Float32"', fixed = TRUE)
    expect_match(json, '"count":{"datatype":"Float64"', fixed = TRUE)
})
