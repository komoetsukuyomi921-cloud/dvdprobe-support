#!/usr/bin/env bash
# LGPL-only ffmpeg command-line tool for embedding in the sandboxed app (DVDProbe.app/Contents/Helpers/ffmpeg).
# Only what the make pipeline uses: iPhone / camera inputs -> MPEG-2 video + AC-3/LPCM elementary streams.
#   - no --enable-gpl / --enable-nonfree, no external libraries (autodetect off): configure must report LGPL
#   - shared libraries (LGPL relinking), installed with @rpath names; build-app.sh copies them to Contents/Frameworks
#   - HEVC/H.264 decode through VideoToolbox (hardware); HDR -> SDR with scale_vt (VTPixelTransferSession), no zimg
#
#   scripts/build-ffmpeg-app.sh [version] [prefix]      default 7.1.2, work/ffmpeg-app
set -euo pipefail
cd "$(dirname "$0")/.."
VER="${1:-7.1.2}"; PREFIX="${2:-$PWD/work/ffmpeg-app}"; ARCH="${ARCH:-$(uname -m)}"
SRC="work/ffmpeg-$VER"
mkdir -p work
[[ -d "$SRC" ]] || { curl -fsSL "https://ffmpeg.org/releases/ffmpeg-$VER.tar.gz" -o "work/ffmpeg-$VER.tar.gz"; tar -C work -xzf "work/ffmpeg-$VER.tar.gz"; }

join() { local IFS=,; echo "$*"; }
DEMUXERS=(mov matroska mpegts mpegps avi m4v h264 hevc aac ac3 eac3 mp3 wav)
DECODERS=(h264 hevc mpeg2video mpeg4 mjpeg prores aac aac_fixed ac3 eac3 mp3 alac flac opus
          pcm_s16le pcm_s16be pcm_s24le pcm_s24be pcm_s32le pcm_f32le pcm_u8)
PARSERS=(h264 hevc mpeg4video mpegvideo aac ac3 mpegaudio opus flac mjpeg)
HWACCELS=(h264_videotoolbox hevc_videotoolbox mpeg2_videotoolbox mpeg4_videotoolbox prores_videotoolbox)
ENCODERS=(mpeg2video ac3 pcm_s16be)
MUXERS=(mpeg2video ac3 s16be)
FILTERS=(scale scale_vt hwdownload format pad crop overlay split gblur lutyuv fps setsar trim setpts concat
         transpose hflip vflip null
         aresample aformat apad atrim asetpts anullsrc anull)

cd "$SRC"
make distclean >/dev/null 2>&1 || true
./configure --prefix="$PREFIX" \
  --arch="$ARCH" --target-os=darwin --cc="clang -arch $ARCH" \
  --extra-cflags="-mmacosx-version-min=14.0" --extra-ldflags="-mmacosx-version-min=14.0 -Wl,-headerpad_max_install_names" \
  --install-name-dir="@rpath" \
  --enable-shared --disable-static --disable-doc --disable-debug \
  --disable-autodetect --disable-network --disable-everything \
  --disable-ffplay --disable-ffprobe --enable-ffmpeg \
  --disable-avdevice --disable-postproc \
  --enable-videotoolbox \
  --enable-protocol=file,pipe \
  --enable-demuxer="$(join "${DEMUXERS[@]}")" \
  --enable-decoder="$(join "${DECODERS[@]}")" \
  --enable-parser="$(join "${PARSERS[@]}")" \
  --enable-hwaccel="$(join "${HWACCELS[@]}")" \
  --enable-encoder="$(join "${ENCODERS[@]}")" \
  --enable-muxer="$(join "${MUXERS[@]}")" \
  --enable-filter="$(join "${FILTERS[@]}")" \
  > ../ffmpeg-app-configure.log
grep -E "^License" ../ffmpeg-app-configure.log
grep -q "^License: LGPL" ../ffmpeg-app-configure.log || { echo "configure did not report an LGPL license" >&2; exit 1; }
make -j"$(sysctl -n hw.ncpu)" >/dev/null
make install >/dev/null
# the ffmpeg binary finds the dylibs next to it in the app bundle (Contents/Frameworks)
install_name_tool -add_rpath "@executable_path/../Frameworks" "$PREFIX/bin/ffmpeg" 2>/dev/null || true
echo "installed to $PREFIX"
ls "$PREFIX/bin" "$PREFIX/lib"/*.dylib
