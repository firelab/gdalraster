## Creates inst/extdata/mdim_small.nc, a small multidimensional test dataset
## (netCDF-4) for class GDALMultiDimRaster.
##
## A multidimensional VRT is written with inline values, then converted to
## netCDF with mdim_translate(). Contents:
## * root group attributes of type string, Int32 and Float64
## * dimensions time (4), lat (5), lon (6), each with an indexing variable
## * time in "hours since 2000-01-01 00:00:00", calendar "standard"
## * t2m: Int16 (time, lat, lon) with unit, nodata, scale and offset, a string
##   attribute and a two-valued Int16 attribute (valid_range)
## * sub-group /ocean with a string attribute and array sst: Float32
##   (time, lat, lon) referencing the dimensions of the root group
##
## Run from the package root directory: Rscript data-raw/mdim_small.R

library(gdalraster)

nt <- 4
ny <- 5
nx <- 6
time <- c(0, 6, 12, 18)
lat <- seq(-41, -42, by = -0.25)
lon <- seq(145, 146.25, by = 0.25)

## stored values, time slowest, lon fastest (C order)
t2m <- as.integer(round(outer(seq_len(ny * nx), seq_len(nt),
                              function(i, k) 1185 + 100 * k + 10 * i)))
t2m[3] <- -32767L
sst <- round(t2m * 0.01 + 1, 2)
sst[c(1, 2)] <- -999

attr_xml <- function(name, type, values) {
    paste0('<Attribute name="', name, '"><DataType>', type, '</DataType>',
           paste0('<Value>', values, '</Value>', collapse = ""),
           '</Attribute>')
}

v <- function(x) paste(format(x, scientific = FALSE, trim = TRUE),
                       collapse = " ")

inline <- function(x) {
    paste0('<InlineValues offset="0,0,0" count="', nt, ',', ny, ',', nx,
           '">', v(x), '</InlineValues>')
}

xml <- c(
    '<VRTDataset>',
    '<Group name="/">',
    paste0('<Dimension name="time" type="TEMPORAL" size="', nt,
           '" indexingVariable="time"/>'),
    paste0('<Dimension name="lat" type="HORIZONTAL_Y" direction="NORTH" ',
           'size="', ny, '" indexingVariable="lat"/>'),
    paste0('<Dimension name="lon" type="HORIZONTAL_X" direction="EAST" ',
           'size="', nx, '" indexingVariable="lon"/>'),
    attr_xml("Conventions", "String", "CF-1.8"),
    attr_xml("title", "String", "gdalraster multidim test dataset"),
    attr_xml("version", "Int32", 1),
    attr_xml("resolution", "Float64", 0.25),

    '<Array name="time"><DataType>Float64</DataType>',
    '<DimensionRef ref="time"/>',
    attr_xml("units", "String", "hours since 2000-01-01 00:00:00"),
    attr_xml("calendar", "String", "standard"),
    attr_xml("standard_name", "String", "time"),
    paste0('<InlineValues>', v(time), '</InlineValues></Array>'),

    '<Array name="lat"><DataType>Float64</DataType>',
    '<DimensionRef ref="lat"/>',
    attr_xml("units", "String", "degrees_north"),
    attr_xml("standard_name", "String", "latitude"),
    paste0('<InlineValues>', v(lat), '</InlineValues></Array>'),

    '<Array name="lon"><DataType>Float64</DataType>',
    '<DimensionRef ref="lon"/>',
    attr_xml("units", "String", "degrees_east"),
    attr_xml("standard_name", "String", "longitude"),
    paste0('<InlineValues>', v(lon), '</InlineValues></Array>'),

    '<Array name="t2m"><DataType>Int16</DataType>',
    '<DimensionRef ref="time"/><DimensionRef ref="lat"/>',
    '<DimensionRef ref="lon"/>',
    '<Unit>degC</Unit><NoDataValue>-32767</NoDataValue>',
    '<Offset>0</Offset><Scale>0.01</Scale>',
    attr_xml("long_name", "String", "2 metre temperature"),
    attr_xml("valid_range", "Int16", c(-5000, 5000)),
    inline(t2m),
    '</Array>',

    '<Group name="ocean">',
    attr_xml("source", "String", "synthetic"),
    '<Array name="sst"><DataType>Float32</DataType>',
    '<DimensionRef ref="/time"/><DimensionRef ref="/lat"/>',
    '<DimensionRef ref="/lon"/>',
    '<Unit>degC</Unit><NoDataValue>-999</NoDataValue>',
    attr_xml("long_name", "String", "sea surface temperature"),
    inline(sst),
    '</Array>',
    '</Group>',

    '</Group>',
    '</VRTDataset>')

vrt_file <- tempfile(fileext = ".vrt")
writeLines(xml, vrt_file)

out_file <- file.path("inst", "extdata", "mdim_small.nc")
if (file.exists(out_file))
    unlink(out_file)
mdim_translate(vrt_file, out_file, output_format = "netCDF")
unlink(vrt_file)
