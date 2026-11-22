# Generate an index of chunk offsets and sizes for iterating an MDArray

`mdim_chunk_index()` returns a matrix of chunk indexes, start offsets
and sizes for iterating I/O operations over an array of a GDAL
Multidimensional Raster dataset, one row per chunk. It is the
multidimensional counterpart of
[`make_chunk_index()`](https://firelab.github.io/gdalraster/reference/make_chunk_index.md).
**This function is experimental**. Its interface may change in future
releases.

## Usage

``` r
mdim_chunk_index(x, chunk_size = NULL, start = NULL, count = NULL)
```

## Arguments

- x:

  Either an object of class
  [`GDALMDArray`](https://firelab.github.io/gdalraster/reference/GDALMDArray-class.md),
  or a numeric vector of dimension sizes (in the array's own dimension
  order).

- chunk_size:

  Optional numeric vector with the chunk size along each dimension. A
  value of `0` or `NA` means the whole dimension. By default, the block
  size of the array if `x` is a `GDALMDArray` object. Required if `x` is
  a vector of dimension sizes.

- start:

  Optional numeric vector of 0-based start indexes of a hyperslab, one
  value per dimension.

- count:

  Optional numeric vector giving the number of values of a hyperslab
  along each dimension. Required if `start` is given.

## Value

A numeric matrix with one row per chunk and, for an array of `n`
dimensions, `3 * n` named columns: `chunkoff0`, ..., `off0`, ...,
`size0`, ..., where the suffix is the 0-based dimension index.
`chunkoff` is the 0-based index of the chunk along the dimension, `off`
is its 0-based start index and `size` is its size. Columns `off` and
`size` of a row are the `start` and `count` arguments for
`GDALMDArray$read()`. Rows are ordered with the last dimension varying
fastest.

## Details

The chunks tile the array exactly, on a regular grid of `chunk_size`
starting at index `0` of each dimension. Chunks at the end of a
dimension are clipped to the array. By default, the chunks are the
blocks of the array as stored (see `$getBlockSize()` of class
[`GDALMDArray`](https://firelab.github.io/gdalraster/reference/GDALMDArray-class.md)),
so that each row is a read of exactly one stored block: one fetch and
one decode, the natural unit of cost for chunked formats such as Zarr,
netCDF-4 and HDF5. A `chunk_size` from `$getProcessingChunkSize()` gives
larger chunks, aligned to the blocks, that fit a memory limit.

If `start` and `count` are given, only the chunks that intersect that
hyperslab are returned (as whole chunks, i.e., not clipped to the
hyperslab). This gives the stored blocks that a planned read would
touch.

## See also

[GDALMDArray](https://firelab.github.io/gdalraster/reference/GDALMDArray-class.md),
[`make_chunk_index()`](https://firelab.github.io/gdalraster/reference/make_chunk_index.md),
[`mdim_read()`](https://firelab.github.io/gdalraster/reference/mdim_read.md)

## Examples

``` r
# dimension sizes and chunk sizes given directly
mdim_chunk_index(c(4, 5, 6), c(2, 5, 4))
#>      chunkoff0 chunkoff1 chunkoff2 off0 off1 off2 size0 size1 size2
#> [1,]         0         0         0    0    0    0     2     5     4
#> [2,]         0         0         1    0    0    4     2     5     2
#> [3,]         1         0         0    2    0    0     2     5     4
#> [4,]         1         0         1    2    0    4     2     5     2

# the chunks that a hyperslab read would touch
mdim_chunk_index(c(4, 5, 6), c(2, 5, 4), start = c(1, 0, 3),
                 count = c(1, 5, 1))
#>      chunkoff0 chunkoff1 chunkoff2 off0 off1 off2 size0 size1 size2
#> [1,]         0         0         0    0    0    0     2     5     4

# iterate over an array in chunks that fit a memory limit (here 120 bytes,
# i.e., 60 values of Int16)
f <- system.file("extdata/mdim_small.nc", package="gdalraster")
ds <- new(GDALMultiDimRaster, f)
arr <- ds$openMDArray("/t2m")
idx <- mdim_chunk_index(arr, arr$getProcessingChunkSize(120))
idx
#>      chunkoff0 chunkoff1 chunkoff2 off0 off1 off2 size0 size1 size2
#> [1,]         0         0         0    0    0    0     2     5     6
#> [2,]         1         0         0    2    0    0     2     5     6

off_cols <- startsWith(colnames(idx), "off")
size_cols <- startsWith(colnames(idx), "size")
chunk_max <- numeric(nrow(idx))
for (i in seq_len(nrow(idx))) {
  v <- arr$read(idx[i, off_cols], idx[i, size_cols], NULL)
  chunk_max[i] <- max(v, na.rm = TRUE)
}
chunk_max
#> [1] 1685 1885

arr$close()
ds$close()
```
