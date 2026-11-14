/* Implementation of class GDALMultiDimRaster. Encapsulates a multidimensional
   GDALDataset and its root GDALGroup, using the GDAL C API.

   Michael D. Sumner
   Copyright (c) 2026 gdalraster authors
*/

#include <gdal.h>
#include <gdal_utils.h>
#include <cpl_conv.h>
#include <cpl_error.h>
#include <cpl_port.h>
#include <cpl_string.h>

#include <Rcpp.h>

#include <algorithm>
#include <string>
#include <vector>

#include "gdalraster.h"
#include "gdalmultidimraster.h"
#include "rcpp_util.h"

using std::string_literals::operator""s;

constexpr int MDIM_MIN_GDAL_ = GDAL_COMPUTE_VERSION(3, 2, 0);


// ****************************************************************************
// helpers not exported to R
// ****************************************************************************

// Normalize a full path to a group or array: "" -> "/", ensure a leading
// "/", and drop a trailing "/" except for the root group
std::string mdim_normalize_path_(const std::string &path) {
    std::string out = path;
    if (out.empty())
        return "/";
    if (out[0] != '/')
        out = "/" + out;
    while (out.size() > 1 && out.back() == '/')
        out.pop_back();
    return out;
}

// Convert a GDAL attribute to an R vector by its data type class:
// string -> character, integer types that fit in int32 -> integer,
// other numeric types -> double, compound and complex types -> raw
SEXP mdim_attribute_to_sexp_(GDALAttributeH hAttr) {
    if (hAttr == nullptr)
        return R_NilValue;

    GDALExtendedDataTypeH hDT = GDALAttributeGetDataType(hAttr);
    if (hDT == nullptr)
        return R_NilValue;

    const GDALExtendedDataTypeClass eClass = GDALExtendedDataTypeGetClass(hDT);
    GDALDataType eDT = GDT_Unknown;
    if (eClass == GEDTC_NUMERIC)
        eDT = GDALExtendedDataTypeGetNumericDataType(hDT);
    GDALExtendedDataTypeRelease(hDT);

    if (eClass == GEDTC_STRING) {
        char **papszValues = GDALAttributeReadAsStringArray(hAttr);
        Rcpp::CharacterVector out = Rcpp::CharacterVector::create();
        if (papszValues != nullptr) {
            for (int i = 0; papszValues[i] != nullptr; ++i)
                out.push_back(papszValues[i]);
        }
        CSLDestroy(papszValues);
        return out;
    }

    if (eClass == GEDTC_NUMERIC && !GDALDataTypeIsComplex(eDT)) {
        size_t nCount = 0;
        if (GDALDataTypeIsInteger(eDT) && GDALGetDataTypeSizeBits(eDT) <= 32 &&
                eDT != GDT_UInt32) {

            int *panValues = GDALAttributeReadAsIntArray(hAttr, &nCount);
            Rcpp::IntegerVector out(nCount);
            for (size_t i = 0; i < nCount; ++i)
                out[i] = panValues[i];
            CPLFree(panValues);
            return out;
        }
        else {
            double *padfValues = GDALAttributeReadAsDoubleArray(hAttr, &nCount);
            Rcpp::NumericVector out(nCount);
            for (size_t i = 0; i < nCount; ++i)
                out[i] = padfValues[i];
            CPLFree(padfValues);
            return out;
        }
    }

    // compound or complex: raw bytes as stored
    size_t nSize = 0;
    GByte *pabyRaw = GDALAttributeReadAsRaw(hAttr, &nSize);
    Rcpp::RawVector out(nSize);
    if (pabyRaw != nullptr) {
        std::copy(pabyRaw, pabyRaw + nSize, out.begin());
        GDALAttributeFreeRawResult(hAttr, pabyRaw, nSize);
    }
    return out;
}

// Convert an array of attribute handles to a named list, and release them
Rcpp::List mdim_attributes_to_list_(GDALAttributeH *pahAttrs, size_t nCount) {
    Rcpp::List out(nCount);
    Rcpp::CharacterVector names(nCount);
    for (size_t i = 0; i < nCount; ++i) {
        names[i] = GDALAttributeGetName(pahAttrs[i]);
        out[i] = mdim_attribute_to_sexp_(pahAttrs[i]);
    }
    if (pahAttrs != nullptr)
        GDALReleaseAttributes(pahAttrs, nCount);
    out.names() = names;
    return out;
}

// Describe an array of dimension handles as a data frame, and release them
static Rcpp::DataFrame dimensions_to_df_(GDALDimensionH *pahDims,
                                         size_t nCount) {

    Rcpp::CharacterVector name(nCount);
    Rcpp::CharacterVector full_name(nCount);
    Rcpp::NumericVector size(nCount);
    Rcpp::CharacterVector type(nCount);
    Rcpp::CharacterVector direction(nCount);
    Rcpp::CharacterVector indexing_variable(nCount);

    for (size_t i = 0; i < nCount; ++i) {
        const char *pszName = GDALDimensionGetName(pahDims[i]);
        name[i] = pszName ? pszName : "";
        const char *pszFullName = GDALDimensionGetFullName(pahDims[i]);
        full_name[i] = pszFullName ? pszFullName : "";
        size[i] = static_cast<double>(GDALDimensionGetSize(pahDims[i]));
        const char *pszType = GDALDimensionGetType(pahDims[i]);
        type[i] = pszType ? pszType : "";
        const char *pszDir = GDALDimensionGetDirection(pahDims[i]);
        direction[i] = pszDir ? pszDir : "";

        GDALMDArrayH hVar = GDALDimensionGetIndexingVariable(pahDims[i]);
        if (hVar != nullptr) {
            const char *pszVar = GDALMDArrayGetFullName(hVar);
            indexing_variable[i] = pszVar ? pszVar : "";
            GDALMDArrayRelease(hVar);
        }
        else {
            indexing_variable[i] = "";
        }
    }
    if (pahDims != nullptr)
        GDALReleaseDimensions(pahDims, nCount);

    return Rcpp::DataFrame::create(
        Rcpp::Named("name") = name,
        Rcpp::Named("full_name") = full_name,
        Rcpp::Named("size") = size,
        Rcpp::Named("type") = type,
        Rcpp::Named("direction") = direction,
        Rcpp::Named("indexing_variable") = indexing_variable,
        Rcpp::Named("stringsAsFactors") = false);
}

static Rcpp::CharacterVector string_list_to_cv_(char **papszList) {
    Rcpp::CharacterVector out = Rcpp::CharacterVector::create();
    if (papszList != nullptr) {
        for (int i = 0; papszList[i] != nullptr; ++i)
            out.push_back(papszList[i]);
    }
    CSLDestroy(papszList);
    return out;
}


// ****************************************************************************
// class GDALMultiDimRaster
// ****************************************************************************

GDALMultiDimRaster::GDALMultiDimRaster()
        : infoOptions(Rcpp::CharacterVector::create()),
          m_open_options(Rcpp::CharacterVector::create()),
          m_allowed_drivers(Rcpp::CharacterVector::create()) {

    // undocumented default constructor with no arguments
    // currently not intended for user code
}

GDALMultiDimRaster::GDALMultiDimRaster(const Rcpp::CharacterVector &filename)
        : GDALMultiDimRaster(filename, true, R_NilValue, false, R_NilValue) {}

GDALMultiDimRaster::GDALMultiDimRaster(const Rcpp::CharacterVector &filename,
                                       bool read_only)
        : GDALMultiDimRaster(filename, read_only, R_NilValue, false,
                             R_NilValue) {}

GDALMultiDimRaster::GDALMultiDimRaster(
        const Rcpp::CharacterVector &filename, bool read_only,
        const Rcpp::CharacterVector &open_options)
        : GDALMultiDimRaster(filename, read_only, open_options, false,
                             R_NilValue) {}

GDALMultiDimRaster::GDALMultiDimRaster(
        const Rcpp::CharacterVector &filename, bool read_only,
        const Rcpp::Nullable<Rcpp::CharacterVector> &open_options,
        bool shared,
        const Rcpp::Nullable<Rcpp::CharacterVector> &allowed_drivers)
        : infoOptions(Rcpp::CharacterVector::create()) {

    m_filename = Rcpp::as<std::string>(check_gdal_filename(filename));

    if (open_options.isNotNull())
        m_open_options = Rcpp::CharacterVector(open_options);
    else
        m_open_options = Rcpp::CharacterVector::create();

    m_shared = shared;

    if (allowed_drivers.isNotNull())
        m_allowed_drivers = Rcpp::CharacterVector(allowed_drivers);
    else
        m_allowed_drivers = Rcpp::CharacterVector::create();

    open(read_only);
}

GDALMultiDimRaster::~GDALMultiDimRaster() {
    close();
}

std::string GDALMultiDimRaster::getFilename() const {
    return m_filename;
}

void GDALMultiDimRaster::open(bool read_only) {
    if (GDAL_VERSION_NUM < MDIM_MIN_GDAL_)
        Rcpp::stop("GDALMultiDimRaster requires GDAL >= 3.2");

    if (m_filename == "")
        Rcpp::stop("'filename' is not set");

    if (m_hDataset != nullptr)
        close();

    std::vector<char *> oOpenOptions = {};
    for (R_xlen_t i = 0; i < m_open_options.size(); ++i) {
        if (!EQUAL(m_open_options[i], ""))
            oOpenOptions.push_back((char *) m_open_options[i]);
    }
    oOpenOptions.push_back(nullptr);

    std::vector<char *> oAllowedDrivers = {};
    for (R_xlen_t i = 0; i < m_allowed_drivers.size(); ++i) {
        if (!EQUAL(m_allowed_drivers[i], ""))
            oAllowedDrivers.push_back((char *) m_allowed_drivers[i]);
    }
    oAllowedDrivers.push_back(nullptr);

    unsigned int nOpenFlags = GDAL_OF_MULTIDIM_RASTER | GDAL_OF_VERBOSE_ERROR;
    if (read_only)
        nOpenFlags |= GDAL_OF_READONLY;
    else
        nOpenFlags |= GDAL_OF_UPDATE;
    if (m_shared)
        nOpenFlags |= GDAL_OF_SHARED;

    m_hDataset = GDALOpenEx(m_filename.c_str(), nOpenFlags,
                            oAllowedDrivers.size() > 1 ?
                                oAllowedDrivers.data() : nullptr,
                            oOpenOptions.data(), nullptr);

    if (m_hDataset == nullptr)
        Rcpp::stop("open multidimensional raster failed");

    m_hRootGroup = GDALDatasetGetRootGroup(m_hDataset);
    if (m_hRootGroup == nullptr) {
        GDALReleaseDataset(m_hDataset);
        m_hDataset = nullptr;
        Rcpp::stop("failed to get the root group");
    }

    m_eAccess = read_only ? GA_ReadOnly : GA_Update;
}

bool GDALMultiDimRaster::isOpen() const {
    return m_hDataset != nullptr;
}

bool GDALMultiDimRaster::isReadOnly() const {
    checkAccess_(GA_ReadOnly);

    return m_eAccess == GA_ReadOnly;
}

std::string GDALMultiDimRaster::getDriverShortName() const {
    checkAccess_(GA_ReadOnly);

    GDALDriverH hDriver = GDALGetDatasetDriver(m_hDataset);
    if (hDriver == nullptr)
        return "";

    return GDALGetDriverShortName(hDriver);
}

std::string GDALMultiDimRaster::getDriverLongName() const {
    checkAccess_(GA_ReadOnly);

    GDALDriverH hDriver = GDALGetDatasetDriver(m_hDataset);
    if (hDriver == nullptr)
        return "";

    return GDALGetDriverLongName(hDriver);
}

Rcpp::CharacterVector GDALMultiDimRaster::getFileList() const {
    checkAccess_(GA_ReadOnly);

    const CPLStringList files(GDALGetFileList(m_hDataset));
    if (!files.empty())
        return wrap_gdal_string_list_(files);
    else
        return "";
}

void GDALMultiDimRaster::info() const {
    checkAccess_(GA_ReadOnly);

    const Rcpp::CharacterVector argv = this->infoOptions;
    std::vector<char *> opt = {};
    for (R_xlen_t i = 0; i < argv.size(); ++i) {
        if (!EQUAL(argv[i], ""))
            opt.push_back((char *) argv[i]);
    }
    opt.push_back(nullptr);

    GDALMultiDimInfoOptions *psOptions =
            GDALMultiDimInfoOptionsNew(opt.data(), nullptr);
    if (psOptions == nullptr)
        Rcpp::stop("creation of GDALMultiDimInfoOptions failed "
                   "(check $infoOptions)");

    char *pszInfo = GDALMultiDimInfo(m_hDataset, psOptions);
    if (pszInfo != nullptr)
        Rcpp::Rcout << pszInfo << "\n";
    CPLFree(pszInfo);
    GDALMultiDimInfoOptionsFree(psOptions);
}

void GDALMultiDimRaster::close() {
    if (m_hRootGroup != nullptr) {
        GDALGroupRelease(m_hRootGroup);
        m_hRootGroup = nullptr;
    }
    if (m_hDataset != nullptr) {
        GDALReleaseDataset(m_hDataset);
        m_hDataset = nullptr;
    }
}

Rcpp::CharacterVector GDALMultiDimRaster::getGroupNames(
        const std::string &path) const {

    checkAccess_(GA_ReadOnly);

    GDALGroupH hGroup = openGroup_(path, true);
    char **papszNames = GDALGroupGetGroupNames(hGroup, nullptr);
    GDALGroupRelease(hGroup);
    return string_list_to_cv_(papszNames);
}

Rcpp::CharacterVector GDALMultiDimRaster::getMDArrayNames(
        const std::string &path) const {

    checkAccess_(GA_ReadOnly);

    GDALGroupH hGroup = openGroup_(path, true);
    char **papszNames = GDALGroupGetMDArrayNames(hGroup, nullptr);
    GDALGroupRelease(hGroup);
    return string_list_to_cv_(papszNames);
}

Rcpp::DataFrame GDALMultiDimRaster::getDimensions(
        const std::string &path) const {

    checkAccess_(GA_ReadOnly);

    size_t nCount = 0;
    GDALDimensionH *pahDims = nullptr;

    GDALGroupH hGroup = openGroup_(path, false);
    if (hGroup != nullptr) {
        pahDims = GDALGroupGetDimensions(hGroup, &nCount, nullptr);
        GDALGroupRelease(hGroup);
        return dimensions_to_df_(pahDims, nCount);
    }

    GDALMDArrayH hArray = openMDArray_(path, false);
    if (hArray != nullptr) {
        pahDims = GDALMDArrayGetDimensions(hArray, &nCount);
        GDALMDArrayRelease(hArray);
        return dimensions_to_df_(pahDims, nCount);
    }

    Rcpp::stop("no group or array found at path: " +
               mdim_normalize_path_(path));
}

Rcpp::List GDALMultiDimRaster::getAttributes(const std::string &path) const {
    checkAccess_(GA_ReadOnly);

    size_t nCount = 0;
    GDALAttributeH *pahAttrs = nullptr;

    GDALGroupH hGroup = openGroup_(path, false);
    if (hGroup != nullptr) {
        pahAttrs = GDALGroupGetAttributes(hGroup, &nCount, nullptr);
        GDALGroupRelease(hGroup);
        return mdim_attributes_to_list_(pahAttrs, nCount);
    }

    GDALMDArrayH hArray = openMDArray_(path, false);
    if (hArray != nullptr) {
        pahAttrs = GDALMDArrayGetAttributes(hArray, &nCount, nullptr);
        GDALMDArrayRelease(hArray);
        return mdim_attributes_to_list_(pahAttrs, nCount);
    }

    Rcpp::stop("no group or array found at path: " +
               mdim_normalize_path_(path));
}

Rcpp::List GDALMultiDimRaster::getGroupInfo(const std::string &path) const {
    checkAccess_(GA_ReadOnly);

    GDALGroupH hGroup = openGroup_(path, true);

    const char *pszName = GDALGroupGetName(hGroup);
    const char *pszFullName = GDALGroupGetFullName(hGroup);
    std::string name = pszName ? pszName : "";
    std::string full_name = pszFullName ? pszFullName : "";

    Rcpp::CharacterVector group_names =
            string_list_to_cv_(GDALGroupGetGroupNames(hGroup, nullptr));
    Rcpp::CharacterVector array_names =
            string_list_to_cv_(GDALGroupGetMDArrayNames(hGroup, nullptr));

    size_t nDims = 0;
    GDALDimensionH *pahDims = GDALGroupGetDimensions(hGroup, &nDims, nullptr);
    Rcpp::DataFrame dims = dimensions_to_df_(pahDims, nDims);

    size_t nAttrs = 0;
    GDALAttributeH *pahAttrs = GDALGroupGetAttributes(hGroup, &nAttrs,
                                                      nullptr);
    Rcpp::List attrs = mdim_attributes_to_list_(pahAttrs, nAttrs);

    GDALGroupRelease(hGroup);

    return Rcpp::List::create(
        Rcpp::Named("name") = name,
        Rcpp::Named("full_name") = full_name,
        Rcpp::Named("group_names") = group_names,
        Rcpp::Named("array_names") = array_names,
        Rcpp::Named("dimensions") = dims,
        Rcpp::Named("attributes") = attrs);
}

void GDALMultiDimRaster::show() const {
    if (!isOpen()) {
        cli_text_("C++ object of class {.cls GDALMultiDimRaster}");
        cli_ul_();
        cli_li_("{.emph Filename}: {.str "s + m_filename + "}");
        cli_li_("{.emph Dataset is closed}");
        cli_end_();
        return;
    }

    char **papszGroups = GDALGroupGetGroupNames(m_hRootGroup, nullptr);
    char **papszArrays = GDALGroupGetMDArrayNames(m_hRootGroup, nullptr);
    const int nGroups = CSLCount(papszGroups);
    const int nArrays = CSLCount(papszArrays);
    std::string arrays = "";
    for (int i = 0; i < nArrays && i < 6; ++i) {
        if (i > 0)
            arrays += ", ";
        arrays += papszArrays[i];
    }
    if (nArrays > 6)
        arrays += ", ...";
    CSLDestroy(papszGroups);
    CSLDestroy(papszArrays);

    cli_text_("C++ object of class {.cls GDALMultiDimRaster}");
    cli_ul_();
    cli_li_("{.emph Driver}: "s + getDriverLongName() + " (" +
            getDriverShortName() + ")");
    cli_li_("{.emph Filename}: {.str "s + m_filename + "}");
    cli_li_("{.emph Access}: "s + (m_eAccess == GA_ReadOnly ? "read-only" :
                                   "update"));
    cli_li_("{.emph Groups in root}: "s + std::to_string(nGroups));
    cli_li_("{.emph Arrays in root}: "s + std::to_string(nArrays) +
            (nArrays > 0 ? " (" + arrays + ")" : ""));
    cli_end_();
}

// ****************************************************************************
// class methods for internal use not exposed in R
// ****************************************************************************

void GDALMultiDimRaster::checkAccess_(GDALAccess access_needed) const {
    if (!isOpen())
        Rcpp::stop("dataset is not open");

    if (access_needed == GA_Update && m_eAccess == GA_ReadOnly)
        Rcpp::stop("dataset is read-only");
}

// Open a group by full path. The caller must release the returned handle
// with GDALGroupRelease(). Returns nullptr if not found and !must_exist.
GDALGroupH GDALMultiDimRaster::openGroup_(const std::string &path,
                                          bool must_exist) const {

    checkAccess_(GA_ReadOnly);

    const std::string full_path = mdim_normalize_path_(path);
    GDALGroupH hGroup = nullptr;

#if GDAL_VERSION_NUM >= GDAL_COMPUTE_VERSION(3, 2, 0)
    if (full_path == "/") {
        // a new handle to the root group, released by the caller
        hGroup = GDALDatasetGetRootGroup(m_hDataset);
    }
    else {
        CPLPushErrorHandler(CPLQuietErrorHandler);
        hGroup = GDALGroupOpenGroupFromFullname(m_hRootGroup,
                                                full_path.c_str(), nullptr);
        CPLPopErrorHandler();
        CPLErrorReset();
    }
#endif

    if (hGroup == nullptr && must_exist)
        Rcpp::stop("group not found: " + full_path);

    return hGroup;
}

// Open an array by full path. The caller must release the returned handle
// with GDALMDArrayRelease(). Returns nullptr if not found and !must_exist.
GDALMDArrayH GDALMultiDimRaster::openMDArray_(const std::string &path,
                                              bool must_exist) const {

    checkAccess_(GA_ReadOnly);

    const std::string full_path = mdim_normalize_path_(path);
    GDALMDArrayH hArray = nullptr;

#if GDAL_VERSION_NUM >= GDAL_COMPUTE_VERSION(3, 2, 0)
    if (full_path != "/") {
        CPLPushErrorHandler(CPLQuietErrorHandler);
        hArray = GDALGroupOpenMDArrayFromFullname(m_hRootGroup,
                                                  full_path.c_str(), nullptr);
        CPLPopErrorHandler();
        CPLErrorReset();
    }
#endif

    if (hArray == nullptr && must_exist)
        Rcpp::stop("array not found: " + full_path);

    return hArray;
}

// ****************************************************************************

RCPP_MODULE(mod_GDALMultiDimRaster) {
    Rcpp::class_<GDALMultiDimRaster>("GDALMultiDimRaster")

    .constructor
        ("Default constructor, no dataset opened")
    .constructor<Rcpp::CharacterVector>
        ("Usage: new(GDALMultiDimRaster, filename)")
    .constructor<Rcpp::CharacterVector, bool>
        ("Usage: new(GDALMultiDimRaster, filename, read_only=[TRUE|FALSE])")
    .constructor<Rcpp::CharacterVector, bool, Rcpp::CharacterVector>
        ("Usage: new(GDALMultiDimRaster, filename, read_only, open_options)")
    .constructor<Rcpp::CharacterVector, bool,
                 Rcpp::Nullable<Rcpp::CharacterVector>, bool,
                 Rcpp::Nullable<Rcpp::CharacterVector>>
        ("Usage: new(GDALMultiDimRaster, filename, read_only, open_options, "
         "shared, allowed_drivers)")

    // exposed read/write fields
    .field("infoOptions", &GDALMultiDimRaster::infoOptions)
    .field("quiet", &GDALMultiDimRaster::quiet)

    // exposed member functions
    .const_method("getFilename", &GDALMultiDimRaster::getFilename,
        "Return the filename")
    .method("open", &GDALMultiDimRaster::open,
        "(Re-)open the dataset on the existing filename")
    .const_method("isOpen", &GDALMultiDimRaster::isOpen,
        "Is the dataset open")
    .const_method("isReadOnly", &GDALMultiDimRaster::isReadOnly,
        "Is the dataset open read-only")
    .const_method("getDriverShortName",
        &GDALMultiDimRaster::getDriverShortName,
        "Return the dataset driver short name")
    .const_method("getDriverLongName", &GDALMultiDimRaster::getDriverLongName,
        "Return the dataset driver long name")
    .const_method("getFileList", &GDALMultiDimRaster::getFileList,
        "Fetch files forming the dataset")
    .const_method("info", &GDALMultiDimRaster::info,
        "Print various information about the dataset (gdalmdiminfo)")
    .method("close", &GDALMultiDimRaster::close,
        "Release the dataset for proper cleanup")
    .const_method("getGroupNames", &GDALMultiDimRaster::getGroupNames,
        "Return the names of the sub-groups of a group, by full path")
    .const_method("getMDArrayNames", &GDALMultiDimRaster::getMDArrayNames,
        "Return the names of the arrays in a group, by full path")
    .const_method("getDimensions", &GDALMultiDimRaster::getDimensions,
        "Return the dimensions of a group or array, by full path")
    .const_method("getAttributes", &GDALMultiDimRaster::getAttributes,
        "Return the attributes of a group or array, by full path")
    .const_method("getGroupInfo", &GDALMultiDimRaster::getGroupInfo,
        "Return a list describing a group, by full path")
    .const_method("show", &GDALMultiDimRaster::show,
        "S4 show()")

    ;
}
