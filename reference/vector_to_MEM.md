# Create a GDAL in-memory dataset from R data without copying

`vector_to_MEM()` creates a GDAL MEM dataset that references pixel data
in an existing R vector. It returns an object of class `GDALRaster` for
a writable in-memory dataset without copying the source data. The
underlying R object is protected from garbage collection until the
returned dataset is closed. GDAL MEM datasets support most kinds of
auxiliary information including metadata, coordinate systems,
georeferencing, color interpretation, nodata, color tables and all pixel
data types (see Details).

## Usage

``` r
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

## Note

The `$close()` method should be called when the `GDALRaster` object is
no longer needed so that resources can be freed. MEM datasets cannot be
re-opened once the object's `$close()` method has been called.

## See also

[`GDALRaster-class`](https://firelab.github.io/gdalraster/reference/GDALRaster-class.md)

## Examples

``` r
v <- sample(0:255, 50, replace = TRUE)
(ds_mem <- vector_to_MEM(v, xsize = 10, ysize = 5))
#> failed to get projection ref
#> C++ object of class GDALRaster
#>  Driver : In Memory Raster (MEM)
#>  DSN    : MEM:::DATAPOINTER=0x560dc543b040,PIXELS=10,LINES=5,BANDS=1,DATATYPE=Int32,GEOTRANSFORM=0/1/0/0/0/1,BANDOFFSET=200
#>  Dim    : 10, 5, 1
#>  CRS    : 
#>  Res    : 1.000000, 1.000000
#>  Bbox   : 0.000000, 0.000000, 10.000000, 5.000000

all((ds_mem$read(1, 0, 0, 10, 5, 10, 5) == v))
#> [1] TRUE

ds_mem$write(1, 0, 0, 10, 5, (v * -1))
print(v)
#>  [1]  -10  -25  -21 -140 -112 -190 -227   -1 -179  -34 -176 -214 -189 -118  -20
#> [16] -183 -132 -135 -243 -201  -64 -135 -224  -47  -51  -78 -224  -11  -31  -77
#> [31] -195  -51 -124  -44  -81  -52 -188 -189  -42 -121  -75  -49 -132 -160  -63
#> [46] -166  -58 -109    0  -90

ds_mem$close()
```
