#!/usr/bin/env python3
"""
CUDA Auto-Installer for Ubuntu 22.04
Automatically fetches and installs the latest CUDA toolkit from NVIDIA.
"""

import glob
import re
import requests
import shlex
import subprocess
import sys

from pathlib import Path

class CudaInstaller:
    def __init__(self):
        self.base_url = "https://developer.nvidia.com"
        self.downloads_url = "https://developer.nvidia.com/cuda-downloads"
        self.api_url = "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64"
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:141.0) Gecko/20100101 Firefox/141.0'
        })
        self.packages_content = None

    def check_os(self):
        """Verify Ubuntu 22.04 compatibility."""
        try:
            with open('/etc/os-release') as f:
                content = f.read()
                if 'ID=ubuntu' in content and 'VERSION_ID="22.04"' in content:
                    return True
                else:
                    print("❌ This script is designed for Ubuntu 22.04 only.")
                    return False
        except Exception as e:
            print(f"❌ Cannot verify OS: {e}")
            return False

    def check_sudo(self):
        """Verify sudo access."""
        try:
            result = subprocess.run(['sudo', '-n', 'true'], capture_output=True, text=True)
            return result.returncode == 0
        except Exception:
            return False

    def get_packages_content(self):
        """Download and cache packages metadata."""
        if self.packages_content is None:
            try:
                response = self.session.get(f"{self.api_url}/Packages", timeout=10)
                if response.status_code == 200:
                    self.packages_content = response.text
            except Exception as e:
                print(f"Error downloading packages metadata: {e}")
                return None
        return self.packages_content

    def get_latest_cuda_version(self):
        """Get the latest CUDA version from NVIDIA's repository."""
        try:
            content = self.get_packages_content()
            if content is None:
                raise RuntimeError("Could not download package metadata")
            
            # Find all CUDA toolkit versions
            versions = re.findall(r'Package: cuda-toolkit-(\d+-\d+)', content)
            if versions:
                # Convert to semantic version and get the latest
                version_nums = []
                for v in set(versions):
                    major, minor = v.split('-')
                    version_nums.append((int(major), int(minor), v.replace('-', '.')))
                
                latest = max(version_nums, key=lambda x: (x[0], x[1]))
                return latest[2]
            
            raise RuntimeError("No CUDA versions found in repository")
            
        except Exception as e:
            print(f"❌ Error getting CUDA version: {e}")
            raise

    def get_download_urls(self, version):
        """Generate download URLs for the CUDA installation."""
        major, minor = version.split('.')
        version_dash = f"{major}-{minor}"
        
        # The repository packages are hosted at the main CUDA download location
        # not in the repository directory, following the pattern from the working example
        base_download_url = "https://developer.download.nvidia.com/compute/cuda"
        
        # Try to find the exact package name and driver version
        content = self.get_packages_content()
        repo_filename = None
        driver_version = None
        
        if content:
            # Look for the local repository package in the packages metadata
            stanzas = content.split('\n\n')
            
            for stanza in stanzas:
                if f'Package: cuda-repo-ubuntu2204-{version_dash}-local' in stanza:
                    for line in stanza.splitlines():
                        if line.startswith('Filename:'):
                            filename = line.split(':', 1)[1].strip()
                            # Extract driver version from filename pattern
                            # e.g., cuda-repo-ubuntu2204-13-0-local_13.0.0-580.65.06-1_amd64.deb
                            match = re.search(rf'cuda-repo-ubuntu2204-{version_dash}-local_({version}\.\d+)-(\d+\.\d+\.\d+)-1_amd64\.deb', filename)
                            if match:
                                full_version = match.group(1)  # e.g., 13.0.0
                                driver_version = match.group(2)  # e.g., 580.65.06
                                repo_filename = filename
                            break
                    if repo_filename:
                        break
        
        # If we couldn't find exact details, use fallback pattern from working example
        if not repo_filename or not driver_version:
            # Use pattern from working example: 13.0.0 with driver 580.65.06
            full_version = f"{version}.0"  # Convert 13.0 to 13.0.0
            driver_version = "580.65.06"  # Known working driver version
            repo_filename = f"cuda-repo-ubuntu2204-{version_dash}-local_{full_version}-{driver_version}-1_amd64.deb"

        return {
            'pin_file': f"{self.api_url}/cuda-ubuntu2204.pin",
            'repo_package': f"{base_download_url}/{full_version}/local_installers/{repo_filename}",
            'version': version,
            'version_dash': version_dash,
            'repo_filename': repo_filename,
            'full_version': full_version,
            'driver_version': driver_version
        }

    def download_file(self, url, filename):
        """Download a file with progress indication."""
        print(f"Downloading {filename}...")
        try:
            response = self.session.get(url, stream=True, timeout=30)
            response.raise_for_status()
            
            total_size = int(response.headers.get('content-length', 0))
            downloaded = 0
            
            with open(filename, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
                        if total_size > 0:
                            progress = (downloaded / total_size) * 100
                            print(f"\rProgress: {progress:.1f}%", end='', flush=True)
            
            print(f"\n✓ Downloaded: {filename}")
            return True
        except Exception as e:
            print(f"\n❌ Error downloading {filename}: {e}")
            return False

    def run_command(self, command, description):
        """Run a command with error handling (secure version)."""
        print(f"\n{description}...")
        
        # Convert string commands to list for security
        if isinstance(command, str):
            command = shlex.split(command)
        
        print(f"Command: {' '.join(command)}")
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=300)
            if result.returncode == 0:
                print("✓ Success")
                if result.stdout.strip():
                    print(f"Output: {result.stdout.strip()}")
                return True
            else:
                print(f"❌ Failed with return code {result.returncode}")
                if result.stderr.strip():
                    print(f"Error: {result.stderr.strip()}")
                return False
        except subprocess.TimeoutExpired:
            print("❌ Command timed out")
            return False
        except Exception as e:
            print(f"❌ Exception: {e}")
            return False

    def install_cuda(self):
        """Main installation process."""
        print("🚀 CUDA Auto-Installer for Ubuntu 22.04")
        print("=" * 50)
        
        # Pre-installation checks
        if not self.check_os():
            return False
            
        if not self.check_sudo():
            print("❌ This script requires sudo access. Please run 'sudo -v' first.")
            return False
            
        print("✓ System checks passed")
        
        try:
            # Get latest version
            version = self.get_latest_cuda_version()
            print(f"Latest CUDA version: {version}")
            
            # Get download URLs
            urls = self.get_download_urls(version)
            print(f"Repository package: {urls['repo_filename']}")
            print(f"Full version: {urls['full_version']}, Driver: {urls['driver_version']}")
            
            # Create downloads directory
            downloads_dir = Path("cuda_downloads")
            downloads_dir.mkdir(exist_ok=True)
            
            # Download pin file
            pin_file = downloads_dir / "cuda-ubuntu2204.pin"
            if not self.download_file(urls['pin_file'], pin_file):
                raise RuntimeError("Failed to download pin file")
            
            # Download repository package
            repo_file = downloads_dir / urls['repo_filename']
            if not self.download_file(urls['repo_package'], repo_file):
                raise RuntimeError("Failed to download repository package")
            
            print("\n🔧 Installing CUDA...")
            print("=" * 30)
            
            # Secure installation commands using lists
            commands = [
                (["sudo", "mv", str(pin_file), "/etc/apt/preferences.d/cuda-repository-pin-600"], "Moving pin file"),
                (["sudo", "dpkg", "-i", str(repo_file)], "Installing repository package")
            ]
            
            # Add a step to handle keyring files after package installation
            keyring_pattern = f"/var/cuda-repo-ubuntu2204-{urls['version_dash']}-local/cuda-*-keyring.gpg"
            
            # We need to check for keyring files after the dpkg step, so add this as a separate command
            def copy_keyring_files():
                keyring_files = glob.glob(keyring_pattern)
                if keyring_files:
                    return (["sudo", "cp"] + keyring_files + ["/usr/share/keyrings/"], "Adding GPG key")
                else:
                    print(f"Warning: No keyring files found at {keyring_pattern}")
                    return None
            
            # Execute the first two commands first
            for command, description in commands:
                if not self.run_command(command, description):
                    raise RuntimeError(f"Installation failed at: {description}")
            
            # Now try to copy the keyring files
            keyring_cmd = copy_keyring_files()
            if keyring_cmd:
                if not self.run_command(keyring_cmd[0], keyring_cmd[1]):
                    raise RuntimeError(f"Installation failed at: {keyring_cmd[1]}")
            
            # Continue with remaining commands
            remaining_commands = [
                (["sudo", "apt", "update"], "Updating package list"),
                (["sudo", "apt", "-y", "install", f"cuda-toolkit-{urls['version_dash']}"], "Installing CUDA toolkit")
            ]
            
            for command, description in remaining_commands:
                if not self.run_command(command, description):
                    raise RuntimeError(f"Installation failed at: {description}")
            
            
            print("\n🎉 CUDA installation completed successfully!")
            
            # Clean up downloaded files
            print("\n🧹 Cleaning up downloaded files...")
            try:
                import shutil
                shutil.rmtree(downloads_dir)
                print("✓ Cleanup completed")
            except Exception as e:
                print(f"⚠️  Warning: Could not clean up files: {e}")
                print(f"You can manually remove: {downloads_dir}")
            
            print("\nTo complete the installation:")
            print("1. Add CUDA to your PATH by adding these lines to ~/.bashrc:")
            print(f"   export PATH=/usr/local/cuda-{version}/bin:$PATH")
            print(f"   export LD_LIBRARY_PATH=/usr/local/cuda-{version}/lib64:$LD_LIBRARY_PATH")
            print("2. Reload your shell: source ~/.bashrc")
            print("3. Verify installation: nvcc --version")
            
            return True
            
        except Exception as e:
            print(f"\n❌ Installation failed: {e}")
            return False

def main():
    if len(sys.argv) > 1 and sys.argv[1] in ['-h', '--help']:
        print("CUDA Auto-Installer for Ubuntu 22.04")
        print("Usage: python3 cuda_auto_installer.py")
        print("\nThis script will:")
        print("- Detect the latest CUDA version")
        print("- Download required packages")
        print("- Install CUDA toolkit automatically")
        return
    
    installer = CudaInstaller()
    try:
        installer.install_cuda()
    except KeyboardInterrupt:
        print("\n\nInstallation cancelled by user.")
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
