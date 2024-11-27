import os
import numpy as np
import nibabel as nib
import matplotlib.pyplot as plt
import scipy 
import argparse
import sys

m0_ir_file = sys.argv[1]
mask = sys.argv[2]

out_dir = '/flywheel/v0/output'
stats_dir = '/flywheel/v0/output/stats'

ref_data = nib.load(m0_ir_file).get_fdata().astype(np.float64)

mask_img = nib.load(mask).get_fdata().astype(np.float64)

T1 = np.arange(100, 5010, 10)
trec = 5000
TI = 1978

z = (1 - 2 * np.exp(-TI / T1) + np.exp(-trec / T1)) / (1 - np.exp(-trec / T1))

ratio = ref_data[:,:,:,1] / ref_data[:,:,:,0]
# ratio = ratio * mask_img
ratio[ratio==0] = np.min(z)
ratio[ratio>=1] = np.max(z)
f = scipy.interpolate.interp1d(z,T1, fill_value='extrapolate')

t1 = f(ratio)
t1[np.isnan(t1)] = 0
t1 = t1 * mask_img

nii = nib.load(mask)
nii.header.set_data_dtype(np.float32)
nii_data = np.asarray(t1, dtype=np.float32)
nii_img = nib.Nifti1Image(nii_data, nii.affine,nii.header)
name = out_dir + '/t1.nii.gz'
nib.save(nii_img, name)

nii_data_m0 = ref_data[:,:,:,0]
nii_data_m0 = np.asarray(nii_data_m0, dtype=np.float32)
nii_img_m0 = nib.Nifti1Image(nii_data_m0, nii.affine,nii.header)
name_m0 = out_dir + '/m0.nii.gz'
nib.save(nii_img_m0, name_m0)
