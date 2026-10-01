# OpenGothic in the Vinix desktop

`run.py` boots ARM64 Vinix under QEMU/HVF with only what the game needs: the
desktop, Xvfb, the X11 input bridge and the OpenGothic layer. The desktop
opens its Gothic II window, the test presses Return in the game's menu to start
a new game, and the world then has to render for `--seconds` (30 by default)
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
