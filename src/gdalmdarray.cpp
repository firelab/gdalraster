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
#include <cstdio>
#include <cstring>
#include <limits>
#include <memory>
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

#if GDAL_VERSION_NUM >= GDAL_COMPUTE_VERSION(3, 12, 0)
// Stop with the GDAL error message after GDALMDArrayGetRawBlockInfo() failed.
// A driver that does not implement it returns false without a message.
[[noreturn]] static void raw_block_info_stop_() {
    const std::string osMsg(CPLGetLastErrorMsg());
    CPLErrorReset();
    if (osMsg.empty()) {
        Rcpp::stop("failed to get raw block info (not supported for this "
                   "array by the format driver?)");
    }
    Rcpp::stop("failed to get raw block info: " + osMsg);
}
#endif

// min, max, mean, sd and valid_count as a named vector (all NA if !ok)
static Rcpp::NumericVector stats_to_vector_(bool ok, double dfMin,
                                            double dfMax, double dfMean,
                                            double dfStdDev,
                                            GUInt64 nValidCount) {
    Rcpp::NumericVector out = Rcpp::NumericVector::create(
        Rcpp::Named("min") = NA_REAL, Rcpp::Named("max") = NA_REAL,
        Rcpp::Named("mean") = NA_REAL, Rcpp::Named("sd") = NA_REAL,
        Rcpp::Named("valid_count") = NA_REAL);
    if (ok) {
        out[0] = dfMin;
        out[1] = dfMax;
        out[2] = dfMean;
        out[3] = dfStdDev;
        out[4] = static_cast<double>(nValidCount);
    }
    return out;
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
    size_t nDimCount = 0;
    GDALDimensionH *pahDims = GDALMDArrayGetDimensions(hArray, &nDimCount);
    for (size_t i = 0; i < nDimCount && i < nDims; ++i)
        anSize[i] = GDALDimensionGetSize(pahDims[i]);
    if (pahDims != nullptr)
        GDALReleaseDimensions(pahDims, nDimCount);

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
        // not read_(), which stops on failure: free the strings first
        GDALExtendedDataTypeH hBufDT = GDALExtendedDataTypeCreateString(0);
        const int ok = GDALMDArrayRead(hArray, panStart, panCount, panStep,
                                       nullptr, hBufDT, buf.data(), nullptr, 0);
        GDALExtendedDataTypeRelease(hBufDT);
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

SEXP GDALMDArrayR::read(const Rcpp::Nullable<Rcpp::NumericVector> &start,
                        const Rcpp::Nullable<Rcpp::NumericVector> &count,
                        const Rcpp::Nullable<Rcpp::NumericVector> &step) const {
    checkAccess_();

    // NULL start and count read the whole array
    if (start.isNull() != count.isNull())
        Rcpp::stop("'start' and 'count' must both be given, or both NULL");

    Rcpp::NumericVector start_in = Rcpp::NumericVector::create();
    Rcpp::NumericVector count_in = Rcpp::NumericVector::create();
    if (start.isNotNull()) {
        start_in = Rcpp::NumericVector(start);
        count_in = Rcpp::NumericVector(count);
        if (start_in.size() == 0 || count_in.size() == 0)
            Rcpp::stop("'start' and 'count' must have one value per "
                       "dimension, or be NULL");
    }

    return mdim_read_array_(m_hArray, start_in, count_in, step,
                            this->readByteAsRaw);
}

GDALMDArrayR *GDALMDArrayR::getView(const std::string &view_expr) const {
    checkAccess_();

    if (view_expr.empty())
        Rcpp::stop("'view_expr' must be a non-empty string, e.g., \"[0,...]\"");

    GDALMDArrayH hView = GDALMDArrayGetView(m_hArray, view_expr.c_str());
    return newDerived_(hView, "view for expression '" + view_expr + "'");
}

GDALMDArrayR *GDALMDArrayR::transpose(const Rcpp::IntegerVector &axes) const {
    checkAccess_();

    const int nDims = static_cast<int>(GDALMDArrayGetDimensionCount(m_hArray));
    std::vector<int> anMapNewAxisToOldAxis;
    for (R_xlen_t i = 0; i < axes.size(); ++i) {
        if (axes[i] == NA_INTEGER || axes[i] < -1 || axes[i] >= nDims) {
            Rcpp::stop("'axes' must contain 0-based dimension indexes, from "
                       "0 to " + std::to_string(nDims - 1) + ", or -1 for "
                       "a new axis of size 1");
        }
        anMapNewAxisToOldAxis.push_back(axes[i]);
    }

    GDALMDArrayH hTransposed = GDALMDArrayTranspose(
        m_hArray, anMapNewAxisToOldAxis.size(), anMapNewAxisToOldAxis.data());
    return newDerived_(hTransposed, "transposed array");
}

GDALMDArrayR *GDALMDArrayR::getUnscaled() const {
    checkAccess_();

    GDALMDArrayH hUnscaled = GDALMDArrayGetUnscaled(m_hArray);
    return newDerived_(hUnscaled, "unscaled array");
}

GDALMDArrayR *GDALMDArrayR::getMask(
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) const {
    checkAccess_();

    const CPLStringList aosOptions = options_to_csl_(options);

    GDALMDArrayH hMask = GDALMDArrayGetMask(m_hArray, aosOptions.List());
    return newDerived_(hMask, "mask array");
}

GDALRaster *GDALMDArrayR::asClassicDataset(
        int idx_xdim, int idx_ydim,
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) const {
    checkAccess_();

    const int nDims = static_cast<int>(GDALMDArrayGetDimensionCount(m_hArray));
    if (nDims < 1)
        Rcpp::stop("a classic dataset needs an array of 1 or more dimensions");
    if (idx_xdim == NA_INTEGER || idx_xdim < 0 || idx_xdim >= nDims) {
        Rcpp::stop("'idx_xdim' must be a 0-based dimension index, from 0 to " +
                   std::to_string(nDims - 1));
    }
    // idx_ydim is ignored by GDAL for a 1D array
    if (nDims > 1 &&
            (idx_ydim == NA_INTEGER || idx_ydim < 0 || idx_ydim >= nDims)) {
        Rcpp::stop("'idx_ydim' must be a 0-based dimension index, from 0 to " +
                   std::to_string(nDims - 1));
    }
    if (nDims > 1 && idx_xdim == idx_ydim)
        Rcpp::stop("'idx_xdim' and 'idx_ydim' must be different dimensions");

    const CPLStringList aosOptions = options_to_csl_(options);

    GDALDatasetH hClassicDS = nullptr;
#if GDAL_VERSION_NUM >= GDAL_COMPUTE_VERSION(3, 8, 0)
    GDALGroupH hRootGroup = nullptr;
    if (m_hDataset != nullptr)
        hRootGroup = GDALDatasetGetRootGroup(m_hDataset);
    hClassicDS = GDALMDArrayAsClassicDatasetEx(
        m_hArray, static_cast<size_t>(idx_xdim),
        static_cast<size_t>(nDims > 1 ? idx_ydim : 0), hRootGroup,
        aosOptions.List());
    if (hRootGroup != nullptr)
        GDALGroupRelease(hRootGroup);
#else
    if (aosOptions.size() > 0)
        Rcpp::stop("'options' for asClassicDataset() require GDAL >= 3.8");
    hClassicDS = GDALMDArrayAsClassicDataset(
        m_hArray, static_cast<size_t>(idx_xdim),
        static_cast<size_t>(nDims > 1 ? idx_ydim : 0));
#endif

    if (hClassicDS == nullptr)
        Rcpp::stop("failed to get the array as a classic dataset");

    auto ds = std::make_unique<GDALRaster>();
    ds->setGDALDatasetH_(hClassicDS);
    // a returned pointer to an exposed class is owned by R (see openMDArray())
    return ds.release();
}

GDALMDArrayR *GDALMDArrayR::getResampled(
        const Rcpp::Nullable<Rcpp::NumericVector> &new_dim_sizes,
        const std::string &resample_alg, const std::string &target_srs,
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) const {
    checkAccess_();

// requires GDAL >= 3.4 for GDALMDArrayGetResampled()
#if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 4, 0)
    Rcpp::stop("getResampled() requires GDAL >= 3.4");
#else
    GDALRIOResampleAlg eResampleAlg = GRIORA_NearestNeighbour;
    if (EQUAL(resample_alg.c_str(), "nearest") ||
            EQUAL(resample_alg.c_str(), "NearestNeighbour"))
        eResampleAlg = GRIORA_NearestNeighbour;
    else if (EQUAL(resample_alg.c_str(), "bilinear"))
        eResampleAlg = GRIORA_Bilinear;
    else if (EQUAL(resample_alg.c_str(), "cubic"))
        eResampleAlg = GRIORA_Cubic;
    else if (EQUAL(resample_alg.c_str(), "cubicspline"))
        eResampleAlg = GRIORA_CubicSpline;
    else if (EQUAL(resample_alg.c_str(), "lanczos"))
        eResampleAlg = GRIORA_Lanczos;
    else if (EQUAL(resample_alg.c_str(), "average"))
        eResampleAlg = GRIORA_Average;
    else if (EQUAL(resample_alg.c_str(), "rms"))
        eResampleAlg = GRIORA_RMS;
    else if (EQUAL(resample_alg.c_str(), "mode"))
        eResampleAlg = GRIORA_Mode;
    else
        Rcpp::stop("'resample_alg' is not valid");

    size_t nDims = 0;
    GDALDimensionH *pahDims = GDALMDArrayGetDimensions(m_hArray, &nDims);

    Rcpp::NumericVector sizes(nDims, NA_REAL);
    if (new_dim_sizes.isNotNull()) {
        sizes = Rcpp::NumericVector(new_dim_sizes);
        if (static_cast<size_t>(sizes.size()) != nDims) {
            GDALReleaseDimensions(pahDims, nDims);
            Rcpp::stop("'new_dim_sizes' must have one value per dimension (" +
                       std::to_string(nDims) + "), or be NULL");
        }
    }

    // new dimensions of a given size are created in a MEM dataset, with the
    // name, type and direction of the source dimension. NA (nullptr) lets
    // GDAL keep the dimension, or compute the horizontal ones.
    GDALDatasetH hMemDS = nullptr;
    GDALGroupH hMemRoot = nullptr;
    std::vector<GDALDimensionH> ahNewDims(nDims, nullptr);
    bool bError = false;
    std::string osError = "";
    for (size_t i = 0; i < nDims; ++i) {
        if (Rcpp::NumericVector::is_na(sizes[i]))
            continue;
        if (!is_whole_in_range_(sizes[i], 1, 1e15)) {
            bError = true;
            osError = "'new_dim_sizes' must be whole numbers >= 1, or NA";
            break;
        }
        if (hMemDS == nullptr) {
            GDALDriverH hMemDrv = GDALGetDriverByName("MEM");
            if (hMemDrv != nullptr) {
                hMemDS = GDALCreateMultiDimensional(hMemDrv, "", nullptr,
                                                    nullptr);
            }
            if (hMemDS != nullptr)
                hMemRoot = GDALDatasetGetRootGroup(hMemDS);
            if (hMemRoot == nullptr) {
                bError = true;
                osError = "failed to create the new dimensions";
                break;
            }
        }
        ahNewDims[i] = GDALGroupCreateDimension(
            hMemRoot, GDALDimensionGetName(pahDims[i]),
            GDALDimensionGetType(pahDims[i]),
            GDALDimensionGetDirection(pahDims[i]),
            static_cast<GUInt64>(sizes[i]), nullptr);
        if (ahNewDims[i] == nullptr) {
            bError = true;
            osError = "failed to create the new dimensions";
            break;
        }
    }
    GDALReleaseDimensions(pahDims, nDims);

    OGRSpatialReferenceH hSRS = nullptr;
    if (!bError && !target_srs.empty()) {
        // without a source SRS, GDAL returns the array unchanged
        OGRSpatialReferenceH hSrcSRS = GDALMDArrayGetSpatialRef(m_hArray);
        if (hSrcSRS == nullptr) {
            bError = true;
            osError = "the array has no spatial reference, so it cannot be "
                      "reprojected to 'target_srs'";
        }
        else {
            OSRDestroySpatialReference(hSrcSRS);
        }
    }
    if (!bError && !target_srs.empty()) {
        hSRS = OSRNewSpatialReference(nullptr);
        if (OSRSetFromUserInput(hSRS, target_srs.c_str()) != OGRERR_NONE) {
            bError = true;
            osError = "'target_srs' is not a valid spatial reference";
        }
        else {
            OSRSetAxisMappingStrategy(hSRS, OAMS_TRADITIONAL_GIS_ORDER);
        }
    }

    GDALMDArrayH hResampled = nullptr;
    if (!bError) {
        const CPLStringList aosOptions = options_to_csl_(options);
        hResampled = GDALMDArrayGetResampled(m_hArray, nDims,
                                             ahNewDims.data(), eResampleAlg,
                                             hSRS, aosOptions.List());
    }

    for (GDALDimensionH hDim : ahNewDims) {
        if (hDim != nullptr)
            GDALDimensionRelease(hDim);
    }
    if (hMemRoot != nullptr)
        GDALGroupRelease(hMemRoot);
    if (hMemDS != nullptr)
        GDALReleaseDataset(hMemDS);
    if (hSRS != nullptr)
        OSRDestroySpatialReference(hSRS);

    if (bError)
        Rcpp::stop(osError);

    return newDerived_(hResampled, "resampled array");
#endif
}

GDALMDArrayR *GDALMDArrayR::getGridded(
        const std::string &grid_options, SEXP x_array, SEXP y_array,
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) const {
    checkAccess_();

// requires GDAL >= 3.7 for GDALMDArrayGetGridded()
#if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 7, 0)
    Rcpp::stop("getGridded() requires GDAL >= 3.7");
#else
    if (grid_options.empty())
        Rcpp::stop("'grid_options' must be a non-empty string, e.g., "
                   "\"invdist\"");

    GDALMDArrayH hXArray = nullptr;
    if (!Rf_isNull(x_array)) {
        const GDALMDArrayR *x = Rcpp::as<GDALMDArrayR *>(x_array);
        x->checkAccess_();
        hXArray = x->getMDArrayH_();
    }
    GDALMDArrayH hYArray = nullptr;
    if (!Rf_isNull(y_array)) {
        const GDALMDArrayR *y = Rcpp::as<GDALMDArrayR *>(y_array);
        y->checkAccess_();
        hYArray = y->getMDArrayH_();
    }
    if ((hXArray == nullptr) != (hYArray == nullptr))
        Rcpp::stop("'x_array' and 'y_array' must both be given, or both NULL");

    const CPLStringList aosOptions = options_to_csl_(options);

    GDALMDArrayH hGridded = GDALMDArrayGetGridded(
        m_hArray, grid_options.c_str(), hXArray, hYArray, aosOptions.List());
    return newDerived_(hGridded, "gridded array");
#endif
}

bool GDALMDArrayR::adviseRead(
        const Rcpp::Nullable<Rcpp::NumericVector> &start,
        const Rcpp::Nullable<Rcpp::NumericVector> &count,
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) const {
    checkAccess_();

    if (start.isNull() != count.isNull())
        Rcpp::stop("'start' and 'count' must both be given, or both NULL");

    const size_t nDims = GDALMDArrayGetDimensionCount(m_hArray);
    std::vector<GUInt64> anStart(nDims, 0);
    std::vector<size_t> anCount(nDims, 1);
    // NULL start and count advise for the whole array
    const bool bWholeArray = start.isNull();
    if (!bWholeArray) {
        Rcpp::NumericVector start_in(start);
        Rcpp::NumericVector count_in(count);
        if (static_cast<size_t>(start_in.size()) != nDims ||
                static_cast<size_t>(count_in.size()) != nDims) {
            Rcpp::stop("'start' and 'count' must have one value per "
                       "dimension (" + std::to_string(nDims) + ")");
        }
        size_t nDimCount = 0;
        GDALDimensionH *pahDims = GDALMDArrayGetDimensions(m_hArray,
                                                           &nDimCount);
        bool bInRange = true;
        for (size_t i = 0; i < nDims && i < nDimCount; ++i) {
            const double dfSize =
                static_cast<double>(GDALDimensionGetSize(pahDims[i]));
            if (!is_whole_in_range_(start_in[i], 0, dfSize - 1) ||
                    !is_whole_in_range_(count_in[i], 1,
                                        dfSize - start_in[i])) {
                bInRange = false;
                break;
            }
            anStart[i] = static_cast<GUInt64>(start_in[i]);
            anCount[i] = static_cast<size_t>(count_in[i]);
        }
        if (pahDims != nullptr)
            GDALReleaseDimensions(pahDims, nDimCount);
        if (!bInRange)
            Rcpp::stop("'start' and 'count' are out of range");
    }

    const CPLStringList aosOptions = options_to_csl_(options);
#if GDAL_VERSION_NUM >= GDAL_COMPUTE_VERSION(3, 4, 0)
    return GDALMDArrayAdviseReadEx(
        m_hArray, bWholeArray ? nullptr : anStart.data(),
        bWholeArray ? nullptr : anCount.data(), aosOptions.List());
#else
    if (aosOptions.size() > 0)
        Rcpp::stop("'options' for adviseRead() require GDAL >= 3.4");
    return GDALMDArrayAdviseRead(
        m_hArray, bWholeArray ? nullptr : anStart.data(),
        bWholeArray ? nullptr : anCount.data());
#endif
}

Rcpp::NumericVector GDALMDArrayR::getProcessingChunkSize(
        double max_chunk_memory) const {
    checkAccess_();

    if (!is_whole_in_range_(max_chunk_memory, 1,
                            static_cast<double>(
                                std::numeric_limits<size_t>::max() / 2))) {
        Rcpp::stop("'max_chunk_memory' must be a number of bytes >= 1");
    }

    size_t nCount = 0;
    size_t *panChunkSize = GDALMDArrayGetProcessingChunkSize(
        m_hArray, &nCount, static_cast<size_t>(max_chunk_memory));
    Rcpp::NumericVector out(nCount);
    for (size_t i = 0; i < nCount; ++i)
        out[i] = static_cast<double>(panChunkSize[i]);
    CPLFree(panChunkSize);
    return out;
}

Rcpp::NumericVector GDALMDArrayR::getStatistics(bool approx_ok,
                                                bool force) const {
    checkAccess_();

    double dfMin = 0, dfMax = 0, dfMean = 0, dfStdDev = 0;
    GUInt64 nValidCount = 0;
    // CE_Warning is returned if there are no statistics and force is false
    const CPLErr err = GDALMDArrayGetStatistics(
        m_hArray, m_hDataset, approx_ok, force, &dfMin, &dfMax, &dfMean,
        &dfStdDev, &nValidCount,
        (force && !quiet) ? GDALTermProgressR : nullptr, nullptr);
    if (err == CE_Failure)
        Rcpp::stop("failed to get statistics");

    return stats_to_vector_(err == CE_None, dfMin, dfMax, dfMean, dfStdDev,
                            nValidCount);
}

Rcpp::NumericVector GDALMDArrayR::computeStatistics(
        bool approx_ok,
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) const {
    checkAccess_();

    double dfMin = 0, dfMax = 0, dfMean = 0, dfStdDev = 0;
    GUInt64 nValidCount = 0;
    const CPLStringList aosOptions = options_to_csl_(options);
    int ok = FALSE;
#if GDAL_VERSION_NUM >= GDAL_COMPUTE_VERSION(3, 8, 0)
    ok = GDALMDArrayComputeStatisticsEx(
        m_hArray, m_hDataset, approx_ok, &dfMin, &dfMax, &dfMean, &dfStdDev,
        &nValidCount, quiet ? nullptr : GDALTermProgressR, nullptr,
        aosOptions.List());
#else
    if (aosOptions.size() > 0)
        Rcpp::stop("'options' for computeStatistics() require GDAL >= 3.8");
    ok = GDALMDArrayComputeStatistics(
        m_hArray, m_hDataset, approx_ok, &dfMin, &dfMax, &dfMean, &dfStdDev,
        &nValidCount, quiet ? nullptr : GDALTermProgressR, nullptr);
#endif
    if (!ok)
        Rcpp::stop("failed to compute statistics");

    return stats_to_vector_(true, dfMin, dfMax, dfMean, dfStdDev,
                            nValidCount);
}

bool GDALMDArrayR::cache(
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) const {
    checkAccess_();

// requires GDAL >= 3.4 for GDALMDArrayCache()
#if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 4, 0)
    Rcpp::stop("cache() requires GDAL >= 3.4");
#else
    const CPLStringList aosOptions = options_to_csl_(options);
    return GDALMDArrayCache(m_hArray, aosOptions.List());
#endif
}

Rcpp::List GDALMDArrayR::getRawBlockInfo(
        const Rcpp::NumericVector &block_coords) const {
    checkAccess_();

// requires GDAL >= 3.12 for GDALMDArrayGetRawBlockInfo()
#if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 12, 0)
    Rcpp::stop("getRawBlockInfo() requires GDAL >= 3.12");
#else
    const size_t nDims = GDALMDArrayGetDimensionCount(m_hArray);
    if (static_cast<size_t>(block_coords.size()) != nDims) {
        Rcpp::stop("'block_coords' must have one value per dimension (" +
                   std::to_string(nDims) + ")");
    }
    // at least one element so that the pointer passed to GDAL is not null
    std::vector<uint64_t> anBlockCoords(std::max<size_t>(nDims, 1), 0);
    for (size_t i = 0; i < nDims; ++i) {
        if (!is_whole_in_range_(block_coords[i], 0,
                                static_cast<double>(MAX_INT_AS_R_NUMERIC_)))
            Rcpp::stop("'block_coords' must be whole numbers >= 0");
        anBlockCoords[i] = static_cast<uint64_t>(block_coords[i]);
    }

    std::unique_ptr<GDALMDArrayRawBlockInfo,
                    decltype(&GDALMDArrayRawBlockInfoRelease)>
        psInfo(GDALMDArrayRawBlockInfoCreate(),
               GDALMDArrayRawBlockInfoRelease);
    if (!psInfo)
        Rcpp::stop("failed to allocate raw block info");

    CPLErrorReset();
    if (!GDALMDArrayGetRawBlockInfo(m_hArray, anBlockCoords.data(),
                                    psInfo.get())) {
        raw_block_info_stop_();
    }

    Rcpp::List out = Rcpp::List::create(
        Rcpp::Named("filename") = Rcpp::CharacterVector::create(NA_STRING),
        Rcpp::Named("offset") = NA_REAL,
        Rcpp::Named("size") = NA_REAL,
        Rcpp::Named("info") = wrap_gdal_string_list_(
            CPLStringList(psInfo->papszInfo, FALSE)),
        Rcpp::Named("inline_data") = R_NilValue);

    if (psInfo->pszFilename != nullptr) {
        out["filename"] = Rcpp::CharacterVector::create(
            Rcpp::String(psInfo->pszFilename));
        out["offset"] = static_cast<double>(psInfo->nOffset);
    }
    // a missing block has no filename, no inline data and a size of 0
    if (psInfo->pszFilename != nullptr || psInfo->pabyInlineData != nullptr)
        out["size"] = static_cast<double>(psInfo->nSize);
    if (psInfo->pabyInlineData != nullptr) {
        Rcpp::RawVector inline_data =
            Rcpp::no_init(static_cast<R_xlen_t>(psInfo->nSize));
        if (psInfo->nSize > 0) {
            std::memcpy(inline_data.begin(), psInfo->pabyInlineData,
                        static_cast<size_t>(psInfo->nSize));
        }
        out["inline_data"] = inline_data;
    }
    return out;
#endif
}

Rcpp::DataFrame GDALMDArrayR::getRawBlockRefs(
        const Rcpp::NumericMatrix &block_coords) const {
    checkAccess_();

// requires GDAL >= 3.12 for GDALMDArrayGetRawBlockInfo()
#if GDAL_VERSION_NUM < GDAL_COMPUTE_VERSION(3, 12, 0)
    Rcpp::stop("getRawBlockRefs() requires GDAL >= 3.12");
#else
    const size_t nDims = GDALMDArrayGetDimensionCount(m_hArray);
    if (static_cast<size_t>(block_coords.ncol()) != nDims) {
        Rcpp::stop("'block_coords' must have one column per dimension (" +
                   std::to_string(nDims) + ")");
    }
    const R_xlen_t nBlocks = block_coords.nrow();
    for (R_xlen_t i = 0; i < block_coords.size(); ++i) {
        if (!is_whole_in_range_(block_coords[i], 0,
                                static_cast<double>(MAX_INT_AS_R_NUMERIC_)))
            Rcpp::stop("'block_coords' must be whole numbers >= 0");
    }

    std::unique_ptr<GDALMDArrayRawBlockInfo,
                    decltype(&GDALMDArrayRawBlockInfoRelease)>
        psInfo(GDALMDArrayRawBlockInfoCreate(),
               GDALMDArrayRawBlockInfoRelease);
    if (!psInfo)
        Rcpp::stop("failed to allocate raw block info");

    Rcpp::CharacterVector filename(nBlocks, NA_STRING);
    Rcpp::NumericVector offset(nBlocks, NA_REAL);
    Rcpp::NumericVector size(nBlocks, NA_REAL);
    Rcpp::List info(nBlocks);
    Rcpp::List inline_data(nBlocks);

    // the driver info is usually the same for every block of an array, in
    // which case one character vector is shared by all rows
    std::vector<std::string> aosLastInfo;
    Rcpp::CharacterVector last_info(0);

    // at least one element so that the pointer passed to GDAL is not null
    std::vector<uint64_t> anBlockCoords(std::max<size_t>(nDims, 1), 0);
    const bool bProgress = !quiet && nBlocks > 1;
    if (bProgress)
        GDALTermProgressR(0, nullptr, nullptr);
    for (R_xlen_t i = 0; i < nBlocks; ++i) {
        if (i % 100 == 0)
            Rcpp::checkUserInterrupt();

        for (size_t j = 0; j < nDims; ++j) {
            anBlockCoords[j] = static_cast<uint64_t>(
                block_coords(i, static_cast<int>(j)));
        }

        CPLErrorReset();
        if (!GDALMDArrayGetRawBlockInfo(m_hArray, anBlockCoords.data(),
                                        psInfo.get())) {
            raw_block_info_stop_();
        }

        if (psInfo->pszFilename != nullptr) {
            filename[i] = Rcpp::String(psInfo->pszFilename);
            offset[i] = static_cast<double>(psInfo->nOffset);
        }
        if (psInfo->pszFilename != nullptr ||
                psInfo->pabyInlineData != nullptr) {
            size[i] = static_cast<double>(psInfo->nSize);
        }
        if (psInfo->pabyInlineData != nullptr) {
            Rcpp::RawVector block_data =
                Rcpp::no_init(static_cast<R_xlen_t>(psInfo->nSize));
            if (psInfo->nSize > 0) {
                std::memcpy(block_data.begin(), psInfo->pabyInlineData,
                            static_cast<size_t>(psInfo->nSize));
            }
            inline_data[i] = block_data;
        }

        std::vector<std::string> aosInfo;
        for (char **papszIter = psInfo->papszInfo;
                papszIter != nullptr && *papszIter != nullptr; ++papszIter) {
            aosInfo.emplace_back(*papszIter);
        }
        if (i == 0 || aosInfo != aosLastInfo) {
            last_info = wrap_gdal_string_list_(
                CPLStringList(psInfo->papszInfo, FALSE));
            aosLastInfo = std::move(aosInfo);
        }
        info[i] = last_info;

        if (bProgress) {
            GDALTermProgressR(static_cast<double>(i + 1) /
                                  static_cast<double>(nBlocks),
                              nullptr, nullptr);
        }
    }

    Rcpp::List df = Rcpp::List::create(
        Rcpp::Named("filename") = filename,
        Rcpp::Named("offset") = offset,
        Rcpp::Named("size") = size,
        Rcpp::Named("info") = info,
        Rcpp::Named("inline_data") = inline_data);
    df.attr("class") = Rcpp::CharacterVector{"data.frame"};
    df.attr("row.names") = Rcpp::seq_len(nBlocks);
    return df;
#endif
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
        std::snprintf(szSize, sizeof(szSize), "%.0f", dim_sizes[i]);
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
        std::snprintf(szSize, sizeof(szSize), "%.0f", block[i]);
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

GDALMDArrayH GDALMDArrayR::getMDArrayH_() const {
    return m_hArray;
}

GDALMDArrayR *GDALMDArrayR::newDerived_(GDALMDArrayH hDerived,
                                        const std::string &what) const {
    if (hDerived == nullptr)
        Rcpp::stop("failed to get " + what);

    auto arr = std::make_unique<GDALMDArrayR>();
    arr->setHandles_(hDerived, m_hDataset);
    arr->readByteAsRaw = this->readByteAsRaw;
    arr->quiet = this->quiet;
    // a returned pointer to an exposed class is owned by R (see openMDArray())
    return arr.release();
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
    .const_method("read", &GDALMDArrayR::read,
        "Read the whole array or a hyperslab given start, count and step")
    .const_method("getView", &GDALMDArrayR::getView,
        "Return a view of the array given a view expression")
    .const_method("transpose", &GDALMDArrayR::transpose,
        "Return a view of the array with its axes reordered")
    .const_method("getUnscaled", &GDALMDArrayR::getUnscaled,
        "Return a view of the array with scale and offset applied")
    .const_method("getMask", &GDALMDArrayR::getMask,
        "Return a mask array of the valid values")
    .const_method("asClassicDataset", &GDALMDArrayR::asClassicDataset,
        "Return a view of the array as a classic raster (GDALRaster)")
    .const_method("getResampled", &GDALMDArrayR::getResampled,
        "Return a resampled (and optionally reprojected) view of the array")
    .const_method("getGridded", &GDALMDArrayR::getGridded,
        "Return a gridded view of an array of scattered points")
    .const_method("adviseRead", &GDALMDArrayR::adviseRead,
        "Advise the driver of an upcoming read request")
    .const_method("getProcessingChunkSize",
        &GDALMDArrayR::getProcessingChunkSize,
        "Return a chunk size for processing, given a memory limit")
    .const_method("getStatistics", &GDALMDArrayR::getStatistics,
        "Return statistics of the array, if available or forced")
    .const_method("computeStatistics", &GDALMDArrayR::computeStatistics,
        "Compute statistics of the array")
    .const_method("cache", &GDALMDArrayR::cache,
        "Cache the content of the array into an auxiliary file")
    .const_method("getRawBlockInfo", &GDALMDArrayR::getRawBlockInfo,
        "Return the file location of one stored block")
    .const_method("getRawBlockRefs", &GDALMDArrayR::getRawBlockRefs,
        "Return the file locations of stored blocks as a data frame")
    .method("close", &GDALMDArrayR::close,
        "Release the array and the dataset reference")
    .const_method("show", &GDALMDArrayR::show,
        "S4 show()")

    ;
}
