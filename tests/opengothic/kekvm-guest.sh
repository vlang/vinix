#!/bin/sh
# Run inside KekVM's prepared Debian GPU guest, with the OpenGothic build
# directory mounted read-only at /mnt/gothic. See kekvm.md.
set -eu

share=${OPENGOTHIC_SHARE:-/mnt/gothic}
work=${OPENGOTHIC_WORK:-/root/opengothic-kekvm}
icd=/usr/share/vulkan/icd.d/virtio_icd.json
export DISPLAY=${DISPLAY:-:0}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/kekvm-gpu}

[ "$(getconf PAGESIZE)" = 16384 ] || {
    echo "KekVM Venus requires the prepared 16 KiB-page guest kernel" >&2
    exit 1
}
[ -f "$icd" ] || { echo "The guest's Venus ICD is missing" >&2; exit 1; }
mkdir -p "$work" "$XDG_RUNTIME_DIR"

case ${1:-build} in
build)
    # Build against Debian's libc and Vulkan loader: its Venus driver cannot
    # be loaded into the ARM64/musl executable built for Vinix.
    tar --exclude=.git --exclude='._*' -cf - -C "$share" source vulkan-headers |
        tar -xf - -C "$work"
    python3 - "$work/source/CMakeLists.txt" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().split("# Vinix execinfo compatibility")[0])
PY
    cmake -S "$work/source" -B "$work/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DGLSLANGVALIDATOR=/usr/bin/glslangValidator \
        "-DCMAKE_CXX_FLAGS=-I$work/vulkan-headers/include -Wno-error=stringop-overflow" \
        -DALSOFT_BACKEND_ALSA=OFF -DALSOFT_BACKEND_PULSEAUDIO=OFF \
        -DALSOFT_BACKEND_JACK=OFF -DALSOFT_BACKEND_PIPEWIRE=OFF -DALSOFT_BACKEND_OSS=OFF
    cmake --build "$work/build" --target Gothic2Notr -j "${OPENGOTHIC_JOBS:-8}"
    ;;
launch)
    [ -x "$work/build/opengothic/Gothic2Notr" ]
    if [ ! -d "$work/game" ]; then
        cp -rs "$share/staging/usr/share/games/gothic2" "$work/game"
        # Skip the demo's movie in this test copy; original assets stay intact.
        find "$work/game" -iname intro.bik -delete
    fi
    mkdir -p "$work/state"
    cd "$work/state"
    setsid env VK_DRIVER_FILES="$icd" ALSOFT_DRIVERS=null \
        VK_INSTANCE_LAYERS=VK_LAYER_MESA_overlay \
        "VK_LAYER_MESA_OVERLAY_CONFIG=output_file=$work/fps.csv,no_display,fps" \
        "$work/build/opengothic/Gothic2Notr" -g "$work/game" -g2c \
        -window -rt 0 -gi 0 -ms 0 -aa 0 -nomenu \
        > "$work/game.log" 2>&1 < /dev/null &
    echo "$!" > "$work/game.pid"
    ;;
capture)
    kill -0 "$(cat "$work/game.pid")"
    grep -q 'GPU = Virtio-GPU Venus (Apple' "$work/game.log"
    if grep -q -- '---crashlog(' "$work/game.log"; then
        echo "OpenGothic crashed; see $work/game.log" >&2
        exit 1
    fi
    # QMP screendump cannot read this VirGL scanout: capture the real X root.
    import -window root "$work/gothic.png"
    echo "$work/gothic.png"
    ;;
*) echo "Usage: $0 build|launch|capture" >&2; exit 2 ;;
esac
