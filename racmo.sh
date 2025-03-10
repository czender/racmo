#!/usr/bin/env bash

# Purpose: Workflow to convert raw RACMO v 2.4.1 data into format used by LIVVKit
# Workflow invokes NCO

# Usage:
# ~/racmo/racmo.sh 
# ~/racmo/racmo.sh > ~/foo.txt 2>&1 &

# Synchronize generated ice-sheet mask files to local grid directory
# cd ${DATA}/grids;rsync 'zender@imua.ess.uci.edu:data/grids/msk_?is_r??.nc' .;ls -l msk_?is_r??.nc

# Part 1: Convert raw RACMO gridfiles to standardized gridfiles and derive SCRIP grids
# This part is slow and only needs be done when new grids are introduced so usually skip it
if false; then
    ~/racmo/racmo_raw2std.sh 
fi # !false

# 
unset sec_per_mth # [s] Seconds per month
declare -a sec_per_mth
sec_per_mth=(0 2678400 2419200 2678400 2592000 2678400 2592000 2678400 2678400 2592000 2678400 2592000 2678400) # noleap 365-day calendar, 1-based indexing

drc_in=/global/cfs/cdirs/fanssie/racmo/raw/RACMO2.4/FGRN055/mon_climos
drc_in=/global/cfs/cdirs/fanssie/racmo/raw/RACMO2.4/PXANT11/???_climos

#drc_root='/global/cfs/cdirs/fanssie' # Perlmutter
drc_root="${DATA}" # Spectral
drc_raw="${drc_root}/racmo/2.4.1/raw"
drc_ts="${drc_root}/racmo/2.4.1/ts"
yyyymm_srt_ais=196001
yyyymm_srt_gis=194501
#for fll_nm in `ls ${drc_raw}`; do
for fll_nm in `ls ${drc_raw}/smbgl_*` ; do # Full filename
    fl_in=$(basename ${fll_nm})
    # https://stackoverflow.com/questions/20348097/bash-extract-string-before-a-colon
    var_nm=${fl_in%%_*}
    # https://stackoverflow.com/questions/21077882/pattern-to-get-string-between-two-specific-words-characters-using-grep
    rgn_sng=${fl_in#*monthlyS_}
    rgn_sng=${rgn_sng%_RACMO2*}
    if [ "${rgn_sng}" = "PXANT11" ]; then
	ice_nm=ais
    elif [ "${rgn_sng}" = "FGRN055" ]; then
	ice_nm=ais
    else
	echo "${spt_nm}: ERROR Invalid \${rgn_sng} = ${rgn_sng}"
	exit 1
    fi # !rgn_sng

    echo "Processing variable ${var_nm} for region ${rgn_sng}..."
#    if false; then
    fl_in=smbgl_monthlyS_PXANT11_RACMO2.4.1_historical_196001_202312.nc
    fl_out=racmo2.4.1_${ice_nm}_${var_nm}_198001_202012.nc

    # Convert to netCDF3 (to avoid rename bugs), eliminate unwanted variables, select 1980--2020
    cmd_sbs="ncks -O -6 -C -d time,1980-01-01,2020-12-31 -x -v rlat,rlon,height ${drc_raw}/${fl_in} ${drc_ts}/${fl_out}"
    echo ${cmd_sbs}
    eval ${cmd_sbs}

    # Make lon,lat coordinates
    cmd_rnm="ncrename -O -d .rlon,lon -d .rlat,lat -a .grid_mapping,grid_mapping_renamed_for_Panoply_sanity ${drc_ts}/${fl_out}"
    echo ${cmd_rnm}
    eval ${cmd_rnm}

    # Eliminate missing_value
    cmd_att="ncatted -O -a missing_value,,d,, ${drc_ts}/${fl_out}"
    echo ${cmd_att}
    eval ${cmd_att}

    # Remove height dimension
    cmd_hgt="ncwa -O -a height ${drc_ts}/${fl_out} ${drc_ts}/${fl_out}"
    echo ${cmd_hgt}
    eval ${cmd_hgt}

    # Convert from monthly sum ("monthlyS") to per-second rate (PSR)
    cmd_flx="ncap2 -O -v --script="*var_nm=${var_nm}" -S ~/racmo/mthsum2flx.nco ${drc_ts}/${fl_out} ~/foo.nc" # works as of fxm
    echo ${cmd_flx}
    eval ${cmd_flx}
    # ncap2 -O -s '*foo=1' ${drc_ts}/${fl_out} ${drc_ts}/${fl_out}

    # if false; then
    #    fi # !false
done # !fll_nm
