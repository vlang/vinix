# Mesa Venus for Vinix

`./build-venus-aarch64.sh` cross-builds Mesa 25.0.5 for ARM64/musl, with only
the Vulkan Venus driver, X11 presentation and the FPS overlay. Mesa's archive
and the Alpine 3.21 build dependencies are checked against pinned hashes.
The runtime is staged under `build-aarch64-venus/staging/opt/venus` and stays
separate from the X11 and Lavapipe libraries.

The build needs the ARM64 musl cross toolchain, Python, Ninja, pkg-config and
OpenGothic's staged Vulkan loader, headers and host glslang tools. Build the
engine first with `./build-opengothic-aarch64.sh --demo` or `--game`.
`VINIX_VENUS_BUILD_DIR` and `VINIX_OPENGOTHIC_BUILD_DIR` override those outputs.

Boot with `VINIX_KEKVM_DIR="$HOME/code/kekvm" ./run-desktop-aarch64.sh --venus`.
KekVM must have its GPU backend prepared with `make setup-gpu`. The launch
script uses its private QEMU, ANGLE, virglrenderer and KosmicKrisp Vulkan-on-
Metal backend. Vinix's 16 KiB pages match Hypervisor.framework's host mappings.
The modern PCI GPU negotiates blobs and context initialization and reserves
a 4 GiB host-visible aperture. Mappable host buffers use the device-reported
cache attributes in both kernel and user mappings. GEM references retain
buffers until every handle, PRIME descriptor and mapping has gone away.

`vinix.patch` lets Venus discover Vinix render nodes without Linux sysfs and
present GPU readbacks to Xvfb through MIT-SHM. Rendering remains on the host
GPU. Shared image storage is reused only after an X server round trip, and
server attachments are removed before client storage is released. An X11
present worker waits for each image's GPU fence before copying its readback,
allowing the game to encode the next frame concurrently. This path avoids
Venus's redundant queue-wide present wait, while retaining the per-image
fence and X server completion checks.

Short Venus waits poll for at most 2 ms before entering the driver's sleeping
backoff. QEMU/HVF deliberately skips host sleep for intervals below 2 ms,
which kept idle CPUs busy and contending with GPU work. On macOS the Venus
launcher prepares a private QEMU copy with a 100 µs cutoff and enables
Vinix's 1 ms virtual idle timer. `prepare-qemu.py` verifies the Mach-O symbol
and complete instruction sequence before changing and signing that copy;
an unknown bottle fails with an error. The original KekVM executable stays
unchanged. Ordinary QEMU boots use a 4 ms virtual idle interval.

The current kernel transport waits for host fences synchronously. Venus control
commands use CPU ring zero; explicit queue indices use their GPU timeline.
External blob teardown waits for the host aperture unmap response; it does
not wait for an unrelated legacy GL fence. Host SHM and Metal references
manage their remaining lifetime independently. Exported
fence descriptors are readable once complete; timeline syncobj submission is
not advertised. The launcher selects Venus only after probing its required
capabilities, and honours an explicit `VK_ICD_FILENAMES` selection.

[OpenGothic's test](../../tests/opengothic/README.md) measures gameplay and
captures the native desktop; [GPU tests](../../tests/virtio-gpu-venus/README.md)
exercise fence descriptors, shared buffers and repeated teardown.
