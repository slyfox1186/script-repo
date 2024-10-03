# vlc_playlist_creator.py

#!/usr/bin/env python3

import argparse
import os
import platform
import re
import subprocess
import sys
import json
import xml.dom.minidom
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.parse import quote

# Import colorama for cross-platform colored output
try:
    from colorama import init, Fore, Back, Style
except ImportError:
    print("colorama module not found. Please install it using 'pip install colorama'.", file=sys.stderr)
    sys.exit(1)

# Initialize colorama
init(autoreset=True)

# Define color constants with clear contrasts
GREEN = Fore.GREEN + Style.BRIGHT
RED = Fore.RED + Style.BRIGHT
CYAN = Fore.CYAN + Style.BRIGHT
YELLOW = Fore.YELLOW + Style.BRIGHT
WHITE_BG = Back.WHITE
RESET_ALL = Style.RESET_ALL

# Define additional color constants for descriptions and values
DESCRIPTION_COLOR = YELLOW
VALUE_COLOR = Fore.WHITE + Style.BRIGHT

# Define symbols with colored backgrounds
SUCCESS_SYMBOL = f"{WHITE_BG}{GREEN}✓{RESET_ALL}"
FAILURE_SYMBOL = f"{WHITE_BG}{RED}✗{RESET_ALL}"

# You must set this to the path of your VLC program as needed. This uses the default vlc.exe installation path.
VLC_PATH = 'C:\\Program Files\\VideoLAN\\VLC\\vlc.exe'

# Set max_workers to the full logical CPU count divided by 2 or 2 whichever is higher
MAX_WORKERS = (os.cpu_count() // 2) if (os.cpu_count() and os.cpu_count() // 2 >= 2) else 2

def is_wsl():
    """
    Determines if the script is running inside WSL (Windows Subsystem for Linux).

    Returns:
        bool: True if running inside WSL, False otherwise.
    """
    try:
        with open('/proc/version', 'r') as f:
            version_info = f.read().lower()
            return 'microsoft' in version_info or 'wsl' in version_info
    except Exception:
        return False

def get_distro_name():
    """
    Retrieves the WSL distribution name by reading /etc/os-release.

    Returns:
        str: Distribution name in the format 'Ubuntu-24.04'.
    """
    distro_name = "UnknownDistro"
    version_id = ""
    try:
        with open('/etc/os-release', 'r') as f:
            for line in f:
                if line.startswith('NAME='):
                    distro_name = line.strip().split('=')[1].strip('"')
                elif line.startswith('VERSION_ID='):
                    version_id = line.strip().split('=')[1].strip('"')
        if version_id:
            return f"{distro_name}-{version_id}"
        else:
            return distro_name
    except Exception as e:
        print(f"\n{RED}Error retrieving distribution name: {e}{RESET_ALL}", file=sys.stderr)
        return "UnknownDistro"

def natural_sort_key(path):
    """
    Generates a natural sort key for sorting file paths.

    Args:
        path (Path): The file path.

    Returns:
        list: A list of strings and integers for natural sorting.
    """
    name = path.name
    return [int(text) if text.isdigit() else text.lower() for text in re.split(r'(\d+)', name)]

def get_video_files(start_dir, video_extensions, recursive=True, verbose=False):
    """
    Scan the start_dir for files with extensions in video_extensions.
    Returns a sorted list of absolute POSIX paths.

    Args:
        start_dir (Path): The directory to scan.
        video_extensions (tuple): Tuple of video file extensions to look for.
        recursive (bool): Whether to search directories recursively.
        verbose (bool): Whether to print verbose logs.

    Returns:
        list of Path: Sorted list of video file paths.
    """
    video_files = []
    if recursive:
        if verbose:
            print(f"{CYAN}Scanning directories recursively in '{start_dir}' for video files...{RESET_ALL}")
        for root, dirs, files in os.walk(start_dir):
            for file in files:
                if file.lower().endswith(video_extensions):
                    full_path = os.path.join(root, file)
                    video_files.append(Path(full_path).resolve())
    else:
        if verbose:
            print(f"{CYAN}Scanning directory '{start_dir}' for video files (non-recursive)...{RESET_ALL}")
        for file in os.listdir(start_dir):
            full_path = start_dir / file
            if full_path.is_file() and file.lower().endswith(video_extensions):
                video_files.append(full_path.resolve())
    # Sort the video files naturally
    video_files.sort(key=natural_sort_key)
    if verbose:
        print(f"{CYAN}Found {len(video_files)} video file{'s' if len(video_files) != 1 else ''}:")
        for vf in video_files:
            print(f"  - {vf}")
    return video_files

def get_video_info(unix_path, verbose=False):
    """
    Retrieves video metadata using ffprobe in JSON format.
    Extracts duration, resolution, codec, bitrate, fps, bit-depth.

    Args:
        unix_path (Path): The video file path.
        verbose (bool): Whether to print verbose logs.

    Returns:
        dict: Dictionary containing 'duration' (int) in milliseconds,
              'resolution' (tuple) as (width, height),
              'codec' (str),
              'bitrate' (int) in kbps,
              'fps' (float),
              'bit_depth' (int)
    """
    try:
        if verbose:
            print(f"{CYAN}Running ffprobe on '{unix_path}'...{RESET_ALL}")
        # Run ffprobe to get detailed metadata in JSON
        result = subprocess.run(
            [
                'ffprobe',
                '-v', 'error',
                '-print_format', 'json',
                '-show_format',
                '-show_streams',
                str(unix_path)
            ],
            capture_output=True,
            text=True,
            check=True
        )
        data = json.loads(result.stdout)
        
        # Extract format information
        format_info = data.get('format', {})
        duration_seconds = float(format_info.get('duration', 0))
        duration_milliseconds = int(duration_seconds * 1000)
        bitrate_kbps = int(format_info.get('bit_rate', 0)) // 1000  # Convert to kbps

        # Extract stream information (video stream)
        streams = data.get('streams', [])
        video_stream = None
        for stream in streams:
            if stream.get('codec_type') == 'video':
                video_stream = stream
                break
        if not video_stream:
            raise ValueError("No video stream found.")

        width = int(video_stream.get('width', 0))
        height = int(video_stream.get('height', 0))
        codec = video_stream.get('codec_name', 'unknown').lower()
        r_frame_rate = video_stream.get('r_frame_rate', '0/0')
        try:
            num, denom = map(int, r_frame_rate.split('/'))
            fps = num / denom if denom != 0 else 0
        except:
            fps = 0.0
        bit_depth = int(video_stream.get('bits_per_raw_sample', 8))  # Default to 8 if not available

        if verbose:
            print(f"{GREEN}Retrieved info for '{unix_path.name}': Duration={duration_milliseconds}ms, "
                  f"Resolution={width}x{height}, Codec={codec}, Bitrate={bitrate_kbps}kbps, "
                  f"FPS={fps}, Bit-depth={bit_depth}{RESET_ALL}")

        return {
            'duration': duration_milliseconds,
            'resolution': (width, height),
            'codec': codec,
            'bitrate': bitrate_kbps,
            'fps': fps,
            'bit_depth': bit_depth
        }

    except subprocess.CalledProcessError as e:
        print(f"\n{RED}Error retrieving info for {unix_path}: {e}{RESET_ALL}", file=sys.stderr)
        return {'duration': 0, 'resolution': (0, 0), 'codec': 'unknown', 'bitrate': 0, 'fps': 0.0, 'bit_depth': 0}
    except (ValueError, IndexError, KeyError) as e:
        print(f"\n{RED}Invalid info format for {unix_path}: {e}{RESET_ALL}", file=sys.stderr)
        return {'duration': 0, 'resolution': (0, 0), 'codec': 'unknown', 'bitrate': 0, 'fps': 0.0, 'bit_depth': 0}

def calculate_quality_score(info):
    """
    Calculates a quality score based on video metadata.

    Args:
        info (dict): Dictionary containing video metadata.

    Returns:
        float: Quality score.
    """
    score = 0.0

    # Encoder type weights
    codec_weights = {
        'hevc': 5,
        'x265': 5,
        'vp9': 4,
        'h264': 3,
        'x264': 3,
        'av1': 6
    }
    codec = info.get('codec', 'unknown')
    codec_weight = codec_weights.get(codec, 2)  # Default weight for unknown codecs
    score += codec_weight

    # Resolution weight (more pixels = higher score)
    width, height = info.get('resolution', (0, 0))
    resolution_pixels = width * height
    # Normalize resolution to a scale, e.g., 1080p=1920*1080=2073600
    resolution_weight = resolution_pixels / 1000000  # e.g., 2073600 / 1000000 = ~2.07
    score += resolution_weight

    # Bitrate weight (higher bitrate = higher score)
    bitrate = info.get('bitrate', 0)  # in kbps
    bitrate_weight = bitrate / 1000  # e.g., 5000 kbps = 5
    score += bitrate_weight

    # FPS weight (higher fps = higher score)
    fps = info.get('fps', 0.0)
    fps_weight = fps / 60  # Assuming 60 fps is very high, scale accordingly
    score += fps_weight

    # Bit-depth weight (higher bit-depth = higher score)
    bit_depth = info.get('bit_depth', 8)
    bit_depth_weight = (bit_depth - 8) * 1.5  # e.g., 10-bit = (10-8)*1.5 = 3
    if bit_depth > 8:
        score += bit_depth_weight

    return score


def prettify_xml(tree):
    """
    Return a pretty-printed XML string for the ElementTree with tab indentation.

    Args:
        tree (ElementTree): The XML tree to prettify.

    Returns:
        str: Pretty-printed XML string with tabs.
    """
    rough_string = ET.tostring(tree.getroot(), 'utf-8')
    reparsed = xml.dom.minidom.parseString(rough_string)
    # Use tab for indentation
    return reparsed.toprettyxml(indent="\t", encoding="UTF-8").decode('utf-8')

def create_xspf_playlist(unix_paths, durations, distro_name, environment, verbose=False):
    """
    Creates an XSPF playlist XML structure with VLC extensions.
    Returns the XML as a string.

    Args:
        unix_paths (list of Path): List of UNIX paths to video files.
        durations (list of int): List of video durations in milliseconds.
        distro_name (str): The WSL distribution name.
        environment (str): 'wsl' or 'windows'
        verbose (bool): Whether to print verbose logs.

    Returns:
        str: Pretty-printed XSPF XML content.
    """
    # Define namespaces
    NS_XSPF = "http://xspf.org/ns/0/"
    NS_VLC = "http://www.videolan.org/vlc/playlist/ns/0/"
    ET.register_namespace('', NS_XSPF)  # Default namespace
    ET.register_namespace('vlc', NS_VLC)  # VLC namespace

    # Create root element with namespace
    playlist = ET.Element(f"{{{NS_XSPF}}}playlist", attrib={"version": "1"})

    # Add title
    title = ET.SubElement(playlist, 'title')
    title.text = "Playlist"

    # Create trackList
    trackList = ET.SubElement(playlist, 'trackList')

    # Add tracks
    for idx, (path, duration) in enumerate(zip(unix_paths, durations)):
        track = ET.SubElement(trackList, 'track')
        
        # Location
        location = ET.SubElement(track, 'location')
        if environment == 'wsl':
            # In WSL, check if the path is in Windows filesystem
            if is_windows_path(path):
                # Convert to Windows path
                windows_path = convert_to_windows_path(str(path))
                if windows_path:
                    location.text = "file:///{0}".format(windows_path.replace('\\', '/'))
                else:
                    print(f"\n{RED}Skipping file due to path conversion failure: {path}{RESET_ALL}", file=sys.stderr)
                    continue
            else:
                # WSL filesystem path
                formatted_path = path.as_posix().lstrip('/')
                location.text = f"file://wsl.localhost/{distro_name}/{formatted_path}"
        elif environment == 'windows':
            windows_path = str(path).replace('\\', '/')
            # URL-encode the path
            encoded_path = quote(windows_path, safe='/')
            location.text = f"file:///{encoded_path}"
        else:
            # Fallback to absolute path and URL-encode it
            encoded_path = quote(path.as_posix(), safe='/')
            location.text = f"file:///{encoded_path}"

        # Duration
        duration_elem = ET.SubElement(track, 'duration')
        duration_elem.text = str(duration)
        
        # Extension with vlc:id
        extension = ET.SubElement(track, 'extension', application="http://www.videolan.org/vlc/playlist/ns/0/")
        vlc_id = ET.SubElement(extension, f"{{{NS_VLC}}}id")
        vlc_id.text = str(idx)
    
    # VLC extension for playlist items
    playlist_extension = ET.SubElement(playlist, 'extension', application="http://www.videolan.org/vlc/playlist/ns/0/")
    for idx in range(len(unix_paths)):
        vlc_item = ET.SubElement(playlist_extension, f"{{{NS_VLC}}}item", tid=str(idx))
    
    if verbose:
        print(f"{CYAN}Creating XSPF playlist with {len(unix_paths)} tracks...{RESET_ALL}")

    # Generate pretty XML with tab indentation
    xml_string = ET.tostring(playlist, encoding='utf-8')
    parsed_xml = ET.ElementTree(ET.fromstring(xml_string))
    pretty_xml = prettify_xml(parsed_xml)

    if verbose:
        print(f"{GREEN}XSPF playlist XML generated successfully.{RESET_ALL}")

    return pretty_xml

def is_windows_path(path):
    """
    Determines if the given path is a Windows filesystem path.

    Args:
        path (Path): The file path.

    Returns:
        bool: True if path is in Windows filesystem, False otherwise.
    """
    posix = path.as_posix()
    # Check for various possible Windows path patterns
    return (posix.startswith('/mnt/') or 
            posix.startswith('/c/') or
            re.match(r'^/[A-Za-z]/', posix) is not None or
            '/Windows/' in posix)

def convert_to_windows_path(unix_path):
    """
    Converts a UNIX path to a Windows path using wslpath -w.
    Returns the Windows path as a string.

    Args:
        unix_path (str): The UNIX path to convert.

    Returns:
        str or None: Windows path string or None if conversion fails.
    """
    try:
        result = subprocess.run(
            ['wslpath', '-w', unix_path],
            capture_output=True,
            text=True,
            check=True
        )
        windows_path = result.stdout.strip()
        return windows_path
    except subprocess.CalledProcessError as e:
        print(f"\n{RED}Error converting path {unix_path} to Windows path: {e}{RESET_ALL}", file=sys.stderr)
        return None

def convert_to_wsl_path(windows_path):
    """
    Converts a Windows path to a WSL-compatible UNIX path using wslpath -u.
    Returns the UNIX path as a string.

    Args:
        windows_path (str): The Windows path to convert.

    Returns:
        str or None: UNIX path string or None if conversion fails.
    """
    try:
        result = subprocess.run(
            ['wslpath', '-u', windows_path],
            capture_output=True,
            text=True,
            check=True
        )
        unix_path = result.stdout.strip()
        return unix_path
    except subprocess.CalledProcessError as e:
        print(f"\n{RED}Error converting path {windows_path} to WSL path: {e}{RESET_ALL}", file=sys.stderr)
        return None

def get_windows_cmd_path(verbose=False):
    """
    Get the WSL path to cmd.exe using wslpath.
    """
    windows_cmd_path = r'C:\Windows\System32\cmd.exe'
    try:
        result = subprocess.run(
            ['wslpath', '-u', windows_cmd_path],
            capture_output=True,
            text=True,
            check=True
        )
        wsl_cmd_path = result.stdout.strip()
        if verbose:
            print(f"{CYAN}Found cmd.exe at: {wsl_cmd_path}{RESET_ALL}")
        return wsl_cmd_path
    except subprocess.CalledProcessError as e:
        print(f"{RED}Error converting Windows cmd path to WSL path: {e}{RESET_ALL}", file=sys.stderr)
        return None

def parse_arguments():
    """
    Parses command-line arguments.

    Returns:
        argparse.Namespace: Parsed arguments.
    """
    parser = argparse.ArgumentParser(
        description="""
Generate a VLC-compatible XSPF playlist from video files in a specified directory.

This script scans the current directory for video files with specified extensions,
extracts their durations, resolutions, and other metadata, and compiles them into an XSPF playlist file compatible with VLC Media Player.

Usage Examples:
    - Scan the current directory non-recursively and generate a playlist:
        python3 vlc_playlist_creator.py

    - Scan the current directory and all subdirectories recursively:
        python3 vlc_playlist_creator.py -r

    - Scan recursively and open the playlist with VLC:
        python3 vlc_playlist_creator.py -r -p

    - Specify a custom output file path:
        python3 vlc_playlist_creator.py -o /c/home/jman/tmp/mp4/vlc_test_playlist.xspf

    - Sort the playlist by video quality:
        python3 vlc_playlist_creator.py -q

    - Enable verbose logging:
        python3 vlc_playlist_creator.py -v

    - Display help message:
        python3 vlc_playlist_creator.py -h
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument('-r', '--recursive', action='store_true',
        help='Enable recursive searching for video files in all subdirectories.'
    )
    parser.add_argument('-p', '--play', action='store_true',
        help='Open the generated playlist with VLC Media Player after creation.'
    )
    parser.add_argument('-o', '--output-file', type=str, default='vlc.xspf',
        help='Set the relative or full path to the output VLC playlist file. Example: /home/user_name/tmp/mp4/vlc_test_playlist.xspf or mp4/vlc_test_playlist.xspf'
    )
    parser.add_argument('-q', '--quality', action='store_true',
        help='Sort the playlist by video quality instead of alphanumerically.'
    )
    parser.add_argument('-v', '--verbose', action='store_true',
        help='Enable verbose logging for detailed output.'
    )

    return parser.parse_args()

def main():
    # Parse command-line arguments
    args = parse_arguments()
    recursive_search = args.recursive
    open_vlc = args.play
    output_file = args.output_file
    sort_by_quality = args.quality
    verbose = args.verbose

    # Detect the execution environment
    wsl = is_wsl()
    environment = 'wsl' if wsl else 'windows'

    if verbose:
        print(f"{CYAN}Detected environment: {environment.upper()}{RESET_ALL}")

    # Retrieve WSL distribution name dynamically if in WSL
    if wsl:
        distro_name = get_distro_name()
        if distro_name == "UnknownDistro":
            print(f"{RED}Unable to determine WSL distribution name. Please ensure you're running within a WSL environment.{RESET_ALL}", file=sys.stderr)
            sys.exit(1)
        if verbose:
            print(f"{CYAN}WSL Distribution Name: {distro_name}{RESET_ALL}")
    else:
        distro_name = None  # Not needed in native Windows

    # Define video file extensions to look for
    video_extensions = ('.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mpeg', '.mpg', '.m4v')

    # Determine the directory to scan (current working directory)
    start_dir = Path.cwd()

    # Define the output playlist path
    output_playlist = Path(output_file).expanduser().resolve()

    if verbose:
        print(f"{CYAN}Output playlist will be saved to: {output_playlist}{RESET_ALL}")

    # Ensure the output directory exists
    output_dir = output_playlist.parent
    try:
        output_dir.mkdir(parents=True, exist_ok=True)
        if verbose:
            print(f"{CYAN}Ensured that the output directory exists: {output_dir}{RESET_ALL}")
    except Exception as e:
        print(f"\n{RED}Error creating directories for the output file: {e}{RESET_ALL}", file=sys.stderr)
        sys.exit(1)

    # Get list of video files
    video_files = get_video_files(start_dir, video_extensions, recursive=recursive_search, verbose=verbose)

    if not video_files:
        if recursive_search:
            print(f"{RED}No video files found in the specified directory and its subdirectories.{RESET_ALL}")
        else:
            print(f"{RED}No video files found in the current directory.{RESET_ALL}")
        sys.exit(0)
    
    print(f"{CYAN}Found {len(video_files)} video file{'s' if len(video_files) != 1 else ''}.\n{RESET_ALL}")

    # Determine max_workers based on CPU count
    cpu_count = MAX_WORKERS
    max_workers = cpu_count

    if verbose:
        print(f"{CYAN}Using ThreadPoolExecutor with max_workers={max_workers} to retrieve video information.{RESET_ALL}\n")

    # Calculate the dynamic width based on the longest file name
    if video_files:
        fixed_width = max(len(video.name) for video in video_files) + 5  # Add padding to ensure proper alignment
    else:
        fixed_width = 30  # Fallback if no files are found

    # Process video files and retrieve durations and resolutions with colorized output
    video_infos = [{'duration': 0, 'resolution': (0, 0), 'codec': 'unknown', 'bitrate': 0, 'fps': 0.0, 'bit_depth': 0} for _ in video_files]
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_index = {executor.submit(get_video_info, path, verbose): idx for idx, path in enumerate(video_files)}

        for future in as_completed(future_to_index):
            idx = future_to_index[future]
            try:
                info = future.result()
                video_infos[idx] = info
                # Indicating successful processing with a green check mark in a white box, aligned with file name
                print(f"{Fore.BLUE}Processing:{RESET_ALL} {video_files[idx].name.ljust(fixed_width)} {SUCCESS_SYMBOL} {RESET_ALL}")
            except Exception as e:
                # Indicating an error with a red cross in a white box, aligned with file name
                print(f"\n{RED}Error retrieving info for {video_files[idx].name}: {e}{RESET_ALL}", file=sys.stderr)
                print(f"{Fore.BLUE}Processing:{RESET_ALL} {video_files[idx].name.ljust(fixed_width)} {FAILURE_SYMBOL}")
                print(f"{Fore.BLUE}Duration:{RESET_ALL} [Error] {FAILURE_SYMBOL}\n")

    # Now sort the video_files and video_infos based on the sort_by_quality flag
    if sort_by_quality:
        if verbose:
            print(f"{CYAN}Sorting playlist by video quality...{RESET_ALL}")
        # Calculate quality scores
        combined = list(zip(video_files, video_infos))
        combined_with_scores = [(video, info, calculate_quality_score(info)) for video, info in combined]
        # Sort by quality score descending
        combined_sorted = sorted(combined_with_scores, key=lambda x: x[2], reverse=True)
        # Unzip back to video_files and video_infos
        if combined_sorted:
            video_files_sorted, video_infos_sorted, scores_sorted = zip(*combined_sorted)
            video_files = list(video_files_sorted)
            video_infos = list(video_infos_sorted)
            if verbose:
                print(f"{CYAN}Playlist sorted by video quality (encoder, resolution, bitrate, fps, bit-depth).{RESET_ALL}")
                print(f"{CYAN}Top 5 highest quality videos:{RESET_ALL}")
                for i in range(min(5, len(video_files))):
                    score = scores_sorted[i]
                    print(f"  {i+1}. {video_files[i].name} - Score: {score:.2f}")
            else:
                print(f"{CYAN}Playlist sorted by video quality (encoder, resolution, bitrate, fps, bit-depth).{RESET_ALL}\n")
        else:
            print(f"{RED}No valid video information to sort by quality.{RESET_ALL}\n")
    else:
        if verbose:
            print(f"{CYAN}Sorting playlist alphanumerically by filename...{RESET_ALL}")
        # Sort alphanumerically based on natural_sort_key
        combined = list(zip(video_files, video_infos))
        combined_sorted = sorted(combined, key=lambda x: natural_sort_key(x[0]))
        if combined_sorted:
            video_files_sorted, video_infos_sorted = zip(*combined_sorted)
            video_files = list(video_files_sorted)
            video_infos = list(video_infos_sorted)
            if verbose:
                print(f"{CYAN}Playlist sorted alphanumerically by filename.{RESET_ALL}")
                print(f"{CYAN}First 5 videos in sorted order:{RESET_ALL}")
                for i in range(min(5, len(video_files))):
                    print(f"  {i+1}. {video_files[i].name}")
            else:
                print(f"{CYAN}Playlist sorted alphanumerically by filename.{RESET_ALL}\n")
        else:
            print(f"{RED}No video files to sort.{RESET_ALL}\n")

    # Now Create XSPF playlist content using appropriate paths, if durations and video_files are valid.
    if video_files and video_infos:
        # Extract durations for playlist creation
        durations = [info['duration'] for info in video_infos]
        xspf_content = create_xspf_playlist(video_files, durations, distro_name, environment, verbose)
    else:
        print(f"{RED}Error: No valid video files or durations found, unable to create playlist.{RESET_ALL}")
        sys.exit(1)  # Exit gracefully if something went wrong

    # Write the XSPF content to the output file with correct encoding
    try:
        with open(output_playlist, 'w', encoding='utf-8') as f:
            f.write(xspf_content)
        print(f"\n{DESCRIPTION_COLOR}Playlist successfully created at:{RESET_ALL} {VALUE_COLOR}{output_playlist}{RESET_ALL}\n")
    except Exception as e:
        print(f"\n{RED}Error writing playlist to {output_playlist}: {e}{RESET_ALL}", file=sys.stderr)
        sys.exit(1)

    # Conditionally open the playlist with VLC if the --play flag is set
    if open_vlc:
        if environment == 'wsl':
            # Define the Windows VLC executable path
            vlc_windows_path = VLC_PATH
            # Convert to WSL path
            mixed_vlc_path = convert_to_wsl_path(vlc_windows_path)
            if not mixed_vlc_path:
                print(f"{RED}Failed to convert VLC executable path to WSL format.{RESET_ALL}", file=sys.stderr)
                sys.exit(1)
            vlc_executable = mixed_vlc_path
            if verbose:
                print(f"{DESCRIPTION_COLOR}Using VLC executable path in WSL:{RESET_ALL} {VALUE_COLOR}{mixed_vlc_path}{RESET_ALL}")
        else:
            # Native Windows environment
            vlc_executable = VLC_PATH
            if verbose:
                print(f"{DESCRIPTION_COLOR}Using VLC executable path on Windows:{RESET_ALL} {VALUE_COLOR}{vlc_executable}{RESET_ALL}")

        # Verify that the VLC executable exists
        if not Path(vlc_executable).exists():
            print(f"\n{RED}VLC executable not found at: {vlc_executable}{RESET_ALL}", file=sys.stderr)
            sys.exit(1)

        # Determine the playlist path based on environment
        if environment == 'wsl':
            # Convert the playlist path to Windows format
            mixed_playlist_path = convert_to_windows_path(str(output_playlist))
            if not mixed_playlist_path:
                print(f"{RED}Failed to convert playlist path to Windows format.{RESET_ALL}", file=sys.stderr)
                sys.exit(1)
            if verbose:
                print(f"{DESCRIPTION_COLOR}Converted playlist path for VLC:{RESET_ALL} {VALUE_COLOR}{mixed_playlist_path}{RESET_ALL}")
        else:
            # Native Windows environment
            mixed_playlist_path = str(output_playlist)
            if verbose:
                print(f"{DESCRIPTION_COLOR}Converted playlist path for VLC:{RESET_ALL} {VALUE_COLOR}{mixed_playlist_path}{RESET_ALL}")
        
        # Launch VLC
        try:
            if verbose:
                print(f"{CYAN}Attempting to launch VLC...{RESET_ALL}")
                print(f"{CYAN}Environment: {environment}{RESET_ALL}")
                print(f"{CYAN}VLC executable: {vlc_executable}{RESET_ALL}")
                print(f"{CYAN}Playlist path: {mixed_playlist_path}{RESET_ALL}")
            
            # Use subprocess.Popen to launch VLC without waiting, redirecting output
            with open(os.devnull, 'w') as devnull:
                subprocess.Popen([vlc_executable, mixed_playlist_path], 
                                 start_new_session=True, 
                                 stdout=devnull, 
                                 stderr=devnull)
            
            print(f"{GREEN}VLC Media Player has been launched with the generated playlist.{RESET_ALL}")
        except subprocess.CalledProcessError as e:
            print(f"{RED}Error opening playlist with VLC: {e}{RESET_ALL}", file=sys.stderr)
        except FileNotFoundError:
            print(f"{RED}VLC Media Player is not installed or not found at the specified path.{RESET_ALL}", file=sys.stderr)

if __name__ == "__main__":
    main()
