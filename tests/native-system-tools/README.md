# Native system guest controllers

These fronts compile and run V directly. The original guest C workloads remain
unchanged; no Python query, package server or object bridge runs on this path.

| Front | Workload |
| --- | --- |
| `tests/disk-root/run_vm`, `run.sh` | Installed ext2 root, large host file, package merge and guest reboot |
| `tests/disk-writeback/run_vm`, `run.sh` | Original 768 MiB stream and responsiveness limits on an 8 GiB volume |
| `tests/docker/run_vm` | Supplied init/archive, first verdict, repeated failure markers and raw log |
| `tests/openbsd-security/run_vm`, `run.sh` | Exact feature counts, pledge report and packet randomness |
| `tests/mount-policy/run_vm`, `run.sh` | Exact mount-policy feature counts |
| `tests/ipv6-multicast/run_vm`, `run.sh` | Socket features, physical packet checks and host IPv6 echo |
| `tests/numa/run_vm`, `run.sh` | Two-node topology, placement features and clean exit |
| `tests/paging/run` | Dedicated encrypted swap, normal/pressure guests on both architectures |
| `tests/securelevel-boot/run` | Five valid policies and three expected boot rejections |
| `tests/securelevel-boot/persistent` | Native ext2 enforcement and host persisted-flag inspection |

Each `run.sh` fixture front builds the unchanged C payload with strict warnings.
The controller snapshots a selected **prebuilt** kernel and never rebuilds it.
Use `--kernel-dir DIR`, `--state-dir DIR` and `--build-only` to select a kernel,
retain artifacts or prepare without booting. Provided image/init/archive and x86
ISO interfaces remain available. Explicit states retain raw serial, guest ELFs,
archives, disks and launch hashes; default scratch is removed. Docker requires
an explicit state. Architecture spelling remains `amd64` for the security family
and `x86_64` for paging/securelevel. Each front supplies `--help`.

The root installer preserves the original size/mtime identity, installed-disk
reuse, capacity and carried `/root`. Saved packages merge into ext2, without a
second boot module. The paging header is the original Linux version-one header
on a fresh 256 MiB swap image. Boot policies, deadlines, failure markers, feature
counts and packet thresholds retain their original assertions. Docker keeps its
first verdict even after a later failure or nonzero exit; NUMA rejects forced or
nonzero exit. Cleanup bytes cannot supply a missing verdict. The PTY owner stops
and reaps the entire process group and closes descriptors on every path.
IPv6 workers join before listener closure, preserve delayed TCP peers and echo
empty UDP datagrams. Quoted extra QEMU arguments remain supported on the original
ARM Docker/root/NUMA/security paths.

`check-system.v` checks independent marker/packet controls, all pcap byte orders,
truncation including unsigned lengths above INT_MAX, modulo wrap, the swap header,
binary and empty IPv6 echo, delayed/silent peers, fragmented serial, late failures,
exit status, descendants, SIGINT and repeated descriptor closure.
`check-system-cli.v` takes a compiled controller prefix, host profile suffix and
kernel directory. It uses a controlled serial process through the full SDK/CLI
path to check Docker overlays/logging/first verdicts, root image reuse/home carry/
package merge and quoted argument forwarding. These controlled checks do not
execute a guest kernel.

Qualification on 2026-10-11 uses ARM, Rosetta x86 and ARM ASan/UBSan hosts.
All ten commands and both checkers build cold on each profile. Host and complete
CLI checks pass on all three. Ninety strict guest SDK preparations cover the
original fixtures, both architectures, pressure selection and all eight boot
policy cases on every profile. Sixteen public fronts also build cold from `/tmp`.

Real TCG guests pass OpenBSD security, mount policy, normal paging, 256 MiB
pressure paging and all eight securelevel policies on both architectures. ARM
NUMA, disk-root reboot, the complete 768 MiB writeback workload and securelevel
ext2 enforcement/host inspection pass. IPv6 physical features and required
packets pass on both; the unchanged membership-retention assertion at test.c:227
fails on both frozen kernels. Those failures remain failures. Docker daemon
staging is absent, so Docker and nested-QEMU smoke workloads were not requalified;
their complete controller path is qualified with controlled processes.

Frozen ARM kernel SHA-256 is
`8866c72f19cba5f95ff22070e193b25cbe0cf57ae89e306067b16a82dba7289f`;
x86 is `f408720b8918d7de51295d6b101e5b070cfa4257bc85b833b80ef4e0dcfe8268`.
No kernel was rebuilt and no Python was run. Local qualification receipts and
logs are under `/Users/alex/.cache/vinix-python-zero-process-20261011/system-*`.
Redundant boot images and the completed writeback disk are retired only after
hashing, with receipts kept; maintained commands do not depend on those paths.
The twelve Python entry/binding files and unused query bridges are retired.
