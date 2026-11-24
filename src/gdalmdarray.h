/* R interface to the GDAL Multidimensional Raster C API.
   A class for a GDALMDArray (an array in a multidimensional dataset).
   https://gdal.org/en/stable/api/raster_c_api.html (GDALMDArray* functions)

   The C++ class is named GDALMDArrayR to avoid a clash with class GDALMDArray
   in gdal_priv.h. It is exposed to R as GDALMDArray.

   Michael D. Sumner
   Copyright (c) 2026 gdalraster authors
*/

#ifndef GDALMDARRAY_H_
#define GDALMDARRAY_H_

#include <Rcpp.h>

#include <string>

// Predeclare some GDAL types until the public header is included
#ifndef GDAL_H_INCLUDED
    #ifndef GDALRASTER_H_
        typedef void *GDALDatasetH;
    #endif
    typedef struct GDALMDArrayHS *GDALMDArrayH;
#endif

class GDALRaster;

class GDALMDArrayR {
 public:
    GDALMDArrayR();
    ~GDALMDArrayR();

    // exposed read/write fields
    bool readByteAsRaw {false};
    bool quiet {false};

    // exposed methods
    bool isOpen() const;
    std::string getName() const;
    std::string getFullName() const;
    int getDimensionCount() const;
    Rcpp::DataFrame getDimensions() const;
    Rcpp::List getDataType() const;
    Rcpp::List getAttributes() const;
    double getNoDataValue() const;
    double getScale() const;
    double getOffset() const;
    std::string getUnit() const;
    std::string getSpatialRef() const;
    Rcpp::NumericVector getBlockSize() const;
    Rcpp::List getInfo() const;
    SEXP getCoordinateValues(int dim) const;

    SEXP read(const Rcpp::Nullable<Rcpp::NumericVector> &start,
              const Rcpp::Nullable<Rcpp::NumericVector> &count,
              const Rcpp::Nullable<Rcpp::NumericVector> &step) const;

    GDALMDArrayR *getView(const std::string &view_expr) const;
    GDALMDArrayR *transpose(const Rcpp::IntegerVector &axes) const;
    GDALMDArrayR *getUnscaled() const;
    GDALMDArrayR *getMask(
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) const;
    GDALRaster *asClassicDataset(
        int idx_xdim, int idx_ydim,
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) const;

    GDALMDArrayR *getResampled(
        const Rcpp::Nullable<Rcpp::NumericVector> &new_dim_sizes,
        const std::string &resample_alg, const std::string &target_srs,
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) const;
    GDALMDArrayR *getGridded(
        const std::string &grid_options, SEXP x_array, SEXP y_array,
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) const;

    bool adviseRead(const Rcpp::Nullable<Rcpp::NumericVector> &start,
                    const Rcpp::Nullable<Rcpp::NumericVector> &count,
                    const Rcpp::Nullable<Rcpp::CharacterVector> &options) const;
    Rcpp::NumericVector getProcessingChunkSize(double max_chunk_memory) const;
    Rcpp::NumericVector getStatistics(bool approx_ok, bool force) const;
    Rcpp::NumericVector computeStatistics(
        bool approx_ok,
        const Rcpp::Nullable<Rcpp::CharacterVector> &options) const;
    bool cache(const Rcpp::Nullable<Rcpp::CharacterVector> &options) const;

    Rcpp::List getRawBlockInfo(const Rcpp::NumericVector &block_coords) const;
    Rcpp::DataFrame getRawBlockRefs(
        const Rcpp::NumericMatrix &block_coords) const;

    void close();
    void show() const;

    // methods for internal use not exported to R
    void checkAccess_() const;
    // takes ownership of hArray, and adds a reference to hDS
    void setHandles_(GDALMDArrayH hArray, GDALDatasetH hDS);
    // a new object for an array derived from this one (view, transpose,
    // etc.), taking ownership of hDerived, or an error if it is NULL
    GDALMDArrayR *newDerived_(GDALMDArrayH hDerived,
                              const std::string &what) const;
    GDALMDArrayH getMDArrayH_() const;

 private:
    GDALMDArrayH m_hArray {nullptr};
    GDALDatasetH m_hDataset {nullptr};
};

// helper shared with class GDALMultiDimRaster, not exported to R
// read a hyperslab from an array handle, see GDALMDArrayR::read()
SEXP mdim_read_array_(GDALMDArrayH hArray,
                      const Rcpp::NumericVector &start,
                      const Rcpp::NumericVector &count,
                      const Rcpp::Nullable<Rcpp::NumericVector> &step,
                      bool read_byte_as_raw);

// cppcheck-suppress unknownMacro
RCPP_EXPOSED_CLASS(GDALMDArrayR)

#endif  // GDALMDARRAY_H_
