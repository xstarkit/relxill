/*
   This file is part of the RELXILL model code.

   RELXILL is free software: you can redistribute it and/or modify it
   under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   any later version.

   RELXILL is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
   GNU General Public License for more details.
   For a copy of the GNU General Public License see
   <http://www.gnu.org/licenses/>.

    Copyright 2020 Thomas Dauser, Remeis Observatory & ECAP
*/

#include "relreturn_corona.h"

#include "relreturn_datastruct.h"
#include "relutility.h"
#include "relbase.h"
#include "writeOutfiles.h"




/**
 * @brief from the known ratio between xillver and power law flux boost, calculate the expected flux
 * correction / factor for any g value (certainly not very accurate for large values of g)
 * @param xill_gshift_fac  : factor between flux boost from xillver wrt to g^Gamma for g=1.5
 * @param g : energy shift
 * @return
 */
double calc_gshift_corr_factor(double xill_gshift_fac, double g){
  if (g>=1){
    return 2*((xill_gshift_fac - 1)*g + 1.5 - xill_gshift_fac );
  } else {
    return 1./(2*((xill_gshift_fac - 1)/g + 1.5 - xill_gshift_fac ) );
  }
}

emisProfile* calc_rrad_emis_corona(const returningFractions *ret_fractions, double gshift_corr_factor,
                                   const emisProfile* emis_input, double gamma, int* status) {


  // make very rough sanity checks here
  assert(gshift_corr_factor>1e-3);
  assert(gshift_corr_factor<1e3);

  int ng = ret_fractions->tabData->ng;
  int nrad = ret_fractions->nrad;

  // need to have emis_input on the SAME radial zone grid, ASCENDING (as tables are ascending in radius)
  //  -> require the grid of the emissivity profile to be identical, means they share the same pointer
  assert(emis_input->re == ret_fractions->rad);
  assert(emis_input->nr == ret_fractions->nrad);
  assert(emis_input->re[0] < emis_input->re[1]);

  double emis_single_zone[nrad];
  double gfac[ng];

  emisProfile* emis_return = new_emisProfile(ret_fractions->rad, ret_fractions->nrad, status); // ret_fractions->rad is not owned by emisReturn

  for (int i_rad_incident = 0; i_rad_incident < nrad; i_rad_incident++) {
    int itab_rad_incident = ret_fractions->irad[i_rad_incident];

    for (int i_rad_emitted = 0; i_rad_emitted < nrad; i_rad_emitted++) {
      int itab_rad_emitted = ret_fractions->irad[i_rad_emitted];

      get_gfac_grid(gfac, ret_fractions->tabData->gmin[itab_rad_incident][itab_rad_emitted],
                    ret_fractions->tabData->gmax[itab_rad_incident][itab_rad_emitted], ng);

      emis_single_zone[i_rad_emitted] = 0.0;
      for (int jj = 0; jj < ng; jj++) {
        emis_single_zone[i_rad_emitted] += pow(gfac[jj], gamma)*calc_gshift_corr_factor(gshift_corr_factor,gfac[jj])
            * ret_fractions->tabData->frac_g[itab_rad_incident][itab_rad_emitted][jj];
      }

      emis_single_zone[i_rad_emitted] *=
          ret_fractions->frac_i[i_rad_incident][i_rad_emitted]
              * emis_input->emis[i_rad_emitted]
              * ret_fractions->tabData->f_ret[ret_fractions->irad[i_rad_emitted]];
    }

    emis_return->emis[i_rad_incident] = calcSum(emis_single_zone, nrad);
  }


  return emis_return;
}

/**
 * @brief determine the lower and upper radius value of the emissivity profile
 * @param emisInput
 * @param rlo_emis [output]
 * @param rhi_emis [output]
 */
void determine_rlo_rhi(const emisProfile *emisInput, double *rlo_emis, double *rhi_emis) {
  if (is_emis_grid_ascending(emisInput)){
    (*rlo_emis) = emisInput->re[0];
    (*rhi_emis) = emisInput->re[emisInput->nr-1];
  } else {
    (*rlo_emis) = emisInput->re[emisInput->nr-1];
    (*rhi_emis) = emisInput->re[0];
  }
  assert((*rlo_emis) < (*rhi_emis));
}

static void apply_returnrad_flux_correction(emisProfile* emis, double flux_correction_factor){
  for (int ii=0; ii < emis->nr; ii++){
    emis->emis[ii] *= flux_correction_factor;
  }
}


/**
 * main function to calculate the returning radiation emissivity profile.
 *
 * Caveat: The radial grid for the relline profile, which is typically used for the emissivity
 * profile, is defined with the radius DESCENDING
 */
emisProfile *get_rrad_emis_corona(const emisProfile* emis_input, const relParam* param, int *status) {

  CHECK_STATUS_RET(*status, NULL);

  double rlo_emis, rhi_emis;
  determine_rlo_rhi(emis_input, &rlo_emis, &rhi_emis);

  returningFractions *ret_fractions = get_rrad_fractions(param->a, rlo_emis, rhi_emis, status);

  emisProfile* emis_input_rebinned = new_emisProfile(ret_fractions->rad, ret_fractions->nrad, status); // ret_fractions->rad is not owned by emis_return
  inv_rebin_mean(emis_input->re, emis_input->emis, emis_input->nr,
                 emis_input_rebinned->re, emis_input_rebinned->emis, emis_input_rebinned->nr, status);

  emisProfile* emis_return = calc_rrad_emis_corona(ret_fractions, param->xillver_gshift_corr_fac,
                                                   emis_input_rebinned, param->gamma, status);
  CHECK_STATUS_RET(*status, NULL);

  emisProfile *emis_return_rebinned = new_emisProfile(emis_input->re, emis_input->nr, status);
  rebin_emisprofile_on_radial_grid(emis_return_rebinned, emis_return, status);

  apply_returnrad_flux_correction(emis_return_rebinned, param->return_rad_flux_correction_factor);

  if( shouldOutfilesBeWritten() ){
    write_data_to_file("test_emis_profile_rrad_input.dat",
                       emis_input_rebinned->re, emis_input_rebinned->emis, emis_input_rebinned->nr);
    write_data_to_file("test_emis_profile_rrad_output.dat",
                       ret_fractions->rad, emis_return->emis, emis_return->nr);
  }

  free_emisProfile(emis_return);
  free_returningFractions(&ret_fractions);

  return emis_return_rebinned;
}

