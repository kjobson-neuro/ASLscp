import sys
import os
import logging
import argparse
import nibabel as nb
import shutil
import numpy as np
from nibabel.processing import smooth_image
import nilearn
from nilearn import plotting

parser = argparse.ArgumentParser(description='get cbf image from the pipeline script')

# Set up parser for the CBF file and output directory
parser.add_argument('-cbf', type=str, help="The path to the CBF file.")
parser.add_argument('-out', type=str, help="The output path.")
args = parser.parse_args()

# Load the images
mcbf_img = args.cbf
mcbf_nii = nb.load(mcbf_img)
outputdir = args.out

# Plot the mean CBF map with two different vmax
nilearn.plotting.plot_epi(mcbf_nii, display_mode='mosaic', bg_img=None, black_bg=True, draw_cross=False, cmap='gist_gray',
                      vmin=0,vmax=80, cut_coords=10, colorbar=True, title="meanCBF_80_mosaic",
                      output_file=os.path.join(outputdir + "meanCBF_80_mosaic.png"))

nilearn.plotting.plot_epi(mcbf_nii, display_mode='mosaic', bg_img=None, black_bg=True, draw_cross=False,cmap='gist_gray',
                      vmin=0, vmax=100, cut_coords=10, colorbar=True, title="meanCBF_100_mosaic",
                      output_file=os.path.join(outputdir + "meanCBF_100_mosaic.png"))


