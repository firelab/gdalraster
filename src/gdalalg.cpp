/* R interface to GDALAlgorithm and related classes
   Chris Toney <jctoney at gmail.com>
   Copyright (c) 2023-2025 gdalraster authors
*/

#include "gdalalg.h"

#if __has_include(<gdalalgorithm.h>)
    #include <gdalalgorithm.h>
#endif
#include <gdal.h>
#include <cpl_port.h>
#include <cpl_string.h>

#include <Rcpp.h>

#include <algorithm>
#include <cstring>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "gdalraster.h"
#include "rcpp_util.h"

using std::string_literals::operator""s;

#define GDALALG_MIN_GDAL_ GDAL_COMPUTE_VERSION(3, 11, 3)

[[maybe_unused]] constexpr char GDALALG_MIN_GDAL_MSG_[] =
    "GDAL CLI bindings require GDAL >= 3.11.3";

#if GDAL_VERSION_NUM >= GDALALG_MIN_GDAL_
constexpr R_xlen_t CMD_TOKENS_MAX_ = 6;  // used here for a rough bound check

#if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 12, 0)
// https://lists.osgeo.org/pipermail/gdal-dev/2025-August/060818.html
// https://github.com/OSGeo/gdal/pull/12853 for GDAL >= 3.12
struct GDALAlgorithmArgHS
{
    GDALAlgorithmArg *ptr = nullptr;

    explicit GDALAlgorithmArgHS(GDALAlgorithmArg *arg) : ptr(arg)
    {
    }
};
#endif  // GDAL < 3.12
#endif  // GDALALG_MIN_GDAL_

#if GDAL_VERSION_NUM >= GDALALG_MIN_GDAL_
// internal helper to get subalgorithm names, descriptions and URLs,
// potentially filtering on 'contains'
void append_subalg_names_desc_(const GDALAlgorithmH alg,
                               const std::string &cmd_str,
                               std::vector<std::string> &names,
                               std::vector<std::string> &desc,
                               std::vector<std::string> &urls,
                               const std::string &contains,
                               bool console_out) {

    const CPLStringList subnames(GDALAlgorithmGetSubAlgorithmNames(alg));
    for (int i = 0; i < subnames.size(); ++i) {
        GDALAlgorithmH subalg = nullptr;
        subalg = GDALAlgorithmInstantiateSubAlgorithm(alg, subnames[i]);
        if (!subalg) {
            cli_alert_danger_(
                "failed to instantiate alg name: "s + subnames[i]);
            continue;
        }

        std::string this_cmd_str = cmd_str + " " + GDALAlgorithmGetName(subalg);
        bool console_out_this = true;
        if (contains == "" ||
            this_cmd_str.find(contains) != std::string::npos) {

            names.push_back(this_cmd_str);
            desc.push_back(GDALAlgorithmGetDescription(subalg));
            urls.push_back(GDALAlgorithmGetHelpFullURL(subalg));
        }
        else {
            console_out_this = false;
        }

        if (console_out && console_out_this) {
            cli_alert_("{.str "s + this_cmd_str + "}");
            cli_alert_info_(GDALAlgorithmGetDescription(subalg));
            if (!EQUAL(GDALAlgorithmGetHelpFullURL(subalg), "")) {
                cli_alert_info_(
                    "{.url "s + GDALAlgorithmGetHelpFullURL(subalg) + "}");
            }
            cli_cat_line_();
        }

        if (GDALAlgorithmHasSubAlgorithms(subalg)) {
            append_subalg_names_desc_(subalg, this_cmd_str, names, desc, urls,
                                      contains, console_out);
        }

        GDALAlgorithmRelease(subalg);
    }
}
#endif  // GDALALG_MIN_GDAL_

//  public R wrapper in R/gdal_cli.R
//' @noRd
// [[Rcpp::export(name = ".gdal_commands")]]
Rcpp::DataFrame gdal_commands(const std::string &contains, bool recurse,
                              bool console_out) {

#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    Rcpp::stop(GDALALG_MIN_GDAL_MSG_);

#else
    GDALAlgorithmRegistryH reg = nullptr;
    reg = GDALGetGlobalAlgorithmRegistry();
    if (!reg)
        Rcpp::stop("failed to obtain global algorithm registry");

    GDALAlgorithmH gdal_alg = nullptr;
    gdal_alg = GDALAlgorithmRegistryInstantiateAlg(
        reg, GDALGlobalAlgorithmRegistry::ROOT_ALG_NAME);

    if (!gdal_alg) {
        GDALAlgorithmRegistryRelease(reg);
        Rcpp::stop("failed to instantiate \"gdal\" entry point");
    }

    const CPLStringList names(GDALAlgorithmGetSubAlgorithmNames(gdal_alg));
    const int num_names = names.size();
    if (num_names == 0) {
        GDALAlgorithmRegistryRelease(reg);
        Rcpp::stop("failed to obtain top-level algorithm names");
    }

    std::vector<std::string> cmd_names = {};
    std::vector<std::string> cmd_descriptions = {};
    std::vector<std::string> cmd_urls = {};

    std::string contains_in = str_tolower_(contains);

    for (int i = 0; i < num_names; ++i) {
        GDALAlgorithmH alg = nullptr;
        alg = GDALAlgorithmRegistryInstantiateAlg(reg, names[i]);
        if (!alg) {
            cli_alert_warning_("failed to instantiate alg name: "s +names[i]);
            continue;
        }

        bool console_out_this = true;
        if (contains_in == "" ||
            std::string(names[i]).find(contains_in) != std::string::npos) {

            cmd_names.push_back(names[i]);
            cmd_descriptions.push_back(GDALAlgorithmGetDescription(alg));
            cmd_urls.push_back(GDALAlgorithmGetHelpFullURL(alg));
        }
        else {
            console_out_this = false;
        }

        if (console_out && console_out_this) {
            cli_alert_("{.str "s + names[i] + "}");
            cli_alert_info_(GDALAlgorithmGetDescription(alg));
            if (!EQUAL(GDALAlgorithmGetHelpFullURL(alg), "")) {
                cli_alert_info_(
                    "{.url "s + GDALAlgorithmGetHelpFullURL(alg) + "}");
            }
            cli_cat_line_();
        }

        if (recurse && GDALAlgorithmHasSubAlgorithms(alg)) {
            append_subalg_names_desc_(alg, std::string(names[i]),
                                      cmd_names, cmd_descriptions,
                                      cmd_urls, contains_in, console_out);
        }

        GDALAlgorithmRelease(alg);
    }

    GDALAlgorithmRelease(gdal_alg);
    GDALAlgorithmRegistryRelease(reg);

    Rcpp::DataFrame df = Rcpp::DataFrame::create(
        Rcpp::Named("command") = Rcpp::wrap(cmd_names),
        Rcpp::Named("description") = Rcpp::wrap(cmd_descriptions),
        Rcpp::Named("URL") = Rcpp::wrap(cmd_urls));

    return df;
#endif  // GDALALG_MIN_GDAL_
}

//  public R wrapper in R/gdal_cli.R
//' @noRd
// [[Rcpp::export(name = ".gdal_global_reg_names")]]
Rcpp::CharacterVector gdal_global_reg_names() {

    Rcpp::CharacterVector out = Rcpp::CharacterVector::create();

#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    cli_alert_danger_(GDALALG_MIN_GDAL_MSG_);
    return out;

#else
    GDALAlgorithmRegistryH reg = nullptr;
    reg = GDALGetGlobalAlgorithmRegistry();
    if (!reg) {
        cli_alert_danger_("failed to obtain global algorithm registry");
        return out;
    }

    const CPLStringList names(GDALAlgorithmRegistryGetAlgNames(reg));
    out = wrap_gdal_string_list_(names);

    GDALAlgorithmRegistryRelease(reg);
    return out;
#endif  // GDALALG_MIN_GDAL_
}

// ****************************************************************************
//  Implementation of exposed class GDALAlg, which wraps GDALAlgorithm and
//  its related classes GDALAlgorithmArg and GDALArgDatasetValue.
//  Documented in R/gdalalg.R.
// ****************************************************************************

GDALAlg::GDALAlg()
        : GDALAlg("gdal", Rcpp::CharacterVector::create())  {}

GDALAlg::GDALAlg(const Rcpp::CharacterVector &cmd)
        : GDALAlg(cmd, Rcpp::CharacterVector::create()) {}

GDALAlg::GDALAlg(const Rcpp::CharacterVector &cmd, const Rcpp::RObject &args) {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    Rcpp::stop(GDALALG_MIN_GDAL_MSG_);
#else

    if (cmd.size() == 0 ||
        (cmd.size() == 1 && EQUAL(cmd[0], "")) ||
        (cmd.size() == 1 && Rcpp::String(cmd[0]) == NA_STRING)) {

        Rcpp::stop("'cmd' is empty");
    }
    else if (Rcpp::is_true(Rcpp::any(Rcpp::is_na(cmd)))) {
        Rcpp::stop("'cmd' contains one or more NA values");
    }
    else if (cmd.size() > CMD_TOKENS_MAX_) {
        Rcpp::stop("number of elements in 'cmd' is out of range");
    }

    Rcpp::CharacterVector cmd_in = enc_to_utf8_(cmd);
    m_cmd_str = "";
    for (R_xlen_t i = 0; i < cmd_in.size(); ++i) {
        m_cmd_str += Rcpp::as<std::string>(cmd_in[i]);
        if (i < cmd_in.size() - 1) {
            m_cmd_str += " ";
        }
    }

    if (has_space_char_(m_cmd_str)) {
        m_cmd = Rcpp::CharacterVector::create();
        std::stringstream ss(m_cmd_str);
        std::string token;
        while (ss >> token) {
            m_cmd.push_back(token);
        }
    }
    else {
        m_cmd = cmd_in;
    }

    if (!args.isNULL()) {
        if (Rcpp::is<Rcpp::CharacterVector>(args)) {
            Rcpp::CharacterVector args_in(args);
            m_args = enc_to_utf8_(args_in);
        }
        else if (Rcpp::is<Rcpp::List>(args)) {
            m_args = parseListArgs_(Rcpp::as<Rcpp::List>(args));
        }
        else {
            Rcpp::stop("'args' must be a character vector or named list");
        }
    }
    else {
        m_args = Rcpp::CharacterVector::create();
    }

    m_args_no_leading_dash = remove_leading_dashes_(m_args);

    instantiateAlg_();
#endif  // GDALALG_MIN_GDAL_
}

GDALAlg::~GDALAlg() {
#if GDAL_VERSION_NUM >= GDALALG_MIN_GDAL_
    if (m_hActualAlg) {
        if (m_hasRun && !m_hasFinalized)
            GDALAlgorithmFinalize(m_hActualAlg);
        GDALAlgorithmRelease(m_hActualAlg);
    }

    if (m_hAlg)
        GDALAlgorithmRelease(m_hAlg);

#endif  // GDALALG_MIN_GDAL_
}

Rcpp::List GDALAlg::info() const {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    Rcpp::stop(GDALALG_MIN_GDAL_MSG_);
#else

    if (!m_hAlg)
        Rcpp::stop("algorithm not instantiated");

    Rcpp::List alg_info = Rcpp::List::create();
    const GDALAlgorithmH &alg = m_hActualAlg ? m_hActualAlg : m_hAlg;

    alg_info.push_back(GDALAlgorithmGetName(alg), "name");
    alg_info.push_back(m_cmd_str, "full_path");
    alg_info.push_back(GDALAlgorithmGetDescription(alg), "description");
    alg_info.push_back(GDALAlgorithmGetLongDescription(alg),
                       "long_description");
    alg_info.push_back(GDALAlgorithmGetHelpFullURL(alg), "URL");
    alg_info.push_back(GDALAlgorithmHasSubAlgorithms(alg),
                       "has_subalgorithms");

    if (GDALAlgorithmHasSubAlgorithms(alg)) {
        const CPLStringList aosNames(GDALAlgorithmGetSubAlgorithmNames(alg));
        alg_info.push_back(wrap_gdal_string_list_(aosNames),
                           "subalgorithm_names");
    }
    else {
        alg_info.push_back(Rcpp::CharacterVector::create(),
                           "subalgorithm_names");
    }

    CPLStringList aosArgNames(GDALAlgorithmGetArgNames(alg));
    int nCount = aosArgNames.size();
    if (nCount > 0) {
        std::vector<std::string> names(aosArgNames);

#if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 12, 0)
        // see https://lists.osgeo.org/pipermail/gdal-dev/2025-August/060825.html
        names.erase(std::remove(names.begin(), names.end(), "help-doc"),
                    names.end());
#else
        // see https://github.com/OSGeo/gdal/pull/12890
        std::vector<std::string> hidden_args = {};
        for (const std::string &nm : names) {
            auto hArg = GDALAlgorithmGetArg(alg, nm.c_str());
            if (!hArg)
                continue;

            if (GDALAlgorithmArgIsHidden(hArg))
                hidden_args.push_back(nm);

            GDALAlgorithmArgRelease(hArg);
        }

        for (const std::string &nm : hidden_args) {
            names.erase(std::remove(names.begin(), names.end(), nm.c_str()),
                        names.end());
        }
#endif  // GDAL < 3.12

        alg_info.push_back(Rcpp::wrap(names), "arg_names");
    }
    else {
        alg_info.push_back(Rcpp::CharacterVector::create(), "arg_names");
    }

    return alg_info;
#endif  // GDALALG_MIN_GDAL_
}

Rcpp::List GDALAlg::argInfo(const Rcpp::String &arg_name) const {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    Rcpp::stop(GDALALG_MIN_GDAL_MSG_);
#else

    if (!m_hAlg)
        Rcpp::stop("algorithm not instantiated");

    if (!arg_name.get_cstring() ||  arg_name == "" || arg_name == NA_STRING)
        Rcpp::stop("'arg_name' is required");

    Rcpp::List arg_info = Rcpp::List::create();

    GDALAlgorithmArgH hArg = nullptr;
    hArg = GDALAlgorithmGetArg(m_hActualAlg ? m_hActualAlg : m_hAlg,
                               arg_name.get_cstring());

    if (!hArg)
        Rcpp::stop("failed to obtain GDALAlgorithmArg object for 'arg_name'");

    arg_info.push_back(GDALAlgorithmArgGetName(hArg), "name");

    GDALAlgorithmArgType eType = GDALAlgorithmArgGetType(hArg);
    std::string arg_type = str_toupper_(GDALAlgorithmArgTypeName(eType));
    arg_info.push_back(arg_type, "type");

    arg_info.push_back(GDALAlgorithmArgGetDescription(hArg), "description");
    arg_info.push_back(GDALAlgorithmArgGetShortName(hArg), "short_name");

    CPLStringList aosAliases(GDALAlgorithmArgGetAliases(hArg));
    arg_info.push_back(wrap_gdal_string_list_(aosAliases), "aliases");

    arg_info.push_back(GDALAlgorithmArgGetMetaVar(hArg), "meta_var");
    arg_info.push_back(GDALAlgorithmArgGetCategory(hArg), "category");
    arg_info.push_back(GDALAlgorithmArgIsPositional(hArg), "is_positional");
    arg_info.push_back(GDALAlgorithmArgIsRequired(hArg), "is_required");
    arg_info.push_back(GDALAlgorithmArgGetMinCount(hArg), "min_count");
    arg_info.push_back(GDALAlgorithmArgGetMaxCount(hArg), "max_count");
    arg_info.push_back(GDALAlgorithmArgGetPackedValuesAllowed(hArg),
                       "packed_values_allowed");
    arg_info.push_back(GDALAlgorithmArgGetRepeatedArgAllowed(hArg),
                       "repeated_arg_allowed");

    if (eType == GAAT_STRING || eType == GAAT_STRING_LIST) {
        const CPLStringList aosChoices(GDALAlgorithmArgGetChoices(hArg));
        arg_info.push_back(wrap_gdal_string_list_(aosChoices), "choices");
    }
    else {
        arg_info.push_back(Rcpp::CharacterVector::create(), "choices");
    }

    arg_info.push_back(GDALAlgorithmArgIsExplicitlySet(hArg),
                       "is_explicitly_set");
    arg_info.push_back(GDALAlgorithmArgHasDefaultValue(hArg),
                       "has_default_value");

    if (GDALAlgorithmArgHasDefaultValue(hArg)) {
    // see https://lists.osgeo.org/pipermail/gdal-dev/2025-August/060818.html
    // see https://github.com/OSGeo/gdal/pull/12853 for GDAL >= 3.12

        if (eType == GAAT_STRING) {
    #if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 12, 0)
            const std::string &val = hArg->ptr->GetDefault<std::string>();
    #else
            const char *val = GDALAlgorithmArgGetDefaultAsString(hArg);
    #endif
            arg_info.push_back(Rcpp::wrap(val), "default_value");
        }

        else if (eType == GAAT_BOOLEAN) {
    #if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 12, 0)
            const bool &val = hArg->ptr->GetDefault<bool>();
    #else
            const bool val = GDALAlgorithmArgGetDefaultAsBoolean(hArg);
    #endif
            arg_info.push_back(Rcpp::wrap(val), "default_value");
        }

        else if (eType == GAAT_INTEGER) {
    #if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 12, 0)
            const int &val = hArg->ptr->GetDefault<int>();
    #else
            const int val = GDALAlgorithmArgGetDefaultAsInteger(hArg);
    #endif
            arg_info.push_back(Rcpp::wrap(val), "default_value");
        }

        else if (eType == GAAT_REAL) {
    #if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 12, 0)
            const double &val = hArg->ptr->GetDefault<double>();
    #else
            const double val = GDALAlgorithmArgGetDefaultAsDouble(hArg);
    #endif
            arg_info.push_back(Rcpp::wrap(val), "default_value");
        }

        else if (eType == GAAT_STRING_LIST) {
    #if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 12, 0)
            const auto &val =
                hArg->ptr->GetDefault<std::vector<std::string>>();

            arg_info.push_back(Rcpp::wrap(val), "default_value");
    #else
            const CPLStringList aosValue(
                GDALAlgorithmArgGetDefaultAsStringList(hArg));

            arg_info.push_back(wrap_gdal_string_list_(aosValue),
                               "default_value");
    #endif
        }

        else if (eType == GAAT_INTEGER_LIST) {
    #if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 12, 0)
            const auto &val =
                hArg->ptr->GetDefault<std::vector<int>>();

            arg_info.push_back(Rcpp::wrap(val), "default_value");
    #else
            size_t nCount = 0;
            const int *panValue =
                GDALAlgorithmArgGetDefaultAsIntegerList(hArg, &nCount);
            Rcpp::IntegerVector val;
            if (panValue && nCount > 0)
                val = Rcpp::IntegerVector(panValue, panValue + nCount);
            else
                val = Rcpp::IntegerVector::create();
            arg_info.push_back(val, "default_value");
    #endif
        }

        else if (eType == GAAT_REAL_LIST) {
    #if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 12, 0)
            const auto &val =
                hArg->ptr->GetDefault<std::vector<double>>();

            arg_info.push_back(Rcpp::wrap(val), "default_value");
    #else
            size_t nCount = 0;
            const double *padfValue =
                GDALAlgorithmArgGetDefaultAsDoubleList(hArg, &nCount);
            Rcpp::NumericVector val;
            if (padfValue && nCount > 0)
                val = Rcpp::NumericVector(padfValue, padfValue + nCount);
            else
                val = Rcpp::NumericVector::create();
            arg_info.push_back(val, "default_value");
    #endif
        }

        else {
            arg_info.push_back(R_NilValue, "default_value");
        }
    }
    else {
        arg_info.push_back(R_NilValue, "default_value");
    }

    #if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 12, 0)
    arg_info.push_back(GDALAlgorithmArgIsHiddenForCLI(hArg),
                       "is_hidden_for_cli");
    arg_info.push_back(GDALAlgorithmArgIsOnlyForCLI(hArg),
                       "is_only_for_cli");
    #else
    arg_info.push_back(GDALAlgorithmArgIsHiddenForAPI(hArg),
                       "is_hidden_for_api");
    arg_info.push_back(GDALAlgorithmArgIsHiddenForCLI(hArg),
                       "is_hidden_for_cli");
    // GDALAlgorithmArgIsOnlyForCLI() is deprecated at GDAL 3.12
    // renamed to GDALAlgorithmArgIsHiddenForAPI()
    // see https://github.com/OSGeo/gdal/pull/12890
    arg_info.push_back(GDALAlgorithmArgIsHiddenForAPI(hArg),
                       "is_only_for_cli");
    #endif

    arg_info.push_back(GDALAlgorithmArgIsInput(hArg), "is_input");
    arg_info.push_back(GDALAlgorithmArgIsOutput(hArg), "is_output");

    if (eType == GAAT_DATASET || eType == GAAT_DATASET_LIST) {

        //  type flags
        GDALArgDatasetType ds_type = GDALAlgorithmArgGetDatasetType(hArg);
        Rcpp::CharacterVector ds_type_flags = Rcpp::CharacterVector::create();
        if (ds_type & GDAL_OF_RASTER)
            ds_type_flags.push_back("RASTER");
        if (ds_type & GDAL_OF_VECTOR)
            ds_type_flags.push_back("VECTOR");
        if (ds_type & GDAL_OF_MULTIDIM_RASTER)
            ds_type_flags.push_back("MULTIDIM_RASTER");
        if (ds_type & GDAL_OF_UPDATE)
            ds_type_flags.push_back("UPDATE");

        arg_info.push_back(ds_type_flags, "dataset_type_flags");

        // input flags
        int ds_input_flags = GDALAlgorithmArgGetDatasetInputFlags(hArg);
        Rcpp::CharacterVector ds_input_flags_out =
            Rcpp::CharacterVector::create();

        if (ds_input_flags & GADV_NAME)
            ds_input_flags_out.push_back("NAME");
        if (ds_input_flags & GADV_OBJECT)
            ds_input_flags_out.push_back("OBJECT");

        arg_info.push_back(ds_input_flags_out, "dataset_input_flags");

        // output flags
        int ds_output_flags = GDALAlgorithmArgGetDatasetOutputFlags(hArg);
        Rcpp::CharacterVector ds_output_flags_out =
            Rcpp::CharacterVector::create();

        if (ds_output_flags & GADV_NAME)
            ds_output_flags_out.push_back("NAME");
        if (ds_output_flags & GADV_OBJECT)
            ds_output_flags_out.push_back("OBJECT");

        arg_info.push_back(ds_output_flags_out, "dataset_output_flags");
    }
    else {
        arg_info.push_back(R_NilValue, "dataset_type_flags");
        arg_info.push_back(R_NilValue, "dataset_input_flags");
        arg_info.push_back(R_NilValue, "dataset_output_flags");
    }

    arg_info.push_back(GDALAlgorithmArgGetMutualExclusionGroup(hArg),
                       "mutual_exclusion_group");

    #if GDAL_VERSION_NUM >= GDAL_COMPUTE_VERSION(3, 13, 0)
    arg_info.push_back(GDALAlgorithmArgGetMutualDependencyGroup(hArg),
                       "mutual_dependency_group");

    const CPLStringList aosValue(
        GDALAlgorithmGetArgDependencies(m_hAlg, GDALAlgorithmArgGetName(hArg)));
    arg_info.push_back(wrap_gdal_string_list_(aosValue), "depends_on");

    arg_info.push_back(GDALAlgorithmArgIsAvailableInPipelineStep(hArg),
                       "available_in_pipeline_step");
    #endif

    GDALAlgorithmArgRelease(hArg);

    return arg_info;
#endif  // GDALALG_MIN_GDAL_
}

void GDALAlg::usage() const {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    Rcpp::stop(GDALALG_MIN_GDAL_MSG_);
#else

    Rcpp::Environment pkg = Rcpp::Environment::namespace_env("gdalraster");
    Rcpp::Function print_usage = pkg[".print_alg_usage"];
    print_usage(Rcpp::wrap(m_cmd_str));
#endif
}

Rcpp::String GDALAlg::usageAsJSON() const {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    Rcpp::stop(GDALALG_MIN_GDAL_MSG_);
#else

    if (!m_hAlg)
        Rcpp::stop("algorithm not instantiated");

    char *pszUsage = nullptr;
    pszUsage = GDALAlgorithmGetUsageAsJSON(
        m_hActualAlg ? m_hActualAlg : m_hAlg);

    Rcpp::String json = "";
    if (pszUsage)
        json = Rcpp::String(pszUsage);
    CPLFree(pszUsage);

    return json;
#endif  // GDALALG_MIN_GDAL_
}

bool GDALAlg::setArg(const Rcpp::String &arg_name,
                     const Rcpp::RObject &arg_value) {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    Rcpp::stop(GDALALG_MIN_GDAL_MSG_);
#else

    if (!m_hAlg) {
        if (!quiet)
            cli_alert_danger_("algorithm not instantiated");
        return false;
    }

    if (m_hasRun) {
        if (!quiet)
            cli_alert_danger_("algorithm has already run");
        return false;
    }

    if (!arg_name.get_cstring() || arg_name == NA_STRING || arg_name == "") {
        if (!quiet)
            cli_alert_danger_("invalid value for {.arg arg_name}");
        return false;
    }

    if (arg_value.isNULL()) {
        if (!quiet)
            cli_alert_danger_("{.arg arg_value} is NULL");
        return false;
    }

    Rcpp::String arg_name_in(arg_name);
    arg_name_in.replace_all("--", "");
    arg_name_in.replace_all("_", "-");
    if (STARTS_WITH(arg_name_in.get_cstring(), "-") &&
        std::strlen(arg_name_in.get_cstring()) < 3) {

        if (!quiet)
            cli_alert_danger_("{.arg arg_name} must be an argument long name");
        return false;
    }

    GDALAlgorithmArgH hArg = nullptr;
    hArg = GDALAlgorithmGetArg(m_hActualAlg ? m_hActualAlg : m_hAlg,
                               arg_name_in.get_cstring());
    if (!hArg) {
        if (!quiet)
            cli_alert_danger_("failed to instantiate algorithm argument named "
                              "{.str "s + arg_name_in.get_cstring() + "}");
        return false;
    }
    if (!GDALAlgorithmArgIsInput(hArg)) {
        if (!quiet)
            cli_alert_danger_("{.str "s + arg_name_in.get_cstring() + "} is "
                              "not an input argument of the algorithm");
        return false;
    }

    std::string true_arg_name = GDALAlgorithmArgGetName(hArg);

    bool ret = false;

    switch (GDALAlgorithmArgGetType(hArg)) {
        case GAAT_BOOLEAN:
        {
            if (!Rcpp::is<Rcpp::LogicalVector>(arg_value)) {
                cli_alert_danger_("logical value required for a BOOLEAN type "
                                  "algorithm argument: "s +
                                  arg_name_in.get_cstring());
                break;
            }

            Rcpp::LogicalVector v(arg_value);
            if (v.size() != 1 || Rcpp::LogicalVector::is_na(v[0])) {
                cli_alert_danger_("single logical value (TRUE|FALSE) required "
                                  "for BOOLEAN type algorithm argument: "s +
                                  arg_name_in.get_cstring());
                break;
            }

            ret = GDALAlgorithmArgSetAsBoolean(
                hArg, v[0] == TRUE ? true : false);
        }
        break;

        case GAAT_STRING:
        {
            if (!Rcpp::is<Rcpp::CharacterVector>(arg_value)) {
                cli_alert_danger_("character value required for a STRING type "
                                  "algorithm argument: "s +
                                  arg_name_in.get_cstring());
                break;
            }

            Rcpp::CharacterVector v(arg_value);
            if (v.size() != 1 || Rcpp::CharacterVector::is_na(v[0])) {
                cli_alert_danger_("single character string is required for "
                                  "a STRING algorithm argument: "s +
                                  arg_name_in.get_cstring());
                break;
            }

            Rcpp::String val(v[0]);
            ret = GDALAlgorithmArgSetAsString(hArg, val.get_cstring());
        }
        break;

        case GAAT_INTEGER:
        {
            if (!Rcpp::is<Rcpp::LogicalVector>(arg_value) &&
                !Rcpp::is<Rcpp::IntegerVector>(arg_value) &&
                !Rcpp::is<Rcpp::NumericVector>(arg_value)) {

                cli_alert_danger_("integer or numeric value required for an "
                                  "INTEGER type algorithm argument: "s +
                                  arg_name_in.get_cstring());
                break;
            }

            Rcpp::IntegerVector v(arg_value);
            if (v.size() != 1) {
                cli_alert_danger_("single numeric value is required for an "
                                  "INTEGER type algorithm argument: "s +
                                  arg_name_in.get_cstring());
                break;
            }
            if (Rcpp::IntegerVector::is_na(v[0])) {
                cli_alert_danger_("{.arg arg_value} cannot be {.val NA}");
                break;
            }

            ret = GDALAlgorithmArgSetAsInteger(hArg, v[0]);
        }
        break;

        case GAAT_REAL:
        {
            if (!Rcpp::is<Rcpp::LogicalVector>(arg_value) &&
                !Rcpp::is<Rcpp::IntegerVector>(arg_value) &&
                !Rcpp::is<Rcpp::NumericVector>(arg_value)) {

                cli_alert_danger_("numeric value required for a REAL type "
                                  "algorithm argument: "s +
                                  arg_name_in.get_cstring());
                break;
            }

            Rcpp::NumericVector v(arg_value);
            if (v.size() != 1) {
                cli_alert_danger_("single numeric value is required for a "
                                  "REAL type algorithm argument: "s +
                                  arg_name_in.get_cstring());
                break;
            }
            if (Rcpp::NumericVector::is_na(v[0])) {
                cli_alert_danger_("{.arg arg_value} cannot be {.val NA}");
                break;
            }

            ret = GDALAlgorithmArgSetAsDouble(hArg, v[0]);
        }
        break;

        case GAAT_STRING_LIST:
        {
            if (!Rcpp::is<Rcpp::CharacterVector>(arg_value)) {
                cli_alert_danger_("character vector required for a STRINGLIST "
                                  "algorithm argument: "s +
                                  arg_name_in.get_cstring());
                break;
            }

            Rcpp::CharacterVector v(arg_value);
            if (v.size() < 1) {
                cli_alert_danger_("{.arg arg_value} is empty");
                break;
            }
            if (Rcpp::is_true(Rcpp::any(Rcpp::is_na(v)))) {
                cli_alert_danger_("{.arg arg_value} cannot contain {.val NA} "
                                  "for a STRING_LIST algorithm argument"s +
                                  arg_name_in.get_cstring());
                break;
            }

            std::vector<const char *> str_list;
            for (R_xlen_t i = 0; i < v.size(); ++i) {
                Rcpp::String s(v[i]);
                str_list.push_back(s.get_cstring());
            }
            str_list.push_back(nullptr);

            ret = GDALAlgorithmArgSetAsStringList(hArg, str_list.data());
        }
        break;

        case GAAT_INTEGER_LIST:
        {
            if (!Rcpp::is<Rcpp::LogicalVector>(arg_value) &&
                !Rcpp::is<Rcpp::IntegerVector>(arg_value) &&
                !Rcpp::is<Rcpp::NumericVector>(arg_value)) {

                cli_alert_danger_("integer or numeric vector required for an "
                                  "INTEGER_LIST algorithm argument: "s +
                                  arg_name_in.get_cstring());
                break;
            }

            Rcpp::IntegerVector v(arg_value);
            if (v.size() < 1) {
                cli_alert_danger_("{.arg arg_value} is empty");
                break;
            }
            if (Rcpp::is_true(Rcpp::any(Rcpp::is_na(v)))) {
                cli_alert_danger_("{.arg arg_value} cannot contain {.val NA} "
                                  "for an INTEGER_LIST algorithm argument");
                break;
            }

            ret = GDALAlgorithmArgSetAsIntegerList(hArg, v.size(), v.begin());
        }
        break;

        case GAAT_REAL_LIST:
        {
            if (!Rcpp::is<Rcpp::LogicalVector>(arg_value) &&
                !Rcpp::is<Rcpp::IntegerVector>(arg_value) &&
                !Rcpp::is<Rcpp::NumericVector>(arg_value)) {

                cli_alert_danger_("numeric vector required for a REAL_LIST "
                                  "algorithm argument: "s +
                                  arg_name_in.get_cstring());
                break;
            }

            Rcpp::NumericVector v(arg_value);
            if (v.size() < 1) {
                cli_alert_danger_("{.arg arg_value} is empty");
                break;
            }
            if (Rcpp::is_true(Rcpp::any(Rcpp::is_na(v)))) {
                cli_alert_danger_("{.arg arg_value} cannot contain {.val NA} "
                                  "for an REAL_LIST algorithm argument");
                break;
            }

            ret = GDALAlgorithmArgSetAsDoubleList(hArg, v.size(), v.begin());
        }
        break;

        case GAAT_DATASET:
        {
            if (m_map_input_hDS.count(arg_name_in.get_cstring()) > 0 ||
                m_map_input_hDS.count(true_arg_name) > 0) {

                cli_alert_danger_("this argument was set in {.cls GDALAlg} "
                                  "object instantiation, cannot set manually");
                break;
            }

            if (EQUAL(GDALAlgorithmArgGetName(hArg), "like") &&
                m_map_input_hDS.count("like") > 0) {

                cli_alert_danger_(".{str like} arg was set in {.cls GDALAlg} "
                                  "object instantiation, cannot set manually");
                break;
            }

            int ds_input_flags = GDALAlgorithmArgGetDatasetInputFlags(hArg);

            if (Rcpp::is<Rcpp::CharacterVector>(arg_value)) {
                if (!(ds_input_flags & GADV_NAME)) {
                    cli_alert_danger_("argument does not accept a dataset "
                                      "name as input (object required): "s +
                                      arg_name_in.get_cstring());
                    break;
                }
                Rcpp::CharacterVector v(arg_value);
                if (v.size() != 1 || Rcpp::CharacterVector::is_na(v[0])) {
                    cli_alert_danger_("string input must be a length-1 "
                                      "character vector for DATASET algorithm "
                                      "argument"s + arg_name_in.get_cstring());
                    break;
                }
                Rcpp::String val(enc_to_utf8_(v));
                ret = GDALAlgorithmArgSetAsString(hArg, val.get_cstring());
                break;
            }
            else if (is_gdalraster_obj_(arg_value)) {
                if (!(ds_input_flags & GADV_OBJECT)) {
                    cli_alert_danger_("argument does not accept a dataset "
                                      "object as input (DSN required, may be "
                                      "created by algorithm)"s +
                                      arg_name_in.get_cstring());
                    break;
                }
                const Rcpp::String cls = arg_value.attr("class");
                if (cls == "Rcpp_GDALRaster") {
                    const GDALRaster &ds = Rcpp::as<GDALRaster &>(arg_value);
                    ret = GDALAlgorithmArgSetDataset(
                        hArg, ds.getGDALDatasetH_());

                    break;
                }
                else if (cls == "Rcpp_GDALVector") {
                    const GDALVector &ds = Rcpp::as<GDALVector &>(arg_value);
                    ret = GDALAlgorithmArgSetDataset(
                        hArg, ds.getGDALDatasetH_());

                    // FIXME: "input" or "dataset" should be okay as of
                    // GDAL 3.13 for vector algorithms, but probably
                    // should not rely on hard coding the names
                    if (ret) {
                        if (EQUAL(arg_name_in.get_cstring(), "input") ||
                            EQUAL(arg_name_in.get_cstring(), "dataset")) {

                            m_in_vector_props.arg_name = true_arg_name;
                            m_in_vector_props.driver_short_name =
                                ds.getDriverShortName();
                            m_in_vector_props.layer_name = ds.getName();
                            m_in_vector_props.is_sql = ds.m_is_sql;
                            m_in_vector_props.layer_sql = ds.m_layer_name;
                            m_in_vector_props.sql_dialect = ds.m_dialect;
                            m_in_vector_props.is_set = true;
                        }
                        else if (EQUAL(arg_name_in.get_cstring(), "like")) {
                            m_like_vector_props.driver_short_name =
                                ds.getDriverShortName();
                            m_like_vector_props.layer_name = ds.getName();
                            m_like_vector_props.is_sql = ds.m_is_sql;
                            m_like_vector_props.layer_sql = ds.m_layer_name;
                            m_like_vector_props.sql_dialect = ds.m_dialect;
                            m_like_vector_props.is_set = true;
                        }
                    }
                    break;
                }
                else {
                    cli_alert_danger_("unhandled object of class {.cls "s +
                                      cls.get_cstring() + "} given for: " +
                                      arg_name_in.get_cstring());
                    break;
                }
            }
            else {
                cli_alert_danger_("unsupported input type for a DATASET "
                                  "algorithm argument: "s +
                                  arg_name_in.get_cstring());
            }
        }
        break;

        case GAAT_DATASET_LIST:
        {
            if (m_map_input_hDS.count(arg_name_in.get_cstring()) > 0 ||
                m_map_input_hDS.count(true_arg_name) > 0) {

                cli_alert_danger_("this argument was set in {.cls GDALAlg} "
                                  "object instantiation, cannot set manually");
                break;
            }

            if (EQUAL(GDALAlgorithmArgGetName(hArg), "like") &&
                m_map_input_hDS.count("like") > 0) {

                cli_alert_danger_(".{str like} arg was set in {.cls GDALAlg} "
                                  "object instantiation, cannot set manually");
                break;
            }

            int ds_input_flags = GDALAlgorithmArgGetDatasetInputFlags(hArg);

            if (Rcpp::is<Rcpp::CharacterVector>(arg_value)) {
                if (!(ds_input_flags & GADV_NAME)) {
                    cli_alert_danger_("argument does not accept dataset "
                                      "names as input: "s +
                                      arg_name_in.get_cstring());
                    break;
                }
                Rcpp::CharacterVector v(arg_value);
                if (v.size() < 1) {
                    cli_alert_danger_("{.arg arg_value} is empty");
                    break;
                }
                if (Rcpp::is_true(Rcpp::any(Rcpp::is_na(v)))) {
                    cli_alert_danger_("{.arg arg_value} cannot contain "
                                      "{.val NA} for a DATASET_LIST algorithm "
                                      "argument");
                    break;
                }
                v = (enc_to_utf8_(v));
                std::vector<const char *> str_list;
                for (R_xlen_t i = 0; i < v.size(); ++i) {
                    Rcpp::String s(v[i]);
                    str_list.push_back(s.get_cstring());
                }
                str_list.push_back(nullptr);
                ret = GDALAlgorithmArgSetDatasetNames(hArg, str_list.data());
                break;
            }
            else if (Rcpp::is<Rcpp::List>(arg_value) ||
                     is_gdalraster_obj_(arg_value)) {

                if (!(ds_input_flags & GADV_OBJECT)) {
                    cli_alert_danger_("argument does not accept dataset "
                                      "objects as input: "s +
                                      arg_name_in.get_cstring());
                    break;
                }

                Rcpp::List ds_list;
                if (is_gdalraster_obj_(arg_value))
                    ds_list = Rcpp::List::create(arg_value);
                else
                    ds_list = Rcpp::List(arg_value);

                std::vector<GDALDatasetH> pahDS;
                bool in_vector_props_were_set = false;
                int nInputVectorDatasets = 0;
                for (R_xlen_t i = 0; i < ds_list.size(); ++i) {
                    if (is_gdalraster_obj_(ds_list[i])) {
                        const Rcpp::RObject &x(ds_list[i]);
                        const Rcpp::String cls = x.attr("class");
                        if (cls == "Rcpp_GDALRaster") {
                            const GDALRaster &ds = Rcpp::as<GDALRaster &>(x);
                            pahDS.push_back(ds.getGDALDatasetH_());
                        }
                        else if (cls == "Rcpp_GDALVector") {
                            const GDALVector &ds = Rcpp::as<GDALVector &>(x);
                            pahDS.push_back(ds.getGDALDatasetH_());
                            ++nInputVectorDatasets;

                            // FIXME: "input" or "dataset" should be okay as of
                            // GDAL 3.13 for vector algorithms, but probably
                            // should not rely on hard coding the names
                            if ((EQUAL(arg_name_in.get_cstring(), "input") ||
                                 EQUAL(arg_name_in.get_cstring(), "dataset")) &&
                                !in_vector_props_were_set) {

                                m_in_vector_props.arg_name = true_arg_name;
                                m_in_vector_props.driver_short_name =
                                    ds.getDriverShortName();
                                m_in_vector_props.layer_name = ds.getName();
                                m_in_vector_props.is_sql = ds.m_is_sql;
                                m_in_vector_props.layer_sql = ds.m_layer_name;
                                m_in_vector_props.sql_dialect = ds.m_dialect;
                                m_in_vector_props.is_set = true;
                                in_vector_props_were_set = true;
                            }
                        }
                        else {
                            cli_alert_danger_("unhandled object of class "
                                              "{.cls "s + cls.get_cstring() +
                                              "} given for: " +
                                              arg_name_in.get_cstring());
                            break;
                        }
                    }
                    else {
                        cli_alert_danger_("an element contains invalid input, "
                                          "in the list given for: "s +
                                          arg_name_in.get_cstring());;
                        break;
                    }
                }
                if (!pahDS.empty()) {
                    ret = GDALAlgorithmArgSetDatasets(hArg, pahDS.size(),
                                                      pahDS.data());

                    if (nInputVectorDatasets > 1) {
                        // since currently, auto setting args from GDALVector
                        // input is not supported for multiple input datasets
                        m_in_vector_props = {};
                    }
                    break;
                }
            }
            else {
                cli_alert_danger_("DATASET_LIST algorithm argument requires a "
                                  "character vector of names, or list of "
                                  "objects");
            }
        }
        break;

        default:
        {
            Rcpp::Rcout << "GDALAlgorithmArgType: " <<
                           GDALAlgorithmArgGetType(hArg) << "\n";
            cli_alert_danger_("unhandled GDAL argument type");
        }
        break;
    }

    GDALAlgorithmArgRelease(hArg);
    return ret;
#endif  // GDALALG_MIN_GDAL_
}

bool GDALAlg::parseCommandLineArgs() {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    Rcpp::stop(GDALALG_MIN_GDAL_MSG_);
#else

    // parses cl args which sets the values, and also instantiates m_hActualAlg

    if (!m_hAlg) {
        if (!quiet)
            cli_alert_danger_("algorithm not instantiated");
        return false;
    }

    if (m_haveParsedCmdLineArgs) {
        if (!quiet)
            cli_alert_danger_("{.code parseCommandLineArgs()} can only be "
                              "called once per instance");
        return false;
    }

    bool res = true;

    if (!m_map_input_hDS.empty()) {

        // set dataset object inputs directly

        for (auto it = m_map_input_hDS.begin(); it != m_map_input_hDS.end();
             ++it) {

            GDALAlgorithmArgH hArg =
                GDALAlgorithmGetArg(m_hAlg, it->first.c_str());

            if (hArg) {
                if (GDALAlgorithmArgGetType(hArg) == GAAT_DATASET) {
                    if (it->second.size() > 1) {
                        cli_alert_danger_(it->first + ": dataset list given "
                                          "where single dataset expected");

                        res = false;
                    } else {
                        res = GDALAlgorithmArgSetDataset(hArg, it->second[0]);
                    }
                }
                else if (GDALAlgorithmArgGetType(hArg) == GAAT_DATASET_LIST) {
                    res = GDALAlgorithmArgSetDatasets(hArg, it->second.size(),
                                                      it->second.data());
                }
                else {
                    res = false;
                }

                GDALAlgorithmArgRelease(hArg);
                if (!res)
                    break;
            }
        }
    }

    if (res && this->setVectorArgsFromObject &&
        (m_in_vector_props.is_set || m_like_vector_props.is_set)) {

        // directly set certain arguments from input GDALVector object(s)

        if (m_in_vector_props.is_set) {
            GDALAlgorithmArgH hArg = GDALAlgorithmGetArg(
                m_hAlg, m_in_vector_props.arg_name.c_str());

            if (GDALAlgorithmArgGetType(hArg) == GAAT_DATASET_LIST) {
                if (m_num_input_datasets > 1) {
                    GDALAlgorithmArgRelease(hArg);
                    cli_alert_danger_("setting args from {.cls GDALVector} "
                                      "currently unsupported for multiple "
                                      "input objects");
                }
            }
            else if (GDALAlgorithmArgGetType(hArg) != GAAT_DATASET) {
                GDALAlgorithmArgRelease(hArg);
                Rcpp::stop("setting args from `GDALVector` incompatible with "
                           "the algorithm argument type of \"input\" arg");
            }
            GDALAlgorithmArgRelease(hArg);
        }

        const Rcpp::List &alg_info = info();
        const Rcpp::CharacterVector &arg_names = alg_info["arg_names"];

        // check for potential args to auto-set
        // some also have aliases to check for
        for (Rcpp::String arg_name : arg_names) {
            const char *pszArgName = arg_name.get_cstring();
            const Rcpp::List &arg_info = argInfo(pszArgName);
            const Rcpp::CharacterVector &aliases = arg_info["aliases"];
            const Rcpp::CharacterVector &aliases_in_args =
                Rcpp::intersect(aliases, m_args_no_leading_dash);

            if (contains_str_(m_args, pszArgName) ||
                aliases_in_args.size() > 0) {

                if (!quiet) {
                    cli_alert_("argument: "s + pszArgName);
                    cli_alert_warning_("the value given in {.arg args} "
                                       "overrides setting from an input "
                                       "object");
                }
            }
            // input-format
            else if (m_in_vector_props.is_set &&
                     EQUAL(pszArgName, "input-format")) {

                // this one can fail silently since it is optional anyway
                res = setArg(arg_name,
                             Rcpp::wrap(m_in_vector_props.driver_short_name));
            }
            // input-layer
            else if (m_in_vector_props.is_set && !m_in_vector_props.is_sql &&
                     EQUAL(pszArgName, "input-layer")) {

                res = setArg(arg_name,
                             Rcpp::wrap(m_in_vector_props.layer_name));

                if (!res) {
                    cli_alert_danger_("argument: "s + pszArgName);
                    Rcpp::warning("failed to set from object");
                    break;
                }
            }
            // sql
            else if (m_in_vector_props.is_set && m_in_vector_props.is_sql &&
                     EQUAL(pszArgName, "sql")) {

                res = setArg(arg_name,
                             Rcpp::wrap(m_in_vector_props.layer_sql));

                if (!res) {
                    cli_alert_danger_("argument: "s + pszArgName);
                    Rcpp::warning("failed to set from object");
                    break;
                }
            }
            // dialect
            else if (m_in_vector_props.is_set && m_in_vector_props.is_sql &&
                     EQUAL(pszArgName, "dialect")) {

                if (!m_in_vector_props.sql_dialect.empty()) {
                    res = setArg(arg_name,
                                 Rcpp::wrap(m_in_vector_props.sql_dialect));
                }

                if (!res) {
                    cli_alert_danger_("argument: "s + pszArgName);
                    Rcpp::warning("failed to set from object");
                    break;
                }
            }
            // like-sql
            else if (m_like_vector_props.is_set && m_like_vector_props.is_sql &&
                     EQUAL(pszArgName, "like-sql")) {

                res = setArg(arg_name,
                             Rcpp::wrap(m_like_vector_props.layer_sql));

                if (!res) {
                    cli_alert_danger_("argument: "s + pszArgName);
                    Rcpp::warning("failed to set from object");
                    break;
                }
            }
            // like-layer
            else if (m_like_vector_props.is_set && !m_like_vector_props.is_sql
                     && EQUAL(pszArgName, "like-layer")) {

                res = setArg(arg_name,
                             Rcpp::wrap(m_like_vector_props.layer_name));

                if (!res) {
                    cli_alert_danger_("argument: "s + pszArgName);
                    Rcpp::warning("failed to set from object");
                    break;
                }
            }
        }
    }

    std::vector<const char*> arg_list = {};
    if (m_args.size() > 0) {
        for (Rcpp::String arg : m_args) {
            arg_list.push_back(arg.get_cstring());
        }
    }
    arg_list.push_back(nullptr);

    if (res && arg_list.size() > 1) {
        // parse arguments from m_args
        res = GDALAlgorithmParseCommandLineArguments(m_hAlg, arg_list.data());
    }

    if (res) {
        m_haveParsedCmdLineArgs = true;
        if (m_hActualAlg == nullptr) {
            m_hActualAlg = GDALAlgorithmGetActualAlgorithm(m_hAlg);
            if (!m_hActualAlg)
                res = false;
        }
    }

    return res;
#endif  // GDALALG_MIN_GDAL_
}

Rcpp::List GDALAlg::getExplicitlySetArgs() const {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    Rcpp::stop(GDALALG_MIN_GDAL_MSG_);
#else
    if (!m_hAlg)
        Rcpp::stop("algorithm not instantiated");

    const CPLStringList aosArgNames(
        GDALAlgorithmGetArgNames(m_hActualAlg ? m_hActualAlg : m_hAlg));

    Rcpp::List out = Rcpp::List::create();

    const int nCount = aosArgNames.size();
    if (nCount > 0) {
        for (int i = 0; i < nCount; ++i) {
            GDALAlgorithmArgH hArg = nullptr;
            hArg = GDALAlgorithmGetArg(m_hActualAlg ? m_hActualAlg : m_hAlg,
                                       aosArgNames[i]);
            if (!hArg) {
                if (!quiet)
                    cli_alert_danger_("got NULL for: "s + aosArgNames[i]);
                continue;
            }
            if (GDALAlgorithmArgIsExplicitlySet(hArg)) {
                Rcpp::String arg_name_out(aosArgNames[i]);
                arg_name_out.replace_all("-", "_");

                // dataset object
                if (GDALAlgorithmArgGetType(hArg) == GAAT_DATASET) {
                    GDALArgDatasetValueH hArgDSValue = nullptr;
                    hArgDSValue = GDALAlgorithmArgGetAsDatasetValue(hArg);
                    if (!hArgDSValue) {
                        if (!quiet)
                            cli_alert_danger_("output dataset value is NULL");
                        GDALAlgorithmArgRelease(hArg);
                        continue;
                    }

                    GDALArgDatasetType ds_type =
                        GDALAlgorithmArgGetDatasetType(hArg);

                    std::string ds_name(
                        GDALArgDatasetValueGetName(hArgDSValue));

                    if (ds_type & GDAL_OF_RASTER) {
                        ds_name = "<raster dataset object: " + ds_name + ">";
                    }
                    else if (ds_type & GDAL_OF_VECTOR) {
                        ds_name = "<vector dataset object: " + ds_name + ">";
                    }
                    else if (ds_type & GDAL_OF_MULTIDIM_RASTER) {
                        ds_name = ("<mutlidim raster dataset object: " +
                                   ds_name + ">");
                    }
                    else {
                        // should not occur
                        ds_name = "<unrecognized dataset object>";
                    }

                    GDALArgDatasetValueRelease(hArgDSValue);
                    out.push_back(ds_name, arg_name_out);
                }
                // list of GDAL datasets
                else if ((GDALAlgorithmArgGetType(hArg) ==
                          GAAT_DATASET_LIST)) {

                    out.push_back("<list of dataset objects>", arg_name_out);
                }
                // boolean, string, integer, real, and lists of
                else {
                    out.push_back(getArgValue_(hArg), arg_name_out);
                }
            }
            GDALAlgorithmArgRelease(hArg);
        }
    }

    return out;
#endif
}

bool GDALAlg::run() {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    Rcpp::stop(GDALALG_MIN_GDAL_MSG_);
#else

    if (!m_hAlg) {
        if (!quiet)
            cli_alert_danger_("algorithm not instantiated");
        return false;
    }

    if (m_hasRun) {
        if (!quiet)
            cli_alert_danger_("algorithm has already run");
        return false;
    }

    if (!m_haveParsedCmdLineArgs) {
        if (!parseCommandLineArgs()) {
            if (!quiet)
                cli_alert_danger_("parse command line arguments failed");
            return false;
        }
    }

    if (!m_hActualAlg) {
        if (!quiet)
            cli_alert_danger_("actual algorithm handle is NULL");
        return false;
    }

    bool res = GDALAlgorithmRun(m_hActualAlg,
                                quiet ? nullptr : GDALTermProgressR,
                                nullptr);

    if (res)
        m_hasRun = true;

    return res;
#endif  // GDALALG_MIN_GDAL_
}

SEXP GDALAlg::output() const {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    Rcpp::stop(GDALALG_MIN_GDAL_MSG_);
#else

    if (!m_hAlg)
        Rcpp::stop("algorithm not instantiated");

    if (!m_hasRun || !m_hActualAlg)
        Rcpp::stop("algorithm has not run");

    std::vector<std::string> out_arg_names = getOutputArgNames_();
    if (out_arg_names.size() == 0) {
        Rcpp::stop("no output argument names found");
    }
    if (out_arg_names.size() > 1) {
        Rcpp::stop(
            "algorithm has multiple outputs, use method `outputs()` instead");
    }

    Rcpp::List out = outputs();
    if (out.size() > 0)
        return out[0];
    else
        return R_NilValue;
#endif  // GDALALG_MIN_GDAL_
}

Rcpp::List GDALAlg::outputs() const {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    Rcpp::stop(GDALALG_MIN_GDAL_MSG_);
#else

    if (!m_hAlg)
        Rcpp::stop("algorithm not instantiated");

    if (!m_hasRun || !m_hActualAlg)
        Rcpp::stop("algorithm has not run");

    std::vector<std::string> out_arg_names = getOutputArgNames_();
    if (out_arg_names.size() == 0)
        Rcpp::stop("no output argument names found");

    Rcpp::List out = Rcpp::List::create();

    for (const std::string &arg_name : out_arg_names) {
        GDALAlgorithmArgH hArg = nullptr;
        hArg = GDALAlgorithmGetArg(m_hActualAlg, arg_name.c_str());
        if (!hArg) {
            if (!quiet)
                cli_alert_danger_("got NULL for arg: "s + arg_name);
            continue;
        }

        if (GDALAlgorithmArgIsOutput(hArg)) {
            Rcpp::String arg_name_out(arg_name);
            arg_name_out.replace_all("-", "_");
            out.push_back(getArgValue_(hArg), arg_name_out);
        }

        GDALAlgorithmArgRelease(hArg);
    }

    return out;
#endif  // GDALALG_MIN_GDAL_
}

bool GDALAlg::close() {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    Rcpp::stop(GDALALG_MIN_GDAL_MSG_);
#else

    if (!m_hAlg) {
        if (!quiet)
            cli_alert_danger_("algorithm not instantiated");
        return false;
    }

    if (!m_hasRun) {
        if (!quiet)
            cli_alert_danger_("algorithm has not run");
        return false;
    }

    if (m_hasFinalized) {
        if (!quiet)
            cli_alert_danger_("algorithm has already been finalized");
        return false;
    }

    if (m_hActualAlg) {
        return GDALAlgorithmFinalize(m_hActualAlg);
    }
    else {
        if (!quiet)
            cli_alert_danger_("actual algorithm is NULL");
        return false;
    }
#endif  // GDALALG_MIN_GDAL_
}

void GDALAlg::release() {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    return;
#else

    if (m_hActualAlg) {
        if (m_hasRun && !m_hasFinalized)
            GDALAlgorithmFinalize(m_hActualAlg);
        GDALAlgorithmRelease(m_hActualAlg);
        m_hActualAlg = nullptr;
    }

    if (m_hAlg) {
        GDALAlgorithmRelease(m_hAlg);
        m_hAlg = nullptr;
    }

#endif  // GDALALG_MIN_GDAL_
}

void GDALAlg::show() const {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    cli_alert_danger_(GDALALG_MIN_GDAL_MSG_);
#else

    cli_text_("C++ object of class {.cls GDALAlg}");

    if (!m_hAlg) {
        cli_alert_("algorithm not instantiated");
    }
    else {
        const GDALAlgorithmH &alg = m_hActualAlg ? m_hActualAlg : m_hAlg;
        cli_ul_();
        cli_li_("{.emph Command}: {.str "s + m_cmd_str + "}");
        cli_li_("{.emph Description}: "s + GDALAlgorithmGetDescription(alg));
        cli_li_("{.emph Help URL}: {.url "s + GDALAlgorithmGetHelpFullURL(alg) +
                "}");
        cli_end_();
    }
#endif  // GDALALG_MIN_GDAL_
}

// ****************************************************************************
// class methods for internal use not exposed in R
// ****************************************************************************

Rcpp::CharacterVector GDALAlg::parseListArgs_(
    const Rcpp::List &list_args) {

    // convert arguments in a named list to character vector form and return it
    // arguments in list form must use arg long names
    // dataset/dataset_list args are added to the std::map m_map_input_hDS

    Rcpp::CharacterVector arg_vec = Rcpp::CharacterVector::create();

    R_xlen_t num_args = 0;
    if (list_args.size() == 0)
        return arg_vec;
    else
        num_args = list_args.size();

    Rcpp::CharacterVector arg_names = list_args.names();
    if (arg_names.size() == 0 || arg_names.size() != num_args)
        Rcpp::stop("argument list must have named elements");

    for (R_xlen_t i = 0; i < num_args; ++i) {
        Rcpp::String nm(arg_names[i]);
        if (!nm.get_cstring() || nm == NA_STRING || nm == "")
            continue;

        if (list_args[i] == R_NilValue) {
            cli_alert_warning_("ignoring NULL arg: "s + nm.get_cstring());
            continue;
        }

        nm.replace_all("--", "");
        nm.replace_all("_", "-");
        if (STARTS_WITH(nm.get_cstring(), "-") &&
            std::strlen(nm.get_cstring()) < 3) {

            cli_alert_danger_("argument: "s + arg_names[i]);
            Rcpp::stop("arguments in list format must use \"long\" names");
        }
        std::string nm_no_lead_dashes(nm);
        nm.push_front("--");

        // boolean
        if (Rcpp::is<Rcpp::LogicalVector>(list_args[i])) {
            const Rcpp::LogicalVector &lv = list_args[i];
            if (lv[0] == TRUE) {
                arg_vec.push_back(nm);
                continue;
            }
        }

        // string, string list
        if (Rcpp::is<Rcpp::CharacterVector>(list_args[i])) {
            Rcpp::CharacterVector arg_value = enc_to_utf8_(list_args[i]);
            nm += "=";
            nm += paste_collapse_(arg_value, ",");
            arg_vec.push_back(nm);
            continue;
        }

        // integer, integer list, real, real list
        if (Rcpp::is<Rcpp::IntegerVector>(list_args[i]) ||
            Rcpp::is<Rcpp::NumericVector>(list_args[i])) {

            nm += "=";
            nm += paste_collapse_(list_args[i], ",");
            arg_vec.push_back(nm);
            continue;
        }

        // potentially a list of datasets
        if (Rcpp::is<Rcpp::List>(list_args[i])) {
            const Rcpp::List &list_tmp = list_args[i];

            std::vector<GDALDatasetH> ds_list = {};

            for (R_xlen_t j = 0; j < list_tmp.size(); ++j) {
                if (is_gdalraster_obj_(list_tmp[j])) {
                    const Rcpp::RObject &val = list_tmp[j];
                    const Rcpp::String cls = val.attr("class");
                    if (cls == "Rcpp_GDALRaster") {
                        const GDALRaster &ds =
                            Rcpp::as<GDALRaster &>(list_tmp[j]);
                        ds_list.push_back(ds.getGDALDatasetH_());
                    }
                    else if (cls == "Rcpp_GDALVector") {
                        const GDALVector &ds =
                            Rcpp::as<GDALVector &>(list_tmp[j]);

                        // FIXME: "input" or "dataset" should be okay as of
                        // GDAL 3.13 for vector algorithms, but probably
                        // should not rely on hard coding the names
                        ds_list.push_back(ds.getGDALDatasetH_());
                        if ((EQUAL(nm.get_cstring(), "--input") ||
                             EQUAL(nm.get_cstring(), "--dataset")) &&
                            !m_in_vector_props.is_set) {

                            m_in_vector_props.arg_name = nm_no_lead_dashes;
                            m_in_vector_props.driver_short_name =
                                ds.getDriverShortName();
                            m_in_vector_props.layer_name = ds.getName();
                            m_in_vector_props.is_sql = ds.m_is_sql;
                            m_in_vector_props.layer_sql = ds.m_layer_name;
                            m_in_vector_props.sql_dialect = ds.m_dialect;
                            m_in_vector_props.is_set = true;
                        }
                    }
                }
                else {
                    cli_alert_warning_("an element of the input list is not a "
                                       "dataset object");
                }
            }

            if (!ds_list.empty()) {
                m_map_input_hDS[nm_no_lead_dashes] = ds_list;
            }
            else {
                cli_alert_danger_("unhandled list input for: "s +
                                  nm_no_lead_dashes.c_str());
            }
            continue;
        }

        // potentially a single dataset
        if (is_gdalraster_obj_(list_args[i])) {
            const Rcpp::RObject &val = list_args[i];
            const Rcpp::String cls = val.attr("class");
            if (cls == "Rcpp_GDALRaster") {
                const GDALRaster &ds = Rcpp::as<GDALRaster &>(list_args[i]);
                std::vector<GDALDatasetH> ds_list = {};
                ds_list.push_back(ds.getGDALDatasetH_());
                m_map_input_hDS[nm_no_lead_dashes] = ds_list;
                continue;
            }
            if (cls == "Rcpp_GDALVector") {
                const GDALVector &ds = Rcpp::as<GDALVector &>(list_args[i]);
                std::vector<GDALDatasetH> ds_list = {};
                ds_list.push_back(ds.getGDALDatasetH_());
                m_map_input_hDS[nm_no_lead_dashes] = ds_list;

                // FIXME: "input" or "dataset" should be okay as of
                // GDAL 3.13 for vector algorithms, but probably
                // should not rely on hard coding the names
                if (EQUAL(nm.get_cstring(), "--input") ||
                    EQUAL(nm.get_cstring(), "--dataset")) {

                    m_in_vector_props.arg_name = nm_no_lead_dashes;
                    m_in_vector_props.driver_short_name =
                        ds.getDriverShortName();
                    m_in_vector_props.layer_name = ds.getName();
                    m_in_vector_props.is_sql = ds.m_is_sql;
                    m_in_vector_props.layer_sql = ds.m_layer_name;
                    m_in_vector_props.sql_dialect = ds.m_dialect;
                    m_in_vector_props.is_set = true;
                }
                else if (EQUAL(nm.get_cstring(), "--like")) {
                    m_like_vector_props.driver_short_name =
                        ds.getDriverShortName();
                    m_like_vector_props.layer_name = ds.getName();
                    m_like_vector_props.is_sql = ds.m_is_sql;
                    m_like_vector_props.layer_sql = ds.m_layer_name;
                    m_like_vector_props.sql_dialect = ds.m_dialect;
                    m_like_vector_props.is_set = true;
                }
                continue;
            }
        }

        cli_alert_danger_("unhandled input type for: "s +
                          nm_no_lead_dashes.c_str());
    }

    if (m_map_input_hDS.count("input") > 0 ||
        m_map_input_hDS.count("dataset") > 0) {

        if (m_map_input_hDS.count("input") > 0) {
            std::vector<GDALDatasetH> ds_list = m_map_input_hDS["input"];
            m_num_input_datasets += ds_list.size();
        }

        if (m_map_input_hDS.count("dataset") > 0) {
            std::vector<GDALDatasetH> ds_list = m_map_input_hDS["dataset"];
            m_num_input_datasets += ds_list.size();
        }

        if (m_num_input_datasets > 1 && m_in_vector_props.is_set) {
            // since currently, auto setting args from GDALVector input is
            // not supported for multiple input datasets
            m_in_vector_props = {};
        }
    }

    return arg_vec;
}

void GDALAlg::instantiateAlg_() {
#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    Rcpp::stop(GDALALG_MIN_GDAL_MSG_);
#else
    // instantiate m_hAlg

    if (m_hAlg || m_hActualAlg) {
        Rcpp::stop(
            "instantiateAlg_(): algorithm object already instantiated");
    }

    GDALAlgorithmRegistryH reg = nullptr;
    reg = GDALGetGlobalAlgorithmRegistry();
    if (!reg)
        Rcpp::stop("failed to obtain global algorithm registry");

    // For GDAL < 3.12, step through the path if there are subcommands, and
    // use GDALAlgorithmRegistryInstantiateAlg().
    // GDAL 3.12 adds GDALAlgorithmRegistryInstantiateAlgFromPath().

#if GDAL_VERSION_NUM >= GDAL_COMPUTE_VERSION(3, 12, 0)
    std::vector<const char *> alg_path = {};
    for (const Rcpp::String s : m_cmd) {
        alg_path.push_back(s.get_cstring());
    }
    alg_path.push_back(nullptr);

    m_hAlg = GDALAlgorithmRegistryInstantiateAlgFromPath(reg, alg_path.data());
    if (!m_hAlg) {
        cli_alert_danger_("algorithm path: "s + m_cmd_str.c_str());
        Rcpp::stop("failed to instantiate CLI algorithm from path");
    }

#else
    if (m_cmd.size() == 1) {
        Rcpp::String cmd(m_cmd[0]);

        m_hAlg = GDALAlgorithmRegistryInstantiateAlg(reg, cmd.get_cstring());

        if (!m_hAlg) {
            GDALAlgorithmRegistryRelease(reg);
            cli_alert_danger_("top-level command: "s + cmd.get_cstring());
            Rcpp::stop("failed to instantiate CLI algorithm");
        }
    }
    else {
        std::vector<GDALAlgorithmH> alg_tmp = {};
        Rcpp::String cmd(m_cmd[0]);

        alg_tmp.push_back(
            GDALAlgorithmRegistryInstantiateAlg(reg, cmd.get_cstring()));

        if (!alg_tmp[0]) {
            GDALAlgorithmRegistryRelease(reg);
            cli_alert_danger_("top-level command: "s + cmd.get_cstring());
            Rcpp::stop("failed to instantiate CLI algorithm");
        }
        for (R_xlen_t i = 1; i < m_cmd.size(); ++i) {
            if (i == (m_cmd.size() - 1)) {
                // the final subcommand, instantiate m_hAlg here
                Rcpp::String sub_cmd(m_cmd[i]);

                m_hAlg =
                    GDALAlgorithmInstantiateSubAlgorithm(alg_tmp[i - 1],
                                                         sub_cmd.get_cstring());

                if (!m_hAlg) {
                    for (GDALAlgorithmH alg : alg_tmp) {
                        if (alg)
                            GDALAlgorithmRelease(alg);
                    }
                    GDALAlgorithmRegistryRelease(reg);
                    cli_alert_danger_("subcommand: "s + sub_cmd.get_cstring());
                    Rcpp::stop("failed to instantiate CLI algorithm");
                }
            }
            else {
                Rcpp::String sub_cmd(m_cmd[i]);

                alg_tmp.push_back(
                    GDALAlgorithmInstantiateSubAlgorithm(
                        alg_tmp[i - 1], sub_cmd.get_cstring()));

                if (alg_tmp.back() == nullptr) {
                    for (GDALAlgorithmH alg : alg_tmp) {
                        if (alg)
                            GDALAlgorithmRelease(alg);
                    }
                    GDALAlgorithmRegistryRelease(reg);
                    cli_alert_danger_("subcommand: "s + sub_cmd.get_cstring());
                    Rcpp::stop("failed to instantiate CLI algorithm");
                }
            }
        }

        for (GDALAlgorithmH alg : alg_tmp) {
            if (alg)
                GDALAlgorithmRelease(alg);
        }
    }
#endif  // GDAL 3.12

    if (reg)
        GDALAlgorithmRegistryRelease(reg);

#endif  // GDALALG_MIN_GDAL_
}

std::vector<std::string> GDALAlg::getOutputArgNames_() const {
    std::vector<std::string> names_out = {};

#if GDAL_VERSION_NUM < GDALALG_MIN_GDAL_
    return names_out;
#else
    CPLStringList aosArgNames;
    if (m_hActualAlg) {
        aosArgNames = GDALAlgorithmGetArgNames(m_hActualAlg);
    }
    else {
        if (!quiet)
            cli_alert_warning_("actual algorithm object not instantiated");
        return names_out;
    }

    for (int i = 0; i < aosArgNames.size(); ++i) {
        GDALAlgorithmArgH hArg = nullptr;
        hArg = GDALAlgorithmGetArg(m_hActualAlg, aosArgNames[i]);
        if (!hArg) {
            if (!quiet)
                cli_alert_danger_("got NULL for arg: "s + aosArgNames[i]);
            continue;
        }
        if (GDALAlgorithmArgIsOutput(hArg)) {
            names_out.push_back(aosArgNames[i]);
        }
        GDALAlgorithmArgRelease(hArg);
    }

    return names_out;
#endif  // GDALALG_MIN_GDAL_
}

#if GDAL_VERSION_NUM >= GDALALG_MIN_GDAL_
SEXP GDALAlg::getArgValue_(const GDALAlgorithmArgH &hArg) const {
    if (!hArg)
        Rcpp::stop("getArgValue_(): got NULL for the GDALAlgorithmArgH");

    SEXP out = R_NilValue;

    switch (GDALAlgorithmArgGetType(hArg)) {
        case GAAT_BOOLEAN:
        {
            out =
                Rcpp::LogicalVector::create(GDALAlgorithmArgGetAsBoolean(hArg));
        }
        break;

        case GAAT_STRING:
        {
            out = Rcpp::wrap(GDALAlgorithmArgGetAsString(hArg));
        }
        break;

        case GAAT_INTEGER:
        {
            out =
                Rcpp::IntegerVector::create(GDALAlgorithmArgGetAsInteger(hArg));
        }
        break;

        case GAAT_REAL:
        {
            out =
                Rcpp::NumericVector::create(GDALAlgorithmArgGetAsDouble(hArg));
        }
        break;

        case GAAT_STRING_LIST:
        {
            const CPLStringList aosValue(GDALAlgorithmArgGetAsStringList(hArg));
            out = wrap_gdal_string_list_(aosValue);
        }
        break;

        case GAAT_INTEGER_LIST:
        {
            size_t nCount = 0;
            const int *panValue =
                GDALAlgorithmArgGetAsIntegerList(hArg, &nCount);

            if (panValue && nCount > 0) {
                out = Rcpp::IntegerVector(panValue, panValue + nCount);
            }
            else {
                out = Rcpp::IntegerVector::create(NA_INTEGER);
            }
        }
        break;

        case GAAT_REAL_LIST:
        {
            size_t nCount = 0;
            const double *padfValue =
                GDALAlgorithmArgGetAsDoubleList(hArg, &nCount);

            if (padfValue && nCount > 0) {
                out = Rcpp::NumericVector(padfValue, padfValue + nCount);
            }
            else {
                out = Rcpp::NumericVector::create(NA_REAL);
            }
        }
        break;

        case GAAT_DATASET:
        {
            GDALArgDatasetValueH hArgDSValue = nullptr;
            hArgDSValue = GDALAlgorithmArgGetAsDatasetValue(hArg);
            if (!hArgDSValue) {
                if (!quiet)
                    cli_alert_warning_("output dataset value is NULL");
                return R_NilValue;
            }

            GDALDatasetH hDS = nullptr;
            hDS = GDALArgDatasetValueGetDatasetIncreaseRefCount(hArgDSValue);
            if (!hDS) {
                GDALArgDatasetValueRelease(hArgDSValue);
                Rcpp::stop("GDAL dataset object is NULL");
            }

            GDALArgDatasetType ds_type = GDALAlgorithmArgGetDatasetType(hArg);

            if (ds_type & GDAL_OF_RASTER) {
                std::string ds_name(GDALArgDatasetValueGetName(hArgDSValue));
                auto ds = std::make_unique<GDALRaster>();
                ds->setFilename(ds_name);
                ds->setGDALDatasetH_(hDS);
                // hand the object itself to R, which owns and deletes it.
                // Rcpp::wrap(*ptr) would copy it, leaking the original.
                out = Rcpp::wrap(Rcpp::object<GDALRaster>(ds.release()));
            }
            else if (ds_type & GDAL_OF_VECTOR) {
                std::string ds_name(GDALArgDatasetValueGetName(hArgDSValue));
                OGRLayerH hLayer = nullptr;
                std::string layer_name = "";
                if (this->outputLayerNameForOpen == "" ||
                    this->outputLayerNameForOpen == NA_STRING) {

                    hLayer = GDALDatasetGetLayer(hDS, 0);
                }
                else {
                    layer_name = this->outputLayerNameForOpen;
                    hLayer = GDALDatasetGetLayerByName(hDS, layer_name.c_str());
                }
                if (layer_name == "") {
                    // default layer first by index was opened
                    if (hLayer)
                        layer_name = OGR_L_GetName(hLayer);
                }

                auto lyr = std::make_unique<GDALVector>();
                lyr->setDsn_(ds_name);
                lyr->setGDALDatasetH_(hDS, true);
                lyr->setOGRLayerH_(hLayer, layer_name);
                if (hLayer)
                    lyr->setFieldNames_();
                // owned by R, no copy (see the raster case above)
                out = Rcpp::wrap(Rcpp::object<GDALVector>(lyr.release()));
            }
            else if (ds_type & GDAL_OF_MULTIDIM_RASTER) {
                // multidim raster currently only as dataset name
                out = Rcpp::wrap(GDALArgDatasetValueGetName(hArgDSValue));
            }
            else {
                // should not occur
                out = Rcpp::wrap("unrecognized dataset type");
            }

            GDALArgDatasetValueRelease(hArgDSValue);
        }
        break;

        case GAAT_DATASET_LIST:
        {
            // seems to apply to input only, at least currently
            Rcpp::warning(
                "unhandled output of type DATASET_LIST (NULL returned)");
            out = R_NilValue;
        }
        break;

        default:
        {
            Rcpp::Rcout << "GDALAlgorithmArgType: " <<
                GDALAlgorithmArgGetType(hArg) << "\n";

            out = Rcpp::wrap("unhandled argument type");
        }
        break;
    }

    return out;
}
#endif  // GDALALG_MIN_GDAL_

// ****************************************************************************

RCPP_MODULE(mod_GDALAlg) {
    Rcpp::class_<GDALAlg>("GDALAlg")

    .constructor
        ("Default constructor, instantiates the root \"gdal\" entry point")
    .constructor<Rcpp::CharacterVector>
        ("Usage: new(GDALAlg, cmd)")
    .constructor<Rcpp::CharacterVector, Rcpp::RObject>
        ("Usage: new(GDALAlg, cmd, cl_arg)")

    // undocumented read-only fields for internal use
    .field_readonly("m_haveParsedCmdLineArgs",
                    &GDALAlg::m_haveParsedCmdLineArgs)
    .field_readonly("m_hasRun", &GDALAlg::m_hasRun)
    .field_readonly("m_hasFinalized", &GDALAlg::m_hasFinalized)

    // read/write fields
    .field("setVectorArgsFromObject", &GDALAlg::setVectorArgsFromObject)
    .field("outputLayerNameForOpen", &GDALAlg::outputLayerNameForOpen)
    .field("quiet", &GDALAlg::quiet)

    // methods
    .const_method("info", &GDALAlg::info,
        "Return a list of algorithm information")
    .const_method("argInfo", &GDALAlg::argInfo,
        "Return a list of information for an algorithm argument")
    .const_method("usage", &GDALAlg::usage,
        "Print usage information to the console")
    .const_method("usageAsJSON", &GDALAlg::usageAsJSON,
        "Return a list of algorithm information")
    .method("setArg", &GDALAlg::setArg,
        "Set the value of an algorithm argument")
    .method("parseCommandLineArgs", &GDALAlg::parseCommandLineArgs,
        "Parse command line arguments")
    .const_method("getExplicitlySetArgs", &GDALAlg::getExplicitlySetArgs,
        "Return a named list of explicitly set arguments and their values")
    .method("run", &GDALAlg::run,
        "Execute the algorithm")
    .const_method("output", &GDALAlg::output,
        "Return the single output value of this algorithm")
    .const_method("outputs", &GDALAlg::outputs,
        "Return the output value(s) of this algorithm as a named list")
    .method("close", &GDALAlg::close,
        "Complete any pending actions, and return the final status")
    .method("release", &GDALAlg::release,
        "Release memory associated with the algorithm (potentially finalize)")
    .const_method("show", &GDALAlg::show,
        "S4 show()")

    ;
}
