# OpenGothic on KekVM's GPU

KekVM's prepared **Debian ARM64** guest can run this engine on Venus, backed
by the Apple GPU. This tests the renderer on accelerated virtual graphics;
Vinix's kernel and desktop are tested by `run.py` separately.

The verified configuration uses OpenGothic
`26b7159230834780fc6a8fc9aa0d060863cb443f` with the same two Tempest patches
as the Vinix build, the public Gothic II demo, Debian's 16 KiB-page kernel,
Mesa 25.0.7 Venus, and `Virtio-GPU Venus (Apple M5 Max)`. The game draws its
world in an X11 window, accepts movement and dialogue selections, and uses
full internal resolution (`vidResIndex=0`). Audio remains disabled in this
test.

A 60-second sample of gameplay in Xardas's tower at 1280×720 recorded 117
Mesa overlay samples: **57.98 FPS median**, 37.87 minimum and 70.61 maximum.
This covers the demo's opening scene. The engine remained running for over
15 minutes without a crash. [Screenshot](../../docs/screenshots/kekvm-opengothic.png).

First stage the engine source, Vulkan headers and demo with
`./scripts/build-opengothic-aarch64.sh --demo`, and prepare the GPU guest in
`~/code/kekvm` as its README describes. Boot the GPU disk in a snapshot, with
private firmware variables and a read-only 9p share of the build directory.
These are KekVM's Venus arguments with that share added:

```sh
gothic_work="$PWD/build/opengothic/kekvm"
kekvm_dir="$HOME/code/kekvm"
guest_dir="$HOME/.local/share/v3-qemu-debian13"
qemu_dir="$kekvm_dir/.tools/qemu-virgl"
mkdir -p "$gothic_work"
cp tests/opengothic/kekvm-guest.sh "$gothic_work/guest.sh"
cp "$guest_dir/kekvm-gpu-vars.fd" "$gothic_work/vars.fd"
VK_DRIVER_FILES="$qemu_dir/share/vulkan/icd.d/libkosmickrisp_icd.json" \
DYLD_FALLBACK_LIBRARY_PATH="$qemu_dir/lib:/usr/local/lib:/usr/lib" \
"$qemu_dir/bin/kekvm-qemu-system-aarch64" \
  -name 'OpenGothic GPU test (Debian)' \
  -machine virt,gic-version=3,accel=hvf,highmem=on -cpu host -smp 8 -m 16384 \
  -drive "if=pflash,format=raw,readonly=on,file=$qemu_dir/share/qemu/edk2-aarch64-code.fd" \
  -drive "if=pflash,format=raw,file=$gothic_work/vars.fd" \
  -drive "if=none,id=osdisk,file=$guest_dir/kekvm-gpu.qcow2,format=qcow2" \
  -device virtio-blk-pci,drive=osdisk,addr=2 \
  -drive "if=none,id=seed,file=$guest_dir/seed.iso,format=raw,readonly=on" \
  -device virtio-blk-pci,drive=seed,addr=3 \
  -device virtio-keyboard-device -device virtio-tablet-device \
  -device virtio-gpu-gl-pci,addr=4,blob=on,hostmem=4G,venus=on \
  -display cocoa,gl=es -nic none -snapshot \
  -fsdev "local,id=gothic,path=$PWD/build/opengothic,security_model=none,readonly=on" \
  -device virtio-9p-pci,fsdev=gothic,mount_tag=gothic,addr=5 \
  -qmp "unix:$gothic_work/qmp.sock,server=on,wait=off" \
  -chardev "socket,id=qga0,path=$gothic_work/qga.sock,server=on,wait=off" \
  -device virtio-serial-device \
  -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
  -serial "file:$gothic_work/serial.log" -monitor none
```

Use `kekvm-control.py` on the host to execute guest commands and copy files
through the guest agent, which works without network access:

```sh
python3 tests/opengothic/kekvm-control.py --socket "$gothic_work/qga.sock" exec 'uname -a'
```

Inside the guest, mount the share and check the GPU before launching:

```sh
mkdir -p /mnt/gothic /tmp/kekvm-gpu
mount -t 9p -o trans=virtio,version=9p2000.L,ro gothic /mnt/gothic
getconf PAGESIZE                     # must print 16384
VK_DRIVER_FILES=/usr/share/vulkan/icd.d/virtio_icd.json vulkaninfo --summary
```

The Debian build needs `g++`, `cmake`, `ninja-build`, `glslang-tools`,
`libvulkan-dev`, `libx11-dev` and `libxcursor-dev`. Xorg, ImageMagick,
`xdotool` and Mesa's overlay layer come from guest preparation; `twm` is an
optional window manager. The accelerated guest is offline, so packages must
be installed during preparation or downloaded on the host and installed
from the share. This run's verified `.deb` files are cached in
`build/opengothic/kekvm/debs`.

Copy `/mnt/gothic/kekvm/guest.sh` to `/root/opengothic-kekvm/guest.sh` and
run it with `build`, then start Xorg using KekVM's `guest-gpu-suite.sh xorg`
step and run it with `launch`. Long builds need `--timeout 600` on the
host controller. Its `put GUEST_PATH HOST_PATH` command can copy KekVM's
suite script into the guest before running its `xorg` step.
The script builds a Debian executable because its glibc Venus driver cannot
load into the Vinix musl executable. Settings, logs and the build stay in
`/root/opengothic-kekvm`, with game assets symlinked to the read-only share.
It skips the intro movie in this private test copy and starts a new game.

For a 1280×720 window on a 1920×1080 screen:

```sh
export DISPLAY=:0
xrandr --output Virtual-1 --mode 1920x1080
window=$(xdotool search --name '^Gothic II$' | head -n 1)
xdotool windowsize "$window" 1280 720
xdotool windowmove "$window" 300 170
xdotool windowfocus "$window"
sh /root/opengothic-kekvm/guest.sh capture
```

Capture through Xorg with ImageMagick, as the helper does: QMP `screendump`
returns black for this VirGL scanout even while the game is drawing.
`game.log` records the selected GPU; `fps.csv` contains Mesa overlay samples
every half second. Exclude loading, window resizing and compilation when
comparing performance. The snapshot's guest writes disappear on exit.

Copy the capture to the host with:

```sh
python3 tests/opengothic/kekvm-control.py --socket "$gothic_work/qga.sock" \
  get /root/opengothic-kekvm/gothic.png "$gothic_work/gothic.png"
```
