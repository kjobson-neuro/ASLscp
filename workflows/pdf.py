import os
import argparse
from xhtml2pdf import pisa

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

def generate_pdf_content(formatted_data, segmentation_images):
    pdf_content = """
    <html>
    <head>
        <title>CBF Values from Segmentations</title>
        <style>
            table {
                border-collapse: collapse;
            }
            th, td {
                border: 1px solid black;
                padding: 5px;
            }
        </style>
    </head>
    <body>
    """
    
    for prefix, data in formatted_data.items():
        seg_img_path = segmentation_images.get(prefix, "")
        if seg_img_path:
            pdf_content += f"""
            <h2>{prefix.capitalize()} CBF values extracted from segmentations</h2>
            <img src="{seg_img_path}" alt="Segmentation Image">
            <table>
                <tr><th>Region</th><th>Mean CBF</th><th>Standard Deviation</th></tr>
            """
            for region, mean_cbf, std_dev in data:
                pdf_content += f"""
                <tr><td>{region}</td><td>{mean_cbf}</td><td>{std_dev}</td></tr>
                """
            pdf_content += "</table>"
        else:
            pdf_content += f"""
            <h2>{prefix.capitalize()} CBF values extracted from segmentations</h2>
            <table>
                <tr><th>Region</th><th>Mean CBF</th><th>Standard Deviation</th></tr>
            """
            for region, mean_cbf, std_dev in data:
                pdf_content += f"""
                <tr><td>{region}</td><td>{mean_cbf}</td><td>{std_dev}</td></tr>
                """
            pdf_content += "</table>"
    
    pdf_content += """
    </body>
    </html>
    """
    
    return pdf_content

def main():
    parser = argparse.ArgumentParser(description='Create PDF file to evaluate pipeline outputs.')
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
    
    formatted_data = {}
    segmentation_images = {}
    
    for i in seg_list:
        file_path = os.path.join(stats_path, f"formatted_cbf_{i}.txt")
        seg_img = os.path.join(viz_path, f"w_{i}_meanCBF_80_mosaic_prism.png")
        
        if os.path.exists(file_path):
            formatted_data[i] = read_formatted_file(file_path)
            segmentation_images[i] = seg_img
    
    pdf_content = generate_pdf_content(formatted_data, segmentation_images)
    
    pdf_path = os.path.join(outputdir, 'output.pdf')
    
    with open(pdf_path, "wb") as pdf_file:
        pisa_status = pisa.CreatePDF(pdf_content, dest=pdf_file)
    
    if not pisa_status.err:
        print(f"PDF generated and saved at {pdf_path}")
    else:
        print("PDF generation failed")

if __name__ == "__main__":
    main()

