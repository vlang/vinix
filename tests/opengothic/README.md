# OpenGothic in the Vinix desktop

`run.py` boots ARM64 Vinix under QEMU/HVF with only what the game needs: the
desktop, Xvfb, the X11 input bridge and the OpenGothic layer. The desktop
opens its Gothic II window, the test presses Return in the game's menu to start
a new game, and the world then has to render for `--seconds` (60 by default, after a 10-second warmup)
without the engine crashing or exiting. It fails on a crash log, a kernel panic
or a game that has gone, and leaves `gothic.png`, a capture of the whole
desktop, and `vinix.log`, the serial console with the engine's log, in
`--work`.

```sh
./build-opengothic-aarch64.sh --demo
./build-desktop-aarch64.sh --no-initramfs
python3 tests/opengothic/run.py --work build/opengothic/test
```

It needs the X11 and userland layers (`build-aarch64-x11`,
`build-aarch64-userland`), a built kernel, `aarch64-linux-musl-gcc`, and
Pillow for the capture. `--repo` names another checkout to take the layers and
`run-aarch64.sh` from, `--kernel-dir` another kernel, `--build` another
OpenGothic build directory and `--desktop` another desktop binary.

Two things differ from an installed system. The test removes the game's intro
video from its copy of the data: a new game plays it once the world has
loaded, and the engine's report that it is missing is what tells the test the
world has started. And it compiles the X11 input bridge from this checkout
rather than take the one in the X11 layer, which may be older than the desktop
under test: a bridge from before `dcf3da61` sends Return as Ctrl+J, and the
menu ignores that.

The key is sent through QEMU's QMP socket, so it travels the whole path a real
keyboard does: the kernel's console, the compositor, the Gothic II process, the
bridge and XTEST.

For native GPU validation, build the private Venus runtime and select KekVM:

```sh
./build-venus-aarch64.sh
VINIX_KEKVM_DIR="$HOME/code/kekvm" python3 tests/opengothic/run.py \
    --venus --work build/opengothic/venus-test
```

`--venus-runtime` selects another staged runtime. Before opening the game,
the guest runs the [native DRM and GPU tests](../virtio-gpu-venus/README.md).
The harness requires their pass markers and the Venus GPU name, records
steady gameplay FPS from the Mesa overlay in `performance.json`, and fails
below a median of 55 FPS. `--min-fps` changes that threshold explicitly.
Menu and loading frames are excluded. The Vulkan overlay also appears in the
screenshot. `--cpus` defaults to four; `--engine` selects an instrumented
engine executable for profiling. Use a normal kernel, without `ALLOC_TRACK`,
for performance measurements.

The accelerated Debian comparison is documented in [kekvm.md](kekvm.md),
with a guest build and launch helper. It exercises KekVM's Venus backend on
the Apple GPU, independently of this Vinix desktop test.
