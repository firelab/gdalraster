/* Implementation of class GDALMDArrayR, exposed to R as GDALMDArray.
   Encapsulates a GDALMDArray and holds a reference to the dataset that
   contains it, using the GDAL C API.

   Michael D. Sumner
   Copyright (c) 2026 gdalraster authors
*/

#include <gdal.h>
#include <cpl_conv.h>
#include <cpl_error.h>
#include <cpl_port.h>
#include <cpl_string.h>
#include <ogr_srs_api.h>

#include <Rcpp.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <string>
#include <vector>

#include "gdalraster.h"
#include "gdalmdarray.h"
#include "gdalmultidimraster.h"
#include "rcpp_util.h"

using std::string_literals::operator""s;


// ****************************************************************************
// helpers not exported to R
// ****************************************************************************

// Check that a numeric value is a whole number, within a range
static bool is_whole_in_range_(double x, double lo, double hi) {
    if (Rcpp::NumericVector::is_na(x) || !std::isfinite(x))
        return false;
    if (std::floor(x) != x)
        return false;
    return x >= lo && x <= hi;
}

// Read a hyperslab from hArray. start, count and step have one value per
// dimension, in the array's own order. Empty start and count read the whole
// array. Values are returned as a plain vector in C order (last dimension
// varies fastest), following GDALRaster$read(): integer types that fit in
// int32 as integer (or Byte as raw if read_byte_as_raw), other real types as
// double, complex types as complex, strings as character. The nodata value
// is replaced with NA (and NaN with NA for floating point types).
SEXP mdim_read_array_(GDALMDArrayH hArray,
                      const Rcpp::NumericVector &start,
                      const Rcpp::NumericVector &count,
                      const Rcpp::Nullable<Rcpp::NumericVector> &step,
                      bool read_byte_as_raw) {

    if (hArray == nullptr)
        Rcpp::stop("array is not open");

    const size_t nDims = GDALMDArrayGetDimensionCount(hArray);

    // dimension sizes
    std::vector<GUInt64> anSize(nDims, 0);
    {
        size_t nCount = 0;
        GDALDimensionH *pahDims = GDALMDArrayGetDimensions(hArray, &nCount);
        for (size_t i = 0; i < nCount && i < nDims; ++i)
            anSize[i] = GDALDimensionGetSize(pahDims[i]);
        if (pahDims != nullptr)
            GDALReleaseDimensions(pahDims, nCount);
    }

    std::vector<GUInt64> anStart(nDims, 0);
    std::vector<size_t> anCount(nDims, 1);
    std::vector<GInt64> anStep(nDims, 1);

    if (start.size() == 0 && count.size() == 0) {
        for (size_t i = 0; i < nDims; ++i)
            anCount[i] = static_cast<size_t>(anSize[i]);
    }
    else {
        if (static_cast<size_t>(start.size()) != nDims ||
                static_cast<size_t>(count.size()) != nDims) {
            Rcpp::stop("'start' and 'count' must have one value per "
                       "dimension (" + std::to_string(nDims) + ")");
        }
        for (size_t i = 0; i < nDims; ++i) {
            const double dfSize = static_cast<double>(anSize[i]);
            if (!is_whole_in_range_(start[i], 0, dfSize - 1))
                Rcpp::stop("'start' out of range for dimension " +
                           std::to_string(i + 1));
            if (!is_whole_in_range_(count[i], 1, dfSize))
                Rcpp::stop("'count' out of range for dimension " +
                           std::to_string(i + 1));
            anStart[i] = static_cast<GUInt64>(start[i]);
            anCount[i] = static_cast<size_t>(count[i]);
        }
    }

    if (step.isNotNull()) {
        Rcpp::NumericVector step_in(step);
        if (static_cast<size_t>(step_in.size()) != nDims)
            Rcpp::stop("'step' must have one value per dimension (" +
                       std::to_string(nDims) + ")");
        for (size_t i = 0; i < nDims; ++i) {
            const double dfSize = static_cast<double>(anSize[i]);
            if (!is_whole_in_range_(step_in[i], -dfSize, dfSize) ||
                    step_in[i] == 0) {
                Rcpp::stop("'step' must be a non-zero whole number for "
                           "dimension " + std::to_string(i + 1));
            }
            anStep[i] = static_cast<GInt64>(step_in[i]);
            // last index read must be inside the dimension
            const double dfLast = static_cast<double>(anStart[i]) +
                    (static_cast<double>(anCount[i]) - 1) * step_in[i];
            if (dfLast < 0 || dfLast > dfSize - 1)
                Rcpp::stop("'start', 'count' and 'step' read outside of "
                           "dimension " + std::to_string(i + 1));
        }
    }
    else {
        for (size_t i = 0; i < nDims; ++i) {
            if (static_cast<double>(anStart[i]) +
                    static_cast<double>(anCount[i]) >
                        static_cast<double>(anSize[i])) {
                Rcpp::stop("'start' + 'count' is out of range for dimension "
                           + std::to_string(i + 1));
            }
        }
    }

    double dfTotal = 1;
    for (size_t i = 0; i < nDims; ++i)
        dfTotal *= static_cast<double>(anCount[i]);
    if (dfTotal > static_cast<double>(R_XLEN_T_MAX))
        Rcpp::stop("requested read is too large for an R vector");
    const R_xlen_t nElems = static_cast<R_xlen_t>(dfTotal);

    const GUInt64 *panStart = nDims > 0 ? anStart.data() : nullptr;
    const size_t *panCount = nDims > 0 ? anCount.data() : nullptr;
    const GInt64 *panStep = nDims > 0 ? anStep.data() : nullptr;

    GDALExtendedDataTypeH hDT = GDALMDArrayGetDataType(hArray);
    const GDALExtendedDataTypeClass eClass = GDALExtendedDataTypeGetClass(hDT);
    GDALDataType eDT = GDT_Unknown;
    if (eClass == GEDTC_NUMERIC)
        eDT = GDALExtendedDataTypeGetNumericDataType(hDT);
    GDALExtendedDataTypeRelease(hDT);

    int bHasNoData = FALSE;
    double dfNoData = 0;
    if (eClass == GEDTC_NUMERIC)
        dfNoData = GDALMDArrayGetNoDataValueAsDouble(hArray, &bHasNoData);

    auto read_ = [&](GDALExtendedDataTypeH hBufDT, void *pBuf) {
        const int ok = GDALMDArrayRead(hArray, panStart, panCount, panStep,
                                       nullptr, hBufDT, pBuf, nullptr, 0);
        GDALExtendedDataTypeRelease(hBufDT);
        if (!ok)
            Rcpp::stop("read array failed");
    };

    if (eClass == GEDTC_STRING) {
        std::vector<char *> buf(nElems, nullptr);
        const int ok = [&]() {
            GDALExtendedDataTypeH hBufDT = GDALExtendedDataTypeCreateString(0);
            const int ret = GDALMDArrayRead(hArray, panStart, panCount,
                                            panStep, nullptr, hBufDT,
                                            buf.data(), nullptr, 0);
            GDALExtendedDataTypeRelease(hBufDT);
            return ret;
        }();
        Rcpp::CharacterVector v(nElems);
        for (R_xlen_t i = 0; i < nElems; ++i) {
            if (buf[i] != nullptr) {
                v[i] = buf[i];
                CPLFree(buf[i]);
            }
            else {
                v[i] = NA_STRING;
            }
        }
        if (!ok)
            Rcpp::stop("read array failed");
        return v;
    }

    if (eClass != GEDTC_NUMERIC)
        Rcpp::stop("arrays of compound data type are not supported");

    if (GDALDataTypeIsComplex(eDT)) {
        Rcpp::ComplexVector v = Rcpp::no_init(nElems);
        read_(GDALExtendedDataTypeCreate(GDT_CFloat64), v.begin());
        return v;
    }

    if (GDALDataTypeIsInteger(eDT) &&
            (GDALGetDataTypeSizeBits(eDT) <= 16 ||
             (GDALGetDataTypeSizeBits(eDT) <= 32 &&
              GDALDataTypeIsSigned(eDT)))) {

        if (read_byte_as_raw && eDT == GDT_Byte) {
            Rcpp::RawVector v = Rcpp::no_init(nElems);
            read_(GDALExtendedDataTypeCreate(GDT_Byte), v.begin());
            return v;
        }

        Rcpp::IntegerVector v = Rcpp::no_init(nElems);
        read_(GDALExtendedDataTypeCreate(GDT_Int32), v.begin());
        if (bHasNoData && std::isfinite(dfNoData)) {
            const int nNoData = static_cast<int>(dfNoData);
            std::replace(v.begin(), v.end(), nNoData, NA_INTEGER);
        }
        return v;
    }

    // UInt32, (U)Int64, Float16, Float32, Float64: double buffer
    // (64-bit integers lose precision above 2^53, as in GDALRaster$read())
    Rcpp::NumericVector v = Rcpp::no_init(nElems);
    read_(GDALExtendedDataTypeCreate(GDT_Float64), v.begin());
    const bool is_floating = GDALDataTypeIsFloating(eDT);
    const bool use_nodata = bHasNoData && !std::isnan(dfNoData);
    if (is_floating || use_nodata) {
        for (double &val : v) {
            if (is_floating && std::isnan(val))
                val = NA_REAL;
            else if (use_nodata && val == dfNoData)
                val = NA_REAL;
        }
    }
    return v;
}


// ****************************************************************************
// class GDALMDArrayR
// ****************************************************************************

GDALMDArrayR::GDALMDArrayR() {
    // objects are returned by GDALMultiDimRaster$openMDArray()
    // the default constructor is not intended for user code
}

GDALMDArrayR::~GDALMDArrayR() {
    close();
}

bool GDALMDArrayR::isOpen() const {
    return m_hArray != nullptr;
}

std::string GDALMDArrayR::getName() const {
    checkAccess_();

    const char *psz = GDALMDArrayGetName(m_hArray);
    return psz ? psz : "";
}

std::string GDALMDArrayR::getFullName() const {
    checkAccess_();

    const char *psz = GDALMDArrayGetFullName(m_hArray);
    return psz ? psz : "";
}

int GDALMDArrayR::getDimensionCount() const {
    checkAccess_();

    return static_cast<int>(GDALMDArrayGetDimensionCount(m_hArray));
}

Rcpp::DataFrame GDALMDArrayR::getDimensions() const {
    checkAccess_();

    size_t nCount = 0;
    GDALDimensionH *pahDims = GDALMDArrayGetDimensions(m_hArray, &nCount);
    return mdim_dimensions_to_df_(pahDims, nCount);
}

Rcpp::List GDALMDArrayR::getDataType() const {
    checkAccess_();

    GDALExtendedDataTypeH hDT = GDALMDArrayGetDataType(m_hArray);
    if (hDT == nullptr)
        Rcpp::stop("failed to get the array data type");

    const GDALExtendedDataTypeClass eClass = GDALExtendedDataTypeGetClass(hDT);
    std::string class_name = "";
    std::string numeric_type = "";
    if (eClass == GEDTC_NUMERIC) {
        class_name = "NUMERIC";
        numeric_type = GDALGetDataTypeName(
                GDALExtendedDataTypeGetNumericDataType(hDT));
    }
    else if (eClass == GEDTC_STRING) {
        class_name = "STRING";
    }
    else if (eClass == GEDTC_COMPOUND) {
        class_name = "COMPOUND";
    }
    const char *pszName = GDALExtendedDataTypeGetName(hDT);
    const std::string name = pszName ? pszName : "";
    const double size = static_cast<double>(GDALExtendedDataTypeGetSize(hDT));
    GDALExtendedDataTypeRelease(hDT);

    return Rcpp::List::create(
        Rcpp::Named("class") = class_name,
        Rcpp::Named("numeric_type") = numeric_type,
        Rcpp::Named("name") = name,
        Rcpp::Named("size") = size);
}

Rcpp::List GDALMDArrayR::getAttributes() const {
    checkAccess_();

    size_t nCount = 0;
    GDALAttributeH *pahAttrs = GDALMDArrayGetAttributes(m_hArray, &nCount,
                                                        nullptr);
    return mdim_attributes_to_list_(pahAttrs, nCount);
}

double GDALMDArrayR::getNoDataValue() const {
    checkAccess_();

    int bHasValue = FALSE;
    const double val = GDALMDArrayGetNoDataValueAsDouble(m_hArray,
                                                         &bHasValue);
    return bHasValue ? val : NA_REAL;
}

double GDALMDArrayR::getScale() const {
    checkAccess_();

    int bHasValue = FALSE;
    const double val = GDALMDArrayGetScale(m_hArray, &bHasValue);
    return bHasValue ? val : NA_REAL;
}

double GDALMDArrayR::getOffset() const {
    checkAccess_();

    int bHasValue = FALSE;
    const double val = GDALMDArrayGetOffset(m_hArray, &bHasValue);
    return bHasValue ? val : NA_REAL;
}

std::string GDALMDArrayR::getUnit() const {
    checkAccess_();

    const char *psz = GDALMDArrayGetUnit(m_hArray);
    return psz ? psz : "";
}

std::string GDALMDArrayR::getSpatialRef() const {
    checkAccess_();

    OGRSpatialReferenceH hSRS = GDALMDArrayGetSpatialRef(m_hArray);
    if (hSRS == nullptr)
        return "";

    char *pszWKT = nullptr;
    std::string wkt = "";
    if (OSRExportToWkt(hSRS, &pszWKT) == OGRERR_NONE && pszWKT != nullptr)
        wkt = pszWKT;
    CPLFree(pszWKT);
    OSRDestroySpatialReference(hSRS);
    return wkt;
}

Rcpp::NumericVector GDALMDArrayR::getBlockSize() const {
    checkAccess_();

    size_t nCount = 0;
    GUInt64 *panBlockSize = GDALMDArrayGetBlockSize(m_hArray, &nCount);
    Rcpp::NumericVector out(nCount);
    for (size_t i = 0; i < nCount; ++i)
        out[i] = static_cast<double>(panBlockSize[i]);
    CPLFree(panBlockSize);
    return out;
}

Rcpp::List GDALMDArrayR::getInfo() const {
    checkAccess_();

    return Rcpp::List::create(
        Rcpp::Named("name") = getName(),
        Rcpp::Named("full_name") = getFullName(),
        Rcpp::Named("dimensions") = getDimensions(),
        Rcpp::Named("datatype") = getDataType(),
        Rcpp::Named("block_size") = getBlockSize(),
        Rcpp::Named("nodata") = getNoDataValue(),
        Rcpp::Named("scale") = getScale(),
        Rcpp::Named("offset") = getOffset(),
        Rcpp::Named("unit") = getUnit(),
        Rcpp::Named("srs") = getSpatialRef(),
        Rcpp::Named("attributes") = getAttributes());
}

SEXP GDALMDArrayR::getCoordinateValues(int dim) const {
    checkAccess_();

    size_t nCount = 0;
    GDALDimensionH *pahDims = GDALMDArrayGetDimensions(m_hArray, &nCount);
    if (dim < 0 || static_cast<size_t>(dim) >= nCount) {
        if (pahDims != nullptr)
            GDALReleaseDimensions(pahDims, nCount);
        Rcpp::stop("'dim' must be a 0-based dimension index, from 0 to " +
                   std::to_string(static_cast<int>(nCount) - 1));
    }

    GDALMDArrayH hVar = GDALDimensionGetIndexingVariable(pahDims[dim]);
    GDALReleaseDimensions(pahDims, nCount);
    if (hVar == nullptr)
        return R_NilValue;

    SEXP out = R_NilValue;
    try {
        out = mdim_read_array_(hVar, Rcpp::NumericVector::create(),
                               Rcpp::NumericVector::create(), R_NilValue,
                               false);
    }
    catch (...) {
        GDALMDArrayRelease(hVar);
        throw;
    }
    GDALMDArrayRelease(hVar);
    return out;
}

SEXP GDALMDArrayR::read() const {
    checkAccess_();

    return mdim_read_array_(m_hArray, Rcpp::NumericVector::create(),
                            Rcpp::NumericVector::create(), R_NilValue,
                            this->readByteAsRaw);
}

SEXP GDALMDArrayR::read(const Rcpp::NumericVector &start,
                        const Rcpp::NumericVector &count) const {
    checkAccess_();

    return mdim_read_array_(m_hArray, start, count, R_NilValue,
                            this->readByteAsRaw);
}

SEXP GDALMDArrayR::read(const Rcpp::NumericVector &start,
                        const Rcpp::NumericVector &count,
                        const Rcpp::Nullable<Rcpp::NumericVector> &step) const {
    checkAccess_();

    return mdim_read_array_(m_hArray, start, count, step,
                            this->readByteAsRaw);
}

void GDALMDArrayR::close() {
    if (m_hArray != nullptr) {
        GDALMDArrayRelease(m_hArray);
        m_hArray = nullptr;
    }
    if (m_hDataset != nullptr) {
        GDALReleaseDataset(m_hDataset);
        m_hDataset = nullptr;
    }
}

void GDALMDArrayR::show() const {
    cli_text_("C++ object of class {.cls GDALMDArray}");
    if (!isOpen()) {
        cli_ul_();
        cli_li_("{.emph Array is closed}");
        cli_end_();
        return;
    }

    Rcpp::DataFrame dims = getDimensions();
    Rcpp::CharacterVector dim_names = dims["name"];
    Rcpp::NumericVector dim_sizes = dims["size"];
    std::string shape = "";
    for (R_xlen_t i = 0; i < dim_names.size(); ++i) {
        if (i > 0)
            shape += ", ";
        char szSize[32];
        snprintf(szSize, sizeof(szSize), "%.0f", dim_sizes[i]);
        shape += std::string(dim_names[i]) + "=" + szSize;
    }
    Rcpp::NumericVector block = getBlockSize();
    std::string block_str = "";
    bool has_block_size = false;
    for (R_xlen_t i = 0; i < block.size(); ++i) {
        if (block[i] > 0)
            has_block_size = true;
    }
    for (R_xlen_t i = 0; has_block_size && i < block.size(); ++i) {
        if (i > 0)
            block_str += " x ";
        char szSize[32];
        snprintf(szSize, sizeof(szSize), "%.0f", block[i]);
        block_str += szSize;
    }
    Rcpp::List dt = getDataType();
    std::string dt_str = Rcpp::as<std::string>(dt["numeric_type"]);
    if (dt_str.empty())
        dt_str = Rcpp::as<std::string>(dt["class"]);

    cli_ul_();
    cli_li_("{.emph Name}: "s + getFullName());
    cli_li_("{.emph Data type}: "s + dt_str);
    cli_li_("{.emph Dimensions}: "s + (shape.empty() ? "(scalar)" : shape));
    if (!block_str.empty())
        cli_li_("{.emph Block size}: "s + block_str);
    if (!getUnit().empty())
        cli_li_("{.emph Unit}: "s + getUnit());
    cli_end_();
}

// ****************************************************************************
// class methods for internal use not exposed in R
// ****************************************************************************

void GDALMDArrayR::checkAccess_() const {
    if (!isOpen())
        Rcpp::stop("array is not open");
}

void GDALMDArrayR::setHandles_(GDALMDArrayH hArray, GDALDatasetH hDS) {
    close();
    m_hArray = hArray;
    if (hDS != nullptr) {
        GDALReferenceDataset(hDS);
        m_hDataset = hDS;
    }
}

// ****************************************************************************

RCPP_MODULE(mod_GDALMDArray) {
    Rcpp::class_<GDALMDArrayR>("GDALMDArray")

    .constructor
        ("Default constructor, objects are returned by "
         "GDALMultiDimRaster$openMDArray()")

    // exposed read/write fields
    .field("readByteAsRaw", &GDALMDArrayR::readByteAsRaw)
    .field("quiet", &GDALMDArrayR::quiet)

    // exposed member functions
    .const_method("isOpen", &GDALMDArrayR::isOpen,
        "Is the array open")
    .const_method("getName", &GDALMDArrayR::getName,
        "Return the array name")
    .const_method("getFullName", &GDALMDArrayR::getFullName,
        "Return the full path of the array")
    .const_method("getDimensionCount", &GDALMDArrayR::getDimensionCount,
        "Return the number of dimensions")
    .const_method("getDimensions", &GDALMDArrayR::getDimensions,
        "Return a data frame describing the dimensions")
    .const_method("getDataType", &GDALMDArrayR::getDataType,
        "Return a list describing the data type")
    .const_method("getAttributes", &GDALMDArrayR::getAttributes,
        "Return the attributes of the array")
    .const_method("getNoDataValue", &GDALMDArrayR::getNoDataValue,
        "Return the nodata value")
    .const_method("getScale", &GDALMDArrayR::getScale,
        "Return the scale value")
    .const_method("getOffset", &GDALMDArrayR::getOffset,
        "Return the offset value")
    .const_method("getUnit", &GDALMDArrayR::getUnit,
        "Return the unit")
    .const_method("getSpatialRef", &GDALMDArrayR::getSpatialRef,
        "Return the spatial reference system as WKT")
    .const_method("getBlockSize", &GDALMDArrayR::getBlockSize,
        "Return the block (chunk) size")
    .const_method("getInfo", &GDALMDArrayR::getInfo,
        "Return a list describing the array")
    .const_method("getCoordinateValues", &GDALMDArrayR::getCoordinateValues,
        "Return the values of the indexing variable of a dimension")
    .const_method("read",
        static_cast<SEXP (GDALMDArrayR::*)() const>(&GDALMDArrayR::read),
        "Read the whole array")
    .const_method("read",
        static_cast<SEXP (GDALMDArrayR::*)(const Rcpp::NumericVector &,
                                           const Rcpp::NumericVector &) const>
            (&GDALMDArrayR::read),
        "Read a hyperslab given start and count")
    .const_method("read",
        static_cast<SEXP (GDALMDArrayR::*)(
            const Rcpp::NumericVector &, const Rcpp::NumericVector &,
            const Rcpp::Nullable<Rcpp::NumericVector> &) const>
            (&GDALMDArrayR::read),
        "Read a hyperslab given start, count and step")
    .method("close", &GDALMDArrayR::close,
        "Release the array and the dataset reference")
    .const_method("show", &GDALMDArrayR::show,
        "S4 show()")

    ;
}
