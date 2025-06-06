# GCC Configuration Management - ADD TO SCRIPT

# Define base configure options as associative arrays
declare -A GCC_BASE_OPTIONS=(
    [prefix]="--prefix=\$install_prefix"
    [build]="--build=\$target_arch"
    [host]="--host=\$target_arch" 
    [target]="--target=\$target_arch"
    [languages]="--enable-languages=all"
    [bootstrap]="--disable-bootstrap"
    [checking]="--enable-checking=release"
    [nls]="--disable-nls"
    [shared]="--enable-shared"
    [threads]="--enable-threads=posix"
    [zlib]="--with-system-zlib"
    [isl]="--with-isl=/usr"
    [suffix]="--program-suffix=-\$major_version"
    [major_version_only]="--with-gcc-major-version-only"
)

# Version-specific option sets
declare -A GCC_VERSION_FEATURES=(
    ["9,10,11"]="default_pie,gnu_unique_object"
    ["12"]="default_pie,gnu_unique_object,link_serialization"
    ["13,14"]="default_pie,gnu_unique_object,link_serialization,cet"
    ["15"]="default_pie,gnu_unique_object,link_serialization,cet"
)

# Feature to option mapping
declare -A GCC_FEATURE_OPTIONS=(
    [default_pie]="--enable-default-pie"
    [gnu_unique_object]="--enable-gnu-unique-object"
    [link_serialization]="--with-link-serialization=2"
    [cet]="--enable-cet"
    [multilib_enable]="--enable-multilib"
    [multilib_disable]="--disable-multilib"
)

# Generate configure options for specific version
get_gcc_configure_options() {
    local major_version="$1"
    local install_prefix="$2"
    local -a options=()
    
    # Add base options
    for key in "${!GCC_BASE_OPTIONS[@]}"; do
        local option="${GCC_BASE_OPTIONS[$key]}"
        # Expand variables in option string
        option=$(eval echo "$option")
        options+=("$option")
    done
    
    # Add multilib option
    if [[ "$enable_multilib_flag" -eq 1 ]]; then
        options+=("${GCC_FEATURE_OPTIONS[multilib_enable]}")
    else
        options+=("${GCC_FEATURE_OPTIONS[multilib_disable]}")
    fi
    
    # Add version-specific features
    for version_range in "${!GCC_VERSION_FEATURES[@]}"; do
        if version_matches "$major_version" "$version_range"; then
            local features="${GCC_VERSION_FEATURES[$version_range]}"
            IFS=',' read -ra feature_list <<< "$features"
            
            for feature in "${feature_list[@]}"; do
                if [[ -n "${GCC_FEATURE_OPTIONS[$feature]}" ]]; then
                    options+=("${GCC_FEATURE_OPTIONS[$feature]}")
                fi
            done
            break
        fi
    done
    
    # Add CUDA support if available
    [[ -n "$cuda_check" ]] && options+=("$cuda_check")
    
    printf '%s\n' "${options[@]}"
}

# Check if version matches version range (e.g., "13" matches "13,14")
version_matches() {
    local version="$1"
    local range="$2"
    
    IFS=',' read -ra versions <<< "$range"
    for v in "${versions[@]}"; do
        [[ "$v" == "$version" ]] && return 0
    done
    return 1
}