/* R interface to the GDAL Multidimensional Raster C API.
   A class for a multidimensional dataset and its root group.
   https://gdal.org/en/stable/api/raster_c_api.html (GDALGroup* functions)
   https://gdal.org/en/stable/user/multidim_raster_data_model.html

   Michael D. Sumner
   Copyright (c) 2026 gdalraster authors
*/

#ifndef GDALMULTIDIMRASTER_H_
#define GDALMULTIDIMRASTER_H_

#include <Rcpp.h>

#include <string>

// Predeclare some GDAL types until the public header is included
#ifndef GDAL_H_INCLUDED
    #ifndef GDALRASTER_H_
        typedef void *GDALDatasetH;
        typedef enum {GA_ReadOnly = 0, GA_Update = 1} GDALAccess;
    #endif
    typedef struct GDALGroupHS *GDALGroupH;
    typedef struct GDALMDArrayHS *GDALMDArrayH;
    typedef struct GDALAttributeHS *GDALAttributeH;
#endif

class GDALMultiDimRaster {
 public:
    GDALMultiDimRaster();
    explicit GDALMultiDimRaster(const Rcpp::CharacterVector &filename);
    GDALMultiDimRaster(const Rcpp::CharacterVector &filename, bool read_only);
    GDALMultiDimRaster(const Rcpp::CharacterVector &filename, bool read_only,
                       const Rcpp::CharacterVector &open_options);
    GDALMultiDimRaster(const Rcpp::CharacterVector &filename, bool read_only,
                       const Rcpp::Nullable<Rcpp::CharacterVector>
                           &open_options,
                       bool shared,
                       const Rcpp::Nullable<Rcpp::CharacterVector>
                           &allowed_drivers);
    ~GDALMultiDimRaster();

    // exposed read/write fields
    Rcpp::CharacterVector infoOptions {};
    bool quiet {false};

    // exposed methods
    std::string getFilename() const;
    void open(bool read_only);
    bool isOpen() const;
    bool isReadOnly() const;
    std::string getDriverShortName() const;
    std::string getDriverLongName() const;
    Rcpp::CharacterVector getFileList() const;
    void info() const;
    void close();

    Rcpp::CharacterVector getGroupNames(const std::string &path) const;
    Rcpp::CharacterVector getMDArrayNames(const std::string &path) const;
    Rcpp::DataFrame getDimensions(const std::string &path) const;
    Rcpp::List getAttributes(const std::string &path) const;
    Rcpp::List getGroupInfo(const std::string &path) const;

    void show() const;

    // methods for internal use not exported to R
    void checkAccess_(GDALAccess access_needed) const;
    GDALGroupH openGroup_(const std::string &path, bool must_exist) const;
    GDALMDArrayH openMDArray_(const std::string &path, bool must_exist) const;

 private:
    std::string m_filename {""};
    Rcpp::CharacterVector m_open_options {};
    Rcpp::CharacterVector m_allowed_drivers {};
    bool m_shared {false};
    GDALDatasetH m_hDataset {nullptr};
    GDALGroupH m_hRootGroup {nullptr};
    GDALAccess m_eAccess {GA_ReadOnly};
};

// helpers shared with the multidim classes, not exported to R
std::string mdim_normalize_path_(const std::string &path);
SEXP mdim_attribute_to_sexp_(GDALAttributeH hAttr);
Rcpp::List mdim_attributes_to_list_(GDALAttributeH *pahAttrs, size_t nCount);

// cppcheck-suppress unknownMacro
RCPP_EXPOSED_CLASS(GDALMultiDimRaster)

#endif  // GDALMULTIDIMRASTER_H_
