#!/usr/bin/env python3

import os
import sys
import pandas as pd
from collections import defaultdict
from pathlib import Path
import logging
from tqdm import tqdm
import argparse
import matplotlib.pyplot as plt

REQUIRED_LIBRARIES = ['pandas', 'xlsxwriter', 'tqdm', 'matplotlib']

def check_required_libraries():
    missing_libraries = []
    for lib in REQUIRED_LIBRARIES:
        try:
            __import__(lib)
        except ImportError:
            missing_libraries.append(lib)
    
    if missing_libraries:
        print("The following required libraries are missing:")
        for lib in missing_libraries:
            print(f" - {lib}")
        print("\nPlease install them using the following command:")
        print(f"pip install {' '.join(missing_libraries)}")
        sys.exit(1)

def setup_logging(log_file):
    logging.basicConfig(
        filename=log_file,
        level=logging.ERROR,
        format='%(asctime)s - %(levelname)s - %(message)s',
    )

def gather_file_info(root_dir, include_hidden):
    file_info = defaultdict(lambda: {"count": 0, "size": 0, "last_modified": None})
    dir_info = defaultdict(lambda: {"count": 0, "size": 0})

    for dirpath, dirnames, filenames in tqdm(os.walk(root_dir), desc="Scanning files"):
        if not include_hidden:
            dirnames[:] = [d for d in dirnames if not d.startswith('.') and not (os.name == 'nt' and is_hidden(os.path.join(dirpath, d)))]
            filenames = [f for f in filenames if not f.startswith('.') and not (os.name == 'nt' and is_hidden(os.path.join(dirpath, f)))]

        for filename in filenames:
            file_path = os.path.join(dirpath, filename)
            try:
                ext = Path(filename).suffix.lower()
                file_size = os.path.getsize(file_path)
                last_modified = os.path.getmtime(file_path)
                file_info[ext]["count"] += 1
                file_info[ext]["size"] += file_size
                if file_info[ext]["last_modified"] is None or file_info[ext]["last_modified"] < last_modified:
                    file_info[ext]["last_modified"] = last_modified

                dir_info[dirpath]["count"] += 1
                dir_info[dirpath]["size"] += file_size
            except Exception as e:
                logging.error(f"Error processing {file_path}: {e}")

    return file_info, dir_info

def is_hidden(filepath):
    """
    Check if a file or directory is hidden on Windows.
    """
    try:
        attrs = os.stat(filepath).st_file_attributes
        return attrs & 2  # FILE_ATTRIBUTE_HIDDEN
    except AttributeError:
        return False

def convert_size(size_bytes):
    if size_bytes == 0:
        return "0B"
    size_name = ("B", "KB", "MB", "GB", "TB")
    i = int(min(len(size_name) - 1, (size_bytes.bit_length() - 1) // 10))
    p = 1 << (i * 10)
    s = size_bytes / p
    return f"{s:.2f} {size_name[i]}"

def create_output_dataframe(file_info, dir_info):
    file_data = {
        "File Type": [],
        "Count": [],
        "Total Size (Bytes)": [],
        "Readable Total Size": [],
        "Average Size": [],
        "Last Modified (Timestamp)": [],
        "Percentage of Total Files": [],
        "Percentage of Total Size": []
    }

    total_files = sum(info["count"] for info in file_info.values())
    total_size = sum(info["size"] for info in file_info.values())

    for ext, info in file_info.items():
        file_data["File Type"].append(ext if ext else "No Extension")
        file_data["Count"].append(info["count"])
        file_data["Total Size (Bytes)"].append(info["size"])
        file_data["Readable Total Size"].append(convert_size(info["size"]))
        file_data["Average Size"].append(convert_size(info["size"] // info["count"] if info["count"] else 0))
        file_data["Last Modified (Timestamp)"].append(pd.to_datetime(info["last_modified"], unit='s').strftime('%m-%d-%Y %H:%M:%S') if info["last_modified"] else "N/A")
        file_data["Percentage of Total Files"].append(f"{(info['count'] / total_files) * 100:.2f}%" if total_files else "0.00%")
        file_data["Percentage of Total Size"].append(f"{(info['size'] / total_size) * 100:.2f}%" if total_size else "0.00%")

    file_df = pd.DataFrame(file_data)
    file_df.sort_values(by="Total Size (Bytes)", ascending=False, inplace=True)

    dir_data = {
        "Directory Path": [],
        "File Count": [],
        "Total Size": [],
        "Average File Size": []
    }

    for dirpath, info in dir_info.items():
        dir_data["Directory Path"].append(dirpath)
        dir_data["File Count"].append(info["count"])
        dir_data["Total Size"].append(convert_size(info["size"]))
        dir_data["Average File Size"].append(convert_size(info["size"] // info["count"] if info["count"] else 0))

    dir_df = pd.DataFrame(dir_data)
    dir_df.sort_values(by="Total Size", ascending=False, inplace=True)

    return file_df, dir_df

def save_to_excel(file_df, dir_df, output_file):
    with pd.ExcelWriter(output_file, engine='xlsxwriter') as writer:
        file_df.to_excel(writer, index=False, sheet_name='File Info')
        dir_df.to_excel(writer, index=False, sheet_name='Directory Info')

        workbook = writer.book
        file_worksheet = writer.sheets['File Info']
        dir_worksheet = writer.sheets['Directory Info']

        for col_num, value in enumerate(file_df.columns.values):
            file_worksheet.write(0, col_num, value)
        for col_num, value in enumerate(dir_df.columns.values):
            dir_worksheet.write(0, col_num, value)

def create_pie_chart(file_df, output_file, root_dir):
    # Group file types into major segments
    major_types = file_df.groupby("File Type").sum()
    major_types = major_types.sort_values("Total Size (Bytes)", ascending=False)

    # Define top N types and group the rest as 'Others'
    top_n = 5  # Adjust this value to control how many top file types to show
    top_types = major_types[:top_n]
    other_types = pd.DataFrame(major_types[top_n:].sum()).T
    other_types.index = ["Others"]
    chart_data = pd.concat([top_types, other_types])

    # Plot pie chart with spacing between slices
    plt.figure(figsize=(10, 6))
    wedges, texts, autotexts = plt.pie(
        chart_data["Total Size (Bytes)"], 
        labels=chart_data.index, 
        autopct="%1.1f%%", 
        startangle=140, 
        wedgeprops=dict(width=0.3)
    )

    # Improve the visibility of the text
    for text in texts:
        text.set_fontsize(10)
    for autotext in autotexts:
        autotext.set_fontsize(10)
    
    plt.axis('equal')  # Equal aspect ratio ensures the pie chart is circular.
    plt.title(f"File Type Distribution\nScanned Folder: {root_dir}", fontsize=12)
    
    # Add legend
    plt.legend(wedges, chart_data.index, title="File Types", loc="center left", bbox_to_anchor=(1, 0, 0.5, 1))

    # Save pie chart to a file
    chart_path = output_file.replace(".xlsx", "_chart.png")
    plt.savefig(chart_path, bbox_inches="tight")
    plt.close()

def parse_arguments():
    parser = argparse.ArgumentParser(description="Gather and analyze file information from a directory.")
    parser.add_argument("root_dir", help="The root directory to scan.")
    parser.add_argument("output_file", help="The output Excel file path.")
    parser.add_argument("--include-hidden", action="store_true", help="Include hidden files and directories.")
    parser.add_argument("--log-file", default="error_log.txt", help="Path to the error log file.")
    
    return parser.parse_args()

def main():
    check_required_libraries()
    
    args = parse_arguments()
    
    setup_logging(args.log_file)
    file_info, dir_info = gather_file_info(args.root_dir, args.include_hidden)
    file_df, dir_df = create_output_dataframe(file_info, dir_info)
    save_to_excel(file_df, dir_df, args.output_file)
    create_pie_chart(file_df, args.output_file, args.root_dir)

    print(f"File and directory information has been saved to {args.output_file}")
    print(f"Errors, if any, have been logged to {args.log_file}")

if __name__ == "__main__":
    main()
