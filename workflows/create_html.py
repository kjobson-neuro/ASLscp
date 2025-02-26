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
    seg_img = os.path.join(viz_path, f"w_{i}_meanCBF_80_mosaic_prism.png")
    if os.path.exists(file_path):
        formatted_data[i] = read_formatted_file(file_path)
        segmentation_images[i] = seg_img

# Generate HTML content
html_content = f"""
<!DOCTYPE html>
<html>
<head>
<title>Pipeline Evaluation</title>
<style>
table, th, td {{
  border: 1px solid black;
  border-collapse: collapse;
  padding: 5px;
  text-align: center;
}}
img {{
  max-width: 800px; /* Adjust as needed */
  height: auto;
}}
</style>
</head>
<body>

<h1>Pipeline Evaluation</h1>

"""

for prefix in seg_list:
    html_content += f"""
    <h2>{prefix.capitalize()} CBF values extracted from segmentations</h2>
    <img src="{segmentation_images.get(prefix, '')}" alt="{prefix.capitalize()} Segmentation">
    <table>
    <tr>
        <th>Region</th>
        <th>Mean CBF</th>
        <th>Standard Deviation</th>
    </tr>
    """
    if formatted_data.get(prefix):
        for region, mean_cbf, std_dev in formatted_data[prefix]:
            html_content += f"""
            <tr>
                <td>{region}</td>
                <td>{mean_cbf}</td>
                <td>{std_dev}</td>
            </tr>
            """
    else:
        html_content += "<tr><td colspan='3'>No data found for this segmentation.</td></tr>"

    html_content += """
    </table>
    <br>
    """

html_content += """
</body>
</html>
"""

# Write HTML content to file
output_file_path = os.path.join(outputdir, "pipeline_evaluation.html")
with open(output_file_path, "w") as file:
    file.write(html_content)

print(f"HTML file generated at: {output_file_path}")

