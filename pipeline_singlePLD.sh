#!/bin/bash

## script created by Manuel Taso
## script edited and uploaded to FW by krj

##
### Minimal ASL Pre-processing and CBF Calculation
##

# Load config or inputs manually
CmdName=$(basename "$0")
Syntax="${CmdName} [-c config][-a ASLZip][-n][-m M0Zip][-v]"
function sys {
	[ -n "${opt_n}${opt_v}" ] && echo "$@" 1>&2
	[ -n "$opt_n" ] || "$@"
}
while getopts a:c:i:m:nv arg
do
	case "$arg" in
		a|c|m|n|v)
			eval "opt_${arg}='${OPTARG:=1}'"
			;;
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

### Data Preprocessing
# Set up data paths
flywheel='/flywheel/v0'
[ -e "$flywheel" ] || mkdir "$flywheel"
data_dir='/flywheel/v0/input'
[ -e "$data_dir" ] || mkdir "$data_dir"
export_dir='/flywheel/v0/output'
[ -e "$export_dir" ] || mkdir "$export_dir"
std='/flywheel/v0/input/std'
[ -e "$std" ] || mkdir "$std"
viz='/flywheel/v0/output/viz'
[ -e "$viz" ] || mkdir "$viz"
workdir='/flywheel/v0/work'
[ -e "$workdir" ] || mkdir "$workdir"
m0_dcmdir='/flywheel/v0/work/m0_dcmdir'
[ -e "$m0_dcmdir" ] || mkdir "$m0_dcmdir"
asl_dcmdir='/flywheel/v0/work/asl_dcmdir'
[ -e "$asl_dcmdir" ] || mkdir "$asl_dcmdir"
stats='/flywheel/v0/output/stats'
[ -e "$stats" ] || mkdir "$stats"

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
while (( attempt <= max_attempts )); do
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
        if (( attempt < max_attempts )); then
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

# Find out data paths for m0 and asl files
m0_file=$(find ${m0_dcmdir} -maxdepth 1 -type f -name "*M0.nii" -print | tail -n 1)
asl_file=$(find ${asl_dcmdir} -maxdepth 1 -type f -name "*ASL.nii" -print | tail -n 1)

# Extract dicom header info to get parameters for cbf calculation
dcm_file=$(find ${m0_dcmdir}/ -maxdepth 2 -type f | head -n 1)
if [ -z "$dcm_file" ]; then
	echo "No dicom file!"
	exit 1
fi

ld=$(iconv -f UTF-8 -t UTF-8//IGNORE "$dcm_file" | awk -F 'sWipMemBlock.alFree\\[0\\][[:space:]]*=[[:space:]]*' '{print $2}' | tr -d '[:space:]')
pld=$(iconv -f UTF-8 -t UTF-8//IGNORE "$dcm_file" | awk -F 'sWipMemBlock.alFree\\[1\\][[:space:]]*=[[:space:]]*' '{print $2}' | tr -d '[:space:]')
nbs=$(iconv -f UTF-8 -t UTF-8//IGNORE "$dcm_file" | awk -F 'sWipMemBlock.alFree\\[11\][[:space:]]*=[[:space:]]*' '{print $2}' | tr -d '[:space:]')
m0_scale=$(iconv -f UTF-8 -t UTF-8//IGNORE "$dcm_file" | awk -F 'sWipMemBlock.alFree\\[20\][[:space:]]*=[[:space:]]*' '{print $2}' | tr -d '[:space:]')
echo $ld $pld $nbs $m0_scale
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
#bet ${workdir}/m0_mc.nii.gz ${workdir}/m0_mc_brain.nii.gz -R -m

# Merge all data then motion correction by running mcflirt
asl_file --data=${workdir}/asl_mc.nii.gz --ntis=1 --iaf=tc --diff --out=${workdir}/sub.nii.gz
fslmaths ${workdir}/sub.nii.gz -abs -Tmean ${workdir}/sub_av.nii.gz

### Calculate CBF 
python3 /flywheel/v0/workflows/cbf_calc.py -m0 ${workdir}/m0_mc.nii.gz -asl ${workdir}/sub_av.nii.gz -m ${workdir}/mask.nii.gz -ld $ld -pld $pld -nbs $nbs -scale $m0_scale -out ${workdir}

# Fit T1 with function z. Skip this step for the recover project bc t1 data is messed up.
python3 /flywheel/v0/workflows/t1fit.py -m0_ir ${workdir}/m0_ir_mc.nii.gz -m ${workdir}/mask.nii.gz -out ${workdir} -stats ${stats}

# Smoothing ASL image subject space, deforming images to match template
fslmaths ${workdir}/sub_av.nii.gz -s 1.5 -mas ${workdir}/mask.nii.gz ${workdir}/s_asl.nii.gz 
${ANTSPATH}/antsRegistration --dimensionality 3 --transform "Affine[0.25]" --metric "MI[${std}/batsasl/bats_asl_masked.nii.gz,${workdir}/s_asl.nii.gz,1,32]" --convergence 100x20 --shrink-factors 4x1 --smoothing-sigmas 2x0mm --transform "SyN[0.1]" --metric "CC[${std}/batsasl/bats_asl_masked.nii.gz,${workdir}/s_asl.nii.gz,1,1]" --convergence 40x20 --shrink-factors 2x1 --smoothing-sigmas 2x0mm  --output "[${workdir}/ind2temp,${workdir}/ind2temp_warped.nii.gz,${workdir}/temp2ind_warped.nii.gz]" --collapse-output-transforms 1 --interpolation BSpline -v 1
echo "ANTs Registration finished"

# Warping atlases, deforming ROI
# Standardize CBF images to a common template
${ANTSPATH}/WarpImageMultiTransform 3 ${std}/batsasl/bats_cbf.nii.gz ${workdir}/w_batscbf.nii.gz -R ${workdir}/sub_av.nii.gz --use-BSpline -i ${workdir}/ind2temp0GenericAffine.mat ${workdir}/ind2temp1InverseWarp.nii.gz
list=("arterial2" "cortical" "subcortical" "thalamus") ##list of ROIs

# deforming ROI
for str in "${list[@]}" 
do
  echo ${str}
  touch ${stats}/tmp_$str.txt
  touch ${stats}/cbf_$str.txt
  ${ANTSPATH}/WarpImageMultiTransform 3 ${std}/${str}.nii.gz ${workdir}/w_${str}.nii.gz -R ${workdir}/sub_av.nii.gz --use-NN -i ${workdir}/ind2temp0GenericAffine.mat ${workdir}/ind2temp1InverseWarp.nii.gz
  fslstats -K ${workdir}/w_${str}.nii.gz ${workdir}/cbf.nii.gz -M -S > ${stats}/tmp_${str}.txt
  paste ${std}/${str}_label.txt -d ' ' ${stats}/tmp_${str}.txt > ${stats}/cbf_${str}.txt #combine label with values
done

# We want just general grey and white matter cbf values, so extract these separately
mri_binarize -i ${std}/subcortical.nii.gz -o ${workdir}/grey_matter.nii.gz --match 2 13
mri_binarize -i ${std}/subcortical.nii.gz -o ${workdir}/white_matter.nii.gz --match 1 12
fslstats -K ${workdir}/grey_matter.nii.gz ${workdir}/cbf.nii.gz -M -S > ${stats}/tmp_grey.txt
fslstats -K ${workdir}/white_matter.nii.gz ${workdir}/cbf.nii.gz -M -S > ${stats}/tmp_white.txt

new_list=("arterial2" "cortical" "subcortical" "thalamus" "grey" "white") ##list of ROIs
for str in "${new_list[@]}"
do
  input_cbf="${stats}/cbf_${str}.txt"
  output_cbf="${stats}/formatted_cbf_${str}.txt"
  temp_dir="/flywheel/v0/work/temp_$(date +%s)"
  mkdir -p "$temp_dir"
  
  # Create a temporary file with a header
  temp_file="$temp_dir/tmp_cbf_${str}.txt"
  echo "Region | Mean CBF | Standard Deviation" > "$temp_file"
  
  while IFS= read -r line; do
    # Skip blank lines
    [[ -z "$line" ]] && continue
    
    # Extract the last two fields as numbers and the rest as region.
    # This assumes that the numeric values are the last two fields.
    mean_cbf=$(echo "$line" | awk '{print $(NF-1)}')
    std_dev=$(echo "$line" | awk '{print $NF}')
    region=$(echo "$line" | awk '{
       for (i=1;i<=NF-2;i++) 
         printf "%s ", $i;
       }' | sed 's/[[:space:]]$//')
    
    # If region is empty or undesired, skip the line.
    if [[ -z "$region" || "$region" == "0" ]]; then
      continue
    fi
    
    # Format numeric values.
    rounded_mean_cbf=$(printf "%.1f" "$mean_cbf")
    rounded_std_dev=$(printf "%.1f" "$std_dev")
    
    # Append the formatted line.
    echo "$region | $rounded_mean_cbf | $rounded_std_dev" >> "$temp_file"
  done < "$input_cbf"
  
  # Reformat the temporary file into neat columns.
  column -t -s '|' -o '|' "$temp_file" > "$output_cbf"
  
  rm -rf "$temp_dir"
done


# Smoothing the deformation field of images obtained previously
fslmaths ${workdir}/ind2temp1Warp.nii.gz -s 5 ${workdir}/swarp.nii.gz
${ANTSPATH}/WarpImageMultiTransform 3 ${workdir}/sub_av.nii.gz ${workdir}/s_ind2temp_warped.nii.gz -R ${workdir}/ind2temp_warped.nii.gz --use-BSpline ${workdir}/swarp.nii.gz ${workdir}/ind2temp0GenericAffine.mat
${ANTSPATH}/WarpImageMultiTransform 3 ${workdir}/cbf.nii.gz ${workdir}/wcbf.nii.gz -R ${workdir}/ind2temp_warped.nii.gz --use-BSpline ${workdir}/swarp.nii.gz ${workdir}/ind2temp0GenericAffine.mat
${ANTSPATH}/WarpImageMultiTransform 3 ${workdir}/t1.nii.gz ${workdir}/wt1.nii.gz -R ${workdir}/ind2temp_warped.nii.gz --use-BSpline ${workdir}/swarp.nii.gz ${workdir}/ind2temp0GenericAffine.mat
#wt1: t1 relaxation time. common space. 

### tSNR calculation
fslmaths ${workdir}/sub.nii.gz -Tmean ${workdir}/sub_mean.nii.gz
fslmaths ${workdir}/sub.nii.gz -Tstd ${workdir}/sub_std.nii.gz
fslmaths ${workdir}/sub_mean.nii.gz -div ${workdir}/sub_std.nii.gz ${workdir}/tSNR_map.nii.gz

### Visualizations
python3 -m pip install nilearn
python3 /flywheel/v0/workflows/viz.py -cbf ${workdir}/cbf.nii.gz -t1 ${workdir}/t1.nii.gz -out ${viz}/ -seg_folder ${workdir}/ -seg ${list[@]}

### Create HTML file and output data into it for easy viewing
python3 /flywheel/v0/workflows/pdf.py -viz ${viz} -stats ${stats}/ -out ${workdir}/ -seg_folder ${workdir}/ -seg ${new_list[@]}

## Move all files we want easy access to into the output directory
find ${workdir} -maxdepth 1 \( -name "cbf.nii.gz" -o -name "viz" -o -name "stats" -o -name "t1.nii.gz" -o -name "tSNR_map.nii.gz" -o -name "Output.pdf" \) -print0 | xargs -0 -I {} mv {} ${export_dir}/
mv ${export_dir}/stats/tmp* ${workdir}/ 

## Zip the output directory for easy download
zip -r ${export_dir}/output.zip ${export_dir}
