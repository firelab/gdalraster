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

    void close();
    void show() const;

    // methods for internal use not exported to R
    void checkAccess_() const;
    // takes ownership of hArray, and adds a reference to hDS
    void setHandles_(GDALMDArrayH hArray, GDALDatasetH hDS);

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
