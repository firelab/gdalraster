/* Misc. utility functions for internal use
   Chris Toney <chris.toney at usda.gov>
   Copyright (c) 2023-2025 gdalraster authors
*/

#ifndef RCPP_UTIL_H_
#define RCPP_UTIL_H_

#include <Rcpp.h>
#include <RcppInt64>

#ifndef GDALRASTER_TYPES_H_
#include <cpl_port.h>
#include <cpl_string.h>
Rcpp::CharacterVector wrap_gdal_string_list_(const CPLStringList &string_list);
CPLStringList options_to_csl_(
        const Rcpp::Nullable<Rcpp::CharacterVector> &options);
std::string get_data_ptr(const Rcpp::RObject &x);
#endif  // GDALRASTER_TYPES_H_

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <limits>
#include <string>
#include <type_traits>

constexpr int64_t MAX_INT_AS_R_NUMERIC_ = 9007199254740991;

// as defined in the bit64 package src/integer64.h:
// #define NA_INTEGER64 LLONG_MIN
// #define ISNA_INTEGER64(X)((X) == NA_INTEGER64)
// #define MIN_INTEGER64 LLONG_MIN+1
// #define MAX_INTEGER64 LLONG_MAX
// replaced here with:
constexpr int64_t NA_INTEGER64 = std::numeric_limits<int64_t>::min();
constexpr bool ISNA_INTEGER64(int64_t x) {return (x == NA_INTEGER64);}
constexpr int64_t MIN_INTEGER64 = std::numeric_limits<int64_t>::min() + 1;
constexpr int64_t MAX_INTEGER64 = std::numeric_limits<int64_t>::max();


Rcpp::NumericMatrix df_to_matrix_(const Rcpp::DataFrame &df);
Rcpp::IntegerMatrix df_to_int_matrix_(const Rcpp::DataFrame &df);

Rcpp::NumericMatrix xy_robject_to_matrix_(const Rcpp::RObject &xy);

Rcpp::CharacterVector path_expand_(const Rcpp::CharacterVector &path);

Rcpp::CharacterVector normalize_path_(const Rcpp::CharacterVector &path,
                                      int must_work);
Rcpp::CharacterVector normalize_path_(const Rcpp::CharacterVector &path,
                                      int must_work = NA_LOGICAL);

Rcpp::CharacterVector enc_to_utf8_(const Rcpp::CharacterVector &x);

Rcpp::CharacterVector strsplit_(const Rcpp::CharacterVector &x,
                                const Rcpp::CharacterVector &split);

Rcpp::String paste_collapse_(const SEXP &x, const Rcpp::String &s);

std::string str_toupper_(const std::string &s);
std::string str_tolower_(const std::string &s);

Rcpp::CharacterVector remove_leading_dashes_(const Rcpp::CharacterVector &x);

bool contains_str_(const Rcpp::CharacterVector &v, const Rcpp::String &s,
                   bool match_if_substr);
bool contains_str_(const Rcpp::CharacterVector &v, const Rcpp::String &s,
                   bool match_if_substr = false);

bool has_space_char_(const std::string &s);

bool is_namespace_loaded_(const Rcpp::String &pkg);

bool is_gdalraster_obj_(const Rcpp::RObject &x);

// cli::cli_* wrappers for use from C++
void cli_alert_(const std::string &text);
void cli_alert_info_(const std::string &text);
void cli_alert_warning_(const std::string &text);
void cli_alert_danger_(const std::string &text);
void cli_alert_success_(const std::string &text);
void cli_text_(const std::string &text);
void cli_ul_();
void cli_li_(const std::string &text);
void cli_end_();
void cli_cat_line_();

SEXP as_nanoarrow_array_stream_(const Rcpp::DataFrame &df);

// case-insensitive comparator for std::map
// https://stackoverflow.com/questions/1801892/how-can-i-make-the-mapfind-operation-case-insensitive
struct _ci_less {
    struct nocase_compare {
        bool operator() (const unsigned char& c1,
                         const unsigned char& c2) const {
            return std::tolower(c1) < std::tolower(c2);
        }
    };
    bool operator() (const std::string & s1, const std::string & s2) const {
        return std::lexicographical_compare(s1.begin(), s1.end(),
                                            s2.begin(), s2.end(),
                                            nocase_compare());
    }
};

// https://en.cppreference.com/cpp/types/numeric_limits/epsilon
// use machine epsilon to compare floating-point values
// This works for `NaN` and therefore R `NA`.
// The cppreference example was modified to handle infinities (with `x == y`).
// NB: This will return TRUE for x = Inf, y = -Inf and is not expected to be
// used where that could occur.
template <class T>
std::enable_if_t<!std::numeric_limits<T>::is_integer, bool>
equal_within_ulps_(T x, T y, std::size_t n = 4)
{
    if (x == y)
        return true;

    // Since `epsilon()` is the gap size (ULP, unit in the last place)
    // of floating-point numbers in interval [1, 2), we can scale it to
    // the gap size in interval [2^e, 2^{e+1}), where `e` is the exponent
    // of `x` and `y`.

    // If `x` and `y` have different gap sizes (which means they have
    // different exponents), we take the smaller one. Taking the bigger
    // one is also reasonable, I guess.
    const T m = std::min(std::fabs(x), std::fabs(y));

    // Subnormal numbers have fixed exponent, which is `min_exponent - 1`.
    const int exp = m < std::numeric_limits<T>::min() ?
                    std::numeric_limits<T>::min_exponent - 1
                    : std::ilogb(m);

    // We consider `x` and `y` equal if the difference between them is
    // within `n` ULPs.
    return std::fabs(x - y) <=
        n * std::ldexp(std::numeric_limits<T>::epsilon(), exp);
}

#endif  // RCPP_UTIL_H_
