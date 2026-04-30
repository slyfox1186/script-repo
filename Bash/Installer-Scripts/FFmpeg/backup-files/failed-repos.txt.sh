# These wont build correctly with ffmpeg... must figure it out...

pre_check_ver 'OpenVisualCloud/SVT-VP9' '1' 'T'
if build 'svtvp9' "${g_ver}"; then
    download "https://codeload.github.com/OpenVisualCloud/SVT-VP9/tar.gz/refs/tags/v${g_ver}" "svtvp9-${g_ver}.tar.gz"
    execute cmake -B build -DCMAKE_{INSTALL_PREFIX="${workspace}",BUILD_TYPE=Release} -DBUILD_SHARED_LIBS=OFF -G 'Ninja' -Wno-dev
    execute ninja "-j${cpu_threads}" -C build
    execute ninja "-j${cpu_threads}" -C build install
    build_done 'svtvp9' "${g_ver}"
fi
ffmpeg_libraries+=('--enable-libsvtvp9')

# These go in with ffmpeg's command line for vp9
execute cp -f "${packages}/svtvp9-0.3.0/ffmpeg_plugin/master-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch" "${PWD}"
git apply --check --ignore-space-change --ignore-whitespace 'master-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch'

pre_check_ver 'Netflix/vmaf' '1' 'T'
if build 'libvmaf' "${g_ver}"; then
    download "https://codeload.github.com/Netflix/vmaf/tar.gz/refs/tags/v${g_ver}" "libvmaf-${g_ver}.tar.gz"
    CFLAGS="-msse2 -mfpmath=sse -mstackrealign ${CFLAGS}"
    execute meson setup --reconfigure libvmaf/build libvmaf --prefix="${workspace}" --libdir="${workspace}"/lib --buildtype=release --default-library=static --strip \
        -Denable_float=true -Dbuilt_in_models=true -Denable_tests=false -Denable_docs=false -Denable_avx512=true
    execute ninja "-j${cpu_threads}" -C libvmaf/build install
    build_done 'libvmaf' "${g_ver}"
fi
CFLAGS+=" -I${workspace}/include/libvmaf"
