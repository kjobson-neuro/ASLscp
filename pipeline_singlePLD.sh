#!/bin/bash

## script created by Manuel Taso
## script edited, added to and uploaded to FW by krj

##
### Minimal ASL Pre-processing and CBF Calculation
##

# Load config or inputs manually
CmdName=$(basename "$0")
Syntax="${CmdName} [-c config][-a ASLZip][-m M0Zip][-s SubjectID][-v][-n][-l]"
function sys {
    [ -n "${opt_n}${opt_v}" ] && echo "$@" 1>&2
    [ -n "$opt_n" ] || "$@"
}

while getopts a:c:i:m:s:nvl arg
do
    case "$arg" in
        a|c|m|n|s|v)
                  eval "opt_${arg}='${OPTARG:=1}'" ;;
    esac
done
shift $(( $OPTIND - 1))

# Check if there is a config
# If so, load info from config,
# If not, load data manually
if [ -n "$opt_c" ]
then
	ConfigJsonFile="$opt_c"
else
	ConfigJsonFile="${FLYWHEEL:=.}/config.json"
fi

if [ -n "$opt_a" ]; then
	asl_zip="$opt_a"
else
	asl_zip=$( jq '.inputs.dicom_asl.location.path' "$ConfigJsonFile" | tr -d '"' )
fi

if [ -n "$opt_m" ]; then
        m0_zip="$opt_m"
else
        m0_zip=$( jq '.inputs.dicom_m0.location.path' "$ConfigJsonFile" | tr -d '"' )
fi
if [ -n "$opt_s" ]; then
       SUBJECT_LABEL="$opt_s" 
else
       SUBJECT_LABEL=$( jq -r '.config.subject_label // empty' "$ConfigJsonFile" )
fi

# Set file paths
flywheel="/flywheel/v0"
[ -e "$flywheel" ] || mkdir "$flywheel"

data_dir="${flywheel}/input"
[ -e "$data_dir" ] || mkdir "$data_dir"

export_dir="${flywheel}/output"
[ -e "$export_dir" ] || mkdir "$export_dir"

std="${data_dir}/std"
[ -e "$std" ] || mkdir "$std"

viz="${export_dir}/viz"
[ -e "$viz" ] || mkdir "$viz"

workdir="${flywheel}/work"
[ -e "$workdir" ] || mkdir "$workdir"

m0_dcmdir="${workdir}/m0_dcmdir"
[ -e "$m0_dcmdir" ] || mkdir "$m0_dcmdir"

asl_dcmdir="${workdir}/asl_dcmdir"
[ -e "$asl_dcmdir" ] || mkdir "$asl_dcmdir"

stats="${export_dir}/stats"
[ -e "$stats" ] || mkdir "$stats"

### Get information about the scan
INFO_OUT=${workdir}/metadata.txt

# --- Pull container IDs from the gear runtime config ---
SUB_ID=$(jq -r '.inputs|to_entries[]?|.value.hierarchy|select(.type=="subject")|.id' "$ConfigJsonFile" | head -n1)
SES_ID=$(jq -r '.inputs|to_entries[]?|.value.hierarchy|select(.type=="session")|.id' "$ConfigJsonFile" | head -n1)
ACQ_ID=$(jq -r '.inputs|to_entries[]?|.value.hierarchy|select(.type=="acquisition")|.id' "$ConfigJsonFile" | head -n1)

# --- Gear identity/version and run time ---
GEAR_NAME=$(jq -r '.gear.name // empty' "$ConfigJsonFile")
GEAR_VERSION=$(jq -r '.gear.version // empty' "$ConfigJsonFile")
if [[ -z "$GEAR_VERSION" && -f "$MAN" ]]; then
  GEAR_VERSION=$(jq -r '.version // empty' "$MAN" || true)
fi
RUN_TIME_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- Resolve labels & scan date with fwget (no direct API) ---
SUB_LABEL=""; SES_LABEL=""; ACQ_LABEL=""; SCAN_DATE=""
if command -v fwget >/dev/null 2>&1; then
  if [[ -n "${SUB_ID:-}" ]]; then
    SUB_JSON=$(mktemp)
    fwget -l "$SUB_ID" > "$SUB_JSON" || true
    SUB_LABEL=$(jq -r '.label // .code // empty' "$SUB_JSON" || true)
  fi

  if [[ -n "${SES_ID:-}" ]]; then
    SES_JSON=$(mktemp)
    fwget -l "$SES_ID" > "$SES_JSON" || true
    SES_LABEL=$(jq -r '.label // empty' "$SES_JSON" || true)
    # Session timestamp is generally the exam/scan datetime
    SCAN_DATE=$(jq -r '.timestamp // empty' "$SES_JSON" || true)
  fi

  if [[ -z "$SCAN_DATE" && -n "${ACQ_ID:-}" ]]; then
    ACQ_JSON=$(mktemp)
    fwget -l "$ACQ_ID" > "$ACQ_JSON" || true
    ACQ_LABEL=$(jq -r '.label // empty' "$ACQ_JSON" || true)
    SCAN_DATE=$(jq -r '.timestamp // empty' "$ACQ_JSON" || true)
  fi
fi

# --- Write provenance file ---
{
  echo "=== Gear provenance ==="
  echo "Gear: ${GEAR_NAME:-unknown}"
  echo "Gear Version: ${GEAR_VERSION:-unknown}"
  echo "Gear Run (UTC): $RUN_TIME_UTC"
  echo "=== Subject / Session / Acquisition ==="
  echo "Subject: ${SUB_LABEL:-}(id=${SUB_ID:-unknown})"
  [[ -n "${SES_ID:-}" ]] && echo "Session: ${SES_LABEL:-}(id=${SES_ID:-})"
  [[ -n "${ACQ_ID:-}" ]] && echo "Acquisition: ${ACQ_LABEL:-}(id=${ACQ_ID:-})"
  echo "Scan Date: ${SCAN_DATE:-unknown}"
  echo
} > "$INFO_OUT"

# Optional: append full fwget dumps (handy for debugging/audit)
if command -v fwget >/dev/null 2>&1; then
  {
    [[ -n "${SUB_ID:-}" ]] && { echo "=== fwget -l ${SUB_ID} ==="; fwget -l "$SUB_ID" || true; echo; }
    [[ -n "${SES_ID:-}" ]] && { echo "=== fwget -l ${SES_ID} ==="; fwget -l "$SES_ID" || true; echo; }
    [[ -n "${ACQ_ID:-}" ]] && { echo "=== fwget -l ${ACQ_ID} ==="; fwget -l "$ACQ_ID" || true; echo; }
  } >> "$INFO_OUT"
fi

echo "Wrote $INFO_OUT"

### Data Preprocessing
# Check if the data is a zip file
# Unzip if so

if file "$asl_zip" | grep -q 'Zip archive data'; then
	unzip -d "$asl_dcmdir" "$asl_zip"  
	dcm2niix -f %d -b y -o ${asl_dcmdir}/ "$asl_dcmdir"
else
	cp -r "$asl_zip" ${asl_dcmdir}/
	dcm2niix -f %d -b y -o ${asl_dcmdir}/ "$asl_zip"
fi

if file "$m0_zip" | grep -q 'Zip archive data'; then
	unzip -d "$m0_dcmdir" "$m0_zip"
	dcm2niix -f %d -b y -o ${m0_dcmdir}/ "$m0_dcmdir"
else
	cp -r "$m0_zip" ${m0_dcmdir}/
	dcm2niix -f %d -b y -o ${m0_dcmdir}/ "$m0_zip"
fi

# Dcm2niix doesn't always work first try, so check and redo if files aren't present

attempt=1
max_attempt=2

# Loop until both files are found or max attempts are reached
while (( attempt <= max_attempt )); do
    echo "Attempt $attempt of $max_attempts..."

    # Use find to locate the files
    asl_file=$(find "$asl_dcmdir" -maxdepth 1 -type f -name "*ASL.nii")
    m0_file=$(find "$m0_dcmdir" -maxdepth 1 -type f -name "*M0.nii")

    # Debugging output
    echo "ASL file: $asl_file"
    echo "M0 file: $m0_file"

    if [[ -n "$asl_file" && -n "$m0_file" ]]; then
        echo "Both files found: $asl_file and $m0_file"
        break  # Exit the loop
    else
        if (( attempt < max_attempt )); then
            echo "Files missing. Retrying..."
            for dir_name in ${asl_zip} ${m0_zip}
                do
                dcm2niix -f %d -b y -o ${workdir}/ ${dir_name}/
            done

        else
            echo "Files still missing after $max_attempts attempts. Exiting."
            exit 1  # Exit with error code
        fi
    fi
    (( attempt++ ))
    sleep 5  # Optional: Wait a few seconds before retrying
done

# Extract dicom header info to get parameters for cbf calculation
dcm_file=$(find "${m0_dcmdir}" -type f -name "*.dcm" | head -n 1)

# If the dicoms are not there or cannot be found, exit
if [ -z "$dcm_file" ]; then
	echo "No dicom file!"
	exit 1
fi

ld=$(iconv -f UTF-8 -t UTF-8//IGNORE "$dcm_file" | awk -F 'sWipMemBlock.alFree\\[0\\][[:space:]]*=[[:space:]]*' '{print $2}' | tr -d '[:space:]')
echo "ld: ${ld}"
pld=$(iconv -f UTF-8 -t UTF-8//IGNORE "$dcm_file" | awk -F 'sWipMemBlock.alFree\\[1\\][[:space:]]*=[[:space:]]*' '{print $2}' | tr -d '[:space:]')
echo "pld: ${pld}"
nbs=$(iconv -f UTF-8 -t UTF-8//IGNORE "$dcm_file" | awk -F 'sWipMemBlock.alFree\\[11\][[:space:]]*=[[:space:]]*' '{print $2}' | tr -d '[:space:]')
echo "nbs: ${nbs}"
m0_scale=$(iconv -f UTF-8 -t UTF-8//IGNORE "$dcm_file" | awk -F 'sWipMemBlock.alFree\\[20\][[:space:]]*=[[:space:]]*' '{print $2}' | tr -d '[:space:]')
echo "m0_scale: ${m0_scale}"

if [[ -z "$ld" || -z "$pld" || -z "$nbs" || -z "$m0_scale" ]]; then
    echo "Error: One or more required variables are unset or empty."
    exit 1
fi

# Merge Data
fslmerge -t ${workdir}/all_data.nii.gz $m0_file $asl_file

# Motion correction
mcflirt -in ${workdir}/all_data.nii.gz -out ${workdir}/mc.nii.gz

# Split the data back up after motion correction
fslroi ${workdir}/mc.nii.gz ${workdir}/m0_mc.nii.gz 0 1
fslroi ${workdir}/mc.nii.gz ${workdir}/m0_ir_mc.nii.gz 0 2
fslroi ${workdir}/mc.nii.gz ${workdir}/asl_mc.nii.gz 2 -1

# Skull-Stripping
${FREESURFER_HOME}/bin/mri_synthstrip -i ${workdir}/m0_mc.nii.gz -m ${workdir}/mask.nii.gz

# Erode mask and use on CBF map
fslmaths ${workdir}/mask.nii.gz -ero ${workdir}/mask_ero.nii.gz

# Merge all data then motion correction by running mcflirt
# If statment to check for nbs of 3 - this is from old data, should not come up for any protocol 2023 and on
if [ "$nbs" == 3 ]; then
    asl_file --data=${workdir}/asl_mc.nii.gz --ntis=1 --iaf=ct --diff --out=${workdir}/sub.nii.gz
    echo "nbs is 3, switching label and control"
else
    asl_file --data=${workdir}/asl_mc.nii.gz --ntis=1 --iaf=tc --diff --out=${workdir}/sub.nii.gz
    echo "nbs is greater than 3, no changes made to pipeline"
fi

fslmaths ${workdir}/sub.nii.gz -Tmean ${workdir}/sub_av.nii.gz

### Calculate CBF
python3 /flywheel/v0/workflows/cbf_calc.py -m0 ${workdir}/m0_mc.nii.gz -asl ${workdir}/sub_av.nii.gz -m ${workdir}/mask.nii.gz -ld $ld -pld $pld -nbs $nbs -scale $m0_scale -out ${workdir}
fslmaths ${workdir}/cbf.nii.gz -mas ${workdir}/mask_ero.nii.gz ${workdir}/cbf_mas.nii.gz

# Check what number is in the file name
sidecar_json="${asl_file%.nii*}.json"      # works for .nii and .nii.gz
qt1_capable=false                          # pessimistic default

if [[ -f "$sidecar_json" ]]; then
    while IFS= read -r s; do
        # Rule 1 – exact Upenn research sequence
        if [[ $s =~ %CustomerSeq%\\upenn_spiral_pcasl ]]; then
            qt1_capable=true; break
        fi
        # Rule 2 – GE spiral Vnn (nn ≥ 23) *without* _Hwem
        if [[ $s =~ %CustomerSeq%\\SPIRAL_V([0-9]{2})_GE ]]; then
            ver=${BASH_REMATCH[1]}
            (( 10#$ver >= 23 )) && [[ ! $s =~ _Hwem ]] && { qt1_capable=true; break; }
        fi
    done < <(jq -r '.. | strings' "$sidecar_json")
else
    echo "Warning: side‑car JSON not found – falling back to filename test."
fi

# If the version is 22 or lower, we cannot generate T1 and we will skip
if [ "$qt1_capable" = true ]; then
    echo "Version is greater than 22. Generating quantitative T1."
# Fit T1 with function z. Skip this step for the recover project bc t1 data is messed up.
    python3 /flywheel/v0/workflows/t1fit.py -m0_ir ${workdir}/m0_ir_mc.nii.gz -m ${workdir}/mask.nii.gz -out ${workdir} -stats ${stats}
else
    echo "Version is 22 or lower. Cannot generate quantitative T1."
fi

# Smoothing ASL image subject space, deforming images to match template
fslmaths ${workdir}/sub_av.nii.gz -s 1.5 -mas ${workdir}/mask.nii.gz ${workdir}/s_asl.nii.gz 
${ANTSPATH}/antsRegistration --dimensionality 3 --transform "Affine[0.25]" --metric "MI[${std}/batsasl/bats_asl_masked.nii.gz,${workdir}/s_asl.nii.gz,1,32]" --convergence 100x20 --shrink-factors 4x1 --smoothing-sigmas 2x0mm --transform "SyN[0.1]" --metric "CC[${std}/batsasl/bats_asl_masked.nii.gz,${workdir}/s_asl.nii.gz,1,1]" --convergence 40x20 --shrink-factors 2x1 --smoothing-sigmas 2x0mm  --output "[${workdir}/ind2temp,${workdir}/ind2temp_warped.nii.gz,${workdir}/temp2ind_warped.nii.gz]" --collapse-output-transforms 1 --interpolation BSpline -v 1
echo "ANTs Registration finished"

# Warping atlases, deforming ROI
# Standardize CBF images to a common template
# Removed --use-BSpline flag because we do not want to deform the ROIs
${ANTSPATH}/WarpImageMultiTransform 3 ${std}/batsasl/bats_cbf.nii.gz ${workdir}/w_batscbf.nii.gz -R ${workdir}/sub_av.nii.gz -i ${workdir}/ind2temp0GenericAffine.mat ${workdir}/ind2temp1InverseWarp.nii.gz
list=("arterial2" "cortical" "subcortical" "thalamus" "landau") ##list of ROIs

# Eroding some ROIs so that they are not touching the edges of the CBF map and not including incorrect CBF values
# deforming ROI
for str in "${list[@]}"
do
  echo ${str}
  touch ${stats}/tmp_${str}.txt
  touch ${stats}/cbf_${str}.txt
  touch ${stats}/${str}_vox.txt
  echo "Printed ${stats}"
  ${ANTSPATH}/WarpImageMultiTransform 3 ${std}/${str}.nii.gz ${workdir}/w_${str}.nii.gz -R ${workdir}/sub_av.nii.gz --use-NN -i ${workdir}/ind2temp0GenericAffine.mat ${workdir}/ind2temp1InverseWarp.nii.gz
  fslmaths ${workdir}/w_${str}.nii.gz -mas ${workdir}/mask_ero.nii.gz ${workdir}/w_${str}_mas.nii.gz
  fslstats -K ${workdir}/w_${str}_mas.nii.gz ${workdir}/cbf_mas.nii.gz -M -S > ${stats}/tmp_${str}.txt
  fslstats -K ${workdir}/w_${str}_mas.nii.gz ${workdir}/cbf_mas.nii.gz -V > ${stats}/${str}_vox.txt
  paste ${std}/${str}_label.txt -d ' ' ${stats}/tmp_${str}.txt ${stats}/${str}_vox.txt > ${stats}/cbf_${str}.txt #combine label with values
done

# Original main processing loop with missing label filter
for str in "${list[@]}"
do
  input_cbf="${stats}/cbf_${str}.txt"
  output_cbf="${stats}/formatted_cbf_${str}.txt"
  temp_dir="/flywheel/v0/work/temp_$(date +%s)"
  mkdir -p "$temp_dir"

  # Create temporary file with updated header
  temp_file="$temp_dir/tmp_cbf_${str}.txt"
  echo "Region | Mean CBF | Standard Deviation | Voxels | Volume" > "$temp_file"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue  # Skip empty lines

    # Extract numeric values
    mean_cbf=$(echo "$line" | awk '{print $(NF-3)}')
    std_dev=$(echo "$line" | awk '{print $(NF-2)}')
    voxels=$(echo "$line" | awk '{print $(NF-1)}')
    volume=$(echo "$line" | awk '{print $NF}')

    # Extract region name
    region=$(echo "$line" | awk '{
      for (i=1; i<=NF-4; i++)
        printf "%s ", $i;
    }' | sed 's/[[:space:]]$//')

    # Skip lines with 'missing label' or bad entries
    [[ -z "$region" || "$region" == "0" || "$region" == *"missing label"* || "$voxels" < "10" ]] && continue

    # Format numeric values
    formatted_mean=$(printf "%.1f" "$mean_cbf")
    formatted_std=$(printf "%.1f" "$std_dev")
    formatted_voxels=$(printf "%.1f" "$voxels")
    formatted_volume=$(printf "%.1f" "$volume")

    echo "$region | $formatted_mean | $formatted_std | $formatted_voxels | $formatted_volume" >> "$temp_file"
  done < "$input_cbf"

  # Format final output
  column -t -s '|' -o '|' "$temp_file" > "$output_cbf"
  rm -rf "$temp_dir"
done

# Extract these regions to display as a general "AD" check
target_regions=(
  "Left_Hippocampus"
  "Right_Hippocampus"
  "Left_Putamen"
  "Right_Putamen"
  "Cingulate_Gyrus,_posterior_division"
  "Precuneous_Cortex"
 # "Landau_metaROI"  # Added Landau region
)

extracted_file="${stats}/extracted_regions_combined.txt"
echo "Region | Mean CBF | Standard Deviation | Voxels | Volume" > "$extracted_file"

# Process only the three specified formatted files
for type in cortical subcortical landau; do
  source_file="${stats}/formatted_cbf_${type}.txt"

  [[ -f "$source_file" ]] || continue

  while IFS= read -r line; do
    # Skip header line and empty lines
    [[ "$line" == "Region |"* ]] || [[ -z "$line" ]] && continue

    region=$(echo "$line" | awk -F '|' '{print $1}' | xargs)

    for target in "${target_regions[@]}"; do
      if [[ "$region" == "$target" ]]; then
        echo "$line" >> "$extracted_file"
      fi
    done
  done < "$source_file"
done

# Calculate a weighted rCBF value
cortical="${stats}/formatted_cbf_cortical.txt"
subcortical="${stats}/formatted_cbf_subcortical.txt"
landau="${stats}/formatted_cbf_landau.txt"

pcc=$(grep "Cingulate_Gyrus,_posterior_division" "$cortical" | awk -F '|' '{print $2}' | xargs)
pcc_voxel=$(grep "Cingulate_Gyrus,_posterior_division" "$cortical" | awk -F '|' '{print $5}' | xargs)
precuneus=$(grep "Precuneous_Cortex" "$cortical" | awk -F '|' '{print $2}' | xargs)
precuneus_voxel=$(grep "Precuneous_Cortex" "$cortical" | awk -F '|' '{print $5}' | xargs)
hipp_left=$(grep "Left_Hippocampus" "$subcortical" | awk -F '|' '{print $2}' | xargs)
hipp_left_voxel=$(grep "Left_Hippocampus" "$subcortical" | awk -F '|' '{print $5}' | xargs)
hipp_right=$(grep "Right_Hippocampus" "$subcortical" | awk -F '|' '{print $2}' | xargs)
hipp_right_voxel=$(grep "Right_Hippocampus" "$subcortical" | awk -F '|' '{print $5}' | xargs)
grey_left=$(grep "Left_Cerebral_Cortex" "$subcortical" | awk -F '|' '{print $2}' | xargs)
grey_left_vox=$(grep "Left_Cerebral_Cortex" "$subcortical" | awk -F '|' '{print $5}' | xargs)
grey_right=$(grep "Right_Cerebral_Cortex" "$subcortical" | awk -F '|' '{print $2}' | xargs)
grey_right_vox=$(grep "Right_Cerebral_Cortex" "$subcortical" | awk -F '|' '{print $5}' | xargs)
white_left=$(grep "Left_Cerebral_White_Matter" "$subcortical" | awk -F '|' '{print $2}' | xargs)
white_left_vox=$(grep "Left_Cerebral_White_Matter" "$subcortical" | awk -F '|' '{print $5}' | xargs)
white_right=$(grep "Right_Cerebral_White_Matter" "$subcortical" | awk -F '|' '{print $2}' | xargs)
white_right_vox=$(grep "Right_Cerebral_White_Matter" "$subcortical" | awk -F '|' '{print $5}' | xargs)
putamen_left=$(grep "Left_Putamen" "$subcortical" | awk -F '|' '{print $2}' | xargs)
putamen_left_vox=$(grep "Left_Putamen" "$subcortical" | awk -F '|' '{print $5}' | xargs)
putamen_right=$(grep "Right_Putamen" "$subcortical" | awk -F '|' '{print $2}' | xargs)
putamen_right_vox=$(grep "Right_Putamen" "$subcortical" | awk -F '|' '{print $5}' | xargs)
landau_meta=$(grep "Landau_metaROI" "$landau" | awk -F '|' '{print $2}' | xargs)
landau_meta_vox=$(grep "Landau_metaROI" "$landau" | awk -F '|' '{print $5}' | xargs)

# Left and right grey matter
grey_matter_weighted=$(echo "scale=4; ($grey_left * $grey_left_vox + $grey_right * $grey_right_vox) / ($grey_left_vox + $grey_right_vox)" | bc -l)

# Left and right white matter
white_matter_weighted=$(echo "scale=4; ($white_left * $white_left_vox + $white_right * $white_right_vox) / ($white_left_vox + $white_right_vox)" | bc -l)

# Whole brain
whole_brain_weighted=$(echo "scale=4; ($grey_left * $grey_left_vox + $grey_right * $grey_right_vox + $white_left * $white_left_vox + $white_right * $white_right_vox) / ($grey_left_vox + $grey_right_vox + $white_left_vox + $white_right_vox)" | bc -l)
echo $whole_brain_weighted
# Left and right putamen
putamen_weighted=$(echo "scale=4; ($putamen_left * $putamen_left_vox + $putamen_right * $putamen_right_vox) / ($putamen_left_vox + $putamen_right_vox)" | bc -l)

# PCC+Precuneus calculation
pcc_precuneus_weighted=$(echo "scale=4; ($pcc * $pcc_voxel + $precuneus * $precuneus_voxel) / ($pcc_voxel + $precuneus_voxel)" | bc -l)

# Hippocampus calculation
hippocampus_weighted=$(echo "scale=4; ($hipp_left * $hipp_left_voxel + $hipp_right * $hipp_right_voxel) / ($hipp_left_voxel + $hipp_right_voxel)" | bc -l)

# Clear or create the output file
weighted_rcbf="${stats}/weighted_rcbf.txt"
: > $weighted_rcbf

# Overwrite or create the weighted_rCBF file in the same format as formatted_cbf_*.txt
echo "Region | CBF | Voxels" > $weighted_rcbf

# Whole brain
if [[ -n "$whole_brain_weighted" && "$whole_brain_weighted" =~ ^[0-9.]+$ ]]; then
   whole_brain_vox=$(echo "scale=4; ($grey_left_vox + $grey_right_vox + $white_left_vox + $white_right_vox)" | bc -l)
   echo "Whole brain | $whole_brain_weighted | $whole_brain_vox" >> $weighted_rcbf
else
   echo "Whole brain CBF value is not a number"
fi

# Grey Matter
if [[ -n "$grey_matter_weighted" && "$grey_matter_weighted" =~ ^[0-9.]+$ ]]; then
    grey_matter_vox=$(echo "$grey_right_vox + $grey_left_vox" | bc -l)
    echo "Grey_Matter L+R | $grey_matter_weighted | $grey_matter_vox" >> $weighted_rcbf
else
    echo "Grey_Matter_L+R value is not a number"
fi

# White Matter
if [[ -n "$white_matter_weighted" && "$white_matter_weighted" =~ ^[0-9.]+$ ]]; then
    white_matter_vox=$(echo "$white_right_vox + $white_right_vox" | bc -l)
    echo "White_Matter L+R | $white_matter_weighted | $white_matter_vox" >> $weighted_rcbf
else
    echo "White_Matter_L+R value is not a number"
fi

# PCC+Precuneus row
if [[ -n "$pcc_precuneus_weighted" && "$pcc_precuneus_weighted" =~ ^[0-9.]+$ ]]; then
   pcc_precuneus_vox=$(echo "$pcc_voxel + $precuneus_voxel" | bc -l)
   echo "PCC+Precuneus | $pcc_precuneus_weighted | $pcc_precuneus_vox" >> $weighted_rcbf
else
    echo "PCC+Precuneus value is not a number"
fi

# Hippocampus row
if [[ -n "$hippocampus_weighted" && "$hippocampus_weighted" =~ ^[0-9.]+$ ]]; then
    hipp_vox=$(echo "$hipp_right_voxel + $hipp_left_voxel" | bc -l)
    echo "Hippocampus L+R | $hippocampus_weighted | $hipp_vox" >> $weighted_rcbf
else
    echo "Hippocampus_L+R value is not a number"
fi

#Landau Meta ROI row
if [[ -n "$landau_meta" && "$landau_meta_vox" =~ ^[0-9.]+$ ]]; then
    echo "Landau Meta ROI | $landau_meta | $landau_meta_vox" >> $weighted_rcbf
else
    echo "Landau Meta ROI value is not a number"
fi

cat $weighted_rcbf

# Calculate reference CBF values
wholebrain_cbf=$(sed -n 's/[^0-9]*\([0-9]\+\).*/\1/p; q' ${stats}/cbf_wholebrain.txt)

# Add ratio columns to extracted file
temp_file="${stats}/temp_ratio_calc.txt"
awk -F '|' -v put_cbf="$putamen_weighted" '
BEGIN {
    OFS = " | "
    print "Region | Mean | rCBF | Voxels"
}
{
    # Skip empty lines
    if (NF < 3 || $0 ~ /^Region/) next
    
    # Convert to numbers (handles any whitespace)
    mean = $2 + 0
    voxels = $3 + 0
    
    # Calculate rCBF putamen ratio
    rCBF = (mean != 0) ? mean / put_cbf : "NA"
    
    printf "%s | %.0f | %.1f | %.0f\n", \
        $1, mean, rCBF, voxels
}' "$weighted_rcbf" | column -t -s '|' -o '|' > "$temp_file"

weighted_table="${stats}/weighted_table.txt"
mv "$temp_file" "$weighted_table"

# Smoothing the deformation field of images obtained previously
fslmaths ${workdir}/ind2temp1Warp.nii.gz -s 5 ${workdir}/swarp.nii.gz
${ANTSPATH}/WarpImageMultiTransform 3 ${workdir}/sub_av.nii.gz ${workdir}/s_ind2temp_warped.nii.gz -R ${workdir}/ind2temp_warped.nii.gz --use-BSpline ${workdir}/swarp.nii.gz ${workdir}/ind2temp0GenericAffine.mat
${ANTSPATH}/WarpImageMultiTransform 3 ${workdir}/cbf.nii.gz ${workdir}/wcbf.nii.gz -R ${workdir}/ind2temp_warped.nii.gz --use-BSpline ${workdir}/swarp.nii.gz ${workdir}/ind2temp0GenericAffine.mat
#wt1: t1 relaxation time. common space. 

### tSNR calculation
fslmaths ${workdir}/sub.nii.gz -Tmean ${workdir}/sub_mean.nii.gz
fslmaths ${workdir}/sub.nii.gz -Tstd ${workdir}/sub_std.nii.gz
fslmaths ${workdir}/sub_mean.nii.gz -div ${workdir}/sub_std.nii.gz ${workdir}/tSNR_map.nii.gz

# New list of ROIs as we do not want to include the thalamus in the PDF output
new_list=("arterial2" "cortical" "subcortical") ##list of ROIs - "landau" removed

# Smoothing for viz
## Upsampling to 1mm and then smoothing to 2 voxels for nicer viz
flirt -in ${workdir}/cbf.nii.gz -ref ${workdir}/cbf.nii.gz -applyisoxfm 1.0 -nosearch -out ${workdir}/cbf_1mm.nii.gz -interp spline
flirt -in ${workdir}/mask.nii.gz -ref ${workdir}/mask.nii.gz -applyisoxfm 1.0 -nosearch -out ${workdir}/mask_1mm.nii.gz
fslmaths ${workdir}/cbf_1mm.nii.gz -s 2 ${workdir}/s_cbf_1mm.nii.gz
 
### Visualizations
# Check if vnumber is numeric, default to 0 or exit if not
if [ "$qt1_capable" = true ]; then
    echo "Version is greater than 22. Generating viz with quantitative T1."
    ${ANTSPATH}/WarpImageMultiTransform 3 ${workdir}/t1.nii.gz ${workdir}/wt1.nii.gz -R ${workdir}/ind2temp_warped.nii.gz --use-BSpline ${workdir}/swarp.nii.gz ${workdir}/ind2temp0GenericAffine.mat
    python3 /flywheel/v0/workflows/viz.py -cbf ${workdir}/s_cbf_1mm.nii.gz -t1 ${workdir}/t1.nii.gz -out ${viz}/ -seg_folder ${workdir}/ -seg ${new_list[@]} -mask ${workdir}/mask_1mm.nii.gz
### Create HTML file and output data into it for easy viewing
    python3 /flywheel/v0/workflows/pdf.py -viz ${viz} -stats ${stats}/ -out ${workdir}/ -seg_folder ${workdir}/ -seg ${new_list[@]}
else
    echo "Version is 22 or lower. Cannot generate viz with quantitative T1."
    python3 /flywheel/v0/workflows/not1_viz.py -cbf ${workdir}/s_cbf_1mm.nii.gz -out ${viz}/ -seg_folder ${workdir}/ -seg ${new_list[@]} -mask ${workdir}/mask_1mm.nii.gz
### Create HTML file and output data into it for easy viewing
    python3 /flywheel/v0/workflows/not1_pdf.py -viz ${viz} -stats ${stats}/ -out ${workdir}/ -seg_folder ${workdir}/ -seg ${new_list[@]}
fi

python3 /flywheel/v0/workflows/qc.py -viz ${viz} -out ${workdir} -seg_folder ${workdir}/ -seg ${new_list[@]}

## Move all files we want easy access to into the output directory
find ${workdir} -maxdepth 1 \( -name "cbf.nii.gz" -o -name "viz" -o -name "stats" -o -name "t1.nii.gz" -o -name "tSNR_map.nii.gz" -o -name "output.pdf" -o -name "qc.pdf" \) -print0 | xargs -0 -I {} mv {} ${export_dir}/
mv ${export_dir}/stats/tmp* ${workdir}/ 

## Zip the output directory for easy download
## Also zip work dir so people can look at the intermediate data to troubleshoot
zip -q -r ${export_dir}/final_output.zip ${export_dir}
zip -q -r ${export_dir}/work_dir.zip ${workdir}
