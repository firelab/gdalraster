# Functions for using GDAL CLI algorithms

This set of functions can be used to access and run `gdal` command line
interface (CLI) algorithms.

**Requires GDAL \>= 3.11.3**

**Experimental** (see the section `Development Status` below)

## Usage

``` r
gdal_commands(contains = NULL, recurse = TRUE, cout = TRUE)

gdal_usage(cmd = NULL)

gdal_run(
  cmd,
  args,
  close = FALSE,
  quiet = FALSE,
  setVectorArgsFromObject = TRUE
)

gdal_run_piped(
  input,
  cmd,
  output = NULL,
  output_format = NULL,
  other_args = NULL,
  output_index = 1,
  outputLayerNameForOpen = NULL
)

gdal_alg(cmd = NULL, args = NULL, parse = TRUE)

gdal_global_reg_names()
```

## Arguments

- contains:

  Optional character string for filtering output to certain commands,
  e.g., `gdal_commands("vector")`.

- recurse:

  Logical value, `TRUE` to include all subcommands recursively (the
  default). Set to `FALSE` to include only the top-level `gdal` commands
  (i.e., `raster`, `vector`, etc.)

- cout:

  Logical value, `TRUE` to print a list of commands along with their
  descriptions and help URLS to the console (the default).

- cmd:

  A character string or character vector containing the path to the
  algorithm, e.g., `"raster reproject"` or `c("raster", "reproject")`.
  Defaults to `"gdal"`, the main entry point to CLI commands.

- args:

  Either a character vector or a named list containing input arguments
  of the algorithm (see section `Algorithm Argument Syntax` below).

- close:

  Logical value, `FALSE` by default. Set to `TRUE` to finalize the
  algorithm immediately after it is run, which completes any pending
  actions such as closing output datasets. This is useful if you do not
  need to access the output as objects, e.g., when only generating file
  output for later use. See `GDALAlg$close()`.

- quiet:

  Logical value, `FALSE` by default. Set to `TRUE` to suppress progress
  reporting along with various messages and warnings. Sets the value of
  `GDALAlg$quiet`.

- setVectorArgsFromObject:

  Logical value, `TRUE` to set algorithm arguments automatically when
  the `"input"` argument or the `"like"` argument is an object of class
  `GDALVector` (the default). Can be set to `FALSE` to disable
  automatically setting algorithm arguments from `GDALVector` input (see
  Note).

- input:

  Value passed as input to the GDAL algorithm specified in `cmd` (i.e.,
  the `"input"`, `"dataset"` or `"source"` argument for the command).
  Typically this is a dataset name (e.g., file or database connection
  string), or an object of class `GDALRaster` or `GDALVector`.

- output:

  Value passed for the `"output"` (or `"destination"`) argument of
  `cmd`. Typically this is a filename for commands that generate a
  raster or vector dataset or other file output. May be `NULL` or empty
  string (`""`) if `output_format` is `"MEM"` (in-memory dataset).

- output_format:

  Optional character string specifying the output format, e.g., a format
  driver short name when output is a raster or vector dataset. Will be
  passed to the algorithm's optional `"output-format"` argument.

- other_args:

  Either a character vector or a named list containing other input
  arguments of the algorithm (i.e., other than those already specified
  via `input`, `output` and `output_format` above, see also the section
  `Algorithm Argument Syntax` below).

- output_index:

  Optional numeric value or character string giving the list index or
  output argument name for an algorithm with more than one output.
  Defaults to `1`.

- outputLayerNameForOpen:

  Optional character string specifying a layer name to open when
  obtaining algorithm output as an object of class `GDALVector` (see the
  class method
  [GDALAlg\$output()](https://firelab.github.io/gdalraster/reference/GDALAlg-class.md)).
  Defaults to empty string (`""`) in which case the first layer by index
  is opened. Ignored if output is not a vector dataset.

- parse:

  Logical value, `TRUE` to attempt parsing `args` if they are given in
  `gdal_alg()` (the default). Set to `FALSE` to instantiate the
  algorithm without parsing arguments. The `$parseCommandLineArgs()`
  method on the returned object can be called to parse arguments and
  obtain the result of that, with potentially useful error messages.

## Details

These functions provide an interface to GDAL CLI algorithms by way of
the C++ exposed class
[`GDALAlg`](https://firelab.github.io/gdalraster/reference/GDALAlg-class.md).
See the class documentation for additional information
([`?GDALAlg`](https://firelab.github.io/gdalraster/reference/GDALAlg-class.md)).

`gdal_commands()` prints a list of commands and their descriptions to
the console, and returns (invisibly) a data frame with columns
`command`, `description`, `URL`. The `contains` argument can be used to
filter the output, e.g., `gdal_commands("vector")` to return only
commands for working with vector inputs.

`gdal_usage()` prints a help message to the console for a given command,
or for the root `gdal` entry point if called with no argument. No return
value, called for that side effect only.

`gdal_run()` executes a GDAL CLI algorithm and returns it as an object
of class
[`GDALAlg`](https://firelab.github.io/gdalraster/reference/GDALAlg-class.md).
A list containing algorithm output(s) can be accessed by calling the
`$outputs()` method (plural) on the returned object, or, more
conveniently in most cases, by calling `$output()` (singular) to return
the the single output value when there is only one. After assigning the
output, or otherwise completing work with the `GDALAlg` object, its
`$release()` method can be called to close datasets and free resources.

`gdal_run_piped()` is a variation of `gdal_run()`. It is suitable for
use with the R native pipe operator (`|>`), but may be useful
stand-alone when it is desirable to obtain the output of the algorithm
directly, and access to the `GDALAlg` object itself is not needed. The
first argument to this function is passed to the `"input"` (or
`"dataset"` or `"source"`) argument of the algorithm (i.e., as input to
the GDAL command specified in `cmd`). The function returns (invisibly)
the output of the CLI algorithm if it has one. If the algorithm has
multiple outputs, the first by index is returned by default but this can
be controlled by the `output_index` argument (numeric index or character
name of the desired output). Logical `TRUE` is returned invisibly if the
algorithm has no output and no error was reported by the `run()` method
of the algorithm object. Logical `FALSE` is returned invisibly but a
message printed if an error occurs. The algorithm object used internally
is always finalized before return.

`gdal_alg()` instantiates and returns an object of class
[`GDALAlg`](https://firelab.github.io/gdalraster/reference/GDALAlg-class.md)
without running it. Passing argument values to the requested CLI
algorithm is optional. This function may be useful (with or without
argument values) for obtaining algorithm properties with the returned
object's `$info()` method, obtaining properties of algorithm arguments
(`$argInfo(arg_name)`), or obtaining algorithm usage as a JSON-formatted
string (`$usageAsJSON()`). This function is simply an alternative to
calling the `new()` constructor for class `GDALAlg`. Executing the
returned algorithm is optional by calling the object's `$run()` method
(assuming argument values were given).

`gdal_global_reg_names()` returns a character vector containing the
names of the algorithms in the GDAL global algorithm registry. These are
the top-level nodes (`raster`, `vector`, etc.) known to GDAL.
Potentially code external to GDAL could register a new command available
for CLI use in a GDAL plugin. This function may be useful in certain
troubleshooting scenarios. It will return a vector of length zero if no
names are returned from the global registry.

## Note

Commands do not require the leading `"gdal"` root node. They may begin
with a top-level command (e.g., `"raster"`, `"vector"`, etc.).

When using argument names as the element names of a list, the underscore
character can be substituted for the dash characters that are used in
some names. This avoids having to surround names in backticks when they
are used to access list elements in the form `args$arg_name` (the form
`args[["arg-name"]]` also works).

When `setVectorArgsFromObject` is `TRUE` (the default) and the `"input"`
or `"like"` argument for an algorithm is given as a `GDALVector` object,
corresponding algorithm arguments will be set automatically based on
properties of the object (when the argument is available to the
algorithm):

- `"input-format"`: set to the `GDALVector` object's driver short name

- `"input-layer"`: set to the `GDALVector` layer name if it is not a SQL
  layer

- `"sql"`: set to the SQL statement if the `GDALVector` layer is defined
  by one

- `"dialect"`: set to the SQL dialect if one is specified for a SQL
  layer

- `"like-layer"`: set to the `GDALVector` layer name if it is not a SQL
  layer

- `"like-sql"`: set to the SQL statement if the `GDALVector` layer is
  defined by one

Argument values specified explicitly will override the automatic setting
(as long as they result in a parsable set of arguments). If
`setVectorArgsFromObject` is `FALSE`, then only the vector dataset is
passed to the algorithm, i.e., without automatically passing any layer
specifications.

## Algorithm Argument Syntax

Arguments are given in R as a character vector or named list, but
otherwise syntax basically matches the GDAL specification for arguments
as they are given on the command line. Those specifications are listed
here along with some amendments regarding the character vector and named
list formats. Programmatic usage also allows passing and receiving
datasets as objects (i.e., `GDALRaster` or `GDALVector`), in addition to
dataset names (e.g., filename, URL, database connection string).

- Commands accept one or several positional arguments, typically for
  dataset names (or in R as `GDALRaster` or `GDALVector` datasets). The
  order is input(s) first, output last. Positional arguments can also be
  specified as named arguments, if preferred to avoid any ambiguity.

- Named arguments have:

  - at least one "long" name, preceded by two dash characters

  - optionally, auxiliary long names (i.e., aliases),

  - and optionally a one-letter short name, preceded by a single dash
    character, e.g.,
    `-f, --of, --format, --output-format <OUTPUT-FORMAT>`

- Boolean arguments are specified by just specifying the argument name
  in character vector format. In R `list` format, the named element must
  be assigned a value of logical `TRUE`.

- Arguments that require a value are specified like:

  - `-f VALUE` for one-letter short names

  - `--format VALUE` or `--format=VALUE` for long names

  - in a named list, this might look like: `args$format <- VALUE`

- Some arguments can be multi-valued. Some of them require all values to
  be packed together and separated with comma. This is, e.g., the case
  of:  
  `--bbox <BBOX> Clipping bounding box as xmin,ymin,xmax,ymax`  
  e.g., `--bbox=2.1,49.1,2.9,49.9`

- Others accept each value to be preceded by a new mention of the
  argument name, e.g., `c("--co", "COMPRESS=LZW", "--co", "TILED=YES")`.
  For that one, if the value of the argument does not contain commas,
  the packed form is also accepted: `--co COMPRESS=LZW,TILED=YES`. Note
  that repeated mentions of an argument are possible in the character
  vector format for argument input, whereas arguments given in named
  list format must use argument long names as the list element names,
  and the packed format for the values (which can be a character vector
  or numeric vector of values).

- Named arguments can be placed before or after positional arguments.

## Development Status

The GDAL Command Line Interface Modernization was first introduced in
the [GDAL 3.11.0
release](https://github.com/OSGeo/gdal/releases/tag/v3.11.0)
(2025-05-09). The GDAL project provides warning that the new CLI "is
provisionally provided as an alternative interface to GDAL and OGR
command line utilities. The project reserves the right to modify,
rename, reorganize, and change the behavior until it is officially
frozen via PSC vote in a future major GDAL release. The utility needs
time to mature, benefit from incremental feedback, and explore
enhancements without carrying the burden of full backward compatibility.
Your usage of it should have no expectation of compatibility until that
time." (<https://gdal.org/en/latest/programs/#gdal-application>)

Initial bindings to enable programmatic use of the CLI algorithms from R
were added in gdalraster 2.2.0, and will evolve over future releases.
*The bindings are considered experimental until the upstream API is
declared stable*. Breaking changes in minor version releases are
possible until then. Please use with those cautions in mind. Bug reports
may be filed at: <https://github.com/firelab/gdalraster/issues>.

## See also

[`GDALAlg-class`](https://firelab.github.io/gdalraster/reference/GDALAlg-class.md)

`gdal` Command Line Interface (CLI)  
<https://gdal.org/en/stable/programs/index.html>

Using `gdal` CLI algorithms from R  
<https://firelab.github.io/gdalraster/articles/use-gdal-cli-from-r.html>

## Examples

``` r
## top-level commands
gdal_commands(recurse = FALSE)
#> → "convert"
#> ℹ Convert a dataset (shortcut for 'gdal raster convert' or 'gdal vector convert').
#> ℹ <https://gdal.org/programs/gdal_convert.html>
#> 
#> → "dataset"
#> ℹ Commands to manage datasets.
#> ℹ <https://gdal.org/programs/gdal_dataset.html>
#> 
#> → "driver"
#> ℹ Command for driver specific operations.
#> 
#> → "info"
#> ℹ Return information on a dataset (shortcut for 'gdal raster info' or 'gdal vector info').
#> ℹ <https://gdal.org/programs/gdal_info.html>
#> 
#> → "mdim"
#> ℹ Multidimensional commands.
#> ℹ <https://gdal.org/programs/gdal_mdim.html>
#> 
#> → "pipeline"
#> ℹ Process a dataset applying several steps.
#> ℹ <https://gdal.org/programs/gdal_pipeline.html>
#> 
#> → "raster"
#> ℹ Raster commands.
#> ℹ <https://gdal.org/programs/gdal_raster.html>
#> 
#> → "vector"
#> ℹ Vector commands.
#> ℹ <https://gdal.org/programs/gdal_vector.html>
#> 
#> → "vsi"
#> ℹ GDAL Virtual System Interface (VSI) commands.
#> ℹ <https://gdal.org/programs/gdal_vsi.html>
#> 

## convert storml_elev.tif to GeoPackage raster
gdal_commands("convert")
#> → "convert"
#> ℹ Convert a dataset (shortcut for 'gdal raster convert' or 'gdal vector convert').
#> ℹ <https://gdal.org/programs/gdal_convert.html>
#> 
#> → "mdim convert"
#> ℹ Convert a multidimensional dataset.
#> ℹ <https://gdal.org/programs/gdal_mdim_convert.html>
#> 
#> → "raster convert"
#> ℹ Convert a raster dataset.
#> ℹ <https://gdal.org/programs/gdal_raster_convert.html>
#> 
#> → "vector convert"
#> ℹ Convert a vector dataset.
#> ℹ <https://gdal.org/programs/gdal_vector_convert.html>
#> 

gdal_usage("raster convert")
#> 
#> Usage: raster convert [OPTIONS] <INPUT> <OUTPUT>
#> 
#> Convert a raster dataset. 
#> 
#> Positional arguments:
#>   -i, --input <INPUT>
#>     Input raster datasets
#>     [required]
#>   -o, --output <OUTPUT>
#>     Output raster dataset
#>     [required]
#> 
#> Options:
#>   -f, --of, --format, --output-format <OUTPUT-FORMAT>
#>     Output format ("GDALG" allowed)
#>   --co, --creation-option <KEY>=<VALUE>
#>     Creation option
#>     [0 or more values]
#>     [packed values not allowed, repeated arg allowed]
#>   --overwrite
#>     Whether overwriting existing output is allowed
#>     [default: FALSE]
#>     [mutually exclusive with --append]
#>   --append
#>     Append as a subdataset to existing output
#>     [default: FALSE]
#>     [mutually exclusive with --overwrite]
#> 
#> Advanced options:
#>   --if, --input-format <INPUT-FORMAT>
#>     Input formats
#>     [0 or more values]
#>     [packed values allowed, repeated arg allowed]
#>   --oo, --open-option <KEY>=<VALUE>
#>     Open options
#>     [0 or more values]
#>     [packed values not allowed, repeated arg allowed]
#> 
#> For more details: <https://gdal.org/programs/gdal_raster_convert.html>

f_tif <- system.file("extdata/storml_elev.tif", package="gdalraster")
f_gpkg <- file.path(tempdir(), "storml_elev.gpkg")
args <- c("--overwrite", f_tif, f_gpkg)

# finalize the algorithm immediately after it is run if only generating
# file output for later use:
# gdal_run("raster convert", args, close = TRUE)

# or, assign to a variable and access algorithm output as a dataset object
(alg <- gdal_run("raster convert", args))
#>  ■                                  0% |  ETA:  0s
#> ✔ Done (8ms)
#> 
#> C++ object of class <GDALAlg>
#>   • Command: "raster convert"
#>   • Description: Convert a raster dataset.
#>   • Help URL: <https://gdal.org/programs/gdal_raster_convert.html>

(ds <- alg$output())
#> C++ object of class <GDALRaster>
#>   • Driver: GeoPackage (GPKG)
#>   • DSN: "/tmp/RtmpYz2q7S/storml_elev.gpkg"
#>   • Dimensions: 143, 107, 1
#>   • CRS: NAD83 / UTM zone 12N (EPSG:26912)
#>   • Pixel resolution: 30.000000, 30.000000
#>   • Bbox: 323476.071971, 5101871.983031, 327766.071971, 5105081.983031

alg$release()

plot_raster(ds, legend = TRUE)


ds$close()
unlink(f_gpkg)

## use the R native pipe operator

if (requireNamespace("ltc")) {
  # make a of plot of 'terrain ruggedness index' (TRI) for Storm Lake AOI
  system.file("extdata/storml_elev.tif", package="gdalraster") |>
    gdal_run_piped("raster tri", "", "MEM") |>
    plot_raster(legend = TRUE,
                minmax_pct_cut = c(0, 99),
                col_map_fn = rev(ltc::ltc("heatmap3")),
                main = "Storm Lake AOI: terrain ruggedness index")
}
#> Loading required namespace: ltc


## get help for vector commands
gdal_usage("vector")
#> 
#> Usage: vector <SUBCOMMAND> [OPTIONS]
#> where <SUBCOMMAND> is one of:
#>   - buffer              : Compute a buffer around geometries of a vector dataset.
#>   - check-coverage      : Check a polygon coverage for validity
#>   - check-geometry      : Check a dataset for invalid geometries
#>   - clean-coverage      : Alter polygon boundaries to make shared edges identical, removing gaps and overlaps
#>   - clip                : Clip a vector dataset.
#>   - concat              : Concatenate vector datasets.
#>   - convert             : Convert a vector dataset.
#>   - edit                : Edit metadata of a vector dataset.
#>   - explode-collections : Explode geometries of type collection of a vector dataset.
#>   - filter              : Filter a vector dataset.
#>   - geom                : Geometry operations on a vector dataset.
#>   - grid                : Create a regular grid from scattered points.
#>   - index               : Create a vector index of vector datasets.
#>   - info                : Return information on a vector dataset.
#>   - layer-algebra       : Perform algebraic operation between 2 layers.
#>   - make-point          : Create point geometries from attribute fields
#>   - make-valid          : Fix validity of geometries of a vector dataset.
#>   - partition           : Partition a vector dataset into multiple files.
#>   - pipeline            : Process a vector dataset applying several steps.
#>   - rasterize           : Burns vector geometries into a raster.
#>   - reproject           : Reproject a vector dataset.
#>   - segmentize          : Segmentize geometries of a vector dataset.
#>   - select              : Select a subset of fields from a vector dataset.
#>   - set-field-type      : Modify the type of a field of a vector dataset.
#>   - set-geom-type       : Modify the geometry type of a vector dataset.
#>   - simplify            : Simplify geometries of a vector dataset.
#>   - simplify-coverage   : Simplify shared boundaries of a polygonal vector dataset.
#>   - sql                 : Apply SQL statement(s) to a dataset.
#>   - swap-xy             : Swap X and Y coordinates of geometries of a vector dataset.
#> 
#> Options:
#>   --drivers
#>     Display vector driver list as JSON document and exit
#>   --output-string <OUTPUT-STRING>
#>     Output string, in which the result is placed
#> 
#> For more details: <https://gdal.org/programs/gdal_vector.html>

## clip a vector layer by a bounding box
gdal_usage("vector clip")
#> 
#> Usage: vector clip [OPTIONS] <INPUT> <OUTPUT>
#> 
#> Clip a vector dataset. 
#> 
#> Positional arguments:
#>   -i, --input <INPUT>
#>     Input vector datasets
#>     [required]
#>   -o, --output <OUTPUT>
#>     Output vector dataset
#>     [required]
#> 
#> Options:
#>   -l, --layer, --input-layer <INPUT-LAYER>
#>     Input layer name(s)
#>     [0 or more values]
#>     [packed values allowed, repeated arg allowed]
#>   -f, --of, --format, --output-format <OUTPUT-FORMAT>
#>     Output format ("GDALG" allowed)
#>   --co, --creation-option <KEY>=<VALUE>
#>     Creation option
#>     [0 or more values]
#>     [packed values not allowed, repeated arg allowed]
#>   --lco, --layer-creation-option <KEY>=<VALUE>
#>     Layer creation option
#>     [0 or more values]
#>     [packed values not allowed, repeated arg allowed]
#>   --overwrite
#>     Whether overwriting existing output is allowed
#>     [default: FALSE]
#>   --update
#>     Whether to open existing dataset in update mode
#>     [default: FALSE]
#>   --overwrite-layer
#>     Whether overwriting existing output is allowed
#>     [default: FALSE]
#>   --append
#>     Whether appending to existing layer is allowed
#>     [default: FALSE]
#>     [mutually exclusive with --upsert]
#>   --output-layer <OUTPUT-LAYER>
#>     Output layer name
#>   --skip-errors
#>     Skip errors when writing features
#>   --active-layer <ACTIVE-LAYER>
#>     Set active layer (if not specified, all)
#>   --bbox <BBOX>
#>     Clipping bounding box as xmin,ymin,xmax,ymax
#>     [4 values]
#>     [packed values allowed, repeated arg not allowed]
#>     [mutually exclusive with --geometry, --like]
#>   --bbox-crs <BBOX-CRS>
#>     CRS of clipping bounding box
#>   --geometry <GEOMETRY>
#>     Clipping geometry (WKT or GeoJSON)
#>     [mutually exclusive with --bbox, --like]
#>   --geometry-crs <GEOMETRY-CRS>
#>     CRS of clipping geometry
#>   --like <DATASET>
#>     Dataset to use as a template for bounds
#>     [mutually exclusive with --bbox, --geometry]
#>   --like-sql <SELECT-STATEMENT>
#>     SELECT statement to run on the 'like' dataset
#>     [mutually exclusive with --like-where]
#>   --like-layer <LAYER-NAME>
#>     Name of the layer of the 'like' dataset
#>   --like-where <WHERE-EXPRESSION>
#>     WHERE SQL clause to run on the 'like' dataset
#>     [mutually exclusive with --like-sql]
#> 
#> Advanced options:
#>   --if, --input-format <INPUT-FORMAT>
#>     Input formats
#>     [0 or more values]
#>     [packed values allowed, repeated arg allowed]
#>   --oo, --open-option <KEY>=<VALUE>
#>     Open options
#>     [0 or more values]
#>     [packed values not allowed, repeated arg allowed]
#>   --output-oo, --output-open-option <KEY>=<VALUE>
#>     Output open options
#>     [0 or more values]
#>     [packed values not allowed, repeated arg allowed]
#>   --upsert
#>     Upsert features (implies 'append')
#>     [mutually exclusive with --append]
#> 
#> For more details: <https://gdal.org/programs/gdal_vector_clip.html>

f <- system.file("extdata/ynp_fires_1984_2022.gpkg", package="gdalraster")
f_clip <- file.path(tempdir(), "ynp_fires_clip.gpkg")

# some multi-valued arguments require all values packed and comma separated
# e.g., --bbox <BBOX>
bb <- c(469686, 11442, 544070, 85508)
bb <- paste(bb, collapse = ",")

args <- c("--bbox", bb, "--overwrite", f, f_clip)
(alg <- gdal_run("vector clip", args))
#> C++ object of class <GDALAlg>
#>   • Command: "vector clip"
#>   • Description: Clip a vector dataset.
#>   • Help URL: <https://gdal.org/programs/gdal_vector_clip.html>

(lyr <- alg$output())
#> C++ object of class <GDALVector>
#>   • Driver: GeoPackage (GPKG)
#>   • DSN: "/tmp/RtmpYz2q7S/ynp_fires_clip.gpkg"
#>   • Layer: mtbs_perims
#>   • CRS: NAD83 / Montana (EPSG:32100)
#>   • Geometry: MULTIPOLYGON

lyr$bbox()
#> [1] 469686  11442 544070  85508

lyr$getFeatureCount()
#> [1] 40

lyr$close()
alg$release()
unlink(f_clip)

## rasterize a vector layer and return output as a GDALRaster object
gdal_usage("vector rasterize")
#> 
#> Usage: vector rasterize [OPTIONS] <INPUT> <OUTPUT>
#> 
#> Burns vector geometries into a raster. 
#> 
#> Positional arguments:
#>   -i, --input <INPUT>
#>     Input vector datasets
#>     [required]
#>   -o, --output <OUTPUT>
#>     Output raster dataset
#>     [required]
#> 
#> Options:
#>   -f, --of, --format, --output-format <OUTPUT-FORMAT>
#>     Output format
#>   --co, --creation-option <KEY>=<VALUE>
#>     Creation option
#>     [0 or more values]
#>     [packed values not allowed, repeated arg allowed]
#>   --overwrite
#>     Whether overwriting existing output is allowed
#>     [default: FALSE]
#>   -b, --band <BAND>
#>     The band(s) to burn values into (1-based index)
#>     [0 or more values]
#>     [packed values allowed, repeated arg allowed]
#>   --invert
#>     Invert the rasterization
#>     [default: FALSE]
#>   --all-touched
#>     Enables the ALL_TOUCHED rasterization option
#>   --burn <BURN>
#>     Burn value
#>     [0 or more values]
#>     [packed values allowed, repeated arg allowed]
#>   -a, --attribute-name <ATTRIBUTE-NAME>
#>     Attribute name
#>   --3d
#>     Indicates that a burn value should be extracted from the Z values of the feature
#>   -l, --input-layer <INPUT-LAYER>
#>     Input layer name
#>     [mutually exclusive with --sql]
#>   --where <WHERE>
#>     SQL where clause
#>   --sql <SQL>
#>     SQL select statement
#>     [mutually exclusive with --input-layer]
#>   --dialect <DIALECT>
#>     SQL dialect
#>   --nodata <NODATA>
#>     Assign a specified nodata value to output bands
#>   --init <INIT>
#>     Pre-initialize output bands with specified value
#>     [0 or more values]
#>     [packed values allowed, repeated arg allowed]
#>   --crs <CRS>
#>     Override the projection for the output file
#>   --transformer-option <NAME>=<VALUE>
#>     Set a transformer option suitable to pass to GDALCreateGenImgProjTransformer2
#>     [0 or more values]
#>     [packed values allowed, repeated arg allowed]
#>   --extent <xmin>,<ymin>,<xmax>,<ymax>
#>     Set the target georeferenced extent
#>     [4 values]
#>     [packed values allowed, repeated arg not allowed]
#>   --resolution <xres>,<yres>
#>     Set the target resolution
#>     [2 values]
#>     [packed values allowed, repeated arg not allowed]
#>     [mutually exclusive with --size]
#>   --tap, --target-aligned-pixels
#>     (target aligned pixels) Align the coordinates of the extent of the output file to the values of the resolution
#>   --size <xsize>,<ysize>
#>     Set the target size in pixels and lines
#>     [2 values]
#>     [packed values allowed, repeated arg not allowed]
#>     [mutually exclusive with --resolution]
#>   --ot, --datatype, --output-data-type <OUTPUT-DATA-TYPE>
#>     Output data type
#>     [Byte|Int8|UInt16|Int16|UInt32|Int32|UInt64|Int64|CInt16|CInt32|Float16|Float32|Float64|CFloat32|CFloat64]
#>   --optimization <OPTIMIZATION>
#>     Force the algorithm used (results are identical)
#>     [AUTO|RASTER|VECTOR]
#>     [default: AUTO]
#>   --add
#>     Add to existing raster
#>     [default: FALSE]
#>   --update
#>     Whether to open existing dataset in update mode
#>     [default: FALSE]
#> 
#> Advanced options:
#>   --oo, --open-option <KEY>=<VALUE>
#>     Open options
#>     [0 or more values]
#>     [packed values not allowed, repeated arg allowed]
#>   --if, --input-format <INPUT-FORMAT>
#>     Input formats
#>     [0 or more values]
#>     [packed values allowed, repeated arg allowed]
#> 
#> For more details: <https://gdal.org/programs/gdal_vector_rasterize.html>

f_out = file.path(tempdir(), "ynp_fire_year.tif")

# arguments in list format
args <- list(input = f,
             sql = "SELECT * FROM mtbs_perims ORDER BY ig_year",
             attribute_name = "ig_year",
             output = f_out,
             overwrite = TRUE,
             creation_option = c("TILED=YES", "COMPRESS=DEFLATE"),
             resolution = c(90, 90),
             output_data_type = "Int16",
             init = -32767,
             nodata = -32767)

(alg <- gdal_run("vector rasterize", args))
#> C++ object of class <GDALAlg>
#>   • Command: "vector rasterize"
#>   • Description: Burns vector geometries into a raster.
#>   • Help URL: <https://gdal.org/programs/gdal_vector_rasterize.html>

(ds <- alg$output())
#> C++ object of class <GDALRaster>
#>   • Driver: GeoTIFF (GTiff)
#>   • DSN: "/tmp/RtmpYz2q7S/ynp_fire_year.tif"
#>   • Dimensions: 1155, 1218, 1
#>   • CRS: NAD83 / Montana (EPSG:32100)
#>   • Pixel resolution: 90.000000, 90.000000
#>   • Bbox: 469640.726682, -12997.663642, 573590.726682, 96622.336358

alg$release()

if (requireNamespace("scales")) {
  pal <- scales::viridis_pal(end = 0.8, direction = -1)(6)
  ramp <- scales::colour_ramp(pal)
  plot_raster(ds, legend = TRUE, col_map_fn = ramp, na_col = "#d9d9d9",
              main = "YNP Fires 1984-2022 - Most Recent Burn Year")
}


ds$close()
deleteDataset(f_out)
#> [1] TRUE

## GDAL CLI pipeline syntax
# "raster pipeline" example 2 from:
# https://gdal.org/en/latest/programs/gdal_raster_pipeline.html
# serialize the command to reproject a GTiff file into GDALG format, and
# then later read the GDALG file
# GDAL Streamed Algorithm format:
# https://gdal.org/en/stable/drivers/raster/gdalg.html

gdal_usage("raster pipeline")
#> 
#> Usage: raster pipeline <PIPELINE>
#> 
#> Process a raster dataset applying several steps. 
#> 
#> Positional arguments:
#>   --pipeline <PIPELINE>
#>     Pipeline string
#> 
#> <PIPELINE> is of the form: read [READ-OPTIONS] ( ! <STEP-NAME> [STEP-OPTIONS] )* ! write [WRITE-OPTIONS]
#> 
#> Options for read input/write output:
#>   -i, --input <INPUT>
#>     Input raster datasets
#>     [1 or more values]
#>     [packed values not allowed, repeated arg allowed]
#>   -f, --of, --format, --output-format <OUTPUT-FORMAT>
#>     Output format ("GDALG" allowed)
#>   -o, --output <OUTPUT>
#>     Output raster dataset
#>   --co, --creation-option <KEY>=<VALUE>
#>     Creation option
#>     [0 or more values]
#>     [packed values not allowed, repeated arg allowed]
#>   --overwrite
#>     Whether overwriting existing output is allowed
#>     [default: FALSE]
#>     [mutually exclusive with --append]
#>   --append
#>     Append as a subdataset to existing output
#>     [default: FALSE]
#>     [mutually exclusive with --overwrite]
#>   --output-string <OUTPUT-STRING>
#>     Output string, in which the result is placed
#> 
#> Advanced options for read input/write output:
#>   --if, --input-format <INPUT-FORMAT>
#>     Input formats
#>     [0 or more values]
#>     [packed values allowed, repeated arg allowed]
#>   --oo, --open-option <KEY>=<VALUE>
#>     Open options
#>     [0 or more values]
#>     [packed values not allowed, repeated arg allowed]
#> 
#> Potential steps are:
#>   aspect
#>     Generate an aspect map
#>   blend
#>     Blend/compose two raster datasets
#>   calc
#>     Perform raster algebra
#>   clip
#>     Clip a raster dataset.
#>   color-map
#>     Generate a RGB or RGBA dataset from a single band, using a color map
#>   compare
#>     Compare two raster datasets.
#>   edit
#>     Edit a raster dataset.
#>   fill-nodata
#>     Fill nodata raster regions by interpolation from edges.
#>   hillshade
#>     Generate a shaded relief map
#>   info
#>     Return information on a raster dataset.
#>   materialize
#>     Materialize a piped dataset on disk to increase the efficiency of the following steps.
#>   mosaic
#>     Build a mosaic, either virtual (VRT) or materialized.
#>   neighbors
#>     Compute the value of each pixel from its neighbors (focal statistics)
#>   nodata-to-alpha
#>     Replace nodata value(s) with an alpha band.
#>   overview
#>     Manage overviews of a raster dataset.
#>   pansharpen
#>     Perform a pansharpen operation.
#>   proximity
#>     Produces a raster proximity map.
#>   reclassify
#>     Reclassify values in a raster dataset
#>   reproject
#>     Reproject a raster dataset.
#>   resize
#>     Resize a raster dataset without changing the georeferenced extents.
#>   rgb-to-palette
#>     Convert a RGB image into a pseudo-color / paletted image.
#>   roughness
#>     Generate a roughness map
#>   scale
#>     Scale the values of the bands of a raster dataset.
#>   select
#>     Select a subset of bands from a raster dataset.
#>   set-type
#>     Modify the data type of bands of a raster dataset.
#>   sieve
#>     Remove small polygons from a raster dataset.
#>   slope
#>     Generate a slope map
#>   stack
#>     Combine together input bands into a multi-band output, either virtual (VRT) or materialized.
#>   tee
#>     Pipes the input into the output stream and side nested pipelines.
#>   tile
#>     Generate tiles in separate files from a raster dataset.
#>   tpi
#>     Generate a Topographic Position Index (TPI) map
#>   tri
#>     Generate a Terrain Ruggedness Index (TRI) map
#>   unscale
#>     Convert scaled values of a raster dataset into unscaled values.
#>   viewshed
#>     Compute the viewshed of a raster dataset.
#> 
#> For more details: <https://gdal.org/programs/gdal_raster_pipeline.html>

f_tif <- system.file("extdata/storml_elev.tif", package="gdalraster")
f_out <- file.path(tempdir(), "storml_elev_epsg_32100.gdalg.json")

args <- c("read", "--input", f_tif, "!",
          "reproject", "--dst-crs=EPSG:32100", "!",
          "write", "--output", f_out, "--overwrite")

alg <- gdal_run("raster pipeline", args)
alg$release()

# content of the .gdalg.json file
readLines(f_out, warn = FALSE) |> writeLines()
#> {
#>   "type":"gdal_streamed_alg",
#>   "command_line":"gdal raster pipeline read --input \/home\/runner\/work\/_temp\/Library\/gdalraster\/extdata\/storml_elev.tif ! reproject --dst-crs EPSG:32100",
#>   "gdal_version":"3120200"
#> }

(ds <- new(GDALRaster, f_out))
#> C++ object of class <GDALRaster>
#>   • Driver: GDAL Streamed Algorithm driver (GDALG)
#>   • DSN: "/tmp/RtmpYz2q7S/storml_elev_epsg_32100.gdalg.json"
#>   • Dimensions: 145, 110, 1
#>   • CRS: NAD83 / Montana (EPSG:32100)
#>   • Pixel resolution: 29.986648, 29.986648
#>   • Bbox: 307558.912155, 206741.650976, 311906.976180, 210040.182306

plot_raster(ds, legend = TRUE)


ds$close()
unlink(f_out)
```
