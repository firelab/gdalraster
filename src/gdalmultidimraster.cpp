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
#include <cmath>
#include <memory>
#include <string>
#include <vector>

#include "gdalraster.h"
#include "gdalmultidimraster.h"
#include "gdalmdarray.h"
#include "rcpp_util.h"

using std::string_literals::operator""s;

constexpr int MDIM_MIN_GDAL_ = GDAL_COMPUTE_VERSION(3, 2, 0);


// ****************************************************************************
// helpers not exported to R
// ****************************************************************************

// Split a full path into the path of the parent group and the name
static void mdim_split_path_(const std::string &path, std::string &parent,
                             std::string &name) {
    const std::string full_path = mdim_normalize_path_(path);
    const size_t pos = full_path.rfind('/');
    parent = pos == 0 ? "/" : full_path.substr(0, pos);
    name = full_path.substr(pos + 1);
}

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
        const CPLStringList values(GDALAttributeReadAsStringArray(hAttr));
        return wrap_gdal_string_list_(values);
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
Rcpp::DataFrame mdim_dimensions_to_df_(GDALDimensionH *pahDims,
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
    const CPLStringList names(GDALGroupGetGroupNames(hGroup, nullptr));
    GDALGroupRelease(hGroup);
    return wrap_gdal_string_list_(names);
}

Rcpp::CharacterVector GDALMultiDimRaster::getMDArrayNames(
        const std::string &path) const {

    checkAccess_(GA_ReadOnly);

    GDALGroupH hGroup = openGroup_(path, true);
    const CPLStringList names(GDALGroupGetMDArrayNames(hGroup, nullptr));
    GDALGroupRelease(hGroup);
    return wrap_gdal_string_list_(names);
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
        return mdim_dimensions_to_df_(pahDims, nCount);
    }

    GDALMDArrayH hArray = openMDArray_(path, false);
    if (hArray != nullptr) {
        pahDims = GDALMDArrayGetDimensions(hArray, &nCount);
        GDALMDArrayRelease(hArray);
        return mdim_dimensions_to_df_(pahDims, nCount);
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

    Rcpp::CharacterVector group_names = wrap_gdal_string_list_(
            CPLStringList(GDALGroupGetGroupNames(hGroup, nullptr)));
    Rcpp::CharacterVector array_names = wrap_gdal_string_list_(
            CPLStringList(GDALGroupGetMDArrayNames(hGroup, nullptr)));

    size_t nDims = 0;
    GDALDimensionH *pahDims = GDALGroupGetDimensions(hGroup, &nDims, nullptr);
    Rcpp::DataFrame dims = mdim_dimensions_to_df_(pahDims, nDims);

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

GDALMDArrayR *GDALMultiDimRaster::openMDArray(const std::string &path) const {
    checkAccess_(GA_ReadOnly);

    GDALMDArrayH hArray = openMDArray_(path, true);
    auto arr = std::make_unique<GDALMDArrayR>();
    arr->setHandles_(hArray, m_hDataset);
    // a returned pointer to an exposed class is owned by R, which deletes it
    // when the R object is garbage collected (no copy, see the Rcpp modules
    // vignette, RcppCore/Rcpp#1533)
    return arr.release();
}

void GDALMultiDimRaster::createGroup(
        const std::string &path,
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) {
    checkAccess_(GA_Update);

    std::string parent, name;
    mdim_split_path_(path, parent, name);
    if (name.empty())
        Rcpp::stop("'path' must be the full path of the group to create");

    const CPLStringList aosOptions = options_to_csl_(options);
    GDALGroupH hParent = openGroup_(parent, true);
    GDALGroupH hGroup = GDALGroupCreateGroup(hParent, name.c_str(),
                                             aosOptions.List());
    GDALGroupRelease(hParent);
    if (hGroup == nullptr)
        Rcpp::stop("failed to create group: " + mdim_normalize_path_(path));
    GDALGroupRelease(hGroup);
}

void GDALMultiDimRaster::createDimension(
        const std::string &path, const std::string &name,
        const std::string &type, const std::string &direction, double size,
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) {
    checkAccess_(GA_Update);

    if (name.empty())
        Rcpp::stop("'name' is required");
    if (Rcpp::NumericVector::is_na(size) || !std::isfinite(size) ||
            std::floor(size) != size || size < 1 ||
            size > static_cast<double>(MAX_INT_AS_R_NUMERIC_)) {
        Rcpp::stop("'size' must be a whole number >= 1");
    }

    const CPLStringList aosOptions = options_to_csl_(options);
    GDALGroupH hGroup = openGroup_(path, true);
    GDALDimensionH hDim = GDALGroupCreateDimension(
        hGroup, name.c_str(), type.c_str(), direction.c_str(),
        static_cast<GUInt64>(size), aosOptions.List());
    GDALGroupRelease(hGroup);
    if (hDim == nullptr) {
        Rcpp::stop("failed to create dimension '" + name + "' in group: " +
                   mdim_normalize_path_(path));
    }
    GDALDimensionRelease(hDim);
}

GDALMDArrayR *GDALMultiDimRaster::createMDArray(
        const std::string &path,
        const Rcpp::Nullable<Rcpp::CharacterVector> &dim_paths_in,
        const std::string &data_type,
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) {
    checkAccess_(GA_Update);

    // NULL is an array with no dimensions, as character(0)
    Rcpp::CharacterVector dim_paths;
    if (dim_paths_in.isNotNull())
        dim_paths = Rcpp::CharacterVector(dim_paths_in);

    std::string parent, name;
    mdim_split_path_(path, parent, name);
    if (name.empty())
        Rcpp::stop("'path' must be the full path of the array to create");

    // released on any exit below
    GDALGroupH hGroup = openGroup_(parent, true);

    GDALExtendedDataTypeH hDT = nullptr;
    if (EQUAL(data_type.c_str(), "String")) {
        hDT = GDALExtendedDataTypeCreateString(0);
    }
    else {
        const GDALDataType eDT = GDALGetDataTypeByName(data_type.c_str());
        if (eDT == GDT_Unknown) {
            GDALGroupRelease(hGroup);
            Rcpp::stop("'data_type' is unknown: " + data_type);
        }
        hDT = GDALExtendedDataTypeCreate(eDT);
    }
    if (hDT == nullptr) {
        GDALGroupRelease(hGroup);
        Rcpp::stop("failed to create the data type");
    }

    // released on any exit below
    std::vector<GDALDimensionH> ahDims;
    std::string err_msg;

    for (R_xlen_t i = 0; i < dim_paths.size() && err_msg.empty(); ++i) {
        if (Rcpp::CharacterVector::is_na(dim_paths[i])) {
            err_msg = "'dim_paths' has NA";
            continue;
        }
        const std::string dim_path(dim_paths[i]);
        GDALDimensionH hDim = openDimension_(dim_path);
        if (hDim == nullptr)
            err_msg = "dimension not found: " + mdim_normalize_path_(dim_path);
        else
            ahDims.push_back(hDim);
    }

    GDALMDArrayH hArray = nullptr;
    if (err_msg.empty()) {
        const CPLStringList aosOptions = options_to_csl_(options);
        hArray = GDALGroupCreateMDArray(
            hGroup, name.c_str(), ahDims.size(),
            ahDims.empty() ? nullptr : ahDims.data(), hDT, aosOptions.List());
        if (hArray == nullptr)
            err_msg = "failed to create array: " + mdim_normalize_path_(path);
    }

    // a 1D array with the full path of its dimension (same group, same name)
    // is the indexing variable of that dimension (some drivers do this
    // themselves, or only on re-opening)
    if (hArray != nullptr && ahDims.size() == 1) {
        const char *pszDimName = GDALDimensionGetFullName(ahDims[0]);
        if (pszDimName != nullptr &&
                mdim_normalize_path_(path) == pszDimName) {
            CPLPushErrorHandler(CPLQuietErrorHandler);
            GDALDimensionSetIndexingVariable(ahDims[0], hArray);
            CPLPopErrorHandler();
            CPLErrorReset();
        }
    }

    GDALGroupRelease(hGroup);
    for (GDALDimensionH hDim : ahDims)
        GDALDimensionRelease(hDim);
    GDALExtendedDataTypeRelease(hDT);

    if (!err_msg.empty())
        Rcpp::stop(err_msg);

    auto arr = std::make_unique<GDALMDArrayR>();
    arr->setHandles_(hArray, m_hDataset);
    return arr.release();
}

void GDALMultiDimRaster::setAttribute(const std::string &path,
                                      const std::string &name,
                                      const Rcpp::RObject &value,
                                      const std::string &data_type) {
    checkAccess_(GA_Update);

    if (name.empty())
        Rcpp::stop("'name' is required");

    if (Rf_isFactor(value) || Rf_inherits(value, "integer64")) {
        Rcpp::stop("'value' must not be a factor or integer64 (convert with "
                   "as.character() or as.numeric())");
    }

    const bool is_string = Rcpp::is<Rcpp::CharacterVector>(value);
    const bool is_int = Rcpp::is<Rcpp::IntegerVector>(value) ||
                        Rcpp::is<Rcpp::LogicalVector>(value);
    const bool is_double = Rcpp::is<Rcpp::NumericVector>(value);
    if (value.isNULL() || !(is_string || is_int || is_double) ||
            Rf_xlength(value) < 1) {
        Rcpp::stop("'value' must be a character, numeric, integer or logical "
                   "vector of length >= 1");
    }
    const R_xlen_t nValues = Rf_xlength(value);

    // the data type of the attribute, inferred from 'value' if not given
    GDALDataType eDT = is_int ? GDT_Int32 : GDT_Float64;
    if (!data_type.empty()) {
        const bool want_string = EQUAL(data_type.c_str(), "String");
        if (!want_string) {
            eDT = GDALGetDataTypeByName(data_type.c_str());
            if (eDT == GDT_Unknown)
                Rcpp::stop("'data_type' is unknown: " + data_type);
        }
        if (want_string != is_string) {
            Rcpp::stop("'data_type' must be \"String\" for a character "
                       "'value', and a numeric type otherwise");
        }
    }

    // the values to write, checked before the attribute is created
    CPLStringList aosValues;
    std::vector<double> adfValues;
    if (is_string) {
        const Rcpp::CharacterVector v(value);
        for (R_xlen_t i = 0; i < nValues; ++i) {
            if (Rcpp::CharacterVector::is_na(v[i]))
                Rcpp::stop("'value' must not have NA");
            aosValues.AddString(v[i]);
        }
    }
    else {
        const Rcpp::NumericVector v = Rcpp::as<Rcpp::NumericVector>(value);
        for (R_xlen_t i = 0; i < nValues; ++i) {
            // NaN is a valid value, NA is not
            if (ISNA(v[i]))
                Rcpp::stop("'value' must not have NA");
            adfValues.push_back(v[i]);
        }
    }

    GDALGroupH hGroup = openGroup_(path, false);
    GDALMDArrayH hArray = nullptr;
    if (hGroup == nullptr)
        hArray = openMDArray_(path, false);
    if (hGroup == nullptr && hArray == nullptr) {
        Rcpp::stop("no group or array found at path: " +
                   mdim_normalize_path_(path));
    }

#if GDAL_VERSION_NUM >= GDAL_COMPUTE_VERSION(3, 8, 0)
    // replace an existing attribute, which may differ in type or length
    CPLPushErrorHandler(CPLQuietErrorHandler);
    GDALAttributeH hExisting = hGroup != nullptr ?
        GDALGroupGetAttribute(hGroup, name.c_str()) :
        GDALMDArrayGetAttribute(hArray, name.c_str());
    if (hExisting != nullptr) {
        GDALAttributeRelease(hExisting);
        if (hGroup != nullptr)
            GDALGroupDeleteAttribute(hGroup, name.c_str(), nullptr);
        else
            GDALMDArrayDeleteAttribute(hArray, name.c_str(), nullptr);
    }
    CPLPopErrorHandler();
    CPLErrorReset();
#endif

    GDALExtendedDataTypeH hDT = nullptr;
    if (is_string)
        hDT = GDALExtendedDataTypeCreateString(0);
    else
        hDT = GDALExtendedDataTypeCreate(eDT);

    // one value is a scalar attribute, otherwise a 1D array
    const GUInt64 nSize = static_cast<GUInt64>(nValues);
    const size_t nAttrDims = nValues == 1 ? 0 : 1;
    GDALAttributeH hAttr = nullptr;
    if (hGroup != nullptr) {
        hAttr = GDALGroupCreateAttribute(hGroup, name.c_str(), nAttrDims,
                                         &nSize, hDT, nullptr);
    }
    else {
        hAttr = GDALMDArrayCreateAttribute(hArray, name.c_str(), nAttrDims,
                                           &nSize, hDT, nullptr);
    }
    GDALExtendedDataTypeRelease(hDT);

    int ok = FALSE;
    if (hAttr != nullptr) {
        if (is_string && nValues == 1)
            ok = GDALAttributeWriteString(hAttr, aosValues[0]);
        else if (is_string)
            ok = GDALAttributeWriteStringArray(hAttr, aosValues.List());
        else
            ok = GDALAttributeWriteDoubleArray(hAttr, adfValues.data(),
                                               adfValues.size());
        GDALAttributeRelease(hAttr);

#if GDAL_VERSION_NUM >= GDAL_COMPUTE_VERSION(3, 8, 0)
        if (!ok) {
            // do not leave an attribute without its value
            CPLPushErrorHandler(CPLQuietErrorHandler);
            if (hGroup != nullptr)
                GDALGroupDeleteAttribute(hGroup, name.c_str(), nullptr);
            else
                GDALMDArrayDeleteAttribute(hArray, name.c_str(), nullptr);
            CPLPopErrorHandler();
            CPLErrorReset();
        }
#endif
    }

    if (hGroup != nullptr)
        GDALGroupRelease(hGroup);
    else
        GDALMDArrayRelease(hArray);

    if (hAttr == nullptr) {
        Rcpp::stop("failed to create attribute '" + name + "' on: " +
                   mdim_normalize_path_(path));
    }
    if (!ok) {
        Rcpp::stop("failed to write attribute '" + name + "' on: " +
                   mdim_normalize_path_(path));
    }
}

void GDALMultiDimRaster::deleteAttribute(const std::string &path,
                                         const std::string &name) {
    checkAccess_(GA_Update);

// requires GDAL >= 3.8 for GDALGroupDeleteAttribute()
#if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 8, 0)
    Rcpp::stop("deleteAttribute() requires GDAL >= 3.8");
#else
    if (name.empty())
        Rcpp::stop("'name' is required");

    bool ok = false;
    GDALGroupH hGroup = openGroup_(path, false);
    if (hGroup != nullptr) {
        ok = GDALGroupDeleteAttribute(hGroup, name.c_str(), nullptr);
        GDALGroupRelease(hGroup);
    }
    else {
        GDALMDArrayH hArray = openMDArray_(path, false);
        if (hArray == nullptr) {
            Rcpp::stop("no group or array found at path: " +
                       mdim_normalize_path_(path));
        }
        ok = GDALMDArrayDeleteAttribute(hArray, name.c_str(), nullptr);
        GDALMDArrayRelease(hArray);
    }
    if (!ok) {
        Rcpp::stop("failed to delete attribute '" + name + "' on: " +
                   mdim_normalize_path_(path));
    }
#endif
}

void GDALMultiDimRaster::show() const {
    if (!isOpen()) {
        cli_text_("C++ object of class {.cls GDALMultiDimRaster}");
        cli_ul_();
        cli_li_("{.emph Filename}: "s + cli_format_dsn_(m_filename));
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
    cli_li_("{.emph Filename}: "s + cli_format_dsn_(m_filename));
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

void GDALMultiDimRaster::setDataset_(GDALDatasetH hDS,
                                     const std::string &filename) {
    close();
    m_filename = filename;
    m_hDataset = hDS;
    m_hRootGroup = GDALDatasetGetRootGroup(m_hDataset);
    if (m_hRootGroup == nullptr) {
        GDALReleaseDataset(m_hDataset);
        m_hDataset = nullptr;
        Rcpp::stop("failed to get the root group");
    }
    m_eAccess = GA_Update;
}

// Open a dimension by full path, i.e., the full path of its group and its
// name. The caller must release the returned handle with
// GDALDimensionRelease(). Returns nullptr if not found.
GDALDimensionH GDALMultiDimRaster::openDimension_(
        const std::string &path) const {

    std::string parent, name;
    mdim_split_path_(path, parent, name);

    GDALGroupH hGroup = openGroup_(parent, false);
    if (hGroup == nullptr)
        return nullptr;

    size_t nCount = 0;
    GDALDimensionH *pahDims = GDALGroupGetDimensions(hGroup, &nCount, nullptr);
    GDALGroupRelease(hGroup);

    GDALDimensionH hDim = nullptr;
    for (size_t i = 0; i < nCount; ++i) {
        const char *pszName = GDALDimensionGetName(pahDims[i]);
        if (hDim == nullptr && pszName != nullptr && name == pszName)
            hDim = pahDims[i];
        else
            GDALDimensionRelease(pahDims[i]);
    }
    // the array of handles only (GDALReleaseDimensions() would also release
    // the handle that is returned)
    CPLFree(pahDims);
    return hDim;
}

// Open a group by full path. The caller must release the returned handle
// with GDALGroupRelease(). Returns nullptr if not found and !must_exist.
GDALGroupH GDALMultiDimRaster::openGroup_(const std::string &path,
                                          bool must_exist) const {

    checkAccess_(GA_ReadOnly);

    const std::string full_path = mdim_normalize_path_(path);
    GDALGroupH hGroup = nullptr;
    std::string err_msg;

#if GDAL_VERSION_NUM >= GDAL_COMPUTE_VERSION(3, 2, 0)
    if (full_path == "/") {
        // a new handle to the root group, released by the caller
        hGroup = GDALDatasetGetRootGroup(m_hDataset);
    }
    else {
        CPLErrorReset();
        CPLPushErrorHandler(CPLQuietErrorHandler);
        hGroup = GDALGroupOpenGroupFromFullname(m_hRootGroup,
                                                full_path.c_str(), nullptr);
        CPLPopErrorHandler();
        if (hGroup == nullptr && CPLGetLastErrorType() != CE_None)
            err_msg = CPLGetLastErrorMsg();
        CPLErrorReset();
    }
#endif

    if (hGroup == nullptr && must_exist) {
        if (err_msg.empty())
            Rcpp::stop("group not found: " + full_path);
        else
            Rcpp::stop("failed to open group " + full_path + ": " + err_msg);
    }

    return hGroup;
}

// Open an array by full path. The caller must release the returned handle
// with GDALMDArrayRelease(). Returns nullptr if not found and !must_exist.
GDALMDArrayH GDALMultiDimRaster::openMDArray_(const std::string &path,
                                              bool must_exist) const {

    checkAccess_(GA_ReadOnly);

    const std::string full_path = mdim_normalize_path_(path);
    GDALMDArrayH hArray = nullptr;
    std::string err_msg;

#if GDAL_VERSION_NUM >= GDAL_COMPUTE_VERSION(3, 2, 0)
    if (full_path != "/") {
        CPLErrorReset();
        CPLPushErrorHandler(CPLQuietErrorHandler);
        hArray = GDALGroupOpenMDArrayFromFullname(m_hRootGroup,
                                                  full_path.c_str(), nullptr);
        CPLPopErrorHandler();
        if (hArray == nullptr && CPLGetLastErrorType() != CE_None)
            err_msg = CPLGetLastErrorMsg();
        CPLErrorReset();
    }
#endif

    if (hArray == nullptr && must_exist) {
        if (err_msg.empty())
            Rcpp::stop("array not found: " + full_path);
        else
            Rcpp::stop("failed to open array " + full_path + ": " + err_msg);
    }

    return hArray;
}

// ****************************************************************************
// object factory
// ****************************************************************************

// Create a new multidimensional dataset, open for update.
// Implemented as a GDALMultiDimRaster object factory registered in
// RCPP_MODULE(mod_GDALMultiDimRaster).
// Unique function signature based on number of parameters.
// Called in R with `ds <- new(GDALMultiDimRaster, ...)` giving all 4
// parameters, as in mdim_create() in R/gdal_mdim.R.
GDALMultiDimRaster *mdim_create(
        const std::string &format, const Rcpp::CharacterVector &dst_filename,
        const Rcpp::Nullable<Rcpp::CharacterVector> &root_group_options,
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) {

    if (GDAL_VERSION_NUM < MDIM_MIN_GDAL_)
        Rcpp::stop("mdim_create() requires GDAL >= 3.2");

    GDALDriverH hDriver = GDALGetDriverByName(format.c_str());
    if (hDriver == nullptr)
        Rcpp::stop("failed to get driver for the specified format");

    CSLConstList papszDriverMD = GDALGetMetadata(hDriver, nullptr);
    if (!CPLFetchBool(papszDriverMD, GDAL_DCAP_CREATE_MULTIDIMENSIONAL, FALSE))
        Rcpp::stop("driver does not support multidimensional create");

    const std::string dst_filename_in =
        Rcpp::as<std::string>(check_gdal_filename(dst_filename));

    const CPLStringList aosRootGroupOptions =
        options_to_csl_(root_group_options);
    const CPLStringList aosOptions = options_to_csl_(options);

    GDALDatasetH hDstDS = GDALCreateMultiDimensional(
        hDriver, dst_filename_in.c_str(), aosRootGroupOptions.List(),
        aosOptions.List());
    if (hDstDS == nullptr)
        Rcpp::stop("mdim_create() failed");

    auto ds = std::make_unique<GDALMultiDimRaster>();
    ds->setDataset_(hDstDS, dst_filename_in);
    return ds.release();
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

    // mdim_create() object factory with 4 parameters
    .factory<const std::string&, const Rcpp::CharacterVector&,
             const Rcpp::Nullable<Rcpp::CharacterVector>&,
             const Rcpp::Nullable<Rcpp::CharacterVector>&>
             (mdim_create)

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
    .const_method("openMDArray", &GDALMultiDimRaster::openMDArray,
        "Open an array by full path, returning an object of class GDALMDArray")
    .method("createGroup", &GDALMultiDimRaster::createGroup,
        "Create a group, by full path")
    .method("createDimension", &GDALMultiDimRaster::createDimension,
        "Create a dimension in a group")
    .method("createMDArray", &GDALMultiDimRaster::createMDArray,
        "Create an array, returning an object of class GDALMDArray")
    .method("setAttribute", &GDALMultiDimRaster::setAttribute,
        "Set an attribute of a group or array, by full path")
    .method("deleteAttribute", &GDALMultiDimRaster::deleteAttribute,
        "Delete an attribute of a group or array, by full path")
    .const_method("show", &GDALMultiDimRaster::show,
        "S4 show()")

    ;
}
