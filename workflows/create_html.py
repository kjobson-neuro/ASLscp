#!/usr/bin/env python3
import os
import argparse

parser = argparse.ArgumentParser(description='Create HTML file to evaluate pipeline outputs.')
parser.add_argument('-viz', type=str, help="The path to the viz folder.")
parser.add_argument('-stats', type=str, help="The path to the stats folder.")
parser.add_argument('-out', type=str, help="The output path.")
parser.add_argument('-seg_folder', type=str, help="The path to the segmentation files.")
parser.add_argument('-seg', type=str, nargs='+', help="The list of segmentations to display.")

args = parser.parse_args()

viz_path = args.viz
stats_path = args.stats
seg_folder = args.seg_folder
seg_list = args.seg
outputdir = args.out

# Function to read formatted text file
def read_formatted_file(file_path):
    try:
        with open(file_path, 'r') as file:
            content = file.read().strip().split('\n')
        data = []
        for line in content[1:]:  # Skip header line
            parts = line.split('|')
            region = parts[0].strip()
            mean_cbf = parts[1].strip()
            std_dev = parts[2].strip()
            data.append((region, mean_cbf, std_dev))
        return data
    except FileNotFoundError:
        return None

# Store formatted data and segmentation image paths
formatted_data = {}
segmentation_images = {}

for i in seg_list:
    file_path = os.path.join(stats_path, f"formatted_cbf_{i}.txt")
for i in seg_list[:-2]:    
    seg_img = os.path.join(viz_path, f"w_{i}_meanCBF_80_mosaic_prism.png")
    if os.path.exists(file_path):
        formatted_data[i] = read_formatted_file(file_path)
        segmentation_images[i] = seg_img


# Generate segmentation sections first
segmentation_sections = ""

for prefix, data in formatted_data.items():
    seg = segmentation_images.get(prefix, "")

    segmentation_sections += f""" 
    <div class="segmentation-section">
        <h2>{prefix.capitalize()} CBF Values</h2>
        <p>{prefix.capitalize()} CBF values extracted from segmentations</p>

        <h3>CBF Values by Region</h3>
        <table>
            <thead>
                <tr>
                    <th>Region</th>
                    <th>Mean CBF</th>
                    <th>Standard Deviation</th>
                </tr>
            </thead>
            <tbody>
    """

    for region, mean_cbf, std_dev in data:
        segmentation_sections += f"""
            <tr>
                <td>{region}</td>
                <td>{mean_cbf}</td>
                <td>{std_dev}</td>
            </tr>
        """

    segmentation_sections += f"""
            </tbody>
        </table>

        <h3>Segmentation Image</h3>
        <img src="{seg}" alt="{prefix.capitalize()} Overlay" width="700">
    </div>
    """

# Generate final HTML content
html_content = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ASL Gear Output</title>
    <style>
        table {{
            width: 30%;
            margin-bottom: 20px;
            border-spacing: 2px;
            border-collapse: collapse;
        }}
        th, td {{
            border: 1px solid black;
            padding: 8px;
            text-align: left;
        }}
        th {{
            background-color: #f2f2f2;
        }}
        .image-container {{
            display: inline-block;
            margin: 20px;
            text-align: center;
        }}
    </style>
</head>
<body>
    <h1>ASL Gear Output</h1>
    
    <h3>Mean CBF Image</h3>
    <img src="{viz_path}/meanCBF_mosaic.png" alt="Mean CBF" width="700">

    <h3>T1w Image</h3>
    <img src="{viz_path}/qT1_mosaic.png" alt="Quantitative T1 Image" width="700">

    {segmentation_sections}
</body>
</html>
"""

# Write HTML content to file
output_file_path = os.path.join(outputdir, "Output.html")
with open(output_file_path, "w") as file:
    file.write(html_content)






