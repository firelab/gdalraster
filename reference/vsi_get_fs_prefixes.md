# Return the list of virtual file system handlers currently registered

`vsi_get_fs_prefixes()` returns the list of prefixes for virtual file
system handlers currently registered (e.g., `"/vsimem/"`, `"/vsicurl/"`,
etc). Wrapper for `VSIGetFileSystemsPrefixes()` in the GDAL API.

## Usage

``` r
vsi_get_fs_prefixes()
```

## Value

Character vector containing prefixes of the virtual file system
handlers.

## See also

[`vsi_get_fs_options()`](https://firelab.github.io/gdalraster/reference/vsi_get_fs_options.md)

<https://gdal.org/en/stable/user/virtual_file_systems.html>

## Examples

``` r
vsi_get_fs_prefixes()
#>  [1] "/vsi7z/"                       "/vsiadls/"                    
#>  [3] "/vsiaz/"                       "/vsiaz_streaming/"            
#>  [5] "/vsicached?"                   "/vsicrypt/"                   
#>  [7] "/vsicurl/"                     "/vsicurl_streaming/"          
#>  [9] "/vsigs/"                       "/vsigs_streaming/"            
#> [11] "/vsigzip/"                     "/vsikerchunk_json_ref/"       
#> [13] "/vsikerchunk_json_ref_cached/" "/vsikerchunk_parquet_ref/"    
#> [15] "/vsimem/"                      "/vsioss/"                     
#> [17] "/vsioss_streaming/"            "/vsipmtiles/"                 
#> [19] "/vsirar/"                      "/vsis3/"                      
#> [21] "/vsis3_streaming/"             "/vsisparse/"                  
#> [23] "/vsistdin/"                    "/vsistdin?"                   
#> [25] "/vsistdout/"                   "/vsistdout_redirect/"         
#> [27] "/vsisubfile/"                  "/vsiswift/"                   
#> [29] "/vsiswift_streaming/"          "/vsitar/"                     
#> [31] "/vsiwebhdfs/"                  "/vsizip/"                     
```
