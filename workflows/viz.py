import sys
import os
import logging
import argparse
import nibabel as nb
import shutil
from nibabel.processing import smooth_image
import nilearn
import nilearn.plotting 
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
import numpy as np

parser = argparse.ArgumentParser(description='Take processed images and create visualizations.')

# Set up parser for the CBF file and output directory
parser.add_argument('-cbf', type=str, help="The path to the CBF file.")
parser.add_argument('-t1', type=str, help="The path to the T1w file.")
parser.add_argument('-out', type=str, help="The output path.")
parser.add_argument('-seg_folder', type=str, help="The path to the segmentation files.")
parser.add_argument('-seg', type=str, nargs='+', help="The list of segmentations to display.")

args = parser.parse_args()

# Load the images
mcbf_img = args.cbf
mcbf_nii = nb.load(mcbf_img)
t1_img = args.t1
t1_nii = nb.load(t1_img)
outputdir = args.out

# Take the list of segmentations and loop through for vizualizations
seg_folder = args.seg_folder
seg_list = args.seg

for i in seg_list:
    seg_file = os.path.join(seg_folder + 'w_' + i + '.nii.gz')
    seg_nii = nb.load(seg_file)
    seg_name = os.path.basename(seg_file)
    split = seg_name.split('.')
    seg = split[0]

    # Plot the mean CBF map with two different vmax
    nilearn.plotting.plot_roi(seg_nii, mcbf_nii, display_mode='mosaic', black_bg=True, alpha=0.5, cmap="prism", draw_cross=False,
        vmin=0,vmax=80, cut_coords=8, title="meanCBF_80_segmentation",
        output_file=os.path.join(outputdir, seg + "_meanCBF_80_mosaic_prism.png"))


# Now plot the absolute CBF with discrete scale
n_colors = 16
base_cmap = plt.get_cmap('jet')
color_list = base_cmap(np.linspace(0, 1, n_colors))
discrete_cmap = ListedColormap(color_list)

nilearn.plotting.plot_stat_map(mcbf_nii, display_mode='mosaic', bg_img=None, black_bg=True, draw_cross=False, cmap=base_cmap,
        vmin=0, vmax=100, cut_coords=8, title="meanCBF_mosaic", cbar_tick_format="%i",
        output_file=os.path.join(outputdir, "meanCBF_mosaic.png"))

nilearn.plotting.plot_stat_map(mcbf_nii, display_mode='mosaic', bg_img=None, black_bg=True, draw_cross=False, cmap='gist_yarg_r',
        vmin=0, vmax=100, cut_coords=8, title="meanCBF_bw", cbar_tick_format="%i",
        output_file=os.path.join(outputdir, "meanCBF_bw.png"))

nilearn.plotting.plot_stat_map(t1_nii, display_mode='mosaic', bg_img=None, black_bg=True,
        vmin=500, vmax=3000, cut_coords=8, title="Quantitative_T1",cmap='gist_yarg_r', cbar_tick_format="%i",
        output_file=os.path.join(outputdir, "qT1_mosaic.png"))

