# Clear progress bar

`progress_bar_clear()` terminates any active cli progress bars and
resets the global progress bar in C++. Generally not needed unless a
process using a progress bar terminates abnormally, or with ctrl-c
interrupt, and a progress bar display anomaly results.

## Usage

``` r
progress_bar_clear()
```

## Value

No return value, call for side effects.
