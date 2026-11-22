# Tests for src/gdalraster.cpp
test_that("class constructors work as expected", {
    # TODO: constructors are tested throughout, but add systematic tests here
    # ...

    # not recognized as being in a supported file format
    f <- system.file("extdata/doctype.xml", package="gdalraster")
    expect_error(ds <- new(GDALRaster, f))

    # allowed drivers
    evt_file <- system.file("extdata/storml_evt.tif", package="gdalraster")
    expect_no_error(ds <- new(GDALRaster, evt_file, TRUE, NULL, TRUE, "GTiff"))
    ds$close()

    # changes in GDAL 3.10.0 affect reliability of identify driver with allowed
    # skip_if(gdal_version_num() < gdal_compute_version(3, 10, 0))
    # expect_error(ds <- new(GDALRaster, evt_file, TRUE, NULL, TRUE, "HFA"))
})

test_that("info() prints output to the console", {
    evt_file <- system.file("extdata/storml_evt.tif", package="gdalraster")
    ds <- new(GDALRaster, evt_file, TRUE)
    # check S4 show here also, needs snapshot test for {cli} formatting
    expect_no_error(show(ds))
    expect_output(ds$info())
    # with args
    ds$infoOptions <- c("-nomd", "-norat", "-noct")
    expect_output(ds$info())
    # with invalid arg
    ds$infoOptions <- "--invalid_arg"
    expect_error(ds$info())
    # restore default
    ds$infoOptions <- ""
    expect_output(ds$info())
    ds$close()
})

test_that("infoAsJSON() returns string output", {
    evt_file <- system.file("extdata/storml_evt.tif", package="gdalraster")
    tmp_file <- paste0(tempdir(), "/", "storml_evt_tmp.tif")
    file.copy(evt_file,  tmp_file)
    ds <- new(GDALRaster, tmp_file, TRUE)
    expect_vector(ds$infoAsJSON(), character(), size = 1)
    expect_true(nchar(ds$infoAsJSON()) > 100)
    # test passing extra `-json`
    ds$infoOptions <- "-json"
    expect_vector(ds$infoAsJSON(), character(), size = 1)
    expect_true(nchar(ds$infoAsJSON()) > 100)

    files <- ds$getFileList()
    on.exit(unlink(files))
    ds$close()
})

test_that("dataset parameters are correct", {
    evt_file <- system.file("extdata/storml_evt.tif", package="gdalraster")
    ds <- new(GDALRaster, evt_file)
    expect_length(ds$getFileList(), 1)
    expect_equal(ds$getDriverShortName(), "GTiff")
    expect_equal(ds$getDriverLongName(), "GeoTIFF")
    expect_equal(ds$getRasterXSize(), 143)
    expect_equal(ds$getRasterYSize(), 107)
    expect_equal(ds$getGeoTransform(),
                 c(323476.1,30.0,0.0,5105082.0,0.0,-30.0))
    expect_equal(ds$bbox(), c(323476.1,5101872.0,327766.1,5105082.0))
    expect_equal(ds$res(), c(30,30))
    expect_equal(ds$dim(), c(143,107,1))
    ds$close()

    # using dataset open options
    elev_file <- system.file("extdata/storml_elev_orig.tif", package="gdalraster")
    oo <- "NUM_THREADS=2"
    ds_oo <- new(GDALRaster, elev_file, TRUE, oo)
    expect_equal(ds_oo$getDriverShortName(), "GTiff")
    expect_equal(ds_oo$getDriverLongName(), "GeoTIFF")
    expect_equal(ds_oo$getRasterXSize(), 143)
    expect_equal(ds_oo$getRasterYSize(), 107)
    expect_equal(ds_oo$getGeoTransform(),
                 c(323476.1,30.0,0.0,5105082.0,0.0,-30.0))
    expect_equal(ds_oo$bbox(), c(323476.1,5101872.0,327766.1,5105082.0))
    expect_equal(ds_oo$res(), c(30,30))
    expect_equal(ds_oo$dim(), c(143,107,1))
    ds_oo$close()

    # without using shared mode
    ds_ns <- new(GDALRaster, elev_file, TRUE, NULL, FALSE)
    expect_equal(ds_ns$getDriverShortName(), "GTiff")
    ds_ns$close()

    # south-up raster bbox()
    f <- system.file("extdata/south-up.tif", package="gdalraster")
    ds <- new(GDALRaster, f)
    expect_equal(ds$bbox(), c(-119.55, 36.55, -118.43, 37.45), tolerance = 1e-6)
    ds$close()

    # rotated raster res()
    f <- system.file("extdata/geomatrix.tif", package="gdalraster")
    ds <- new(GDALRaster, f)
    expect_warning(cellsize <- ds$res())
    expect_equal(cellsize, c(NA_real_, NA_real_))
    ds$close()
})

test_that("band-level parameters are correct", {
    evt_file <- system.file("extdata/storml_evt.tif", package="gdalraster")
    ds <- new(GDALRaster, evt_file, TRUE)
    expect_equal(ds$getBlockSize(1), c(143,28))
    expect_equal(ds$getActualBlockSize(1, 0, 0), c(143,28))
    expect_equal(ds$getOverviewCount(1), 0)
    expect_equal(ds$getDataTypeName(1), "Int16")
    expect_equal(ds$getNoDataValue(1), 32767)
    flags <- ds$getMaskFlags(band = 1)
    expect_true(is.list(flags))
    expect_false(flags$ALL_VALID)
    expect_false(flags$PER_DATASET)
    expect_false(flags$ALPHA)
    expect_true(flags$NODATA)
    mask_band <- ds$getMaskBand(band = 1)
    expect_true(mask_band$MaskFile == "")
    expect_true(mask_band$BandNumber == 0)
    expect_equal(ds$getUnitType(1), "")
    expect_true(is.na(ds$getScale(1)))
    expect_true(is.na(ds$getOffset(1)))
    expect_equal(ds$getDescription(1), "")
    ds$close()
})

test_that("get/set metadata works", {
    evt_file <- system.file("extdata/storml_evt.tif", package="gdalraster")
    ds <- new(GDALRaster, evt_file, TRUE)
    expect_equal(ds$getMetadata(band=0, domain=""), "AREA_OR_POINT=Area")
    expect_equal(ds$getMetadata(band=1, domain=""),
                 "RepresentationType=ATHEMATIC")
    expect_equal(ds$getMetadata(band=0, domain="IMAGE_STRUCTURE"),
                 "INTERLEAVE=BAND")
    expect_equal(ds$getMetadata(band=1, domain="IMAGE_STRUCTURE"), "")
    expect_equal(ds$getMetadataItem(band=0, mdi_name="AREA_OR_POINT",
                                    domain=""),
                 "Area")
    expect_equal(ds$getMetadataItem(band=0, "INTERLEAVE",
                                    domain="IMAGE_STRUCTURE"),
                 "BAND")
    expect_equal(ds$getMetadataItem(band=1, mdi_name="COMPRESSION",
                                    domain="IMAGE_STRUCTURE"),
                 "")
    expect_equal(length(ds$getMetadataDomainList(band=0)), 3)
    expect_equal(length(ds$getMetadataDomainList(band=1)), 1)

    f <- tempfile(fileext = ".tif")
    ds2 <- create(format="GTiff", dst_filename=f, xsize=10, ysize=10,
                  nbands=1, dataType="Int32", return_obj = TRUE)

    srs <- ds$getProjection()
    expect_equal(ds$getProjectionRef(), srs)
    expect_equal(ds$getSpatialRef(), srs)
    ds2$setProjection(srs)
    gt <- ds$getGeoTransform()
    ds2$setGeoTransform(gt)
    md <- ds$getMetadata(band=0, domain="")
    expect_true(ds2$setMetadata(band=0, metadata=md, domain=""))

    expect_true(ds2$setMetadataItem(band=1, mdi_name="RepresentationType",
                                    mdi_value="THEMATIC", domain=""))
    ds2$close()
    ds2$open(read_only = TRUE)
    expect_equal(ds2$getMetadata(band=0, domain=""), "AREA_OR_POINT=Area")
    expect_equal(ds2$getMetadata(band=1, domain=""),
                 "RepresentationType=THEMATIC")

    ds$close()
    ds2$close()
    deleteDataset(f)
})

test_that("open/close/re-open works", {
    elev_file <- system.file("extdata/storml_elev_orig.tif", package="gdalraster")
    ds <- new(GDALRaster, elev_file)
    dm <- ds$dim()
    r <- read_ds(ds)
    ds$close()
    mod_file <- paste0(tempdir(), "/", "storml_elev_mod.tif")
    rasterFromRaster(srcfile = elev_file,
                     dstfile = mod_file,
                     nbands = 1,
                     dtName = "UInt32",
                     init = DEFAULT_NODATA[["UInt32"]])
    ds <- new(GDALRaster, mod_file)
    expect_true(ds$isOpen())
    expect_true(ds$isReadOnly())
    expect_true(all(is.na(read_ds(ds))))
    ds$close()
    expect_false(ds$isOpen())
    expect_equal(ds$getFilename(), .check_gdal_filename(mod_file))
    ds$open(read_only = FALSE)
    expect_true(ds$isOpen())
    expect_false(ds$isReadOnly())
    ds$setDescription(band = 1, "test")
    expect_equal(ds$getDescription(band = 1), "test")
    r[is.na(r)] <- DEFAULT_NODATA[["UInt32"]]
    ds$write(band=1, 0, 0, dm[1], dm[2], r)
    expect_silent(ds$flushCache())
    expect_false(all(is.na(read_ds(ds))))
    expect_true(any(is.na(read_ds(ds))))
    files <- ds$getFileList()
    on.exit(unlink(files))
    ds$close()

    ds <- new(GDALRaster)
    ds$setFilename(elev_file)
    ds$open(TRUE)
    expect_equal(ds$dim(), dm)
    ds$close()
})

test_that("statistics are correct", {
    elev_file <- system.file("extdata/storml_elev_orig.tif", package="gdalraster")
    mod_file <- paste0(tempdir(), "/", "storml_elev_mod.tif")
    file.copy(elev_file,  mod_file)
    ds <- new(GDALRaster, mod_file, read_only=FALSE)
    expect_equal(ds$getMinMax(band=1, approx_ok=FALSE), c(2438, 3046))
    stats <- round(ds$getStatistics(band=1, approx_ok=FALSE, force=TRUE))
    expect_equal(stats, c(2438, 3046, 2676, 133))
    if (as.integer(gdal_version()[2]) >= 3020000) {
        ds$flushCache()
        ds$clearStatistics()
        ds$flushCache()
        stats <- round(ds$getStatistics(band=1, approx_ok=TRUE, force=FALSE))
        expect_true(all(is.na(stats)))
    }

    # quiet
    stats <- NULL
    ds$quiet <- TRUE
    expect_silent(stats <- ds$getStatistics(band=1, approx_ok=FALSE,
                                            force=TRUE))
    expect_equal(round(stats), c(2438, 3046, 2676, 133))

    files <- ds$getFileList()
    on.exit(unlink(files))
    ds$close()
})

test_that("get histogram works", {
    tcc_file <- system.file("extdata/storml_tcc.tif", package="gdalraster")
    f <- paste0(tempdir(), "/", "storml_tcc_test.tif")
    file.copy(tcc_file,  f)
    ds <- new(GDALRaster, f, read_only=TRUE)
    num_bins <- length(ds$getHistogram(1, -0.5, 100.5, 101, FALSE, FALSE))
    expect_equal(num_bins, 101)
    num_pixels <- sum(ds$getHistogram(1, -0.5, 100.5, 101, FALSE, FALSE))
    expect_equal(num_pixels, 15301)
    # quiet
    num_pixels <- 0
    ds$quiet <- TRUE
    expect_silent(num_pixels <- sum(ds$getHistogram(1, -0.5, 100.5, 101,
                                                    FALSE, FALSE)))
    expect_equal(num_pixels, 15301)

    ds$close()
    deleteDataset(f)

    # default histogram
    f2 <- paste0(tempdir(), "/", "storml_tcc_test2.tif")
    file.copy(tcc_file,  f2)
    ds <- new(GDALRaster, f2, read_only=TRUE)
    expect_warning(ds$getDefaultHistogram(1, FALSE))
    expect_length(ds$getDefaultHistogram(1, TRUE), 4)
    ds$close()
    deleteDataset(f2)
})

test_that("getInterBandCovMatrix works", {
    skip_if(gdal_version_num() < gdal_compute_version(3, 13, 0))

    # https://github.com/OSGeo/gdal/blob/master/autotest/gcore/gdal_stats.py

    f <- system.file("extdata/rgbsmall.tif", package="gdalraster")
    f_tmp <- tempfile(fileext = ".tif")
    expect_true(file.copy(f, f_tmp))
    f_tmp_aux <- paste0(f_tmp, ".aux.xml")

    ds <- new(GDALRaster, f_tmp)
    on.exit(ds$close(), add = TRUE)
    on.exit(deleteDataset(f_tmp), add = TRUE)

    x <- c(2241.7045363745387, 2898.8196128051163, 1009.979953581434,
           2898.8196128051163, 3900.269159023618, 1248.65396718687,
           1009.979953581434, 1248.65396718687, 602.4703641456648)

    expected_cov_matrix <- matrix(x, 3, 3, byrow = TRUE)

    cov_matrix <- ds$getInterBandCovMatrix(0, FALSE, TRUE, FALSE, 1)
    ds$flushCache()

    expect_equal(cov_matrix, expected_cov_matrix, tolerance = 1e4)
    expect_false(vsi_stat_exists(f_tmp_aux))

    # write in metadata
    cov_matrix <- ds$getInterBandCovMatrix(0, FALSE, TRUE, TRUE, 1)
    ds$flushCache()

    expect_equal(cov_matrix, expected_cov_matrix, tolerance = 1e4)
    expect_true(vsi_stat_exists(f_tmp_aux))

    # retrieve from metadata
    cov_matrix <- ds$getInterBandCovMatrix(0, FALSE, FALSE, FALSE, 1)
    expect_equal(cov_matrix, expected_cov_matrix, tolerance = 1e4)

    # with band list
    cov_matrix <- ds$getInterBandCovMatrix(c(1, 2, 3), FALSE, FALSE, FALSE, 1)
    expect_equal(cov_matrix, expected_cov_matrix, tolerance = 1e4)

    # invalid bands
    expect_error(ds$getInterBandCovMatrix(c(0, 1, 2), FALSE, FALSE, FALSE, 1))
    expect_error(ds$getInterBandCovMatrix(c(1, 2, 4), FALSE, FALSE, FALSE, 1))
})

test_that("floating point I/O works", {
    f <- paste0(tempdir(), "/", "testfloat.tif")
    create(format="GTiff", dst_filename=f, xsize=10, ysize=10,
           nbands=1, dataType="Float32")
    ds <- new(GDALRaster, f, read_only=FALSE)
    set.seed(42)
    z <- runif(10*10)
    ds$write(band=1, xoff=0, yoff=0, xsize=10, ysize=10, z)
    ds$open(read_only=TRUE)
    expect_warning(r <- read_ds(ds))
    attributes(r) <- NULL
    expect_equal(round(r,5), round(z,5))
    ds$open(read_only=FALSE)
    ds$setNoDataValue(band=1, -99999)
    ds$write(band=1, xoff=0, yoff=0, xsize=10, ysize=10, rep(-99999, 100))
    ds$open(read_only=TRUE)
    expect_warning(r <- read_ds(ds))
    expect_true(all(is.na(r)))
    ds$open(read_only=FALSE)
    ds$deleteNoDataValue(band=1)
    ds$open(read_only=TRUE)
    expect_warning(r <- read_ds(ds))
    attributes(r) <- NULL
    expect_equal(r, rep(-99999, 100))
    files <- ds$getFileList()
    on.exit(unlink(files))
    ds$close()
})

test_that("complex I/O works", {
    f <- paste0(tempdir(), "/", "testcomplex.tif")
    create(format="GTiff", dst_filename=f, xsize=10, ysize=10,
           nbands=1, dataType="CFloat32")
    ds <- new(GDALRaster, f, read_only=FALSE)
    set.seed(42)
    z <- complex(real = stats::rnorm(100), imaginary = stats::rnorm(100))
    ds$write(band=1, xoff=0, yoff=0, xsize=10, ysize=10, z)
    ds$open(read_only=TRUE)
    expect_warning(r <- read_ds(ds))
    attributes(r) <- NULL
    expect_vector(r, ptype=complex(0), size=100)
    files <- ds$getFileList()
    on.exit(unlink(files))
    ds$close()
})

test_that("Byte I/O works", {
    f <- paste0(tempdir(), "/", "testbyte.tif")
    create(format="GTiff", dst_filename=f, xsize=10, ysize=10,
           nbands=1, dataType="Byte")
    ds <- new(GDALRaster, f, read_only=FALSE)
    set.seed(42)
    z <- as.raw(sample(100, 100))
    ds$write(band=1, xoff=0, yoff=0, xsize=10, ysize=10, z)

    ds$open(read_only=TRUE)
    expect_false(ds$readByteAsRaw)
    ## read as raw with the temporary setting
    expect_warning(r_raw <- read_ds(ds, as_raw = TRUE))
    ## read with to-integer conversion (as default, not affected by 'as_raw')
    expect_warning(r_int <- read_ds(ds))
    ## set and read as raw via field
    ds$readByteAsRaw <- TRUE
    expect_warning(r_raw1 <- read_ds(ds, as_raw = TRUE))

    ## read as raw via field only (no as_raw argument)
    ds$readByteAsRaw <- TRUE
    expect_warning(r_raw2 <- read_ds(ds))
    expect_type(r_raw2, "raw")
    ds$readByteAsRaw <- FALSE

    deleteDataset(f)

    expect_type(r_int, "integer")
    expect_type(r_raw, "raw")
    expect_type(r_raw1, "raw")
    attributes(r_raw) <- NULL
    expect_equal(r_raw, z)

    ds$close()
})

test_that("Byte I/O: warn when data type not compatible", {
    ## expect a warning when data type is not Byte
    elev_file <- system.file("extdata/storml_elev_orig.tif", package="gdalraster")
    ds <- new(GDALRaster, elev_file)
    expect_warning(read_ds(ds, 1L, 0L, 0L, 2L, 3L, 2L, 3L, as_raw = TRUE))
    ds$close()
})

test_that("set nodata value, unit type, scale and offset works", {
    elev_file <- system.file("extdata/storml_elev_orig.tif", package="gdalraster")
    mod_file <- paste0(tempdir(), "/", "storml_elev_mod.tif")
    file.copy(elev_file,  mod_file)
    ds <- new(GDALRaster, mod_file, read_only=FALSE)
    ds$setNoDataValue(1, -9999)
    ds$setUnitType(1, "m")
    ds$setScale(1, 1)
    ds$setOffset(1, 0)
    expect_equal(ds$getNoDataValue(1), -9999)
    expect_equal(ds$getUnitType(1), "m")
    expect_equal(ds$getScale(1), 1)
    expect_equal(ds$getOffset(1), 0)

    expect_false(ds$setNoDataValue(1, NA))
    expect_false(ds$setScale(1, NA))
    expect_false(ds$setOffset(1, NA))

    files <- ds$getFileList()
    on.exit(unlink(files))
    ds$close()
})

test_that("build overviews runs without error", {
    elev_file <- system.file("extdata/storml_elev_orig.tif", package="gdalraster")
    mod_file <- paste0(tempdir(), "/", "storml_elev_orig.tif")
    file.copy(elev_file,  mod_file)
    ds <- new(GDALRaster, mod_file, read_only=FALSE)
    expect_no_error(ds$buildOverviews("BILINEAR", c(2,4,8), 0))
    expect_no_error(ds$buildOverviews("NONE", 0, 0))
    # quiet
    ds$quiet <- TRUE
    expect_silent(ds$buildOverviews("BILINEAR", c(2,4,8), 0))
    expect_silent(ds$buildOverviews("NONE", 0, 0))

    files <- ds$getFileList()
    on.exit(unlink(files))
    ds$close()
})

test_that("get/set color table works", {
    f <- system.file("extdata/storml_evc.tif", package="gdalraster")
    f2 <- tempfile("storml_evc_ct", fileext = ".tif")
    on.exit(deleteDataset(f2), add = TRUE)
    calc("A", f, dstfile = f2, dtName = "UInt16", nodata_value = 65535,
         setRasterNodataValue = TRUE)
    ds <- new(GDALRaster, f2, read_only = FALSE)
    evc_csv <- system.file("extdata/LF20_EVC_220.csv", package="gdalraster")
    vat <- read.csv(evc_csv)
    ct <- vat[, c(1, 3:5)]
    expect_warning(ds$setColorTable(1, ct, "RGB"))
    # close and re-open flushes the write cache
    ds$open(read_only = TRUE)
    evc_ct <- ds$getColorTable(1)
    expect_equal(nrow(evc_ct), 65536)
    expect_equal(ds$getPaletteInterp(1), "RGB")
    ds$open(read_only = FALSE)
    expect_true(ds$clearColorTable(1))
    ds$close()
})

test_that("get/set band color interpretation works", {
    f <- paste0(tempdir(), "/", "test_col_interp.tif")
    create(format="GTiff", dst_filename=f, xsize=10, ysize=10,
            nbands=1, dataType="Byte")
    ds <- new(GDALRaster, f, read_only=FALSE)
    expect_equal(ds$getRasterColorInterp(1), "Gray")
    ds$setRasterColorInterp(1, "Palette")
    expect_equal(ds$getRasterColorInterp(1), "Palette")
    ds$setRasterColorInterp(1, "Red")
    expect_equal(ds$getRasterColorInterp(1), "Red")
    ds$setRasterColorInterp(1, "Green")
    expect_equal(ds$getRasterColorInterp(1), "Green")
    ds$setRasterColorInterp(1, "Blue")
    expect_equal(ds$getRasterColorInterp(1), "Blue")
    ds$setRasterColorInterp(1, "Alpha")
    expect_equal(ds$getRasterColorInterp(1), "Alpha")
    ds$setRasterColorInterp(1, "Hue")
    expect_equal(ds$getRasterColorInterp(1), "Hue")
    ds$setRasterColorInterp(1, "Saturation")
    expect_equal(ds$getRasterColorInterp(1), "Saturation")
    ds$setRasterColorInterp(1, "Lightness")
    expect_equal(ds$getRasterColorInterp(1), "Lightness")
    ds$setRasterColorInterp(1, "Cyan")
    expect_equal(ds$getRasterColorInterp(1), "Cyan")
    ds$setRasterColorInterp(1, "Magenta")
    expect_equal(ds$getRasterColorInterp(1), "Magenta")
    ds$setRasterColorInterp(1, "Yellow")
    expect_equal(ds$getRasterColorInterp(1), "Yellow")
    ds$setRasterColorInterp(1, "Black")
    expect_equal(ds$getRasterColorInterp(1), "Black")
    ds$setRasterColorInterp(1, "YCbCr_Y")
    expect_equal(ds$getRasterColorInterp(1), "YCbCr_Y")
    ds$setRasterColorInterp(1, "YCbCr_Cb")
    expect_equal(ds$getRasterColorInterp(1), "YCbCr_Cb")
    ds$setRasterColorInterp(1, "YCbCr_Cr")
    expect_equal(ds$getRasterColorInterp(1), "YCbCr_Cr")
    ds$setRasterColorInterp(1, "Gray")
    expect_equal(ds$getRasterColorInterp(1), "Gray")
    files <- ds$getFileList()
    on.exit(unlink(files))
    ds$close()
})

test_that("Int64 data type is detected", {
    skip_if(as.integer(gdal_version()[2]) < 3050000)

    f <- system.file("extdata/int64.tif", package="gdalraster")
    expect_warning(ds <- new(GDALRaster, f, TRUE))
    expect_equal(ds$getDataTypeName(1), "Int64")
    ds$close()
})

test_that("get/set default RAT works", {
    evt_file <- system.file("extdata/storml_evt.tif", package="gdalraster")
    f <- tempfile(fileext=".tif")
    file.copy(evt_file,  f)
    ds <- new(GDALRaster, f, read_only=FALSE)
    expect_true(is.null(ds$getDefaultRAT(band=1)))
    evt_csv <- system.file("extdata/LF20_EVT_220.csv", package="gdalraster")
    evt_tbl <- read.csv(evt_csv)
    evt_tbl <- evt_tbl[,1:7]
    rat <- buildRAT(ds, table_type="thematic", na_value=-9999, join_df=evt_tbl)
    ds$setDefaultRAT(band=1, rat)
    ds$flushCache()
    rat2 <- ds$getDefaultRAT(band=1)
    expect_equal(nrow(rat2), 24)
    expect_equal(ncol(rat2), 8)
    expect_equal(attr(rat2, "GDALRATTableType"), "thematic")
    expect_equal(attr(rat2$VALUE, "GFU"), "MinMax")
    expect_equal(attr(rat2$COUNT, "GFU"), "PixelCount")
    expect_equal(attr(rat2$EVT_NAME, "GFU"), "Name")
    expect_equal(attr(rat2$EVT_LF, "GFU"), "Generic")
    expect_equal(attr(rat2$B, "GFU"), "Blue")

    # quiet
    ds$close()
    ds$open(TRUE)
    ds$quiet <- TRUE
    expect_silent(rat3 <- ds$getDefaultRAT(band=1))
    expect_equal(nrow(rat2), 24)

    ds$close()
    deleteDataset(f)

    ## test read/write RAT with new field types GFT_Boolean, GFT_DateTime and
    ## and GFT_WKBGeometry with GDAL >= 3.12
    skip_if(gdal_version_num() < gdal_compute_version(3, 12, 0))

    # adapted from GDAL autotest/gcore/tiff_write.py
    # https://github.com/OSGeo/gdal/blob/2327638e4a399ac1e902623bfda68a03956288b6/autotest/gcore/tiff_write.py#L12490
    f <- tempfile(fileext = ".tif")
    on.exit(deleteDataset(f), add = TRUE)

    set_config_option("GTIFF_WRITE_RAT_TO_PAM", "")

    ds <- create(format = "GTiff", dst_filename = f, xsize = 1, ysize = 1,
                 nbands = 1, dataType = "Byte", return_obj = TRUE)

    tbl <- data.frame(v_int = as.integer(123))
    tbl$v_dbl <- 45.5
    tbl$v_str <- "str"
    tbl$v_bool <- TRUE
    tbl$v_dt <- as.POSIXct("2025-12-31 23:58:59.500 GMT", tz = "UTC")
    tbl$v_wkb <- list(g_wk2wk("POINT (1.0 2)"))

    expect_true(ds$setDefaultRAT(band=1, tbl))
    ds$flushCache()

    pam_file <- paste0(f, ".aux.xml")
    expect_false(vsi_stat(pam_file))

    tbl2 <- ds$getDefaultRAT(band=1)
    ignored_attrs <- c("waldo_opts", "GFU", "tzone")
    expect_equal(nrow(tbl2), nrow(tbl))
    expect_equal(ncol(tbl2), ncol(tbl))
    expect_equal(tbl2$v_int, tbl$v_int, ignore_attr = ignored_attrs)
    expect_equal(tbl2$v_dbl, tbl$v_dbl, ignore_attr = ignored_attrs)
    expect_equal(tbl2$v_bool, tbl$v_bool, ignore_attr = ignored_attrs)
    expect_equal(tbl2$v_dt, tbl$v_dt, ignore_attr = ignored_attrs)
    expect_equal(tbl2$v_wkb, tbl$v_wkb, ignore_attr = ignored_attrs)

    rm(tbl2)
    ds$close()

    f2 <- tempfile(fileext = ".tif")
    on.exit(deleteDataset(f2), add = TRUE)
    ds2 <- createCopy("GTiff", f2, f, return_obj = TRUE)
    # repeat on the copied dataset
    tbl2 <- ds2$getDefaultRAT(band=1)
    expect_equal(nrow(tbl2), nrow(tbl))
    expect_equal(ncol(tbl2), ncol(tbl))
    expect_equal(tbl2$v_int, tbl$v_int, ignore_attr = ignored_attrs)
    expect_equal(tbl2$v_dbl, tbl$v_dbl, ignore_attr = ignored_attrs)
    expect_equal(tbl2$v_bool, tbl$v_bool, ignore_attr = ignored_attrs)
    expect_equal(tbl2$v_dt, tbl$v_dt, ignore_attr = ignored_attrs)
    expect_equal(tbl2$v_wkb, tbl$v_wkb, ignore_attr = ignored_attrs)

    ds2$close()
})

test_that("add band works", {
    ds_mem <- create(format="MEM", dst_filename="", xsize=20, ysize=10,
                     nbands=1, dataType="Byte", return_obj = TRUE)

    on.exit(ds_mem$close(), add = TRUE)

    ds_mem$setProjection(epsg_to_wkt(4326))
    ds_mem$setGeoTransform(c(-180, 18, 0, 90, 0, -18))
    ds_mem$fillRaster(1, 255, 0)
    expect_true(ds_mem$addBand("Byte", NULL))
    expect_no_error(ds_mem$fillRaster(2, 255, 0))
    expect_equal(ds_mem$getRasterCount(), 2)
    expect_true(all(ds_mem$read(2, 0, 0, 20, 10, 20, 10) == 255))

    ## add bands from pointers to R data without copy
    v <- sample(0:255, 200, replace = TRUE)

    # raw vector as Byte/UInt8 band
    expect_true(ds_mem$addBand("Byte", as.raw(v)))
    expect_equal(ds_mem$getRasterCount(), 3)
    # make the data type check robust to Byte/UInt8 name change at GDAL 3.13:
    expect_equal(dt_size(ds_mem$getDataTypeName(3), as_bytes = FALSE), 8)
    expect_false(dt_is_signed(ds_mem$getDataTypeName(3)))
    # by default, it is read as Int32 (R integer)
    expect_equal(ds_mem$read(3, 0, 0, 20, 10, 20, 10), v)
    # read as Byte/UInt8 (R raw bytes)
    ds_mem$readByteAsRaw <- TRUE
    expect_equal(ds_mem$read(3, 0, 0, 20, 10, 20, 10), as.raw(v))
    ds_mem$readByteAsRaw <- FALSE

    # integer vector as Int32 band
    expect_true(ds_mem$addBand("Int32", v))
    expect_equal(ds_mem$getRasterCount(), 4)
    expect_equal(ds_mem$getDataTypeName(4), "Int32")
    v_chk <- ds_mem$read(4, 0, 0, 20, 10, 20, 10)
    expect_equal(v_chk, v)

    # "numeric" (double) vector as Float64 band
    v_dbl <- v + 0.5
    expect_true(ds_mem$addBand("Float64", v_dbl))
    expect_equal(ds_mem$getRasterCount(), 5)
    expect_equal(ds_mem$getDataTypeName(5), "Float64")
    v_dbl_chk <- ds_mem$read(5, 0, 0, 20, 10, 20, 10)
    expect_equal(v_dbl_chk, v_dbl, tolerance = 1e4)

    # complex vector as CFloat64 band
    z <- complex(real = stats::rnorm(200), imaginary = stats::rnorm(200))
    expect_true(ds_mem$addBand("CFloat64", z))
    expect_equal(ds_mem$getRasterCount(), 6)
    expect_equal(ds_mem$getDataTypeName(6), "CFloat64")
    z_chk <- ds_mem$read(6, 0, 0, 20, 10, 20, 10)
    expect_equal(z_chk, z, tolerance = 1e4)

    # test that the underlying data objects are preserved from garbage collect
    rm(v)
    rm(v_dbl)
    rm(z)
    gc()
    expect_equal(ds_mem$read(4, 0, 0, 20, 10, 20, 10), v_chk)
    expect_equal(ds_mem$read(5, 0, 0, 20, 10, 20, 10), v_dbl_chk,
                 tolerance = 1e4)
    expect_equal(ds_mem$read(6, 0, 0, 20, 10, 20, 10), z_chk, tolerance = 1e4)

    ## input validation
    # unknown data type
    expect_false(ds_mem$addBand("invalid", NULL))

    # invalid size of vector
    v <- integer(201)
    expect_false(ds_mem$addBand("Byte", as.raw(v)))
    expect_false(ds_mem$addBand("Int32", v))
    v_dbl <- v + 0.5
    expect_false(ds_mem$addBand("Float64", v_dbl))
    z <- complex(real = stats::rnorm(201), imaginary = stats::rnorm(201))
    expect_false(ds_mem$addBand("CFloat64", z))
    expect_equal(ds_mem$getRasterCount(), 6)

    # invalid object type
    v_list <- vector("list", 200)
    v_list[1:200] <- 0L
    expect_false(ds_mem$addBand("Int32", v_list))

    ## specified data type should be overridden when adding a MEM band from
    ## datapointer if specified type is not compatible with the underlying
    ## array
    v <- integer(200)

    # raw vector as Byte/UInt8 band
    expect_true(ds_mem$addBand("Int32", as.raw(v)))
    expect_equal(ds_mem$getRasterCount(), 7)
    # make the data type check robust to Byte/UInt8 name change at GDAL 3.13:
    expect_equal(dt_size(ds_mem$getDataTypeName(7), as_bytes = FALSE), 8)
    expect_false(dt_is_signed(ds_mem$getDataTypeName(7)))
    # by default, it is read as Int32 (R integer)
    expect_equal(ds_mem$read(7, 0, 0, 20, 10, 20, 10), v)
    # read as Byte/UInt8 (R raw bytes)
    ds_mem$readByteAsRaw <- TRUE
    expect_equal(ds_mem$read(7, 0, 0, 20, 10, 20, 10), as.raw(v))
    ds_mem$readByteAsRaw <- FALSE

    # integer vector as Int32 band
    expect_true(ds_mem$addBand("Byte", v))
    expect_equal(ds_mem$getRasterCount(), 8)
    expect_equal(ds_mem$getDataTypeName(8), "Int32")
    expect_equal(ds_mem$read(8, 0, 0, 20, 10, 20, 10), v)

    # "numeric" (double) vector as Float64 band
    v_dbl <- v + 0.5
    expect_true(ds_mem$addBand("Float32", v_dbl))
    expect_equal(ds_mem$getRasterCount(), 9)
    expect_equal(ds_mem$getDataTypeName(9), "Float64")
    expect_equal(ds_mem$read(9, 0, 0, 20, 10, 20, 10), v_dbl, tolerance = 1e4)

    # complex vector as CFloat64 band
    z <- complex(real = stats::rnorm(200), imaginary = stats::rnorm(200))
    expect_true(ds_mem$addBand("Float64", z))
    expect_equal(ds_mem$getRasterCount(), 10)
    expect_equal(ds_mem$getDataTypeName(10), "CFloat64")
    expect_equal(ds_mem$read(10, 0, 0, 20, 10, 20, 10), z, tolerance = 1e4)
})

test_that("pixel extract internal class method returns correct data", {
    # Several of these tests were adapted from:
    #    gdal/autotest/gcore/interpolateatpoint.py
    #    Copyright (c) 2024, Javier Jimenez Shaw <j1@jimenezshaw.com>
    #    SPDX-License-Identifier: MIT

    ## basic tests, 1 point
    f <- system.file("extdata/byte.tif", package="gdalraster")
    ds <- new(GDALRaster, f)
    # GDALRaster::pixel_extract() accepts geospatial xy
    # convert grid xy (10, 12) to geospatial xy
    geo_xy <- ds$apply_geotransform(matrix(c(10 ,12), ncol = 2))
    # geo_xy
    #>        [,1]    [,2]
    #> [1,] 441320 3750600

    extr_nearest <- ds$pixel_extract(xy = geo_xy,
                                     bands = 1,
                                     interp_method = "near",
                                     krnl_dim = 1,
                                     xy_srs = "")

    expect_equal(extr_nearest[1], 173)

    # as vector of x, y
    geo_xy <- c(441320, 3750600)
    extr_nearest <- ds$pixel_extract(xy = geo_xy,
                                     bands = 1,
                                     interp_method = "near",
                                     krnl_dim = 1,
                                     xy_srs = "")

    expect_equal(extr_nearest[1], 173)

    # point exactly on right edge
    # see https://github.com/OSGeo/gdal/pull/12087
    bb <- ds$bbox()
    extr_nearest <- ds$pixel_extract(xy = c(bb[3], (bb[2] + 200)),
                                     bands = 1,
                                     interp_method = "near",
                                     krnl_dim = 1,
                                     xy_srs = "")

    expect_equal(extr_nearest[1], 132)

    # exactly bottom right corner
    bb <- ds$bbox()
    extr_nearest <- ds$pixel_extract(xy = c(bb[3], bb[2]),
                                     bands = 1,
                                     interp_method = "near",
                                     krnl_dim = 1,
                                     xy_srs = "")

    expect_equal(extr_nearest[1], 107)

    # as data frame
    geo_xy <- data.frame(geo_xy[1], geo_xy[2])
    extr_nearest <- ds$pixel_extract(xy = geo_xy,
                                     bands = 1,
                                     interp_method = "near",
                                     krnl_dim = 1,
                                     xy_srs = "")

    expect_equal(extr_nearest[1], 173)

    # krnl_dim ignored with bilinear but a required arg for the internal method
    extr_bilinear <- ds$pixel_extract(xy = geo_xy,
                                      bands = 1,
                                      interp_method = "bilinear",
                                      krnl_dim = 2,
                                      xy_srs = "")

    expect_equal(extr_bilinear[1], 139.75, tolerance = 1e-6)

    # errors
    expect_error(ds$pixel_extract(xy = 441320,
                                  bands = 1,
                                  interp_method = "near",
                                  krnl_dim = 1,
                                  xy_srs = ""))
    expect_error(ds$pixel_extract(xy = matrix(numeric(), nrow = 0),
                                  bands = 1,
                                  interp_method = "near",
                                  krnl_dim = 1,
                                  xy_srs = ""))
    expect_error(ds$pixel_extract(xy = geo_xy,
                                  bands = 1,
                                  interp_method = "invalid",
                                  krnl_dim = 1,
                                  xy_srs = ""))
    # only one band at a time supported for NxN kernel extract
    expect_error(ds$pixel_extract(xy = geo_xy,
                                  bands = c(1, 2),
                                  interp_method = "near",
                                  krnl_dim = 3,
                                  xy_srs = ""))
    # three columns
    geo_xy$new_variable <- 0
    expect_error(ds$pixel_extract(geo_xy,
                                  bands = 1,
                                  interp_method = "near",
                                  krnl_dim = 1,
                                  xy_srs = ""))

    # out of range
    geo_xy <- matrix(c(10000000, 3750600), ncol = 2)
    expect_warning(extr_bilinear <- ds$pixel_extract(xy = geo_xy,
                                                     bands = 1,
                                                     interp_method = "bilinear",
                                                     krnl_dim = 2,
                                                     xy_srs = ""))

    expect_true(is.na(extr_bilinear[1]))

    geo_xy <- matrix(c(441320, 10000000), ncol = 2)
    expect_warning(extr_bilinear <- ds$pixel_extract(xy = geo_xy,
                                                     bands = 1,
                                                     interp_method = "bilinear",
                                                     krnl_dim = 2,
                                                     xy_srs = ""))

    expect_true(is.na(extr_bilinear[1]))

    ds$close()

    ## nodata
    ds <- create(format="MEM", dst_filename="", xsize=2, ysize=2,
                 nbands=1, dataType="Byte", return_obj=TRUE)

    raster_data <- c(255, 0, 0, 0)
    ds$write(band = 1, xoff = 0, yoff = 0, xsize = 2, ysize = 2, raster_data)
    ds$setNoDataValue(band = 1, 255)

    geo_xy <- matrix(c(0, 0), ncol = 2)

    ds$quiet <- TRUE
    # warning for no geotransform
    expect_no_error(extr_nodata <- ds$pixel_extract(xy = geo_xy,
                                                    bands = 0,
                                                    interp_method = "near",
                                                    krnl_dim = 1,
                                                    xy_srs = ""))

    expect_true(length(extr_nodata) == 1)
    expect_true(is.na(extr_nodata))

    ds$close()

    ## bilinear interpolation - 2 bands
    ds <- create(format="MEM", dst_filename="", xsize=2, ysize=2,
                 nbands=2, dataType="Float32", return_obj=TRUE)

    # band 1
    raster_data_1 <- c(10.5, 1.3, 2.4, 3.8)
    ds$write(band = 1, xoff = 0, yoff = 0, xsize = 2, ysize = 2, raster_data_1)
    # also with negative - band 2
    raster_data_2 <- c(10.5, 1.3, -2.4, 3.8)
    ds$write(band = 2, xoff = 0, yoff = 0, xsize = 2, ysize = 2, raster_data_2)

    ds$quiet <-TRUE

    geo_xy <- matrix(c(1, -1), ncol = 2)
    # bands = 0 for all bands
    # krnl_dim ignored with bilinear but a required arg for the internal method
    # warning for no geotransform
    expect_no_error(extr_bilinear <-
        ds$pixel_extract(xy = geo_xy,
                         bands = 0,
                         interp_method = "bilinear",
                         krnl_dim = 2,
                         xy_srs = ""))

    expect_true(is.matrix(extr_bilinear))
    expect_equal(dim(extr_bilinear), c(1, 2))
    expect_equal(colnames(extr_bilinear), c("b1", "b2"))
    colnames(extr_bilinear) <- NULL
    expect_equal(extr_bilinear[1, 1], sum(raster_data_1) / 4, tolerance = 1e-6)
    expect_equal(extr_bilinear[1, 2], sum(raster_data_2) / 4, tolerance = 1e-6)

    ds$close()


    ## bilinear - several points
    ds <- create(format="MEM", dst_filename="", xsize=3, ysize=2,
                 nbands=1, dataType="Float32", return_obj=TRUE)

    raster_data <- c(10.5, 1.3, 0.5,
                     2.4, 3.8, -1.0)
    ds$write(band = 1, xoff = 0, yoff = 0, xsize = 3, ysize = 2, raster_data)

    geo_xy <- matrix(c(0.5, 1.5, 2, -0.5, -1.5, -1), nrow = 3, ncol = 2)
    # krnl_dim ignored with bilinear but a required arg for the internal method
    ds$quiet <- TRUE
    expect_no_warning(
        extr_bilinear <- ds$pixel_extract(xy = geo_xy,
                                          bands = 1,
                                          interp_method = "bilinear",
                                          krnl_dim = 2,
                                          xy_srs = "")
    )

    expect_true(is.matrix(extr_bilinear))
    expect_equal(dim(extr_bilinear), c(3, 1))
    expect_equal(colnames(extr_bilinear), "b1")
    colnames(extr_bilinear) <- NULL
    expect_equal(extr_bilinear[1, 1], 10.5, tolerance = 1e-6)
    expect_equal(extr_bilinear[2, 1], 3.8, tolerance = 1e-6)
    expect_equal(extr_bilinear[3, 1], (1.3 + 0.5 + 3.8 - 1) / 4, tolerance = 1e-6)

    ds$close()
})

test_that("pixel extract interpolate near borders", {
    # Bilinear interp along the edge pixels should match results from
    # GDALRasterInterpolateAtPoint(), as described in
    # https://github.com/OSGeo/gdal/pull/10506.
    # It is currently implemented differently in gdalraster (i.e., not
    # generalized beyond bilinear, but not dependent on GDAL >= 3.10), but we
    # check using tests adapted from:
    #    gdal/autotest/gcore/interpolateatpoint.py
    #    Copyright (c) 2024, Javier Jimenez Shaw <j1@jimenezshaw.com>
    #    SPDX-License-Identifier: MIT

    ds <- create(format="MEM", dst_filename="", xsize=6, ysize=5,
                 nbands=1, dataType="Float32", return_obj=TRUE)

    raster_data <- c(1, 2, 4, 4, 5, 6,
                     9, 8, 7, 6, 3, 4,
                     4, 7, 6, 2, 1, 3,
                     7, 8, 9, 6, 2, 1,
                     2, 5, 2, 1, 7, 8)

    ds$write(band = 1, xoff = 0, yoff = 0, xsize = 6, ysize = 5, raster_data)

    ds$quiet <- TRUE

    geo_xy <- matrix(c(0, 0), ncol = 2)
    extr_bilinear <- ds$pixel_extract(geo_xy, 1, "bilinear", 2, "")
    expect_equal(extr_bilinear[1], 1.0, tolerance = 1e-6)

    geo_xy <- matrix(c(1, 0), ncol = 2)
    extr_bilinear <- ds$pixel_extract(geo_xy, 1, "bilinear", 2,"")
    expect_equal(extr_bilinear[1], 1.5, tolerance = 1e-6)

    geo_xy <- matrix(c(0, -1), ncol = 2)
    extr_bilinear <- ds$pixel_extract(geo_xy, 1, "bilinear", 2, "")
    expect_equal(extr_bilinear[1], 5.0, tolerance = 1e-6)

    geo_xy <- matrix(c(0, -2), ncol = 2)
    extr_bilinear <- ds$pixel_extract(geo_xy, 1, "bilinear", 2, "")
    expect_equal(extr_bilinear[1], 6.5, tolerance = 1e-6)

    geo_xy <- matrix(c(6, 0), ncol = 2)
    extr_bilinear <- ds$pixel_extract(geo_xy, 1, "bilinear", 2, "")
    expect_equal(extr_bilinear[1], 6.0, tolerance = 1e-6)

    geo_xy <- matrix(c(3, -5), ncol = 2)
    extr_bilinear <- ds$pixel_extract(geo_xy, 1, "bilinear", 2, "")
    expect_equal(extr_bilinear[1], 1.5, tolerance = 1e-6)

    geo_xy <- matrix(c(3, -4.6), ncol = 2)
    extr_bilinear <- ds$pixel_extract(geo_xy, 1, "bilinear", 2, "")
    expect_equal(extr_bilinear[1], 1.5, tolerance = 1e-6)

    ds$close()
})

test_that("pixel extract internal class method - all pixels in a kernel", {
    ds <- create(format="MEM", dst_filename="", xsize=6, ysize=5,
                 nbands=1, dataType="Float32", return_obj=TRUE)

    raster_data <- c(1, 2, 4, 4, 5, 6,
                     9, 8, 7, 6, 3, 4,
                     4, 7, 6, 2, 1, 3,
                     7, 8, 9, 6, 2, 1,
                     2, 5, 2, 1, 7, 8)

    ds$write(band = 1, xoff = 0, yoff = 0, xsize = 6, ysize = 5, raster_data)

    ds$quiet <- TRUE

    geo_xy <- matrix(c(1.5, -1.5), ncol = 2)
    extr_krnl <- ds$pixel_extract(geo_xy, 1, "near", 3, "")
    expected_names <- c("b1_p1", "b1_p2", "b1_p3", "b1_p4", "b1_p5", "b1_p6",
                        "b1_p7", "b1_p8", "b1_p9")
    expected_values <- c(1, 2, 4, 9, 8, 7, 4, 7, 6)
    expect_true(is.matrix(extr_krnl))
    expect_equal(dim(extr_krnl), c(1, 9))
    expect_equal(colnames(extr_krnl), expected_names)
    colnames(extr_krnl) <- NULL
    dim(extr_krnl) <- NULL
    expect_equal(extr_krnl, expected_values)

    geo_xy <- matrix(c(4.6, -3.5), ncol = 2)
    extr_krnl <- ds$pixel_extract(geo_xy, 1, "near", 3, "")
    expected_values <- c(2, 1, 3, 6, 2, 1, 1, 7, 8)
    colnames(extr_krnl) <- NULL
    dim(extr_krnl) <- NULL
    expect_equal(extr_krnl, expected_values)

    # portion of kernel outside the raster extent
    # note that the public wrapper in gdalraster_proc.R handles this case
    # with additional tests in test-gdalraster_proc.R
    geo_xy <- matrix(c(0, 0), ncol = 2)
    extr_krnl <- ds$pixel_extract(geo_xy, 1, "near", 3, "")
    colnames(extr_krnl) <- NULL
    expect_true(all(is.na(extr_krnl)))

    geo_xy <- matrix(c(5, -3.5), ncol = 2)
    extr_krnl <- ds$pixel_extract(geo_xy, 1, "near", 3, "")
    colnames(extr_krnl) <- NULL
    expect_true(all(is.na(extr_krnl)))

    ds$close()
})

test_that("pixel extract cubic/cublicspline interpolation", {
    # Requires GDAL >= 3.10
    # Tests adapted from:
    #    gdal/autotest/gcore/interpolateatpoint.py
    #    Copyright (c) 2024, Javier Jimenez Shaw <j1@jimenezshaw.com>
    #    SPDX-License-Identifier: MIT

    skip_if(gdal_version_num() < 3100000)

    ds <- create(format="MEM", dst_filename="", xsize=4, ysize=4,
                 nbands=1, dataType="Float32", return_obj=TRUE)

    raster_data <- c(1.0, 2.0, 1.5, -0.3,
                     1.0, 2.0, 1.5, -0.3,
                     1.0, 2.0, 1.5, -0.3,
                     1.0, 2.0, 1.5, -0.3)

    ds$write(band = 1, xoff = 0, yoff = 0, xsize = 4, ysize = 4, raster_data)

    ds$quiet <- TRUE

    geo_xy <- matrix(c(1.5, -1.5), ncol = 2)
    extr_cubicspline <- ds$pixel_extract(geo_xy, 1, "cubicspline", 4, "")
    expect_equal(extr_cubicspline[1], 1.75, tolerance = 1e-6)

    extr_cubic <- ds$pixel_extract(geo_xy, 1, "cubic", 4, "")
    expect_equal(extr_cubic[1], 2.0, tolerance = 1e-6)

    geo_xy <- matrix(c(2.0, -2.0), ncol = 2)
    extr_cubicspline <- ds$pixel_extract(geo_xy, 1, "cubicspline", 4, "")
    expect_equal(extr_cubicspline[1], 1.6916666, tolerance = 1e-6)

    extr_cubic <- ds$pixel_extract(geo_xy, 1, "cubic", 4, "")
    expect_equal(extr_cubic[1], 1.925, tolerance = 1e-6)

    # cubic may exceed the highest value
    geo_xy <- matrix(c(1.6, -1.5), ncol = 2)
    extr_cubic <- ds$pixel_extract(geo_xy, 1, "cubic", 4, "")
    expect_equal(extr_cubic[1], 2.0166, tolerance = 1e-6)

    ds$close()
})

test_that("raster dimensions multiply without int overflow", {
    f <- "/vsimem/file.tif"
    ds <- create("GTiff", f, 86400, 43200, nbands = 1, dataType = "Byte",
                 options = c("SPARSE_OK=YES"), return_obj = TRUE)

    dm <- ds$dim()
    expect_no_warning(dm[1] * dm[2])  # no warning for NAs produced by overflow
    expect_equal(dm[1] * dm[2], 3732480000)

    xsize <- ds$getRasterXSize()
    ysize <- ds$getRasterYSize()
    expect_no_warning(xsize * ysize)
    expect_equal(xsize * ysize, 3732480000)

    ds$close()
    vsi_unlink(f)
})

test_that("get block indexing works", {
    elev_file <- system.file("extdata/storml_elev_orig.tif", package="gdalraster")
    ds <- new(GDALRaster, elev_file)

    values_expected <- read_ds(ds)
    attributes(values_expected) <- NULL

    blocks <- ds$get_block_indexing(1)
    values <- integer()
    for (i in seq_len(nrow(blocks))) {
        values <- c(values, ds$read(1, blocks[i, "xoff"], blocks[i, "yoff"],
                                    blocks[i, "xsize"], blocks[i, "ysize"],
                                    blocks[i, "xsize"], blocks[i, "ysize"]))
    }
    expect_equal(values, values_expected)

    ds$close()

    f <- tempfile(fileext = ".tif")
    on.exit(deleteDataset(f), add = TRUE)
    opt <- c("TILED=YES", "BLOCKXSIZE=128", "BLOCKYSIZE=128", "COMPRESS=LZW")
    ds2 <- create(format = "GTiff", dst_filename = f, xsize = 671, ysize = 528,
                  nbands = 1, dataType = "Byte", options = opt,
                  return_obj = TRUE)
    ds2$setGeoTransform(c(0.0, 5.0, 0.0, 5.0, 0.0, -5.0))
    blocks <- ds2$get_block_indexing(1)
    expect_equal(nrow(blocks), 30)
    colnames(blocks) <- NULL
    expect_equal(blocks[1, ], c(0, 0, 0, 0, 128, 128, 0, 640, -635, 5))
    expect_equal(blocks[30, ], c(5, 4, 640, 512, 31, 16, 3200, 3355, -2635, -2555))

    ds2$close()
})

test_that("readBlock/writeBlock work", {
    f <- tempfile(fileext = ".tif")
    on.exit(deleteDataset(f), add = TRUE)
    opt <- c("TILED=YES", "BLOCKXSIZE=32", "BLOCKYSIZE=32", "COMPRESS=LZW")
    ds <- create(format = "GTiff", dst_filename = f, xsize = 90, ysize = 80,
                 nbands = 1, dataType = "Byte", options = opt,
                 return_obj = TRUE)
    ds$setGeoTransform(c(0.0, 5.0, 0.0, 5.0, 0.0, -5.0))

    # fill with 1
    ds$fillRaster(band = 1, 1, 0)
    ds$flushCache()

    ## read back
    # first block of first row
    values <- ds$readBlock(band = 1, xblockoff = 0, yblockoff = 0)
    expect_equal(length(values), 32 * 32)
    expect_true(all(values == 1))

    # right edge of first row
    values <- ds$readBlock(band = 1, xblockoff = 2, yblockoff = 0)
    expect_equal(length(values), 26 * 32)
    expect_true(all(values == 1))

    # bottom right corner
    values <- ds$readBlock(band = 1, xblockoff = 2, yblockoff = 2)
    expect_equal(length(values), 26 * 16)
    expect_true(all(values == 1))

    ## write blocks
    # second block of first row
    values <- rep(10, 32 * 32)
    expect_no_error(ds$writeBlock(band = 1, xblockoff = 1, yblockoff = 0,
                                  values))
    # right edge of second row
    values <- rep(20, 26 * 32)
    expect_no_error(ds$writeBlock(band = 1, xblockoff = 2, yblockoff = 1,
                                  values))
    # bottom right corner
    values <- rep(30, 26 * 16)
    expect_no_error(ds$writeBlock(band = 1, xblockoff = 2, yblockoff = 2,
                                  values))

    ds$close()

    ## expect errors on closed dataset
    expect_error(ds$writeBlock(band = 1, xblockoff = 2, yblockoff = 2,
                               values))
    expect_error(ds$readBlock(band = 1, xblockoff = 0, yblockoff = 0))

    ## open a new dataset on the file and read back
    ds2 <- new(GDALRaster, f)

    # first block of first row, unchanged
    values <- ds2$readBlock(band = 1, xblockoff = 0, yblockoff = 0)
    expect_equal(length(values), 32 * 32)
    expect_true(all(values == 1))

    # second block of first row
    values <- ds2$readBlock(band = 1, xblockoff = 1, yblockoff = 0)
    expect_equal(length(values), 32 * 32)
    expect_true(all(values == 10))

    # right edge of first row, unchanged
    values <- ds2$readBlock(band = 1, xblockoff = 2, yblockoff = 0)
    expect_equal(length(values), 26 * 32)
    expect_true(all(values == 1))

    # right edge of second row
    values <- ds2$readBlock(band = 1, xblockoff = 2, yblockoff = 1)
    expect_equal(length(values), 26 * 32)
    expect_true(all(values == 20))

    # bottom right corner
    values <- ds2$readBlock(band = 1, xblockoff = 2, yblockoff = 2)
    expect_equal(length(values), 26 * 16)
    expect_true(all(values == 30))

    ## test input validation
    expect_error(ds2$readBlock(band = 5, xblockoff = 0, yblockoff = 0))
    expect_error(ds2$readBlock(band = 1, xblockoff = -1, yblockoff = 0))
    expect_error(ds2$readBlock(band = 1, xblockoff = 0, yblockoff = -1))

    ds2$open(read_only = FALSE)

    values <- rep(10, 32 * 32)
    expect_error(ds2$writeBlock(band = 5, xblockoff = 0, yblockoff = 0,
                                values))
    expect_error(ds2$writeBlock(band = 1, xblockoff = -1, yblockoff = 0,
                                values))
    expect_error(ds2$writeBlock(band = 1, xblockoff = 0, yblockoff = -1,
                                values))

    # size of input pixel data
    expect_no_error(ds2$writeBlock(band = 1, xblockoff = 0, yblockoff = 0,
                                   values))
    values <- rep(10, 26 * 32)
    expect_error(ds2$writeBlock(band = 1, xblockoff = 0, yblockoff = 0,
                                values))

    ds2$close()
})

test_that("make_chunk_index/readChunk/writeChunk work", {
    f <- tempfile(fileext = ".tif")
    on.exit(deleteDataset(f), add = TRUE)
    opt <- c("TILED=YES", "BLOCKXSIZE=32", "BLOCKYSIZE=32", "COMPRESS=LZW")
    ds <- create(format = "GTiff", dst_filename = f, xsize = 90, ysize = 80,
                 nbands = 1, dataType = "Byte", options = opt,
                 return_obj = TRUE)
    ds$setGeoTransform(c(0.0, 5.0, 0.0, 5.0, 0.0, -5.0))

    # fill with 1
    ds$fillRaster(band = 1, 1, 0)
    ds$flushCache()

    bb <- ds$bbox()

    ## index for a chunk size of two consecutive blocks (< blocks_per_row)
    chunks <- ds$make_chunk_index(band = 1, max_pixels = 2 * 32 * 32)
    expect_true(is.matrix(chunks))
    expect_equal(ncol(chunks), 10)
    expect_equal(nrow(chunks), 6)
    # upper left corner chunk
    expect_equal(unname(chunks[1, 1:4]), c(0 ,0, 0, 0))
    expect_equal(unname(chunks[1, "xsize"]), 64)
    expect_equal(unname(chunks[1, "ysize"]), 32)
    expect_equal(unname(chunks[1, "xmin"]), bb[1])
    expect_equal(unname(chunks[1, "ymax"]), bb[4])
    # lower right corner chunk
    expect_equal(unname(chunks[6, 1:4]), c(1, 2, 64, 64))
    expect_equal(unname(chunks[6, "xsize"]), 26)
    expect_equal(unname(chunks[6, "ysize"]), 16)
    expect_equal(unname(chunks[6, "xmax"]), bb[3])
    expect_equal(unname(chunks[6, "ymin"]), bb[2])

    ## index for a chunk size of three consecutive blocks (> blocks_per_row)
    chunks <- ds$make_chunk_index(band = 1, max_pixels = 3 * 32 * 32)
    expect_true(is.matrix(chunks))
    expect_equal(ncol(chunks), 10)
    expect_equal(nrow(chunks), 3)
    # upper left corner chunk
    expect_equal(unname(chunks[1, "xmin"]), bb[1])
    expect_equal(unname(chunks[1, "ymax"]), bb[4])
    # lower right corner chunk
    expect_equal(unname(chunks[3, "xmax"]), bb[3])
    expect_equal(unname(chunks[3, "ymin"]), bb[2])

    expected_names <- c("xchunkoff", "ychunkoff", "xoff", "yoff", "xsize",
                        "ysize", "xmin", "xmax", "ymin", "ymax")
    expect_equal(colnames(chunks), expected_names)

    expected_values <- c(0, 0, 0,  0, 90, 32, 0, 450, -155,    5,
                         0, 1, 0, 32, 90, 32, 0, 450, -315, -155,
                         0, 2, 0, 64, 90, 16, 0, 450, -395, -315)
    expected_values <- matrix(expected_values, nrow = 3, ncol = 10,
                              byrow = TRUE)
    expect_equal(unname(chunks), unname(expected_values))

    ## read back
    values <- ds$readChunk(band = 1, chunks[1, ])
    expect_equal(length(values), 90 * 32)
    expect_true(all(values == 1))
    values <- ds$readChunk(band = 1, chunks[2, ])
    expect_equal(length(values), 90 * 32)
    expect_true(all(values == 1))
    values <- ds$readChunk(band = 1, chunks[3, ])
    expect_equal(length(values), 90 * 16)
    expect_true(all(values == 1))

    ## write chunks
    values <- rep(10, 90 * 32)
    expect_no_error(ds$writeChunk(band = 1, chunks[1, ], values))
    values <- rep(20, 90 * 32)
    expect_no_error(ds$writeChunk(band = 1, chunks[2, ], values))
    values <- rep(30, 90 * 16)
    expect_no_error(ds$writeChunk(band = 1, chunks[3, ], values))

    ds$close()

    ## expect errors on closed dataset
    expect_error(ds$writeChunk(band = 1, chunks[3, ], values))
    expect_error(ds$readChunk(band = 1, chunks[1, ]))

    ## open a new dataset on the file and read back
    ds2 <- new(GDALRaster, f)

    values <- ds2$readChunk(band = 1, chunks[1, ])
    expect_equal(length(values), 90 * 32)
    expect_true(all(values == 10))
    values <- ds2$readChunk(band = 1, chunks[2, ])
    expect_equal(length(values), 90 * 32)
    expect_true(all(values == 20))
    values <- ds2$readChunk(band = 1, chunks[3, ])
    expect_equal(length(values), 90 * 16)
    expect_true(all(values == 30))

    # chunk_def as length-4 vector of xoff, yoff, xsize, ysize
    values <- 0
    expect_no_error(values <- ds2$readChunk(band = 1, chunks[1, 3:6]))
    expect_equal(length(values), 90 * 32)
    expect_true(all(values == 10))
    values <- 0
    expect_no_error(values <- ds2$readChunk(band = 1, c(0, 32, 90, 32)))
    expect_equal(length(values), 90 * 32)
    expect_true(all(values == 20))

    ## test input validation
    expect_error(ds2$readChunk(band = 5, chunks[1, ]))
    expect_error(ds2$readChunk(band = 1, matrix(numeric(0))))
    expect_error(ds2$readChunk(band = 1, chunks[1, 1:2]))
    expect_error(ds2$readChunk(band = 1, chunks[1, 1:5]))

    ds2$open(read_only = FALSE)

    values <- rep(10, 90 * 32)
    expect_error(ds2$writeChunk(band = 5, chunks[1, ], values))
    expect_error(ds2$writeChunk(band = 1, matrix(numeric(0)), values))
    expect_error(ds2$writeChunk(band = 1, chunks[1, 1:2], values))
    expect_error(ds2$writeChunk(band = 1, chunks[1, 1:5], values))

    # size of input pixel data
    expect_no_error(ds2$writeChunk(band = 1, chunks[1, ], values))
    values <- rep(10, 90 * 16)
    expect_error(ds2$writeChunk(band = 1, chunks[1, ], values))

    ds2$close()
})

test_that("getMinMaxLocation works", {
    skip_if(gdal_version_num() < gdal_compute_version(3, 11, 0))

    f <- system.file("extdata/byte.tif", package="gdalraster")
    ds <- new(GDALRaster, f)

    ret <- ds$getMinMaxLocation(band = 1)
    expected <- c(74, 9, 17, 441290.0, 3750270.0, -117.63581, 33.89293,
                  255, 2, 18, 440870.0, 3750210.0, -117.64035, 33.89237)
    expect_equal(unname(ret), expected, tolerance = 0.01)

    ds$close()

    ds <- create(format = "MEM", dst_filename = "", xsize = 2, ysize = 2,
                 nbands = 1, dataType = "Float32", return_obj = TRUE)
    ds$fillRaster(1, NaN, 0)

    ret <- ds$getMinMaxLocation(band = 1)
    expect_true(all(is.na(ret)))

    ds$close()
})

test_that("read to nativeRaster works", {
    gray_file <- system.file("extdata/geomatrix.tif", package="gdalraster")
    ds <- new(GDALRaster, gray_file)
    r1 <- ds$readToNativeRaster(0, 0, 10, 12, 20, 24)
    r1_1 <- read_to_nativeRaster(ds, xsize = 10, ysize = 12, out_xsize = 20,
                                 out_ysize =  24)
    expect_true(identical(r1, r1_1))

    expect_true(all(dim(r1) == c(24, 20)))
    expect_s3_class(r1, "nativeRaster")
    expect_true(attr(r1, "channels") == 3)
    r2 <- ds$readToNativeRaster(0, 0, ds$getRasterXSize(), ds$getRasterYSize(),
                                ds$getRasterXSize(), ds$getRasterYSize())
    r2_2 <- read_to_nativeRaster(ds)
    expect_true(identical(r2, r2_2))

    expect_true(unique(dim(r2)) == 20)
    expect_s3_class(r2, "nativeRaster")
    expect_true(attr(r2, "channels") == 3)

    ds$close()

    ## we are >= 3.1.0 so we can assume vrt://...?bands=
    ds <- new(GDALRaster, sprintf("vrt://%s?bands=1,1,1", gray_file))
    r3 <- ds$readToNativeRaster(0, 0, 20, 20, 20, 20)
    expect_true(attr(r3, "channels") == 3)
    r4 <- read_to_nativeRaster(ds)
    expect_true(attr(r4, "channels") == 3)
    ds$close()
})

test_that("/vsistdout/ redirection works", {
    f <- system.file("extdata/ynp_features.zip", package = "gdalraster")
    zf_gpkg <- file.path("/vsizip", f, "ynp_features.gpkg")

    expected_output <- 'X,Y,poiname,poitype,createdate,editdate
-110.692921344,44.7390491040001,Norris Campground Loop C Comfort Station,Flush Toilet,2024/02/23,2024/02/23
-110.157825952,44.4784871940001,Sylvan Lake Picnic Area Vault Toilet,Vault Toilet,2024/02/23,2024/02/23
-110.182290061,44.324319185,"5E1",Campsite,2015/12/30,2018/06/13
-110.386556517,44.8907427240001,Tower Fall Parking Area Northern End Vault Toilet,Vault Toilet,2024/02/23,2024/02/23
-110.826393985,44.5316894210001,,Parking Lot,2016/02/22,2020/09/21
-110.570605761,44.41759791,Big Cone,Geyser,2016/02/17,2018/06/13
-110.450915693,44.948928046,,Parking Lot,2016/02/22,2020/09/21
-110.860329219,44.61843165,Firehole Canyon Swimming Area Vault Toilet,Vault Toilet,2024/02/23,2024/02/23
-110.800428191,44.535760318,Surprise Pool,Geyser,2016/09/13,2018/06/13
-110.235181696,44.6354910580001,The Mudkettles,Geyser,2015/11/27,2018/06/13'

    expect_output(
        ogr2ogr(zf_gpkg, "/vsistdout/", "points_of_interest",
                c("-f", "CSV", "-lco", "GEOMETRY=AS_XY", "-limit", 10)),
        expected_output)

    skip_if(gdal_version_num() < gdal_compute_version(3, 11, 3))
    skip_if(length(gdal_global_reg_names()) == 0)  # GDAL CLI bindings availability

    expected_output <- 'admn_type,state_fips,state_name,sub_region
"Park, monument, etc.",56,Wyoming,Mtn'

    expect_output(
        gdal_run_piped(zf_gpkg, "vector sql", "/vsistdout/", "CSV",
                       list(sql = "SELECT * FROM ynp_bnd")),
        expected_output)
})

test_that("show() escapes braces and shortens a long DSN", {
    elev_file <- system.file("extdata/storml_elev.tif", package="gdalraster")

    # braces in a DSN are printed literally, not interpreted by cli
    f <- "/vsimem/show_{braces}.tif"
    on.exit(vsi_unlink(f), add = TRUE)
    translate(elev_file, f, quiet = TRUE)
    ds <- new(GDALRaster, f)
    out <- paste(capture_messages(show(ds)), collapse = "")
    expect_match(out, "\"/vsimem/show_{braces}.tif\"", fixed = TRUE)
    ds$close()

    # a long DSN is shortened in the middle, keeping the file name
    f2 <- paste0("/vsimem/", strrep("d", 100), "/storml_elev.tif")
    on.exit(vsi_unlink(f2), add = TRUE)
    translate(elev_file, f2, quiet = TRUE)
    ds <- new(GDALRaster, f2)
    out <- paste(capture_messages(show(ds)), collapse = "")
    expect_match(out, "\"/vsimem/d+\\.\\.\\.d+/storml_elev\\.tif\"")
    expect_no_match(out, strrep("d", 100), fixed = TRUE)
    ds$close()
})
