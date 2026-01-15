# Get file and directory names matching a pattern that may contain wildcards

`vsi_glob()` returns a character vector of file and directory names
matching a pattern that can contain wildcards. This function has similar
behavior to the POSIX `glob()` function. Wrapper of `VSIGlob()` in the
GDAL Common Portability Library. Requires GDAL \>= 3.11.

## Usage

``` r
vsi_glob(pattern, show_progress = FALSE)
```

## Arguments

- pattern:

  Character string. The relative or absolute path of a directory to
  read, potentially containing wildcards, assumed to be UTF-8 encoded
  (see Details).

- show_progress:

  Logical scalar. If `TRUE`, a progress bar will be displayed. Default
  is `FALSE`.

## Value

A character vector containing the matching names of files and
directories.

## Details

The following wildcards are supported

- `*`: match any string

- `?`: match any single character

- `[`: match character class or range, with `!` immediately after `[` to
  indicate negation

Refer to to the `glob()` man page for more details
(<https://man7.org/linux/man-pages/man7/glob.7.html>). It also supports
the `**` recursive wildcard, behaving similarly to Python `glob.glob()`
with `recursive = True`. Be careful of the amount of memory and time
required when using the recursive wildcard on directories with a large
amount of files and subdirectories.

Examples, given a file hierarchy:

- `one.tif`

- `my_subdir/two.tif`

- `my_subdir/subsubdir/three.tif`

    vsi_glob("one.tif")
      # returns ("one.tif")
    vsi_glob("*.tif")
      # returns ("one.tif")
    vsi_glob("on?.tif")
      # returns ("one.tif")
    vsi_glob("on[a-z].tif")
      # returns ("one.tif")
    vsi_glob("on[ef].tif")
      # returns ("one.tif")
    vsi_glob("on[!e].tif")
      # returns empty vector character()
    vsi_glob("my_subdir/*.tif")
      # returns ("my_subdir/two.tif")
    vsi_glob("**/*.tif") returns
      # returns ("one.tif", "my_subdir/two.tif", "my_subdir/subsubdir/three.tif")

In the current implementation, matching is done based on the assumption
that a character fits into a single byte, which will not work properly
on non-ASCII UTF-8 filenames.

## Note

GDAL's `VSIGlob()` works with any virtual file systems supported by
GDAL, including network file systems such as /vsis3/, /vsigs/, /vsiaz/,
etc. But note that for those, the pattern is not passed to the remote
server, and thus a large amount of filenames can be transferred from the
remote server to the host where the filtering is done.

## See also

[`vsi_read_dir()`](https://firelab.github.io/gdalraster/reference/vsi_read_dir.md)

## Examples

``` r
if (FALSE) { # gdal_version_num() >= gdal_compute_version(3, 11, 0)
# Requires GDAL >= 3.11
data_dir <- system.file("extdata", package="gdalraster")
vsi_glob(file.path(data_dir, "ynp*"))
}
```
