What you were trying to accomplish
  - I am trying to build a standard release version of FFmpeg with as many addon optional libraries as I can fit.

The problem you encountered
  - Below is the tail end of the file `config.log`
  - Please notice the line `cc1: error: bad value ('16') for '-march=' switch`
  - It thinks `-march=native` is `-march=16`

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
gcc -I/home/jman/tmp/ffmpeg-build-script/workspace/include -I/usr/local/include -I/usr/include -I/usr/lib/jvm/java-17-openjdk-amd64/include -g -O3 -march=native -I/home/jman/tmp/ffmpeg-build-script/workspace/include -I/home/jman/tmp/ffmpeg-build-script/workspace/include/jxl -I/usr/local/include -I/usr/include -I/home/jman/tmp/ffmpeg-build-script/workspace/include/CL -I/usr/include/x86_64-linux-gnu -I/usr/include/SDL2 -I/usr/lib/x86_64-linux-gnu/pulseaudio -I/usr/include/openjpeg-2.5 -I/usr/include/vk_video -I/usr/include/vulkan -I/home/jman/tmp/ffmpeg-build-script/workspace/include/avisynth -I/usr/include/flite -I/home/jman/tmp/ffmpeg-build-script/workspace/include/lilv-0 -I/usr/local/cuda/include -g -O3 -march=native -I/home/jman/tmp/ffmpeg-build-script/workspace/include -I/home/jman/tmp/ffmpeg-build-script/workspace/include/jxl -I/usr/local/include -I/usr/include -I/home/jman/tmp/ffmpeg-build-script/workspace/include/CL -I/usr/include/x86_64-linux-gnu -I/usr/include/SDL2 -I/usr/lib/x86_64-linux-gnu/pulseaudio -I/usr/include/openjpeg-2.5 -I/usr/include/vk_video -I/usr/include/vulkan -I/home/jman/tmp/ffmpeg-build-script/workspace/include/avisynth -I/usr/include/flite -I/home/jman/tmp/ffmpeg-build-script/workspace/include/lilv-0 -I/usr/local/cuda/include -march=16 -c -o /tmp/ffconf.G39JKF9Y/test.o /tmp/ffconf.G39JKF9Y/test.c
cc1: error: bad value ('16') for '-march=' switch
cc1: note: valid arguments to '-march=' switch are: nocona core2 nehalem corei7 westmere sandybridge corei7-avx ivybridge core-avx-i haswell core-avx2 broadwell skylake skylake-avx512 cannonlake icelake-client rocketlake icelake-server cascadelake tigerlake cooperlake sapphirerapids alderlake bonnell atom silvermont slm goldmont goldmont-plus tremont knl knm x86-64 x86-64-v2 x86-64-v3 x86-64-v4 eden-x2 nano nano-1000 nano-2000 nano-3000 nano-x2 eden-x4 nano-x4 k8 k8-sse3 opteron opteron-sse3 athlon64 athlon64-sse3 athlon-fx amdfam10 barcelona bdver1 bdver2 bdver3 bdver4 znver1 znver2 znver3 btver1 btver2 native
C compiler test failed.


The exact command line you were using (e.g., "ffmpeg -i input.mov -an -vcodec foo output.avi")
The full, uncut console output provided by ffmpeg -v 9 -loglevel 99 -i followed by the name of your input file (copy/pasted from the console, including the banner that indicates version and configuration options), paste ffplay or ffprobe output only if your problem is not reproducible with ffmpeg.
Sufficient information, including any required input files, to reproduce the bug and confirm a potential fix.
```
