#!/usr/bin/env python3
"""
Find all image files (JPG, JPEG, PNG, WebP) recursively and display the top N largest per directory.
Uses parallel processing for maximum performance.
"""

import os
import argparse
import time
from pathlib import Path
from collections import defaultdict
from typing import List, Tuple, Optional, Dict
from concurrent.futures import ThreadPoolExecutor, as_completed
from functools import partial

ALL_IMAGE_EXTENSIONS = ('.jpg', '.jpeg', '.png', '.webp')

def format_size(size_bytes: int) -> str:
    """Convert bytes to human-readable format."""
    units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
    size = size_bytes
    unit_idx = 0
    while size >= 1024 and unit_idx < len(units) - 1:
        size /= 1024.0
        unit_idx += 1
    return f"{size:.2f} {units[unit_idx]}"

def process_file(file_info: Tuple[Path, str], exclude_patterns: List[str]) -> Optional[Tuple[Path, Path, int]]:
    """
    Process a single file to check if it should be excluded and get its size.
    
    Args:
        file_info: Tuple of (dirpath: Path, filename: str)
        exclude_patterns: List of patterns to exclude
        
    Returns:
        Tuple of (dirpath, full_path, size) or None if excluded/invalid
    """
    dirpath, filename = file_info
    file_path = dirpath / filename
    
    # Check if file should be excluded
    file_path_str = str(file_path)
    for pattern in exclude_patterns:
        if pattern in file_path_str:
            return None
    
    try:
        file_size = file_path.stat().st_size
        return (dirpath, file_path, file_size)
    except OSError:
        # Skip files that can't be accessed
        return None

def get_potential_image_files(root_dir: Path, extensions: Tuple[str, ...], recursive: bool = True) -> List[Tuple[Path, str]]:
    """
    Get all potential image files in directory tree as a list for parallel processing.
    
    Args:
        root_dir: Root directory to search
        extensions: Tuple of file extensions to match
        recursive: If True, search subdirectories; if False, only search root_dir
    
    Returns:
        List of (dirpath: Path, filename: str) tuples
    """
    all_files = []
    if recursive:
        for dirpath_str, _, filenames in os.walk(str(root_dir)):
            dirpath = Path(dirpath_str).resolve()
            for filename in filenames:
                if filename.lower().endswith(extensions):
                    all_files.append((dirpath, filename))
    else:
        dirpath = root_dir.resolve()
        for entry in dirpath.iterdir():
            if entry.is_file() and entry.name.lower().endswith(extensions):
                all_files.append((dirpath, entry.name))
    return all_files

def process_batch(batch: List[Tuple[Path, str]], exclude_patterns: List[str]) -> List[Tuple[Path, Path, int]]:
    """
    Process a batch of files.
    
    Args:
        batch: List of (dirpath: Path, filename: str) tuples
        exclude_patterns: List of patterns to exclude
        
    Returns:
        List of (dirpath, full_path, size) tuples for valid image files
    """
    results = []
    for file_info in batch:
        result = process_file(file_info, exclude_patterns)
        if result:
            results.append(result)
    return results

def find_images_parallel(root_dir: str = '.', exclude_patterns: Optional[List[str]] = None, extensions: Optional[Tuple[str, ...]] = None, recursive: bool = True) -> Dict[str, List[Tuple[str, int]]]:
    """
    Find all image files using parallel processing.
    
    Args:
        root_dir: Root directory to search in
        exclude_patterns: List of text patterns to exclude from results
        extensions: Tuple of file extensions to search for
        recursive: If True, search subdirectories; if False, only search root_dir
        
    Returns:
        Dictionary mapping directory paths (str) to list of (file_path: str, size: int) tuples.
    """
    start_time = time.perf_counter()
    root_path = Path(root_dir).resolve()
    exclude_patterns = exclude_patterns or []
    extensions = extensions or ALL_IMAGE_EXTENSIONS
    images_by_dir: Dict[str, List[Tuple[str, int]]] = defaultdict(list)
    
    # Get potential image files first
    ext_list = ', '.join(extensions)
    mode = "recursively" if recursive else "in top-level directory only"
    print(f"Scanning {mode} for image files ({ext_list})...")
    potential_files = get_potential_image_files(root_path, extensions, recursive)
    
    if not potential_files:
        return images_by_dir
    
    print(f"Found {len(potential_files)} potential image files")
    
    # Determine optimal number of workers
    num_cores = os.cpu_count() or 1
    num_workers = min(num_cores * 4, len(potential_files), 64)  # More workers since threads are lightweight
    
    print(f"Processing with {num_workers} parallel threads on {num_cores} CPU cores...")
    
    # Split files into batches for processing
    batch_size = max(1, len(potential_files) // (num_workers * 4))  # Create more batches than workers
    batches = [potential_files[i:i + batch_size] for i in range(0, len(potential_files), batch_size)]
    
    # Process batches in parallel
    valid_image_files = []
    
    with ThreadPoolExecutor(max_workers=num_workers) as executor:
        # Submit all batch processing tasks
        future_to_batch = {
            executor.submit(process_batch, batch, exclude_patterns): batch
            for batch in batches
        }
        
        # Collect results as they complete
        for future in as_completed(future_to_batch):
            try:
                batch_results = future.result()
                valid_image_files.extend(batch_results)
            except Exception as e:
                print(f"Error processing batch: {e}")
    
    # Group results by directory
    for dirpath, file_path, file_size in valid_image_files:
        dir_str = str(dirpath)
        file_str = str(file_path)
        images_by_dir[dir_str].append((file_str, file_size))
    
    # Count skipped files
    skipped_count = len(potential_files) - len(valid_image_files)
    
    if skipped_count > 0 and exclude_patterns:
        print(f"Skipped {skipped_count} files matching exclude patterns: {', '.join(exclude_patterns)}")
        print()
    
    print(f"Processed {len(valid_image_files)} image files")
    elapsed = time.perf_counter() - start_time
    print(f"Processing time: {elapsed:.2f} seconds")
    print()
    
    return images_by_dir

def display_results(images_by_dir: Dict[str, List[Tuple[str, int]]], top_n: int = 5) -> None:
    """Display the top N largest images per directory."""
    if not images_by_dir:
        print("No image files found in the directory tree.")
        return
    
    # Sort directories alphabetically
    sorted_dirs = sorted(images_by_dir.keys())
    
    print("=" * 80)
    print(f"Images by Directory (Top {top_n} Largest per Directory)")
    print("=" * 80)
    
    total_images = 0
    total_size = 0
    
    for dir_path in sorted_dirs:
        images = images_by_dir[dir_path]
        # Sort images by size (descending)
        images.sort(key=lambda x: x[1], reverse=True)
        
        # Take only the top N
        top_images = images[:top_n]
        
        print(f"\nDirectory: {dir_path}")
        print(f"Total image files in directory: {len(images)}")
        print("-" * 80)
        
        for i, (file_path, size) in enumerate(top_images, 1):
            filename = os.path.basename(file_path)
            print(f"  {i}. {filename}")
            print(f"     Full path: {file_path}")
            print(f"     Size: {format_size(size)} ({size:,} bytes)")
            print()
        
        # Calculate directory totals
        dir_total_size = sum(size for _, size in images)
        total_images += len(images)
        total_size += dir_total_size
        
        print(f"  Directory total: {len(images)} files, {format_size(dir_total_size)}")
        print("-" * 80)
    
    # Display overall summary
    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Total directories with images: {len(images_by_dir)}")
    print(f"Total image files found: {total_images}")
    print(f"Total size of all images: {format_size(total_size)}")
    
    # Find and display the absolute largest files across all directories
    all_images = []
    for images in images_by_dir.values():
        all_images.extend(images)
    
    if all_images:
        all_images.sort(key=lambda x: x[1], reverse=True)
        top_n_overall = all_images[:top_n]
        
        print("\n" + "=" * 80)
        print(f"TOP {top_n} LARGEST IMAGE FILES OVERALL")
        print("=" * 80)
        
        for i, (file_path, size) in enumerate(top_n_overall, 1):
            print(f"{i}. {os.path.basename(file_path)}")
            print(f"   Full path: {file_path}")
            print(f"   Size: {format_size(size)} ({size:,} bytes)")
            print()

def main():
    """Main function to find and display largest image files."""
    # Set up argument parser
    parser = argparse.ArgumentParser(
        description="Find all image files (JPG, JPEG, PNG, WebP) and display the top N largest per directory.",
        epilog="Example: %(prog)s -d /photos --jpg --png -r -e='-IM'"
    )
    parser.add_argument(
        "-d", "--dir",
        default=".",
        dest="root_dir",
        help="Directory to search (default: current directory)"
    )
    parser.add_argument(
        "-r", "--recursive",
        action="store_true",
        help="Search subdirectories recursively (default: top-level only)"
    )
    parser.add_argument(
        "-e", "--exclude",
        action="append",
        dest="exclude_patterns",
        default=[],
        help="Exclude files containing this text in their path. Use -e=PATTERN for patterns starting with dash"
    )
    parser.add_argument(
        "-n", "--top",
        type=int,
        default=5,
        help="Number of largest files to display per directory (default: 5)"
    )
    parser.add_argument(
        "--jpg",
        action="store_true",
        help="Include .jpg files"
    )
    parser.add_argument(
        "--jpeg",
        action="store_true",
        help="Include .jpeg files"
    )
    parser.add_argument(
        "--png",
        action="store_true",
        help="Include .png files"
    )
    parser.add_argument(
        "--webp",
        action="store_true",
        help="Include .webp files"
    )
    
    args = parser.parse_args()
    
    # Build extensions tuple from flags; if none specified, use all
    ext_map = {
        'jpg': '.jpg',
        'jpeg': '.jpeg',
        'png': '.png',
        'webp': '.webp',
    }
    selected = [ext for key, ext in ext_map.items() if getattr(args, key)]
    extensions = tuple(selected) if selected else ALL_IMAGE_EXTENSIONS
    
    # Resolve root directory
    root_path = Path(args.root_dir).resolve()
    print(f"Searching for image files in: {root_path}")
    print(f"Extensions: {', '.join(extensions)}")
    print(f"Recursive: {'yes' if args.recursive else 'no'}")
    
    if args.exclude_patterns:
        print(f"Excluding patterns: {', '.join(args.exclude_patterns)}")
    print()
    
    # Find all images using parallel processing
    images_by_dir = find_images_parallel(str(root_path), exclude_patterns=args.exclude_patterns, extensions=extensions, recursive=args.recursive)
    
    # Display results
    display_results(images_by_dir, top_n=args.top)

if __name__ == "__main__":
    main()
