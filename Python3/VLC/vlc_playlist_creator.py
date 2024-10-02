# GitHub: 

#!/usr/bin/env python3

import argparse
import os
import platform
import re
import subprocess
import sys
import xml.dom.minidom
import xml.etree.ElementTree as ET
from pathlib import Path

VLC_PATH = 'C:\\Program Files\\VideoLAN\\VLC\\vlc.exe' # Set this as needed.

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
                    # Extract the value and remove quotes
                    distro_name = line.strip().split('=')[1].strip('"')
                elif line.startswith('VERSION_ID='):
                    version_id = line.strip().split('=')[1].strip('"')
        if version_id:
            return f"{distro_name}-{version_id}"
        else:
            return distro_name
    except Exception as e:
        print(f"Error retrieving distribution name: {e}", file=sys.stderr)
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

def get_video_files(start_dir, video_extensions, recursive=True):
    """
    Scan the start_dir for files with extensions in video_extensions.
    Returns a sorted list of absolute POSIX paths.

    Args:
        start_dir (Path): The directory to scan.
        video_extensions (tuple): Tuple of video file extensions to look for.
        recursive (bool): Whether to search directories recursively.

    Returns:
        list of Path: Sorted list of video file paths.
    """
    video_files = []
    if recursive:
        for root, dirs, files in os.walk(start_dir):
            for file in files:
                if file.lower().endswith(video_extensions):
                    full_path = os.path.join(root, file)
                    video_files.append(Path(full_path).resolve())
    else:
        for file in os.listdir(start_dir):
            full_path = start_dir / file
            if full_path.is_file() and file.lower().endswith(video_extensions):
                video_files.append(full_path.resolve())
    # Sort the video files naturally
    video_files.sort(key=natural_sort_key)
    return video_files

def get_video_duration(unix_path):
    """
    Retrieves the duration of the video file in milliseconds using ffprobe.
    Returns the duration as an integer.

    Args:
        unix_path (Path): The video file path.

    Returns:
        int: Duration in milliseconds. Returns 0 if retrieval fails.
    """
    try:
        result = subprocess.run(
            [
                'ffprobe',
                '-v', 'error',
                '-select_streams', 'v:0',
                '-show_entries', 'format=duration',
                '-of', 'default=noprint_wrappers=1:nokey=1',
                str(unix_path)
            ],
            capture_output=True,
            text=True,
            check=True
        )
        duration_seconds = float(result.stdout.strip())
        duration_milliseconds = int(duration_seconds * 1000)
        return duration_milliseconds
    except subprocess.CalledProcessError as e:
        print(f"Error retrieving duration for {unix_path}: {e}", file=sys.stderr)
        return 0
    except ValueError:
        print(f"Invalid duration format for {unix_path}.", file=sys.stderr)
        return 0

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

def create_xspf_playlist(unix_paths, durations, distro_name, environment):
    """
    Creates an XSPF playlist XML structure with VLC extensions.
    Returns the XML as a string.

    Args:
        unix_paths (list of Path): List of UNIX paths to video files.
        durations (list of int): List of video durations in milliseconds.
        distro_name (str): The WSL distribution name.
        environment (str): 'wsl' or 'windows'

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
        # Determine the correct file URL based on environment and file location
        if environment == 'wsl':
            # In WSL, check if the path is in Windows filesystem
            if is_windows_path(path):
                # Convert to Windows path
                windows_path = convert_to_windows_path(str(path))
                if windows_path:
                    location.text = f"file:///{windows_path.replace('\\', '/')}"
                else:
                    print(f"Skipping file due to path conversion failure: {path}", file=sys.stderr)
                    continue
            else:
                # WSL filesystem path
                formatted_path = path.as_posix().lstrip('/')
                location.text = f"file://wsl.localhost/{distro_name}/{formatted_path}"
        elif environment == 'windows':
            # Native Windows environment
            windows_path = str(path)
            # Ensure backslashes are replaced with forward slashes and colon after drive letter
            windows_path = windows_path.replace('\\', '/')
            # Handle paths that start with a drive letter
            if not re.match(r'^[A-Za-z]:/', windows_path):
                # If path does not start with drive letter, attempt to add it
                windows_path = f"C:/{windows_path.lstrip('/')}"
            location.text = f"file:///{windows_path}"
        else:
            # Fallback to absolute path
            location.text = f"file:///{path.as_posix()}"

        # Duration
        duration_elem = ET.SubElement(track, 'duration')
        duration_elem.text = str(duration)
        
        # Extension with vlc:id
        extension = ET.SubElement(track, 'extension', application="http://www.videolan.org/vlc/playlist/0")
        vlc_id = ET.SubElement(extension, f"{{{NS_VLC}}}id")
        vlc_id.text = str(idx)
    
    # VLC extension for playlist items
    playlist_extension = ET.SubElement(playlist, 'extension', application="http://www.videolan.org/vlc/playlist/0")
    for idx in range(len(unix_paths)):
        vlc_item = ET.SubElement(playlist_extension, f"{{{NS_VLC}}}item", tid=str(idx))
    
    # Generate pretty XML with tab indentation
    xml_string = ET.tostring(playlist, encoding='utf-8')
    parsed_xml = ET.ElementTree(ET.fromstring(xml_string))
    return prettify_xml(parsed_xml)

def is_windows_path(path):
    """
    Determines if the given path is a Windows filesystem path.

    Args:
        path (Path): The file path.

    Returns:
        bool: True if path is in Windows filesystem, False otherwise.
    """
    posix = path.as_posix()
    # In WSL, Windows paths are typically under /mnt/<drive letter>/ or /<drive letter>/
    return posix.startswith('/mnt/') or re.match(r'^/[A-Za-z]/', posix) is not None

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
        print(f"Error converting path {unix_path} to Windows path: {e}", file=sys.stderr)
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
        print(f"Error converting path {windows_path} to WSL path: {e}", file=sys.stderr)
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
extracts their durations, and compiles them into an XSPF playlist file compatible with VLC Media Player.

Usage Examples:
    - Scan the current directory non-recursively and generate a playlist:
        python3 a.py

    - Scan the current directory and all subdirectories recursively:
        python3 a.py -r

    - Scan recursively and open the playlist with VLC:
        python3 a.py -r -p

    - Display help message:
        python3 a.py -h
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        '-r', '--recursive',
        action='store_true',
        help='Enable recursive searching for video files in all subdirectories.'
    )

    parser.add_argument(
        '-p', '--play',
        action='store_true',
        help='Open the generated playlist with VLC Media Player after creation.'
    )

    return parser.parse_args()

def main():
    # Parse command-line arguments
    args = parse_arguments()
    recursive_search = args.recursive
    open_vlc = args.play

    # Detect the execution environment
    wsl = is_wsl()
    environment = 'wsl' if wsl else 'windows'

    # Retrieve WSL distribution name dynamically if in WSL
    if wsl:
        distro_name = get_distro_name()
        if distro_name == "UnknownDistro":
            print("Unable to determine WSL distribution name. Please ensure you're running within a WSL environment.", file=sys.stderr)
            sys.exit(1)
    else:
        distro_name = None  # Not needed in native Windows

    # Define video file extensions to look for
    video_extensions = ('.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mpeg', '.mpg', '.m4v')

    # Determine the directory to scan (current working directory)
    start_dir = Path.cwd()

    print(f"Scanning for video files in: {start_dir}")
    print(f"Recursive search enabled: {'Yes' if recursive_search else 'No'}")
    print(f"Execution environment: {'WSL' if wsl else 'Windows'}")

    # Get list of video files
    video_files = get_video_files(start_dir, video_extensions, recursive=recursive_search)

    if not video_files:
        if recursive_search:
            print("No video files found in the specified directory and its subdirectories.")
        else:
            print("No video files found in the current directory.")
        sys.exit(0)
    
    print(f"Found {len(video_files)} video file{'s' if len(video_files) != 1 else ''}.")

    # Get durations for each video file
    durations = []
    for unix_path in video_files:
        duration = get_video_duration(unix_path)
        durations.append(duration)
        print(f"Duration for {unix_path.name}: {duration} ms")

    # Create XSPF playlist content using appropriate paths
    xspf_content = create_xspf_playlist(video_files, durations, distro_name, environment)

    # Determine the script's directory to save the playlist
    try:
        script_dir = Path(__file__).parent.resolve()
    except NameError:
        # Fallback if __file__ is not defined
        script_dir = Path.cwd()

    # Define the output playlist path
    output_playlist = script_dir / 'vlc.xspf'

    # Write the XSPF content to the output file with correct encoding
    try:
        with open(output_playlist, 'w', encoding='utf-8') as f:
            f.write(xspf_content)
    except Exception as e:
        print(f"Error writing playlist to {output_playlist}: {e}", file=sys.stderr)
        sys.exit(1)
    
    print(f"Playlist successfully created at: {output_playlist}")

    # Conditionally open the playlist with VLC if the --play flag is set
    if open_vlc:
        if environment == 'wsl':
            # Define the Windows VLC executable path
            vlc_windows_path = VLC_PATH
            # Convert to WSL path
            mixed_vlc_path = convert_to_wsl_path(vlc_windows_path)
            if not mixed_vlc_path:
                print("Failed to convert VLC executable path to WSL format.", file=sys.stderr)
                sys.exit(1)
            vlc_executable = mixed_vlc_path
            print(f"Using VLC executable path in WSL: {vlc_executable}")
        else:
            # Native Windows environment
            vlc_executable = VLC_PATH
            print(f"Using VLC executable path on Windows: {vlc_executable}")

        # Verify that the VLC executable exists
        if not Path(vlc_executable).exists():
            print(f"VLC executable not found at: {vlc_executable}", file=sys.stderr)
            sys.exit(1)

        # Determine the playlist path based on environment
        if environment == 'wsl':
            # Convert the playlist path to Windows format
            mixed_playlist_path = convert_to_windows_path(str(output_playlist))
            if not mixed_playlist_path:
                print("Failed to convert playlist path to Windows format.", file=sys.stderr)
                sys.exit(1)
            print(f"Converted playlist path for VLC: {mixed_playlist_path}")
        else:
            # Native Windows environment
            mixed_playlist_path = str(output_playlist)
        
        # Launch VLC with the appropriate playlist path
        try:
            subprocess.run([vlc_executable, mixed_playlist_path], check=True)
            print("VLC Media Player has been launched with the generated playlist.")
        except subprocess.CalledProcessError as e:
            print(f"Error opening playlist with VLC: {e}", file=sys.stderr)
        except FileNotFoundError:
            print("VLC Media Player is not installed or not found at the specified path.", file=sys.stderr)

if __name__ == "__main__":
    main()
