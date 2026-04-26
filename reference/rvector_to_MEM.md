# Create a GDAL in-memory dataset from R data without copying

`rvector_to_MEM()` creates a GDAL MEM dataset that references pixel data
in an existing R vector. It returns an object of class `GDALRaster` for
a writable in-memory dataset without copying the source data. The
underlying R object is protected from garbage collection until the
returned dataset is closed. GDAL MEM datasets support most kinds of
auxiliary information including metadata, coordinate systems,
georeferencing, color interpretation, nodata, color tables and all pixel
data types (see Details).

## Usage

``` r
rvector_to_MEM(
  data,
  xsize,
  ysize,
  nbands = 1L,
  gt = NULL,
  bbox = NULL,
  srs = NULL
)

vector_to_MEM(
  data,
  xsize,
  ysize,
  nbands = 1L,
  gt = NULL,
  bbox = NULL,
  srs = NULL
)
```

## Arguments

- data:

  An R vector of type `"double"`, `"integer"`, `"raw"` or `"complex"`,
  containing pixel values to be exposed as a GDAL in-memory raster. The
  pixels must be arranged in left-to-right, top-to-bottom order
  interleaved by band. `length(data)` must equal
  `xsize * ysize * nbands`.

- xsize:

  Integer value giving the number of raster columns.

- ysize:

  Integer value giving the number of raster rows.

- nbands:

  Integer value giving the number of raster bands.

- gt:

  A numeric vector of length six containing the affine geotransform for
  the raster. Defaults to `c(0, 1, 0, 0, 0, 1)` if neither `gt` nor
  `bbox` are given.

- bbox:

  A numeric vector of length four containing the raster bounding box
  geospatial coordinates (`c(xmin, ymin, xmax, ymax)`). Ignored if `gt`
  is given.

- srs:

  Optional character string containing the raster spatial reference
  coordinate system as a WKT string.
  [`epsg_to_wkt()`](https://firelab.github.io/gdalraster/reference/srs_convert.md)
  or
  [`srs_to_wkt()`](https://firelab.github.io/gdalraster/reference/srs_convert.md)
  can be used to convert from other formats to WKT if necessary.

## Value

An object of class `GDALRaster` providing a GDAL MEM dataset with write
access pointing to the underlying C array for `data`. The R object
referenced by `data` is protected from garbage collection during the
lifetime of the returned dataset, i.e., until its `$close()` is called
or the dataset object itself is garbage collected. An error is raised if
creation of the MEM dataset fails.

## Details

The returned dataset is open with write access. Methods of the
`GDALRaster` object can be called to modify dataset and band properties,
e.g., to set nodata values, metadata items, band descriptions, color
tables, etc. The original R vector will be modified in place if the
object's `$write()` method is used.

The MEM dataset will have a GDAL data type matching the type of the
input vector:

|                   |                              |
|-------------------|------------------------------|
| **R vector type** | **GDAL raster type**         |
| double            | Float64                      |
| integer           | Int32                        |
| raw               | UInt8 (Byte in GDAL \< 3.13) |
| complex           | CFloat64                     |

`vector_to_MEM()` is an alias of `rvector_to_MEM()` for backward
compatibility. It is a deprecated name of the function that will be
removed in a future version. Please use `rvector_to_MEM()` instead.

## Note

The `$close()` method should be called when the `GDALRaster` object is
no longer needed so that resources can be freed. MEM datasets cannot be
re-opened once the object's `$close()` method has been called.

`vector_to_MEM()` is a deprecated name for the function, currently set
as an alias of `rvector_to_MEM()`. *The `vector_to_MEM()` alias will be
removed in a future version*.

## See also

[`GDALRaster-class`](https://firelab.github.io/gdalraster/reference/GDALRaster-class.md)

## Examples

``` r
v <- sample(0:255, 50, replace = TRUE)
(ds_mem <- rvector_to_MEM(v, xsize = 10, ysize = 5))
#> C++ object of class <GDALRaster>
#>   • Driver: In Memory Raster (MEM)
#>   • DSN:
#>   "MEM:::DATAPOINTER=0x55c2189b96a0,PIXELS=10,LINES=5,BANDS=1,DATATYPE=Int32,GEOTRANSFORM=0/1/0/0/0/1,BANDOFFSET=200"
#>   • Dimensions: 10, 5, 1
#>   • CRS: not set
#>   • Pixel resolution: 1.000000, 1.000000
#>   • Bbox: 0.000000, 0.000000, 10.000000, 5.000000

all((ds_mem$read(1, 0, 0, 10, 5, 10, 5) == v))
#> [1] TRUE

ds_mem$write(1, 0, 0, 10, 5, (v * -1))
print(v)
#>  [1]  -46  -43 -196 -142 -124 -149 -196  -63 -111 -176  -53 -254 -202  -79 -141
#> [16] -148 -179  -64  -47 -151 -123 -245  -58  -31 -140 -211  -59 -125 -125  -75
#> [31] -156  -60 -132 -232 -177 -233 -179 -205  -47 -199 -201 -161 -249 -127  -42
#> [46] -157  -21 -250  -10  -25

ds_mem$close()
```
