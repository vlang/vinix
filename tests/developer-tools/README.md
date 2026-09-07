# Native developer tools smoke test

`smoke.sh` runs inside the aarch64 Vinix userland. It validates the packaged
Git, GNU make, CMake, Ninja, Meson, pkg-config, Autoconf, Automake, Libtool,
patch/diffutils, file, GDB and strace programs.

The test creates and commits a local Git repository, compiles and executes C
programs through GNU make, CMake/Ninja and Meson/Ninja, has Autoconf generate a
configure script, checks Automake, Libtool, `file`, GDB and strace startup,
resolves a local `.pc` file, and applies and verifies a patch.

Build the package overlay with:

```sh
./build-developer-tools-aarch64.sh
```

The aarch64 userland builders automatically copy the overlay and run the smoke
test at boot when the staging directory is present.
