# Native developer tools smoke test

`smoke.sh` runs inside the aarch64 Vinix userland. It validates the packaged
Git, GNU make, CMake, Ninja, Meson, pkg-config, Autoconf, Automake, Libtool,
patch/diffutils, file, GDB, radare2, strace, and tmux programs.

The test creates and commits a local Git repository, compiles and executes C
programs through GNU make, CMake/Ninja and Meson/Ninja, has Autoconf generate a
configure script, checks Automake, Libtool, `file`, GDB and strace startup,
uses `rabin2` and `r2` to inspect and analyze the resulting ARM64 ELF,
resolves a local `.pc` file, applies and verifies a patch, and starts a
detached tmux session. The tmux check verifies its control socket, server
lifecycle, and PTY-backed pane.

Build the package overlay with:

```sh
./build-developer-tools-aarch64.sh
```

The aarch64 userland builder automatically copies the overlay when the staging
directory is present. Run `/root/developer-tools-smoke.sh` in Vinix to execute
the smoke test, or launch `r2 <binary>` for an interactive analysis session.
