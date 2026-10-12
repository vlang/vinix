# Host identity through Alpine commands

`run` executes the imported Alpine BusyBox, the installed Vinix `uname`,
`sysctl`, `cat`, `arch`, and `hostname` in a standalone QEMU guest. It checks
both kernel reports and the staged OS metadata and login banners, then repeats
the kernel identity checks from a child in a private UTS namespace.

```sh
tests/userland-identity/run --arch aarch64 --kernel-dir /path/to/kernel \
  --sysroot /path/to/alpine/staging --state-dir /tmp/identity-arm
tests/userland-identity/run --arch x86_64 --kernel-dir /path/to/amd64/kernel \
  --sysroot /path/to/amd64/staging --state-dir /tmp/identity-x86
```

`--audit` copies the existing image's metadata and prints the observations
without enforcing Vinix branding. Use a fresh state directory per invocation.
The ARM fixture compiler uses `VINIX_AARCH64_SYSROOT` when set; the default is
the repository's `build-aarch64-userland/sysroot`.

The host's `uname`, `/proc/version`, `kernel.ostype`, and `kernel.osrelease`
must agree on Vinix 0.1.0. Private UTS namespaces retain Linux 5.15.0-vinix for
Linux container applications. `/etc/os-release`, `/usr/lib/os-release`, and
`/etc/lsb-release` describe Vinix, and login messages welcome the user to Vinix.

Alpine BusyBox hardcodes the operating-system label of its own `uname -o`
applet to Linux. The normal `/bin/uname` and `/usr/bin/uname` commands correct
that label without modifying BusyBox. The audit records the direct applet's
label separately. Compiler target triples and `/etc/alpine-release` retain
their Alpine package provenance; they do not describe the running kernel.

`build-support/stage-uname.sh` now delegates to the V identity stager. All four
base-userland and desktop builders already call this entry point after merging
package layers. It replaces individual metadata links atomically, including
absolute guest symlinks, without following them into the host. The desktop's
content fingerprint includes the stager's V sources so cached images pick up
identity changes.

Host staging checks:

```sh
v -nocache -cc clang -stats build-support/identitycore/core_test.v
```
