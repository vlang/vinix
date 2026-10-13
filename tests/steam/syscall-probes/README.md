# Native Steam syscall probes

`steam-init.sh` invokes `/usr/bin/steam-syscall-probe` for the six original
prerequisite checks. The Steam staging recipe builds and installs this static V
executable through `build-validation-guest`.

The checks retain the System V semaphore fork/wake and five-second child alarm;
the eventfd roundtrip and pread into an untouched 64 KiB mapping; Unix epoll
hangup with `ab`, `c`, EOF; IPv4 recvmsg with spare ancillary storage; 150 ms
empty ppoll with a 100 ms minimum; and the 26,214,416-byte exclusive shared file
with mapped endpoints. The shell keeps its original verdict lines, failure
messages and five-second wrappers for IPv4/ppoll. Native structures come from
the real musl headers; C integer fields use their fixed-width types. ARM uses
ppoll syscall 73, and x86 uses 271.

Resources retire on errors. Successful probes also check close, munmap and
unlink results, and the semaphore parent reaps its child on every path. The
eventfd closes before the lazy file-buffer phase. No first-party Python source,
evaluation strings or interpreter bridge remain in these probes.

The three embedded launcher timeout blocks also use V. `hosted-command/run`
invokes a native command owner with the original 20-second bound. The existing
launcher fixtures still test initial installation, an installed client and an
updater retry, including exact arguments and stylesheet changes. Tests can set
`VINIX_STEAM_HOSTED_COMMAND` to a freshly compiled profile executable.

```sh
build-support/run-v-tool.sh tests/steam/qualify-probes.v \
  /path/to/qualified/v /fresh/evidence arm /path/to/arm-kernel /path/to/x86-kernel
# Also x86 or san for the host controller and builder.
```

Qualification builds the host launcher/controller and guest producer for ARM,
Rosetta x86 and ARM ASan/UBSan, plus production and test-only static guest ELFs
for both architectures. Each profile boots private RAM-only Linux SDK VMs;
each VM repeats all six probes ten times and checks descriptors, mappings,
probe files and child retirement. The reference kernels come from Alpine's
official [ARM](https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/aarch64/netboot/)
and [x86](https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/netboot/)
netboot directories, with the exact downloaded bytes hashed in the receipts.
Mapping retirement is checked with `mincore` immediately after each successful
`munmap`, before any later allocation can reuse that address. Counting all
process VMAs would include the test process's V allocator arenas.
The V qualifier writes its own newc/gzip initramfs; it executes no SDK installer
or Python. `steam_probe_sdk` enables only the private test boot mode, mounts
guest tmpfs/procfs, enables guest loopback and powers that VM off after passing.

These are real Linux syscall and cleanup checks. They establish reference SDK
behavior; they do not establish a new Vinix-kernel, Steam-client or graphical
runtime pass. Host sanitizers instrument the native host tools; the Linux probe
ELFs use the normal static musl build. The nine embedded blocks receive zero
Python-file retirement credit because their containing files were Shell.
