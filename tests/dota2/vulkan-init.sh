#!/bin/sh
# Run the x86-64 glibc Vulkan driver on the Vinix kernel, without Steam.
set -eu
trap 'echo VINIX-DOTA2-VULKAN-FAIL' 0
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root
export USER=root
export XDG_RUNTIME_DIR=/run/user/0
export DISPLAY=:99
export LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules
mkdir -p /tmp/.X11-unix /tmp/vulkan /run/user/0
chmod 1777 /tmp /tmp/.X11-unix
echo VINIX-DOTA2-VULKAN-START
uname -a

Xvfb :99 -screen 0 320x240x24 -fbdir /tmp/vulkan -nolisten tcp -ac -noreset \
    -extension MIT-SHM >/tmp/xvfb.log 2>&1 &
xpid=$!
sleep 3
root=/usr/libexec/vinix-dota2/root
export VINIX_X86_64_ROOT="$root"
export VINIX_X86_MULTIARCH=1
export VINIX_ALLOW_WX=1
# Mesa 22's LLVM JIT infers the target from CPUID. QEMU's synthetic "max"
# signature can resolve to a 32-bit CPU; Haswell describes an x86-64 target
# with the SSE4 baseline used by Valve's current binaries.
export QEMU_CPU=Haswell
export LP_NUM_THREADS=2
if [ "$(cat /etc/vinix-dota2-vulkan-driver 2>/dev/null)" = venus ]; then
    # Host GPU through Vinix's virtio-gpu render node on KekVM.
    export VK_ICD_FILENAMES="$root/usr/share/vulkan/icd.d/virtio_icd.x86_64.json"
    if [ -x /opt/venus/bin/venus-available ]; then
        /opt/venus/bin/venus-available && echo VINIX-DOTA2-VENUS-NATIVE-READY ||
            echo VINIX-DOTA2-VENUS-NATIVE-UNAVAILABLE
    fi
    # Report Venus initialisation and any ioctl the translator cannot pass.
    export VN_DEBUG=init,result QEMU_LOG=unimp
else
    export VK_ICD_FILENAMES="$root/usr/share/vulkan/icd.d/lvp_icd.x86_64.json"
fi
export MESA_SHADER_CACHE_DISABLE=true
"$root/usr/bin/vulkaninfo" --summary >/tmp/vulkaninfo.log 2>&1 || {
    cat /tmp/vulkaninfo.log /tmp/xvfb.log
    exit 1
}
cat /tmp/vulkaninfo.log
grep -q -E 'llvmpipe|Venus' /tmp/vulkaninfo.log
echo VINIX-DOTA2-VULKAN-ENUMERATE-PASS

"$root/usr/bin/vkcube" --width 320 --height 240 --c 3000 >/tmp/vkcube.log 2>&1 &
cpid=$!
# Capture when the first scene appears, before a fast software renderer
# closes its window. The final 320x240x4 bytes are the XWD pixel payload.
attempt=0
while [ "$attempt" -lt 120 ]; do
    kill -0 "$cpid" 2>/dev/null || { cat /tmp/vkcube.log; exit 1; }
    patterns=$(/bin/busybox tail -c 307200 /tmp/vulkan/Xvfb_screen0 | \
        /bin/busybox od -An -tu4 | /bin/busybox sort -u | /bin/busybox wc -l)
    [ "$patterns" -le 8 ] || break
    attempt=$((attempt + 1))
    sleep 1
done
[ "$attempt" -lt 120 ]
# Kernel messages from other CPUs can land inside this long serial output.
# Send a fixed snapshot twice with numbered lines; the host keeps intact lines
# and checks the reassembled image against its hash.
/bin/busybox cat /tmp/vulkan/Xvfb_screen0 >/tmp/vkcube.xwd
shot=$(/bin/busybox sha256sum /tmp/vkcube.xwd | /bin/busybox cut -d' ' -f1)
echo VINIX-DOTA2-VULKAN-SHOT-BEGIN
for copy in 1 2; do
    echo "VINIX-DOTA2-VULKAN-SHOT-SHA256: $shot"
    base64 /tmp/vkcube.xwd | /bin/busybox awk '{ print "S" NR " " $0 }'
done
echo VINIX-DOTA2-VULKAN-SHOT-END
status=0
wait "$cpid" || status=$?
cat /tmp/vkcube.log /tmp/xvfb.log
[ "$status" -eq 0 ]
kill "$xpid"
trap - 0
echo VINIX-DOTA2-VULKAN-PASS
exec /bin/sh </dev/console >/dev/console 2>&1
