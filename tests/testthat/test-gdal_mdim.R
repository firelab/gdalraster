skip_if(gdal_version_num() < gdal_compute_version(3, 2, 0))
skip_if(nrow(gdal_formats("netCDF")) == 0 ||
            isFALSE(gdal_formats("netCDF")$multidim_raster))

test_that("mdim_as_classic works", {
    f <- system.file("extdata/byte.nc", package="gdalraster")

    ds <- mdim_as_classic(f, "Band1", 1, 0)
    expect_false(is.null(ds))
    expect_equal(ds$dim(), c(20, 20, 1))
    expect_equal(ds$getGeoTransform(),
                 c(440720.0, 60.0, 0.0, 3750120.0, 0.0, 60.0))

    # matches checksum from GDAL autotest:
    #   autotest/gdrivers/data/vrt/arraysource_array.vrt on byte.nc
    #   https://github.com/OSGeo/gdal/blob/a8f0531cc90bc1fb554da9f6a94d059dbb995f81/autotest/gdrivers/vrtmultidim.py#L1417
    #       ds = gdal.Open("data/vrt/arraysource_array.vrt")
    #       assert ds.GetRasterBand(1).Checksum() == 4855
    # and Python:
    #   from osgeo import gdal
    #   f = 'byte.nc'
    #   ds = gdal.OpenEx(f, gdal.OF_MULTIDIM_RASTER)
    #   rg = ds.GetRootGroup()
    #   ar = rg.OpenMDArray("Band1")
    #   classic_ds = ar.AsClassicDataset(1, 0)
    #   classic_ds.GetRasterBand(1).Checksum()
    #   # 4855
    expect_equal(ds$getChecksum(1, 0, 0, 20, 20), 4855)

    ds$close()
    # filename is not set / driver-less dataset:
    expect_error(ds$open(read_only = TRUE))

    # view expressions
    f2 <- tempfile(fileext = ".nc")
    on.exit(unlink(f2), add = TRUE)
    file.copy(f, f2, overwrite = TRUE)

    ds <- mdim_as_classic(f2, "Band1", 1, 0, read_only = FALSE,
                          view_expr = "[0:10,...]")

    # https://github.com/OSGeo/gdal/blob/2b1c4d1fdb9377b62d821d70d022e7426940aec6/autotest/gdrivers/netcdf_multidim.py#L4036
    expect_equal(ds$getStatistics(1, FALSE, TRUE),
                 c(74.0, 255.0, 126.82, 26.729713803182),
                 tolerance = 0.01)

    ds$close()

    ds <- mdim_as_classic(f2, "Band1", 1, 0, read_only = FALSE,
                          view_expr = "[10:20,...]")

    # https://github.com/OSGeo/gdal/blob/2b1c4d1fdb9377b62d821d70d022e7426940aec6/autotest/gdrivers/netcdf_multidim.py#L4042
    expect_equal(ds$getStatistics(1, FALSE, TRUE),
                 c(99.0, 206.0, 126.71, 18.356086184152),
                 tolerance = 0.01)

    ds$close()
})

test_that("mdim_info works", {
    f <- system.file("extdata/byte.nc", package="gdalraster")

    expect_output(mdim_info(f))
    expect_silent(mdim_info(f, cout = FALSE))
    
    expect_no_error(info <- mdim_info(f, array_options = "SHOW_ALL=YES"))
    expect_vector(info, ptype = character(), size = 1)
    expect_true(startsWith(info, "{"))
    expect_true(nchar(info) > 1000)

    expect_no_error(
        info <- mdim_info(f, "Band1", pretty = FALSE, detailed = TRUE,
                          limit = 5, allowed_drivers = "netCDF",
                          open_options = "HONOUR_VALID_RANGE=NO"))

    expect_vector(info, ptype = character(), size = 1)
    expect_true(startsWith(info, "{"))
    expect_true(nchar(info) > 1000)
})

test_that("mdim_translate works", {
    skip_if(gdal_version_num() < gdal_compute_version(3, 8, 0))

    f <- system.file("extdata/byte.nc", package="gdalraster")

    f2 <- tempfile(fileext = ".nc")
    on.exit(deleteDataset(f2), add = TRUE)

    opt <- NULL
    if (isTRUE(gdal_get_driver_md("netCDF")$NETCDF_HAS_HDF4 == "YES"))
        opt <- "ARRAY:IF(NAME=Band1):COMPRESS=DEFLATE"

    ar <- "name=Band1,view=[10:20,...]"
    expect_true(res <- mdim_translate(f, f2,
                                      creation_options = opt,
                                      array_specs = ar,
                                      allowed_drivers = c("HDF5", "netCDF"),
                                      open_options = "HONOUR_VALID_RANGE=NO",
                                      quiet = TRUE))

    ds <- mdim_as_classic(f2, "Band1", 1, 0, read_only = FALSE)
    expect_equal(ds$dim(), c(20, 10, 1))

    ds$close()

    f3 <- tempfile(fileext = ".nc")
    on.exit(deleteDataset(f3), add = TRUE)

    expect_true(mdim_translate(f, f3, group_specs = "name=/"))

    ds <- mdim_as_classic(f3, "Band1", 1, 0)
    expect_equal(ds$dim(), c(20, 20, 1))

    ds$close()

    f4 <- tempfile(fileext = ".nc")
    on.exit(deleteDataset(f4), add = TRUE)

    subsets <- c("x(441000,441800)", "y(3750400,3751000)")
    expect_true(mdim_translate(f, f4, subset_specs = subsets))

    ds <- mdim_as_classic(f4, "Band1", 1, 0)
    expect_equal(ds$dim(), c(13, 10, 1))

    ds$close()

    f5 <- tempfile(fileext = ".nc")
    on.exit(deleteDataset(f5), add = TRUE)

    expect_true(mdim_translate(f, f5, scaleaxes_specs = "x(2),y(2)"))

    ds <- mdim_as_classic(f5, "Band1", 1, 0)
    expect_equal(ds$dim(), c(10, 10, 1))

    ds$close()
})

test_that("mdim_read works", {
    f <- system.file("extdata/mdim_small.nc", package="gdalraster")

    # by filename, the whole array
    v <- mdim_read(f, "/t2m")
    expect_type(v, "integer")
    expect_length(v, 120)
    expect_null(dim(v))
    gis <- attr(v, "gis")
    expect_equal(names(gis),
                 c("type", "dim", "dim_names", "coords", "bbox", "srs",
                   "datatype", "nodata", "scale", "offset", "unit",
                   "dim_units", "calendar"))
    expect_equal(gis$type, "multidim")
    expect_equal(gis$dim, c(6, 5, 4))
    expect_equal(gis$dim_names, c("lon", "lat", "time"))
    expect_equal(names(gis$coords), c("lon", "lat", "time"))
    expect_equal(gis$coords$lon, seq(145, 146.25, by = 0.25))
    expect_equal(gis$coords$lat, seq(-41, -42, by = -0.25))
    expect_equal(gis$coords$time, c(0, 6, 12, 18))
    expect_equal(gis$bbox, c(144.875, -42.125, 146.375, -40.875))
    expect_equal(gis$datatype, "Int16")
    expect_equal(gis$nodata, -32767)
    expect_equal(gis$scale, 0.01)
    expect_equal(gis$offset, 0)
    expect_equal(gis$unit, "degC")
    expect_equal(gis$dim_units,
                 c("degrees_east", "degrees_north",
                   "hours since 2000-01-01 00:00:00"))
    expect_equal(gis$calendar, "standard")

    # from an open dataset, a hyperslab as an R array [lon, lat, time]
    ds <- new(GDALMultiDimRaster, f)
    a <- mdim_read(ds, "/t2m", start = c(1, 1, 2), count = c(2, 3, 4),
                   as_array = TRUE)
    expect_equal(dim(a), c(4, 3, 2))
    full <- array(mdim_read(ds, "/t2m"), dim = c(6, 5, 4))
    expect_identical(a[, , ], full[3:6, 2:4, 2:3])
    gis <- attr(a, "gis")
    expect_equal(gis$coords$lon, seq(145.5, 146.25, by = 0.25))
    expect_equal(gis$coords$lat, c(-41.25, -41.5, -41.75))
    expect_equal(gis$coords$time, c(6, 12))
    expect_equal(gis$bbox, c(145.375, -41.875, 146.375, -41.125))

    # step, with count computed from start and step
    v <- mdim_read(ds, "/t2m", step = c(2, 2, 2))
    gis <- attr(v, "gis")
    expect_equal(gis$dim, c(3, 3, 2))
    expect_equal(gis$coords$time, c(0, 12))
    expect_identical(as.vector(v), as.vector(full[c(1, 3, 5), c(1, 3, 5),
                                                  c(1, 3)]))

    # array in a sub-group, and a 1-D coordinate array
    v <- mdim_read(ds, "/ocean/sst")
    expect_type(v, "double")
    expect_true(is.na(attr(v, "gis")$scale))
    v <- mdim_read(ds, "/time")
    expect_equal(as.vector(v), c(0, 6, 12, 18))
    expect_true(all(is.na(attr(v, "gis")$bbox)))

    # srs from a projected array
    v <- mdim_read(system.file("extdata/byte.nc", package="gdalraster"),
                   "/Band1")
    expect_equal(attr(v, "gis")$bbox, c(440720, 3750120, 441920, 3751320))
    expect_true(nchar(attr(v, "gis")$srs) > 0)

    expect_error(mdim_read(ds, "/nope"), "array not found")
    expect_error(mdim_read(ds, "/t2m", start = c(0, 0)), "one value")
    expect_error(mdim_read(1, "/t2m"), "GDALMultiDimRaster")

    # the dataset is still open after reading
    expect_true(ds$isOpen())
    ds$close()
})
