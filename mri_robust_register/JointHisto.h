/**
 * @file  JointHisto.h
 * @brief A class for a joint histogram of two images
 *
 */

/*
 * Original Author: Martin Reuter
 * CVS Revision Info:
 *    $Author: mreuter $
 *    $Date: 2011/09/13 03:08:25 $
 *    $Revision: 1.1 $
 *
 * Copyright © 2011 The General Hospital Corporation (Boston, MA) "MGH"
 *
 * Terms and conditions for use, reproduction, distribution and contribution
 * are found in the 'FreeSurfer Software License Agreement' contained
 * in the file 'LICENSE' found in the FreeSurfer distribution, and here:
 *
 * https://surfer.nmr.mgh.harvard.edu/fswiki/FreeSurferSoftwareLicense
 *
 * Reporting: freesurfer@nmr.mgh.harvard.edu
 *
 */
//
// written by Martin Reuter
// Sep. 1st ,2011
//

#ifndef JointHisto_H
#define JointHisto_H

#ifdef __cplusplus
extern "C"
{
#endif
#include "mri.h"
#ifdef __cplusplus
}
#endif

#include <vnl/vnl_matrix_fixed.h>
#include <vnl/vnl_matlab_print.h>
#include <vcl_iostream.h>


class JointHisto
{
public:
  
  JointHisto():n(256),sum(0.0),histo(256,256),haseps(false){};
  JointHisto(MRI *mri1, MRI * mri2, int d1=1, int d2=1, int d3=1):n(256),sum(0.0),histo(256,256),haseps(false)
    {create(mri1,mri2,d1,d2,d3);};
  JointHisto(MRI *mri1, MRI * mri2,
             const vnl_matrix_fixed < double, 4,4 >& M1,
             const vnl_matrix_fixed < double, 4,4 >& M2,
             int d1=1, int d2=1, int d3=1):n(256),sum(0.0),histo(256,256),haseps(false)
    {create(mri1,mri2,M1,M2,d1,d2,d3);};
  void create(MRI *mri1, MRI * mri2, int d1=1, int d2=1, int d3=1);
  void create(MRI *mri1, MRI * mri2, 
              const vnl_matrix_fixed < double, 4,4 >& M1,
              const vnl_matrix_fixed < double, 4,4 >& M2,
              int d1=1, int d2=1, int d3=1);
  void set(const  vnl_matrix < double > & histo);
  void smooth(double fwhm1 = 7.0);
  void print(const std::string & n = "H"){vnl_matlab_print(vcl_cerr,histo,n.c_str());std::cerr << std::endl;};
  void normalize(){if (sum == 0.0 || sum == 1.0) return; else { histo /= sum; sum = 1.0;} };

  double computeMI();
  double computeNMI();
  double computeECC();
  double computeNCC();
  double computeLS();

protected:

  void computeRCsums()
  {
     // compute row and column sums
     vnl_matrix < double > v1(n,1,1);
     vnl_matrix < double > v2(1,n,1);
     rowsum = (histo *v1).get_column(0);
     colsum = (v2 * histo).get_row(0);
  };
  
  void addeps(double eps=2.2204E-16) { if (haseps) return; else {histo += eps;haseps=true;} };

  int n;
  double sum;
  vnl_matrix < double > histo;
  vnl_vector < double > rowsum;
  vnl_vector < double > colsum;
  bool haseps;
};



#endif