# Raw block references of a multidimensional array

`mdim_block_refs()` returns the location of the stored blocks (chunks)
of an array of a GDAL Multidimensional Raster dataset: for each block,
the file that contains it, and the byte offset and size of the block in
that file. The blocks are not read or decoded. This is the information
needed to fetch the raw bytes of a block directly (e.g., with a byte
range request), or to build a table of references to the blocks of a set
of files (a "virtual" dataset in the style of kerchunk or VirtualiZarr).
Requires GDAL \>= 3.12. **This function is experimental**. Its interface
may change in future releases.

## Usage

``` r
mdim_block_refs(x, start = NULL, count = NULL)
```

## Arguments

- x:

  An object of class
  [`GDALMDArray`](https://firelab.github.io/gdalraster/reference/GDALMDArray-class.md).

- start:

  Optional numeric vector of 0-based start indexes of a hyperslab, one
  value per dimension.

- count:

  Optional numeric vector giving the number of values of a hyperslab
  along each dimension. Required if `start` is given.

## Value

A data frame with one row per block. For an array of `n` dimensions, the
first `3 * n` columns are those of
[`mdim_chunk_index()`](https://firelab.github.io/gdalraster/reference/mdim_chunk_index.md)
(`chunkoff0`, ..., `off0`, ..., `size0`, ...), followed by:

- `filename`: the file that contains the block, or `NA`

- `offset`: the offset in bytes of the block in that file, or `NA`

- `size`: the size in bytes of the block as stored, or `NA`

- `info`: list column of character vectors of driver-specific
  `NAME=VALUE` pairs that describe how the block is encoded

- `inline_data`: list column with a `raw` vector for a block that the
  dataset holds inline (`filename` and `offset` are then `NA`),
  otherwise `NULL`

A block that is missing in the dataset (all values are nodata) has `NA`
for `filename`, `offset` and `size`.

## Details

The blocks are those of
[`mdim_chunk_index()`](https://firelab.github.io/gdalraster/reference/mdim_chunk_index.md)
with the block size of the array as stored, optionally limited to the
blocks that intersect a hyperslab given by `start` and `count`. Their
locations are obtained with `$getRawBlockRefs()` of class
[`GDALMDArray`](https://firelab.github.io/gdalraster/reference/GDALMDArray-class.md)
(see that method for details of the values returned and the formats
supported).

The time needed depends on the format. For netCDF-4 and HDF5, the index
of blocks in the file is read once. For Zarr, each block is a file (or a
part of a file) that GDAL has to query, so a remote store takes one or
more network requests per block. Use `start` and `count` to limit the
number of blocks.

## See also

[GDALMDArray](https://firelab.github.io/gdalraster/reference/GDALMDArray-class.md),
[`mdim_chunk_index()`](https://firelab.github.io/gdalraster/reference/mdim_chunk_index.md),
[`mdim_read()`](https://firelab.github.io/gdalraster/reference/mdim_read.md)

## Examples

``` r
f <- system.file("extdata/mdim_small.nc", package="gdalraster")
ds <- new(GDALMultiDimRaster, f)
arr <- ds$openMDArray("/t2m")

# this array is stored as one block, not compressed
refs <- mdim_block_refs(arr)
refs[, c("filename", "offset", "size")]
#>                                                           filename offset size
#> 1 /home/runner/work/_temp/Library/gdalraster/extdata/mdim_small.nc   2040  240
refs$info[[1]]
#> [1] "ENDIANNESS=LITTLE"

# the bytes of the block, read directly from the file and decoded
con <- file(refs$filename[1], "rb")
invisible(seek(con, refs$offset[1]))
b <- readBin(con, "raw", n = refs$size[1])
close(con)
v <- readBin(b, "integer", n = length(b) / 2, size = 2, endian = "little")
v[v == arr$getNoDataValue()] <- NA

identical(v, arr$read(NULL, NULL, NULL))
#> [1] TRUE

arr$close()
ds$close()
```
