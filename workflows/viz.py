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
from nilearn.plotting import cm, plot_roi, show
import matplotlib.pyplot as plt
from nilearn.plotting.cm import _cmap_d as nilearn_cmaps
import matplotlib.colors as mcolors
import pandas as pd

parser = argparse.ArgumentParser(description='get cbf image from the pipeline script')

# Set up parser for the CBF file and output directory
parser.add_argument('-cbf', type=str, help="The path to the CBF file.")
parser.add_argument('-out', type=str, help="The output path.")
parser.add_argument('-seg', type=str, help="The path to the segmentation file.")
args = parser.parse_args()

# Load the images
mcbf_img = args.cbf
mcbf_nii = nb.load(mcbf_img)
seg_file = args.seg
seg_nii = nb.load(seg_file)
seg_name = os.path.basename(seg_file)
outputdir = args.out

def read_color_file(file_path):
    colors = []
    with open(file_path, 'r') as f:
        for line in f:
            r, g, b = map(float, line.strip().split())
            colors.append((r, g, b))
    return colors

# Read color information
color_file = 'color.txt'
colors = read_color_file(color_file)

import xml.etree.ElementTree as ET

def read_xml_labels(xml_file):
    tree = ET.parse(xml_file)
    root = tree.getroot()
    
    labels = []
    for label in root.findall('.//label'):
        labels.append(label.text)
    
    return labels

# Read XML and pair with colors
xml_file = 'HarvardOxford-Subcortical.xml'
labels = read_xml_labels(xml_file)
paired_colors = dict(zip(labels, colors[:len(labels)]))

import matplotlib.colors as mcolors

color_list = [paired_colors.get(label, (0,0,0)) for label in labels]
cmap = mcolors.ListedColormap(color_list)
cmap = mcolors.ListedColormap(color_list)


# Plot the mean CBF map with two different vmax
nilearn.plotting.plot_roi(seg_nii, mcbf_nii, display_mode='mosaic', black_bg=True, alpha=0.25, draw_cross=False,
                      vmin=0,vmax=80, cut_coords=10, title="meanCBF_80_segmentation",
                      output_file=os.path.join(outputdir + seg_name + "meanCBF_80_mosaic.png"))

nilearn.plotting.plot_roi(seg_nii, mcbf_nii, display_mode='mosaic', black_bg=True, alpha=0.5, cmap=cmap, draw_cross=False,
                      vmin=0,vmax=80, cut_coords=10, title="meanCBF_80_segmentation",
                      output_file=os.path.join(outputdir + seg_name + "meanCBF_80_mosaic_cmap.png"))

nilearn.plotting.plot_roi(seg_nii, mcbf_nii, display_mode='mosaic', black_bg=True, alpha=0.5, cmap="plasma", draw_cross=False,
                      vmin=0,vmax=80, cut_coords=10, title="meanCBF_80_segmentation",
                      output_file=os.path.join(outputdir + seg_name + "meanCBF_80_mosaic_plasma.png"))

nilearn.plotting.plot_epi(mcbf_nii, display_mode='mosaic', bg_img=None, black_bg=True, draw_cross=False,cmap='gist_gray',
                      vmin=0, cut_coords=10, colorbar=True, title="meanCBF_mosaic",
                      output_file=os.path.join(outputdir + "meanCBF_mosaic.png"))
