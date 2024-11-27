#!/bin/bash

#### NOTES FOR KATIE 102224
# change dcm2niix to include series description (-f %d)
# then do fslmerge of all data, followed by mcflirt, followed by fslroi to extract just the 1st volume (m0), first and second in the same array (M0+IR# ), and from 3rd volume to the end 

### Data Preprocessing
# Set up data paths

data_dir='/flywheel/v0/input'
out_dir='/flywheel/v0/output'
std='/flywheel/v0/input/std'
stats='/flywheel/v0/output/stats'

# Convert dicom to nifti files
# Doing the loop so we can read in all data at once
# Will also make it easier for variable number of DICOMs
for dir_name in ${data_dir}/dicoms/*
do
dcm2niix -f %d -b y -o ${out_dir}/ ${dir_name}/
done

# Dcm2niix doesn't always work first try, so check and redo if files aren't present

attempt=1
max_attempt=2

# Loop until both files are found or max attempts are reached
while (( attempt <= max_attempts )); do
    echo "Attempt $attempt of $max_attempts..."

    # Use find to locate the files
    asl_file=$(find "$out_dir" -maxdepth 1 -type f -name "*ASL.nii" | head -n 1)
    m0_file=$(find "$out_dir" -maxdepth 1 -type f -name "*M0.nii" | head -n 1)

    # Debugging output
    echo "ASL file: $asl_file"
    echo "M0 file: $m0_file"

    if [[ -n "$asl_file" && -n "$m0_file" ]]; then
        echo "Both files found: $asl_file and $m0_file"
        break  # Exit the loop
    else
        if (( attempt < max_attempts )); then
            echo "Files missing. Retrying..."
            for dir_name in ${data_dir}/dicoms/*
                do
                dcm2niix -f %d -b y -o ${out_dir}/ ${dir_name}/
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
m0_file=$(find ${out_dir} -maxdepth 1 -type f -name "*M0*.nii" -print | tail -n 1)
asl_file=$(find ${out_dir} 1 -type f -name "*ASL*.nii" -print | head -n 1)

# Extract dicom header info to get parameters for cbf calculation
dcm_file=$(find ${data_dir}/dicoms -maxdepth 2 -type f|head -n 1)

dcm_content=$(<$dcm_file)

ld=$(iconv -f UTF-8 -t UTF-8//IGNORE <<< "$dcm_content" | awk -F 'sWipMemBlock.alFree\\[0\\][[:space:]]*=[[:space:]]*' '{print $2}' | tr -d '[:space:]')
pld=$(iconv -f UTF-8 -t UTF-8//IGNORE <<< "$dcm_content" | awk -F 'sWipMemBlock.alFree\\[1\\][[:space:]]*=[[:space:]]*' '{print $2}' | tr -d '[:space:]')
nbs=$(iconv -f UTF-8 -t UTF-8//IGNORE <<< "$dcm_content" | awk -F 'sWipMemBlock.alFree\\[11\][[:space:]]*=[[:space:]]*' '{print $2}' | tr -d '[:space:]')
m0_scale=$(iconv -f UTF-8 -t UTF-8//IGNORE <<< "$dcm_content" | awk -F 'sWipMemBlock.alFree\\[20\][[:space:]]*=[[:space:]]*' '{print $2}' | tr -d '[:space:]')


# Merge Data
fslmerge -t ${out_dir}/all_data.nii.gz $m0_file $asl_file

# Motion correction
mcflirt -in ${out_dir}/all_data.nii.gz -out ${out_dir}/mc.nii.gz

# Split the data back up after motion correction
fslroi ${out_dir}/mc.nii.gz ${out_dir}/m0_mc.nii.gz 0 1
fslroi ${out_dir}/mc.nii.gz ${out_dir}/m0_ir_mc.nii.gz 0 2
fslroi ${out_dir}/mc.nii.gz ${out_dir}/asl_mc.nii.gz 2 10

# Skull-Stripping
mri_synthstrip -i ${out_dir}/m0_mc.nii.gz -m ${out_dir}/mask.nii.gz

# Merge all data then motion correction by running mcflirt
asl_file --data=${out_dir}/asl_mc.nii.gz --ntis=1 --iaf=tc --diff --out=${out_dir}/sub.nii.gz
fslmaths ${out_dir}/sub.nii.gz -abs -Tmean ${out_dir}/sub_av.nii.gz

### Calculate CBF 
python3 /flywheel/v0/workflows/cbf_calc.py -m0 ${out_dir}/m0_mc.nii.gz -asl ${out_dir}/sub_av.nii.gz -m ${out_dir}/mask.nii.gz -ld $ld -pld $pld -nbs $nbs -scale $m0_scale
# Fit T1 with function z. Skip this step for the recover project bc t1 data is messed up.
python3 /flywheel/v0/workflows/t1fit.py ${out_dir}/m0_ir_mc.nii.gz ${out_dir}/mask.nii.gz

# Smoothing ASL image subject space, deforming images to match template
fslmaths ${out_dir}/sub_av.nii.gz -s 1.5 -mas ${out_dir}/mask.nii.gz ${out_dir}/s_asl.nii.gz 
${ANTSPATH}/antsRegistration --dimensionality 3   --transform "Affine[0.25]" --metric "MI[${std}/batsasl/bats_asl_masked.nii.gz,${out_dir}/s_asl.nii.gz,1,32]" --convergence 100x20 --shrink-factors 4x1 --smoothing-sigmas 2x0mm --transform "SyN[0.1]" --metric "CC[${std}/batsasl/bats_asl_masked.nii.gz,${out_dir}/s_asl.nii.gz,1,1]" --convergence 40x20 --shrink-factors 2x1 --smoothing-sigmas 2x0mm  --output "[${out_dir}/ind2temp,${out_dir}/ind2temp_warped.nii.gz,${out_dir}/temp2ind_warped.nii.gz]" --collapse-output-transforms 1 --interpolation BSpline -v 1
echo "ANTs Registration finished"

# Warping atlases, deforming ROI
# Standardize CBF images to a common template
${ANTSPATH}/WarpImageMultiTransform 3 ${std}/batsasl/bats_cbf.nii.gz ${out_dir}/w_batscbf.nii.gz -R ${out_dir}/sub_av.nii.gz --use-BSpline -i ${out_dir}/ind2temp0GenericAffine.mat ${out_dir}/ind2temp1InverseWarp.nii.gz
list=("arterial" "cortical" "subcortical" "thalamus") ##list of ROIs
echo ${list}
# deforming ROI

for str in "${list[@]}" 
do

echo ${str}

touch ${stats}/tmp_$str.txt

touch ${stats}/cbf_$str.txt

${ANTSPATH}/WarpImageMultiTransform 3 ${std}/${str}.nii.gz ${out_dir}/w_${str}.nii.gz -R ${out_dir}/sub_av.nii.gz --use-NN -i ${out_dir}/ind2temp0GenericAffine.mat ${out_dir}/ind2temp1InverseWarp.nii.gz

fslstats -K ${out_dir}/w_${str}.nii.gz ${out_dir}/cbf.nii.gz -M -S > ${stats}/tmp_${str}.txt

paste ${std}/${str}_label.txt -d ' ' ${stats}/tmp_${str}.txt > ${stats}/cbf_${str}.txt #combine label with values
done

# Smoothing the deformation field of images obtained previously
fslmaths ${out_dir}/ind2temp1Warp.nii.gz -s 5 ${out_dir}/swarp.nii.gz
${ANTSPATH}/WarpImageMultiTransform 3 ${out_dir}/sub_av.nii.gz ${out_dir}/s_ind2temp_warped.nii.gz -R ${out_dir}/ind2temp_warped.nii.gz --use-BSpline ${out_dir}/swarp.nii.gz ${out_dir}/ind2temp0GenericAffine.mat
${ANTSPATH}/WarpImageMultiTransform 3 ${out_dir}/cbf.nii.gz ${out_dir}/wcbf.nii.gz -R ${out_dir}/ind2temp_warped.nii.gz --use-BSpline ${out_dir}/swarp.nii.gz ${out_dir}/ind2temp0GenericAffine.mat
${ANTSPATH}/WarpImageMultiTransform 3 ${out_dir}/t1.nii.gz ${out_dir}/wt1.nii.gz -R ${out_dir}/ind2temp_warped.nii.gz --use-BSpline ${out_dir}/swarp.nii.gz ${out_dir}/ind2temp0GenericAffine.mat
#wt1: t1 relaxation time. common space. 
