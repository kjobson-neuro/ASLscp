import os
import argparse
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Image, Paragraph, Spacer, PageBreak
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet

def read_formatted_file(file_path):
    try:
        with open(file_path, 'r') as file:
            content = file.read().strip().split('\n')
            data = []
            for line in content[1:]:  # Skip header line
                parts = line.split('|')
                parts = [p.strip() for p in parts]
                if len(parts) == 4:
                    region, mean_cbf, rcbf, vox = parts
                    data.append((region, mean_cbf, rcbf, vox))
                elif len(parts) == 5:
                    region, mean_cbf, std_dev, vox, vol = parts
                    data.append((region, mean_cbf, std_dev, vox, vol))
            return data
    except FileNotFoundError:
        return []

def generate_pdf(formatted_data, segmentation_images, output_path, mean_cbf_img=None, mean_cbf_bw_img=None, qt1_img=None, stats_path=None):
    doc = SimpleDocTemplate(output_path, pagesize=letter)
    elements = []
    styles = getSampleStyleSheet()

    # Add main title
    elements.append(Paragraph("ASL self-contained processing pipeline output", styles['Title']))
    elements.append(Spacer(1, 24))

    # Add mean_CBF and qT1 images if provided
    if mean_cbf_img and os.path.exists(mean_cbf_img):
        elements.append(Paragraph("Mean CBF", styles['Heading2']))
        elements.append(Image(mean_cbf_img, width=400, height=157))
        elements.append(Spacer(1, 12))

    if mean_cbf_bw_img and os.path.exists(mean_cbf_bw_img):
        elements.append(Paragraph("Mean CBF", styles['Heading2']))
        elements.append(Image(mean_cbf_bw_img, width=400, height=157))
        elements.append(Spacer(1, 12))

    if qt1_img and os.path.exists(qt1_img):
        elements.append(PageBreak())
        elements.append(Paragraph("qT1", styles['Heading2']))
        elements.append(Image(qt1_img, width=400, height=157))
        elements.append(Spacer(1, 24))

    # Add extracted regions section (after qT1, before segmentation)
    weighted_path = os.path.join(stats_path, 'weighted_table.txt')
    weighted_data = read_formatted_file(weighted_path)
    if weighted_data:
        elements.append(Paragraph("CBF and rCBF values for AD Regions", styles['Heading2']))
        elements.append(Spacer(1, 12))
        table_data = [["Region", "Mean CBF (mL/100g/min)", "rCBF", "Voxels (count)"]]
        for region, mean, rcbf, voxels in weighted_data:
            table_data.append([region, mean, rcbf, voxels])
        table = Table(table_data)
        table.setStyle(TableStyle([
            ('BACKGROUND', (0,0), (-1,0), colors.lightgrey),
            ('TEXTCOLOR', (0,0), (-1,0), colors.black),
            ('ALIGN', (0,0), (-1,-1), 'CENTER'),
            ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
            ('BOTTOMPADDING', (0,0), (-1,0), 12),
            ('GRID', (0,0), (-1,-1), 1, colors.black),
        ]))
        elements.append(table)
        elements.append(Spacer(1, 36))

    # Add segmentation tables, each on a new page
    for idx, (prefix, data) in enumerate(formatted_data.items()):
        if idx != 0:
            elements.append(PageBreak())
        elements.append(Paragraph(f"{prefix.capitalize()} CBF values extracted from segmentations", styles['Heading2']))
        elements.append(Spacer(1, 12))

        seg_img_path = segmentation_images.get(prefix, "")
        if seg_img_path and os.path.exists(seg_img_path):
            elements.append(Image(seg_img_path, width=400, height=200))
            elements.append(Spacer(1, 12))

        table_data = [["Region", "Mean CBF (mL/100g/min)", "Standard Deviation", "Voxels (count)", "Volume (mm^3)"]]
        for region, mean_cbf, std_dev, vox, vol in data:
            table_data.append([region, mean_cbf, std_dev, vox, vol])
        table = Table(table_data)
        table.setStyle(TableStyle([
            ('BACKGROUND', (0,0), (-1,0), colors.lightgrey),
            ('TEXTCOLOR', (0,0), (-1,0), colors.black),
            ('ALIGN', (0,0), (-1,-1), 'CENTER'),
            ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
            ('BOTTOMPADDING', (0,0), (-1,0), 12),
            ('GRID', (0,0), (-1,-1), 1, colors.black),
        ]))
        elements.append(table)
        elements.append(Spacer(1, 24))

    doc.build(elements)
    print(f"PDF generated and saved at {output_path}")

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
            data = read_formatted_file(file_path)
            if data:
                formatted_data[i] = data
            segmentation_images[i] = seg_img

    pdf_path = os.path.join(outputdir, 'output.pdf')
    mean_cbf_img = os.path.join(viz_path, "meanCBF_mosaic.png")
    mean_cbf_bw_img = os.path.join(viz_path, "meanCBF_bw.png")
    qt1_img = os.path.join(viz_path, "qT1_mosaic.png")

    generate_pdf(
        formatted_data,
        segmentation_images,
        pdf_path,
        mean_cbf_img=mean_cbf_img,
        mean_cbf_bw_img=mean_cbf_bw_img,
        qt1_img=qt1_img,
        stats_path=stats_path
    )

if __name__ == "__main__":
    main()
