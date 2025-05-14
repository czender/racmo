#!/usr/bin/env bash

# Purpose: Convert raw RACMO v2.4.1 data into LIVVKit input
# Prequisites: NCO

# Usage:
# ~/racmo/racmo.sh 
# ~/racmo/racmo.sh > ~/foo.txt 2>&1 & # Takes ~85m30s on Perlmutter login node

# Production:
# screen # Start screen
# ~/racmo/racmo.sh > ~/foo.txt 2>&1 &
# Ctl-A D # Detach screen
# tail ~/foo.txt # Monitor progress
# screen -ls # List screens
# screen -r <ID> # Re-attach screen

# Locations of final processed RACMO data:
# /global/cfs/cdirs/fanssie/racmo/2.4.1/clm

# Locations of Chloe's original raw RACMO data:
# /global/cfs/cdirs/fanssie/racmo/raw/RACMO2.4/FGRN055/mon_climos
# /global/cfs/cdirs/fanssie/racmo/raw/RACMO2.4/PXANT11/???_climos

spt_src="${BASH_SOURCE[0]}"
[[ -z "${spt_src}" ]] && spt_src="${0}" # Use ${0} when BASH_SOURCE is unavailable (e.g., dash)
while [ -h "${spt_src}" ]; do # Recursively resolve ${spt_src} until file is no longer a symlink
  drc_spt="$( cd -P "$( dirname "${spt_src}" )" && pwd )"
  spt_src="$(readlink "${spt_src}")"
  [[ ${spt_src} != /* ]] && spt_src="${drc_spt}/${spt_src}" # If ${spt_src} was relative symlink, resolve it relative to path where symlink file was located
done
cmd_ln="${spt_src} ${@}"
drc_spt="$( cd -P "$( dirname "${spt_src}" )" && pwd )"
spt_nm=$(basename ${spt_src}) # [sng] Script name (unlike $0, ${BASH_SOURCE[0]} works well with 'source <script>')

if [ "${LMOD_SYSTEM_NAME}" = 'perlmutter' ]; then
    drc_root='/global/cfs/cdirs/fanssie' # Perlmutter
elif [ "${HOSTNAME}" = 'spectral' ]; then
    drc_root="${DATA}" # Spectral
else
    echo "${spt_nm}: ERROR Invalid \${rgn_rsn} = ${rgn_rsn}"
    exit 1
fi # !HOSTNAME

# Human-readable summary
date_srt=$(date +"%s")
if [ ${vrb_lvl} -ge ${vrb_3} ]; then
    printf "RACMO raw data to timeseries invoked with command:\n"
    echo "${cmd_ln}"
fi # !vrb_lvl

# Set default values and paths
dbg_lvl=1
drc_raw="${drc_root}/racmo/2.4.1/raw"
drc_ts="${drc_root}/racmo/2.4.1/ts"
drc_clm="${drc_root}/racmo/2.4.1/clm"
yr_srt=1980
yr_end=2020

# Define variables
yyyy_srt=`printf "%04d" ${yr_srt}`
yyyy_end=`printf "%04d" ${yr_end}`
yyyymm_srt_end_out="${yyyy_srt}01_${yyyy_end}12" # 198001_202012

# Step 1: Clean up raw data and convert per-month sums into per-second rates where appropriate
[[ ${dbg_lvl} -ge 1 ]] && date_tm=$(date +"%s")
printf "Begin Step 1: Clean up raw data and, when necessary, convert per-month sums into per-second timeseries\n\n"
for fll_nm in `ls ${drc_raw}`; do # Loop over all fields
#for fll_nm in `ls ${drc_raw}/*monthlyA*`; do # Loop over monthlyA fields
#for fll_nm in `ls ${drc_raw}/smbgl_*` ; do # Debug loop over single field
#for fll_nm in `ls ${drc_raw}/gbot_*` ; do # Debug loop over single field
#for fll_nm in `` ; do # Skip loop
    fl_in=$(basename ${fll_nm})
    # https://stackoverflow.com/questions/20348097/bash-extract-string-before-a-colon
    var_nm=${fl_in%%_*}
    # https://stackoverflow.com/questions/21077882/pattern-to-get-string-between-two-specific-words-characters-using-grep
    rgn_rsn=${fl_in#*monthly?_}
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
    # Is field stored as monthly sums ("monthlyS") or averages ("monthlyA")?
    flg_mth_sum=false
    flg_mth_avg=false
    if [[ "${fl_in}" == *'monthlyS'* ]]; then flg_mth_sum=true; fi
    if [[ "${fl_in}" == *'monthlyA'* ]]; then flg_mth_avg=true; fi
    if ${flg_mth_sum}; then mth_sng='monthlyS'; else mth_sng='monthlyA'; fi
    
    # Exclude variables with weird dimensions, etc.
    if [ ${var_nm} = 'gbot' ]; then
	# gbot has two time dimensions (!)
	printf "Excluding variable ${var_nm} which has two time dimensions\n\n"
	continue
    fi # !var_nm

    echo "Processing variable ${var_nm} for region/resolution ${rgn_rsn}..."
    fl_in=${var_nm}_${mth_sng}_${rgn_rsn}_RACMO2.4.1_historical_${yyyymm_srt_end_in}.nc
    fl_out=${var_nm}_${ice_nm}_${yyyymm_srt_end_out}.nc

    # Convert to netCDF3 (to avoid rename bugs), eliminate unwanted variables, select 1980--2020
    cmd_sbs="ncks -O -6 -C --hdr_pad=10000 -d time,${yr_srt}-01-01,${yr_end}-12-31 -x -v rlat,rlon,height ${drc_raw}/${fl_in} ${drc_ts}/${fl_out}"
    echo ${cmd_sbs}
    eval ${cmd_sbs}

    # Make lon,lat coordinates, ensure Panoply can plot output
    cmd_rnm="ncrename -O -d .rlon,lon -d .rlat,lat -a .grid_mapping,grid_mapping_renamed_for_Panoply_sanity ${drc_ts}/${fl_out}"
    echo ${cmd_rnm}
    eval ${cmd_rnm}

    if ${flg_mth_sum}; then
	# Convert field from monthly sum ("monthlyS") to monthly mean rate (aka, per-second rate (PSR))
	cmd_flx="ncap2 -O -S ~/racmo/mthsum2flx.nco ${drc_ts}/${fl_out} ${drc_ts}/${fl_out}" # works as of 20250310
	echo ${cmd_flx}
	eval ${cmd_flx}
    fi # !flg_mth_sum

    # Eliminate missing_value attribute, add standard names
    cmd_att="ncatted -O -a missing_value,,d,, -a standard_name,lon,o,c,longitude -a standard_name,lat,o,c,latitude -a standard_name,time,o,c,time -a axis,time,o,c,T ${drc_ts}/${fl_out}"
    echo ${cmd_att}
    eval ${cmd_att}

    # Remove height dimension (fxm: if it exists), though do not add a cell_methods attribute about it
    cmd_hgt="ncwa -O --no_cll_mth -a height ${drc_ts}/${fl_out} ${drc_ts}/${fl_out}"
    echo ${cmd_hgt}
    eval ${cmd_hgt}

    # Print space for tidy output
    echo ""
done # !fll_nm

if [ ${dbg_lvl} -ge 1 ]; then
    date_crr=$(date +"%s")
    date_dff=$((date_crr-date_tm))
    printf "Elapsed time to clean raw data and process monthly timeseries $((date_dff/60))m$((date_dff % 60))s\n\n"
fi # !dbg

# Step 2: Convert per-variable timeseries files to climos
[[ ${dbg_lvl} -ge 1 ]] && date_clm=$(date +"%s")
printf "Begin Step 2: Convert per-variable timeseries files to climos\n\n"
for fll_nm in `ls ${drc_ts}`; do # Loop over all fields
#for fll_nm in `ls ${drc_ts}/tas*` `ls ${drc_ts}/tsgl*` `ls ${drc_ts}/u10*` `ls ${drc_ts}/v10*` ; do # Loop over monthlyA fields
#for fll_nm in `ls ${drc_ts}/smbgl_*` ; do # Debug loop over single field
#for fll_nm in `ls ${drc_ts}/gbot_*` ; do # Debug loop over single field
    fl_in=$(basename ${fll_nm})
    # https://stackoverflow.com/questions/20348097/bash-extract-string-before-a-colon
    var_nm=${fl_in%%_*}
    drc_var=${drc_clm}/${var_nm}
    ice_nm=${fl_in#*${var_nm}_}
    ice_nm=${ice_nm%_${yyyymm_srt_end_out}*}
    caseid=${var_nm}_${ice_nm}
    
    # Create directory to store monthly and climo files
    if [ -n "${drc_var}" ] && [ ! -d "${drc_var}" ]; then 
	cmd_mkd="mkdir -p ${drc_var}"
	eval ${cmd_mkd}
	if [ "$?" -ne 0 ]; then
	    printf "${spt_nm}: ERROR Attempt to create output climo directory. Debug this:\n${cmd_mkd}\n"
	    printf "${spt_nm}: HINT Creating a directory requires proper write permissions\n"
	    exit 1
	fi # !err
    fi # !drc_var

    printf "Decatenating variable ${var_nm} timeseries for ${ice_nm} into ${drc_var}\n"
    let tm_idx=0
    for yr in `seq ${yyyy_srt} ${yyyy_end}`; do
	YYYY=`printf "%04d" ${yr}`
	for mth in {1..12}; do
	    MM=`printf "%02d" ${mth}`
	    fl_out[${tm_idx}]="${caseid}_${YYYY}${MM}.nc"
	    #printf "Decatenating variable ${var_nm} timeseries for ${ice_nm} into ${fl_out[${tm_idx}]}\n"

	    # Extract current month info 
	    cmd_sbs="ncks -O -d time,${tm_idx} ${drc_ts}/${fl_in} ${drc_var}/${fl_out[${tm_idx}]}"
	    echo ${cmd_sbs}
	    eval ${cmd_sbs}

	    let tm_idx=$((tm_idx + 1))
	done # !mth
    done # !yr

    # Create climos    
    cmd_clm="ncclimo -c ${caseid}_${yyyy_srt}01.nc -s ${yyyy_srt} -e ${yyyy_end} -i ${drc_var} -o ${drc_var}"
    printf "\nCreating ${var_nm} climatology with ${cmd_clm}\n"
    echo ${cmd_clm}
    eval ${cmd_clm}

    # Remove monthly files to save space
    cmd_cln="/bin/rm ${drc_var}/${caseid}_??????.nc"
    printf "\nCleaning ${var_nm} climatology with ${cmd_cln}\n"
    echo ${cmd_cln}
    eval ${cmd_cln}
    
done # !fll_nm

if [ ${dbg_lvl} -ge 1 ]; then
    date_crr=$(date +"%s")
    date_dff=$((date_crr-date_clm))
    printf "Elapsed time to convert monthly timeseries to climos $((date_dff/60))m$((date_dff % 60))s\n\n"
fi # !dbg

date_end=$(date +"%s")
printf "Completed RACMO reformatting and climatology operations for input data at `date`\n"
date_dff=$((date_end-date_srt))
echo "Elapsed time $((date_dff/60))m$((date_dff % 60))s"
