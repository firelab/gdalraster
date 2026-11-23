/* Misc. utility functions for internal use
   Chris Toney <chris.toney at usda.gov>
   Copyright (c) 2023-2025 gdalraster authors
*/

#include "rcpp_util.h"

#include <cpl_port.h>
#include <cpl_string.h>

#include <algorithm>
#include <cctype>
#include <string>

// convert data frame to numeric matrix in Rcpp
Rcpp::NumericMatrix df_to_matrix_(const Rcpp::DataFrame &df) {
    Rcpp::NumericMatrix m = Rcpp::no_init(df.nrows(), df.size());
    for (R_xlen_t i = 0; i < df.size(); ++i) {
        if (Rcpp::is<Rcpp::NumericVector>(df[i]) ||
            Rcpp::is<Rcpp::IntegerVector>(df[i]) ||
            Rcpp::is<Rcpp::LogicalVector>(df[i])) {

            m.column(i) = Rcpp::NumericVector(df[i]);
        }
        else {
            Rcpp::stop("data frame columns must be numeric");
        }
    }
    return m;
}

// convert data frame to integer matrix in Rcpp
Rcpp::IntegerMatrix df_to_int_matrix_(const Rcpp::DataFrame &df) {
    Rcpp::IntegerMatrix m = Rcpp::no_init(df.nrows(), df.size());
    for (R_xlen_t i = 0; i < df.size(); ++i) {
        if (Rcpp::is<Rcpp::NumericVector>(df[i]) ||
            Rcpp::is<Rcpp::IntegerVector>(df[i]) ||
            Rcpp::is<Rcpp::LogicalVector>(df[i])) {

            m.column(i) = Rcpp::IntegerVector(df[i]);
        }
        else {
            Rcpp::stop("data frame columns must be numeric");
        }
    }
    return m;
}

// convert allowed xy inputs to numeric matrix
Rcpp::NumericMatrix xy_robject_to_matrix_(const Rcpp::RObject &xy) {
    if (xy.isNULL())
        Rcpp::stop("NULL was given for the input coordinates");

    Rcpp::NumericMatrix xy_ret;

    if (Rcpp::is<Rcpp::NumericVector>(xy) ||
        Rcpp::is<Rcpp::IntegerVector>(xy) ||
        Rcpp::is<Rcpp::LogicalVector>(xy)) {

        if (!Rf_isMatrix(xy)) {
            Rcpp::NumericVector v = Rcpp::as<Rcpp::NumericVector>(xy);
            if (v.size() < 2 || v.size() > 4)
                Rcpp::stop("input as vector must have one xy, xyz, or xyzm");

            xy_ret = Rcpp::NumericMatrix(1, v.size(), v.begin());
        }
        else {
            xy_ret = Rcpp::as<Rcpp::NumericMatrix>(xy);
        }
    }
    else if (Rcpp::is<Rcpp::DataFrame>(xy)) {
        xy_ret = df_to_matrix_(xy);
    }
    else {
        Rcpp::stop("coordinates must be in a vector, matrix or data frame");
    }

    return xy_ret;
}

// wrapper for base R path.expand()
Rcpp::CharacterVector path_expand_(const Rcpp::CharacterVector &path) {
    Rcpp::Function f("path.expand");
    return f(path);
}

// wrapper for base R normalizePath()
// int must_work should be NA_LOGICAL (the default), 0 or 1
Rcpp::CharacterVector normalize_path_(const Rcpp::CharacterVector &path,
                                      int must_work) {

    Rcpp::Function f("normalizePath");
    return f(path, Rcpp::Named("mustWork") = must_work);
}

// wrapper for base R enc2utf8()
Rcpp::CharacterVector enc_to_utf8_(const Rcpp::CharacterVector &x) {
    Rcpp::Function f("enc2utf8");
    return f(x);
}

// wrapper for base R strsplit()
Rcpp::CharacterVector strsplit_(const Rcpp::CharacterVector &x,
                                const Rcpp::CharacterVector &split) {
    Rcpp::Function f("strsplit");
    return f(x, split);
}

// wrapper for base R paste() with a value for collapse
// the single input x is expected to be a vector of values to collapse
Rcpp::String paste_collapse_(const SEXP &x, const Rcpp::String &s) {
    Rcpp::Function f("paste");
    Rcpp::CharacterVector tmp = f(x, Rcpp::Named("collapse") = s);
    Rcpp::CharacterVector ret = enc_to_utf8_(tmp);
    return ret[0];
}

// std::string to uppercase
std::string str_toupper_(const std::string &s) {
    std::string s_out = s;
    std::transform(s_out.begin(), s_out.end(), s_out.begin(),
                   [](unsigned char c){ return std::toupper(c); });
    return s_out;
}

// std::string to lowercase
std::string str_tolower_(const std::string &s) {
    std::string s_out = s;
    std::transform(s_out.begin(), s_out.end(), s_out.begin(),
                   [](unsigned char c){ return std::tolower(c); });
    return s_out;
}

// return a new character vector with leading "-" or "--" removed from each
// element of the input vector
// for handling character vectors of GDAL CLI arguments
Rcpp::CharacterVector remove_leading_dashes_(const Rcpp::CharacterVector &x) {
    Rcpp::CharacterVector out(x.size());
    for (R_xlen_t i = 0; i < x.size(); ++i) {
        Rcpp::String s(x[i]);
        s.replace_first("--", "");
        if (EQUALN(s.get_cstring(), "-", 1))
            s.replace_first("-", "");
        out[i] = s;
    }
    return out;
}

// does character vector contain string element
bool contains_str_(const Rcpp::CharacterVector &v, const Rcpp::String &s,
                   bool match_if_substr) {

    bool ret = false;

    if (match_if_substr) {
        auto has_substr = [&s](const Rcpp::String &vec_element) {
            std::string vec_element_str(vec_element);
            return vec_element_str.find(s) != std::string::npos;
        };

        auto it = std::find_if(v.cbegin(), v.cend(), has_substr);

        if (it == v.cend())
            ret = false;
        else
            ret = true;
    }
    else {
        auto it = std::find(v.cbegin(), v.cend(), s);

        if (it == v.cend())
            ret = false;
        else
            ret = true;
    }

    return ret;
}

// does std::string contain a space character
bool has_space_char_(const std::string &s) {
    if (std::any_of(s.begin(), s.end(), [](unsigned char ch) {
                    return std::isspace(ch);})) {

        return true;
    }

    return false;
}

// wrapper for base R isNamespaceLoaded()
bool is_namespace_loaded_(const Rcpp::String &pkg) {
    Rcpp::Function f("isNamespaceLoaded");
    Rcpp::LogicalVector res = f(pkg);
    return Rcpp::is_true(Rcpp::all(res));
}

// is this a gdalraster spatial object?
bool is_gdalraster_obj_(const Rcpp::RObject &x) {
    if (x.isNULL())
        return false;

    if (x.isObject()) {
        const Rcpp::String cls = x.attr("class");
        if (cls == "Rcpp_GDALRaster" || cls == "Rcpp_GDALVector")
            return true;
        else
            return false;
    }

    return false;
}

// wrap a GDAL CPLStringList as R character vector
// (since CPLStringList .begin() and .end() require GDAL >= 3.9)
Rcpp::CharacterVector wrap_gdal_string_list_(const CPLStringList &string_list) {
    int nCount = string_list.size();
    Rcpp::CharacterVector out = Rcpp::no_init(nCount);
    for (int i = 0; i < nCount; ++i) {
        out[i] = string_list[i];
    }
    return out;
}

// convert an optional R character vector of "NAME=VALUE" pairs to a
// CPLStringList (empty if NULL)
CPLStringList options_to_csl_(
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) {
    CPLStringList aosOptions;
    if (options.isNotNull()) {
        Rcpp::CharacterVector options_in(options);
        for (R_xlen_t i = 0; i < options_in.size(); ++i)
            aosOptions.AddString(options_in[i]);
    }
    return aosOptions;
}

//' Get pointer address of an R vector as a character string
//'
//' `get_data_ptr()` returns a character string representation of the address
//' of the first value in the C array underlying a given R vector of `raw`,
//' `integer`, `double` or `complex`. The returned string is suitable for use
//' as a DATAPOINTER for a GDAL MEM dataset
//' (\url{https://gdal.org/en/stable/drivers/raster/mem.html}).
//' @param x Vector of type `double`, `integer`, `raw` or `complex`.
//' @returns Character string pointer address with format suitable as
//' DATAPOINTER for a GDAL MEM dataset.
//'
//' @seealso
//' [rvector_to_MEM()]
//'
//' @examples
//' v <- sample(0:255, 20, replace = TRUE)
//' get_data_ptr(v)
// [[Rcpp::export()]]
std::string get_data_ptr(const Rcpp::RObject &x) {
    if (x.isNULL())
        Rcpp::stop("'x' must be a vector of numeric, integer, raw or complex");

    char buf[32] = {'\0'};
    if (Rcpp::is<Rcpp::IntegerVector>(x)) {
        Rcpp::IntegerVector v = Rcpp::as<Rcpp::IntegerVector>(x);
        if (v.size() == 0)
            Rcpp::stop("'x' is empty");
        int n = CPLPrintPointer(buf, v.begin(), sizeof(buf));
        buf[n] = 0;
    }
    else if (Rcpp::is<Rcpp::NumericVector>(x)) {
        Rcpp::NumericVector v = Rcpp::as<Rcpp::NumericVector>(x);
        if (v.size() == 0)
            Rcpp::stop("'x' is empty");
        int n = CPLPrintPointer(buf, v.begin(), sizeof(buf));
        buf[n] = 0;
    }
    else if (Rcpp::is<Rcpp::RawVector>(x)) {
        Rcpp::RawVector v = Rcpp::as<Rcpp::RawVector>(x);
        if (v.size() == 0)
            Rcpp::stop("'x' is empty");
        int n = CPLPrintPointer(buf, v.begin(), sizeof(buf));
        buf[n] = 0;
    }
    else if (Rcpp::is<Rcpp::ComplexVector>(x)) {
        Rcpp::ComplexVector v = Rcpp::as<Rcpp::ComplexVector>(x);
        if (v.size() == 0)
            Rcpp::stop("'x' is empty");
        int n = CPLPrintPointer(buf, v.begin(), sizeof(buf));
        buf[n] = 0;
    }
    else {
        Rcpp::stop("'x' must be a vector of double, integer, raw or complex");
    }

    return std::string(buf);
}

// wrapper for cli::cli_alert()
void cli_alert_(const std::string &text) {
    Rcpp::Environment pkg = Rcpp::Environment::namespace_env("cli");
    Rcpp::Function fn = pkg["cli_alert"];
    fn(text);
}

// wrapper for cli::cli_alert_info()
void cli_alert_info_(const std::string &text) {
    Rcpp::Environment pkg = Rcpp::Environment::namespace_env("cli");
    Rcpp::Function fn = pkg["cli_alert_info"];
    fn(text);
}

// wrapper for cli::cli_alert_warning()
void cli_alert_warning_(const std::string &text) {
    Rcpp::Environment pkg = Rcpp::Environment::namespace_env("cli");
    Rcpp::Function fn = pkg["cli_alert_warning"];
    fn(text);
}

// wrapper for cli::cli_alert_danger()
void cli_alert_danger_(const std::string &text) {
    Rcpp::Environment pkg = Rcpp::Environment::namespace_env("cli");
    Rcpp::Function fn = pkg["cli_alert_danger"];
    fn(text);
}

// wrapper for cli::cli_alert_success()
void cli_alert_success_(const std::string &text) {
    Rcpp::Environment pkg = Rcpp::Environment::namespace_env("cli");
    Rcpp::Function fn = pkg["cli_alert_success"];
    fn(text);
}

// wrapper for cli::cli_text()
void cli_text_(const std::string &text) {
    Rcpp::Environment pkg = Rcpp::Environment::namespace_env("cli");
    Rcpp::Function fn = pkg["cli_text"];
    fn(text);
}

// wrapper for cli::cli_ul()
void cli_ul_() {
    Rcpp::Environment pkg = Rcpp::Environment::namespace_env("cli");
    Rcpp::Function fn = pkg["cli_ul"];
    fn();
}

// wrapper for cli::cli_li()
void cli_li_(const std::string &text) {
    Rcpp::Environment pkg = Rcpp::Environment::namespace_env("cli");
    Rcpp::Function fn = pkg["cli_li"];
    fn(text);
}

// wrapper for cli::cli_end()
void cli_end_() {
    Rcpp::Environment pkg = Rcpp::Environment::namespace_env("cli");
    Rcpp::Function fn = pkg["cli_end"];
    fn();
}

// Format a dataset name (DSN) for display in a cli message, e.g., in the
// show() methods. An inline XML DSN (e.g., a VRT string) is replaced by a
// short placeholder giving its root element and length. Otherwise, a DSN
// longer than `max_len` is shortened by eliding the middle with "...", then
// quoted, with braces escaped since cli interprets {} as glue expressions.
// The returned string is ready to be embedded in text passed to cli_*_().
// The default max_len of 76 (see rcpp_util.h) keeps the quoted DSN on one
// line of an 80-column console when cli wraps it below an indented item.
std::string cli_format_dsn_(const std::string &dsn, std::size_t max_len) {
    const std::size_t first = dsn.find_first_not_of(" \t\r\n");
    if (first != std::string::npos && dsn[first] == '<') {
        const std::size_t name_end = dsn.find_first_of(" \t\r\n/>",
                                                       first + 1);
        std::string root = dsn.substr(first + 1, name_end == std::string::npos
                                                 ? std::string::npos
                                                 : name_end - first - 1);
        if (root.empty() || root.size() > 64 ||
                root.find_first_of("{}") != std::string::npos) {
            root = "";
        }
        else {
            root += " ";
        }
        return "<inline " + root + "XML, " + std::to_string(dsn.size()) +
               " chars>";
    }

    std::string out = dsn;
    if (max_len >= 10 && out.size() > max_len) {
        // keep the start and the end (usually the most informative part of a
        // path or URL), without splitting a UTF-8 multi-byte sequence
        std::size_t head = (max_len - 3) / 2;
        std::size_t tail_start = out.size() - (max_len - 3 - head);
        while (head > 0 &&
               (static_cast<unsigned char>(out[head]) & 0xC0) == 0x80)
            --head;
        while (tail_start < out.size() &&
               (static_cast<unsigned char>(out[tail_start]) & 0xC0) == 0x80)
            ++tail_start;
        out.replace(head, tail_start - head, "...");
    }

    std::string escaped;
    escaped.reserve(out.size());
    for (char c : out) {
        escaped += c;
        if (c == '{' || c == '}')
            escaped += c;
    }
    // quoted as plain text rather than inside a {.str } span, where an
    // unbalanced (even if doubled) brace is a glue parse error
    return "\"" + escaped + "\"";
}

// wrapper for cli::cat_line()
void cli_cat_line_() {
    Rcpp::Environment pkg = Rcpp::Environment::namespace_env("cli");
    Rcpp::Function fn = pkg["cat_line"];
    fn();
}

// expose equal_within_ulps_() in R for unit tests
//' @noRd
// [[Rcpp::export(name = ".equal_within_ulps")]]
bool equal_within_ulps_r_(double x, double y, int n = 4) {
    if (n < 0)
        Rcpp::stop("`n` must be >= 0");

    return equal_within_ulps_(x, y, n);
}

// wrapper for nanoarrow::as_nanoarrow_array_stream() on a data frame
SEXP as_nanoarrow_array_stream_(const Rcpp::DataFrame &df) {
    Rcpp::Environment pkg = Rcpp::Environment::namespace_env("nanoarrow");
    Rcpp::Function fn = pkg["as_nanoarrow_array_stream"];
    return fn(df);
}
