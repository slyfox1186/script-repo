What you were trying to accomplish
  - I am trying to build a standard release version of FFmpeg with as many addon optional libraries as I can fit.

The problem you encountered
  - Below is the tail end of the file `config.log`
  - Please notice the line `cc1: error: bad value ('16') for '-march=' switch`
  - It thinks `-pipe -fno-plt -march=native` is `-march=16`

```
zlib_decoder='yes'
zlib_decoder_select='inflate_wrapper'
zlib_encoder='yes'
zlib_encoder_select='deflate_wrapper'
zmbv_decoder='yes'
zmbv_decoder_select='inflate_wrapper'
zmbv_encoder='yes'
zmbv_encoder_select='deflate_wrapper'
zmq_filter='yes'
zmq_filter_deps='libzmq'
zoneplate_filter='yes'
zoompan_filter='yes'
zoompan_filter_deps='swscale'
zscale_filter='yes'
zscale_filter_deps='libzimg const_nan'
mktemp -u XXXXXX
53NDzR
test_ld cc
test_cc
BEGIN /tmp/ffconf.G39JKF9Y/test.c
    1	int main(void){ return 0; }
END /tmp/ffconf.G39JKF9Y/test.c
gcc -I/home/jman/tmp/ffmpeg-build-script/workspace/include -I/usr/local/include -I/usr/include -I/usr/lib/jvm/java-17-openjdk-amd64/include -g -O3 -pipe -fno-plt -march=native -I/home/jman/tmp/ffmpeg-build-script/workspace/include -I/home/jman/tmp/ffmpeg-build-script/workspace/include/jxl -I/usr/local/include -I/usr/include -I/home/jman/tmp/ffmpeg-build-script/workspace/include/CL -I/usr/include/x86_64-linux-gnu -I/usr/include/SDL2 -I/usr/lib/x86_64-linux-gnu/pulseaudio -I/usr/include/openjpeg-2.5 -I/usr/include/vk_video -I/usr/include/vulkan -I/home/jman/tmp/ffmpeg-build-script/workspace/include/avisynth -I/usr/include/flite -I/home/jman/tmp/ffmpeg-build-script/workspace/include/lilv-0 -I/usr/local/cuda/include -g -O3 -march=native -I/home/jman/tmp/ffmpeg-build-script/workspace/include -I/home/jman/tmp/ffmpeg-build-script/workspace/include/jxl -I/usr/local/include -I/usr/include -I/home/jman/tmp/ffmpeg-build-script/workspace/include/CL -I/usr/include/x86_64-linux-gnu -I/usr/include/SDL2 -I/usr/lib/x86_64-linux-gnu/pulseaudio -I/usr/include/openjpeg-2.5 -I/usr/include/vk_video -I/usr/include/vulkan -I/home/jman/tmp/ffmpeg-build-script/workspace/include/avisynth -I/usr/include/flite -I/home/jman/tmp/ffmpeg-build-script/workspace/include/lilv-0 -I/usr/local/cuda/include -march=16 -c -o /tmp/ffconf.G39JKF9Y/test.o /tmp/ffconf.G39JKF9Y/test.c
cc1: error: bad value ('16') for '-march=' switch
cc1: note: valid arguments to '-march=' switch are: nocona core2 nehalem corei7 westmere sandybridge corei7-avx ivybridge core-avx-i haswell core-avx2 broadwell skylake skylake-avx512 cannonlake icelake-client rocketlake icelake-server cascadelake tigerlake cooperlake sapphirerapids alderlake bonnell atom silvermont slm goldmont goldmont-plus tremont knl knm x86-64 x86-64-v2 x86-64-v3 x86-64-v4 eden-x2 nano nano-1000 nano-2000 nano-3000 nano-x2 eden-x4 nano-x4 k8 k8-sse3 opteron opteron-sse3 athlon64 athlon64-sse3 athlon-fx amdfam10 barcelona bdver1 bdver2 bdver3 bdver4 znver1 znver2 znver3 btver1 btver2 native
C compiler test failed.
```

The exact command line you were using (e.g., "ffmpeg -i input.mov -an -vcodec foo output.avi")
```
../configure --prefix=/usr/local --arch=x86_64 --cpu=16 --cc=gcc --cxx=g++ --disable-debug --disable-doc --disable-large-tests --disable-shared --enable-ladspa --enable-openssl --enable-libxml2 --enable-libaribb24 --enable-libfreetype --enable-libfontconfig --enable-libfribidi --enable-libass --enable-libwebp --enable-lcms2 --enable-libjxl --enable-opencl --enable-libtesseract --enable-librubberband --enable-libzimg --enable-lv2 --enable-libpulse --enable-libfdk-aac --enable-libvorbis --enable-libopus --enable-libmysofa --enable-libvpx --enable-libopencore-amrnb --enable-libopencore-amrwb --enable-libmp3lame --enable-libtheora --enable-libkvazaar --enable-decklink --enable-libaom --enable-libdav1d --enable-librav1e --enable-libkvazaar --enable-libbluray --enable-libvidstab --enable-frei0r --enable-amf --enable-libsvtav1 --enable-libx264 --enable-libx265 --enable-cuda-nvcc --enable-cuda-llvm --enable-cuvid --enable-nvdec --enable-nvenc --enable-ffnvcodec --nvccflags='-gencode arch=compute_86,code=sm_86' --enable-libsrt --enable-avisynth --enable-vapoursynth --enable-libxvid --enable-libopenjpeg --enable-chromaprint --enable-gpl --enable-libbs2b --enable-libcaca --enable-libcdio --enable-libgme --enable-libmodplug --enable-libshine --enable-libsmbclient --enable-libsnappy --enable-libsoxr --enable-libspeex --enable-libssh --enable-libtwolame --enable-libv4l2 --enable-libvo-amrwbenc --enable-libzvbi --enable-lto --enable-nonfree --enable-opengl --enable-pic --enable-pthreads --enable-small --enable-static --enable-vulkan --enable-version3 --extra-cflags='-g -O3 -pipe -fno-plt -march=native -I/home/jman/tmp/ffmpeg-build-script/workspace/include -I/home/jman/tmp/ffmpeg-build-script/workspace/include/jxl -I/usr/local/include -I/usr/include -I/home/jman/tmp/ffmpeg-build-script/workspace/include/CL -I/usr/include/x86_64-linux-gnu -I/usr/include/SDL2 -I/usr/lib/x86_64-linux-gnu/pulseaudio -I/usr/include/openjpeg-2.5 -I/usr/include/vk_video -I/usr/include/vulkan -I/home/jman/tmp/ffmpeg-build-script/workspace/include/avisynth -I/usr/include/flite -I/home/jman/tmp/ffmpeg-build-script/workspace/include/lilv-0 -I/usr/local/cuda/include' --extra-cxxflags='-g -O3 -march=native' --extra-ldflags='-L/home/jman/tmp/ffmpeg-build-script/workspace/lib64 -L/home/jman/tmp/ffmpeg-build-script/workspace/lib -L/home/jman/tmp/ffmpeg-build-script/workspace/lib/x86_64-linux-gnu -L/usr/local/lib64 -L/usr/local/lib -L/usr/lib/x86_64-linux-gnu -L/usr/lib64 -L/usr/lib -L/lib64 -L/lib -L/usr/local/cuda/lib64' --extra-ldexeflags= --extra-libs='-ldl -lpthread -lm -lz -L/usr/lib/x86_64-linux-gnu -lcurl -lvulkan -L/home/jman/tmp/ffmpeg-build-script/workspace/lib -llcms2 -llcms2_threaded -lhwy -lbrotlidec -lbrotlienc -ltesseract -L/usr/local/cuda/targets/x86_64-linux/lib -lOpenCL' --pkg-config-flags=--static --pkg-config=/usr/local/bin/pkg-config --pkgconfigdir=/usr/local/lib/pkgconfig --strip=/bin/strip
```

Sufficient information, including any required input files, to reproduce the bug and confirm a potential fix.

I don't know what to say. It is a bonafide bug. It should be using `-pipe -fno-plt -march=native` and instead the code uses `-march=16`
