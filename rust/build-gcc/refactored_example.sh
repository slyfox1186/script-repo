# Example of how the refactored code would look - INTEGRATION EXAMPLE

# Replace this repetitive block:
# OLD WAY (repeated 11 times):
# mkdir -p "$some_dir" || fail "Failed to create $some_dir"
# mkdir -p "$another_dir" || fail "Failed to create $another_dir"

# NEW WAY:
create_directories "$build_dir" "$packages" "$workspace" "$install_prefix"

#########################################

# Replace this repetitive configure options:
# OLD WAY (repeated for each version):
# case "$major_version" in
#     13|14) 
#         configure_options+=("--enable-default-pie")
#         configure_options+=("--enable-gnu-unique-object")
#         configure_options+=("--with-link-serialization=2")
#         configure_options+=("--enable-cet")
#         ;;

# NEW WAY:
mapfile -t configure_options < <(get_gcc_configure_options "$major_version" "$install_prefix")

#########################################

# Replace repetitive package management:
# OLD WAY:
# local -a required_pkgs=(build-essential binutils gawk m4 flex bison...)
# for pkg in "${required_pkgs[@]}"; do
#     if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
#         pkgs_to_install+=("$pkg")
#     fi
# done

# NEW WAY:
mapfile -t required_packages < <(get_required_packages)
local package_status
package_status=$(check_packages_installed "${required_packages[@]}")
if [[ "$package_status" == missing:* ]]; then
    local missing_packages="${package_status#missing:}"
    install_packages $missing_packages
fi

#########################################

# Replace repetitive file operations:
# OLD WAY:
# if [[ -f "$download_path" ]]; then
#     if tar -tf "$download_path" &>/dev/null; then
#         log "INFO" "File exists and is valid"
#     else
#         rm -f "$download_path"
#         # download again...
#     fi
# fi

# NEW WAY:
if validate_file "$download_path" "exists" && validate_file "$download_path" "tarball"; then
    log "INFO" "Using existing valid file: $download_path"
else
    download_file "$url" "$download_path"
fi

#########################################

# Replace repetitive system checks:
# OLD WAY:
# local available_ram_mb
# available_ram_mb=$(free -m | awk '/^Mem:/ {print $2}')
# local threads
# threads=$(nproc --all 2>/dev/null || echo 2)

# NEW WAY:
local build_settings
build_settings=$(calculate_build_settings "${#selected_versions[@]}")
local optimal_threads
optimal_threads=$(echo "$build_settings" | grep optimal_threads | cut -d':' -f2 | tr -d ' ",')

validate_system_requirements "${#selected_versions[@]}" "$build_dir" || fail "System requirements not met"

#########################################

# Replace repetitive error-prone commands:
# OLD WAY:
# if ! verbose_logging_cmd sudo mkdir -p "$dir"; then
#     fail "Failed to create $dir"
# fi

# NEW WAY:
create_directory "$dir" "installation directory" "true"

# OR for commands with retry:
execute_with_retry 3 5 sudo mkdir -p "$dir"