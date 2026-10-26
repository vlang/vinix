The kernel replacement tool applies a frozen AArch64 kernel build to a fresh,
unlaunched browser diagnostic stage. Create the stage with `stage.v` from the
unchanged r8 browser bundle and the original Maps372 media, then run:

```sh
v -prod -path '@vlib|build-support|build-support/android' -o /tmp/browser-patch-kernel tests/android-webview-browser-probe/patch-kernel.v
/tmp/browser-patch-kernel --self-test
/tmp/browser-patch-kernel FRESH_STAGE FROZEN_KERNEL_BUILD BUILD_JSON_SHA256
```

The explicit receipt SHA256 pins `FROZEN_KERNEL_BUILD/build.json`. The tool checks
its kernel, Unix socket source, complete `sha256.json` inventory and symlinks.
The receipt identifies the source revision, AArch64 architecture, generated C,
compiler, deterministic link seed and absence of guest execution. The build's
`input-pins.json` retains the complete source input pins.

Only the fresh stage's `::/boot/vinix` changes. The tool checks the original
Maps372 boot image, both Limine configurations, the baseline kernel, every
original module and the exact browser overlay before installation. Kernel and
module readback checks follow installation; firmware and source media remain
pinned. A stage with launch evidence or an existing patch is rejected.

`stage-before-kernel.json` preserves the original stage receipt. `stage.json`
retains its existing baseline and payload pins, updates the boot image hash and
adds the kernel provenance. `kernel-patch.json`, the carried tool/source, command
receipts and copied build receipts preserve the verification chain. Keep the
complete frozen kernel build alongside the stage; copied receipts do not replace
its source and artifact inventory. Interrupted replacement leaves a once-only
request or command directory; create another fresh stage instead of retrying it.

The self-test uses small real FAT images to check kernel replacement, module and
overlay preservation, unchanged firmware, receipt preservation, wrong build-pin
rejection and rejection of a second patch. It also checks malformed Limine paths,
inventory traversal, symlink substitution and historical launch guards.

Run a syscall regression separately before the unchanged browser guest command
when collecting evidence. This tool does not launch QEMU or change the browser
payload. Its results establish installation and byte preservation, not syscall
behavior, a functioning browser or Google account login.

The stager accepts an optional final `REGRESSION_BUILD_ROOT` after the authority
fixture argument. Its existing calls with four or five arguments still work.
The additional complete frozen fixture is inventoried under
`/opt/vinix-unix-recvmsg-flags`, using the same collision and overlay readback
checks as the browser and authority fixtures. Its reviewed build receipt,
executable hash, kernel source hash and complete manifest are checked before
staging. Run `/opt/vinix-unix-recvmsg-flags/guest > /dev/console 2>&1` before
`/opt/vinix-browser-probe/bin/browser-guest` and preserve both outputs. Staging the
regression does not establish that it passed in the guest.
