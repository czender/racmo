#!/usr/bin/env bash

# Purpose: Convert raw RACMO v2.4.1 data into format used by LIVVKit
# Prequisites: NCO

# Usage:
# ~/racmo/racmo.sh 
# ~/racmo/racmo.sh > ~/foo.txt 2>&1 &

# Synchronize generated ice-sheet mask files to local grid directory
# cd ${DATA}/grids;rsync 'zender@imua.ess.uci.edu:data/grids/msk_?is_r??.nc' .;ls -l msk_?is_r??.nc

unset sec_per_mth # [s] Seconds per month
declare -a sec_per_mth
sec_per_mth=(0 2678400 2419200 2678400 2592000 2678400 2592000 2678400 2678400 2592000 2678400 2592000 2678400) # noleap 365-day calendar, 1-based indexing

# Locations of Chloe's GIS data
# /global/cfs/cdirs/fanssie/racmo/raw/RACMO2.4/FGRN055/mon_climos
# /global/cfs/cdirs/fanssie/racmo/raw/RACMO2.4/PXANT11/???_climos

#drc_root='/global/cfs/cdirs/fanssie' # Perlmutter
drc_root="${DATA}" # Spectral
drc_raw="${drc_root}/racmo/2.4.1/raw"
drc_ts="${drc_root}/racmo/2.4.1/ts"
#for fll_nm in `ls ${drc_raw}`; do
for fll_nm in `ls ${drc_raw}/smbgl_*` ; do # Full filename
    fl_in=$(basename ${fll_nm})
    # https://stackoverflow.com/questions/20348097/bash-extract-string-before-a-colon
    var_nm=${fl_in%%_*}
    # https://stackoverflow.com/questions/21077882/pattern-to-get-string-between-two-specific-words-characters-using-grep
    rgn_rsn=${fl_in#*monthlyS_}
    rgn_rsn=${rgn_rsn%_RACMO2*}
    if [ "${rgn_rsn}" = "PXANT11" ]; then
	ice_nm=ais
	yyyymm_srt_end_in=196001_202312
    elif [ "${rgn_rsn}" = "FGRN055" ]; then
	ice_nm=gis
	yyyymm_srt_end_in=194501_202308
    else
	echo "${spt_nm}: ERROR Invalid \${rgn_rsn} = ${rgn_rsn}"
	exit 1
    fi # !rgn_rsn
    yyyymm_srt_end_out=198001_202012

    echo "Processing variable ${var_nm} for region/resolution ${rgn_rsn}..."
#    if false; then
    fl_in=${var_nm}_monthlyS_${rgn_rsn}_RACMO2.4.1_historical_${yyyymm_srt_end_in}.nc
    fl_out=${var_nm}_${ice_nm}_${yyyymm_srt_end_out}.nc

    # Convert to netCDF3 (to avoid rename bugs), eliminate unwanted variables, select 1980--2020
    cmd_sbs="ncks -O -6 -C --hdr_pad=10000 -d time,1980-01-01,2020-12-31 -x -v rlat,rlon,height ${drc_raw}/${fl_in} ${drc_ts}/${fl_out}"
    echo ${cmd_sbs}
    eval ${cmd_sbs}

    # Make lon,lat coordinates
    cmd_rnm="ncrename -O -d .rlon,lon -d .rlat,lat -a .grid_mapping,grid_mapping_renamed_for_Panoply_sanity ${drc_ts}/${fl_out}"
    echo ${cmd_rnm}
    eval ${cmd_rnm}

    # Convert from monthly sum ("monthlyS") to per-second rate (PSR)
    cmd_flx="ncap2 -O -v -S ~/racmo/mthsum2flx.nco ${drc_ts}/${fl_out} ${drc_ts}/${fl_out}" # works as of 20250310
    echo ${cmd_flx}
    eval ${cmd_flx}

    # Remove height dimension (fxm: if it exists)
    cmd_hgt="ncwa -O -a height ${drc_ts}/${fl_out} ${drc_ts}/${fl_out}"
    echo ${cmd_hgt}
    eval ${cmd_hgt}

    # Eliminate missing_value attribute and change units to fluxes not sums
    if [ ${var_nm} = 'smbgl' ]; then
	new_units='kg m-2 s-1'
    fi # !var_nm
    cmd_att="ncatted -O -a missing_value,,d,, -a units,${var_nm},o,c,\"${new_units}\" ${drc_ts}/${fl_out}"
    echo ${cmd_att}
    eval ${cmd_att}

    # Print space for tidy output
    echo ""
    # if false; then
    #    fi # !false
done # !fll_nm
