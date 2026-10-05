The EGL/GLES and GLUT triangle implementations live in `eglcore/core.v` and
`glutcore/core.v`. `gl_v.h` binds the native graphics, framebuffer and libc
ABI. The V programs retain the original fixed buffers, callback lifetimes and
explicit image allocation/free behavior.
`legacycore/core.v` preserves the separate small GLUT demo originally embedded
in the userland image builder, including its original colors and callbacks.

Generate an EGL build artifact with
`python3 gl-triangle/compile-v.py /tmp/egl_triangle.c --arch arm64`, then
compile it against the target EGL/GLES userspace with `-std=gnu11 -fwrapv
-fno-strict-aliasing -Igl-triangle`. Use `--kind glut` for the GLUT demo.
`stage.py` packages the maintained V, ABI header and generated C artifacts for
guest rebuilding; generated C is not maintained source.

Run `python3 tests/gl-triangle/run.py` for independent sanitizer fixtures.
`USE_TCG=1 python3 tests/gl-triangle/run-vm.py --kernel-dir <isolated-kernel>
--state-dir <new-directory>` cross-builds an ARM executable, assembles the
matching local Mesa runtime and runs the original eight fake-G17 guest checks.
It requires the ARM userland and Asahi staging directories used by the build
scripts. Physical AGX operation remains untested.
