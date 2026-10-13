Independent statx lifetime review: PASS

Reviewer: `/root/procstat_lifetime_review`; no edits or commits.
Reviewed the owned kernel source, both candidate C files, probe/wrapper
sources and emitted C, and completed native/Linux reference captures.

The NULL-path branch uses existing fstat ownership: the FD remains held
through copying metadata into the caller's stack scratch and is then released
by existing cleanup. Conversion reads that independent copy after release.
The other branch retains existing fstatat ownership. No new lock, allocation,
escaping pointer or ownership transfer appears. Conversion scratch remains
on the stack. Fixture guards/references/counters/samples and wrapper argv
use stack storage. Every opened descriptor closes on failure/success;
forked cohorts are reaped before inherited descriptors are closed.

Both architectures pass 6214 semantic calls on Vinix and Linux 6.12.51.
The reference boots use byte-identical native probe ELFs. Native retention
checks keep all 18 ARM and 14 x86 live slab classes flat over 200 cycles,
with large pages 63/63 and 160/160 respectively in both credential cohorts.
Each cycle covers 18 successful and refused statx calls.

SHA-256 pins:

- kernel source: 37cf7a0466a468e1bda7c8e3806b894342026f4f6cb5b83a914a8f63194a4e37
- probe source: 8e267e3f8b68c25dfc8544738f019ad8c5039a41d0dc3cab693618eccdd4e57c
- reference wrapper source: 287c38f3cdb71a0b19c44d87051f0496678cdb41216d99f23b78a86340dc6467
- both probe previews: 92a6652ed22bd08afa843023946f6c093f0f660081f4fa0520a9ef3372ae8e5a
- both reference wrapper C files: 57b77ae3cc197551973cfe09e4fc0f2702a7ff977be5367eb55d925dcf2aff27
- ARM candidate kernel C: c2acc81e363cb7cd49f460921723a5a78e65e30d02eaeef8b3486bb6cad35b04
- x86 candidate kernel C: 18b9de262e1a0a1d0a99e8e2051893a4b9768aac2c9762bb0c6c76c252ff75d0
- ARM native serial: f7c8c812a1df5d55e3706b226abbf8a885cea393059f3b13d45b1e290866c1be
- x86 native serial: 3fc4eb9e4538a53a4e7500157032c6e711192283d3df82dcb62d82c7f3e7f869
- ARM Linux reference serial: 6b19ab58c8068b9219ad2a20db0ff09a9ca89e070f7f56cbba7c7f7802f4d0d5
- x86 Linux reference serial: 3a9107fbe07ad058226906b96723699a08335ea160ee0c58f736487c13673d49
- ARM shared probe ELF: 3d52e3d76c2db18050f64c466e938311c942f56e1e7b045cc74524e6619c2df2
- x86 shared probe ELF: 75fc159ad467e7fd1e47660d6229c7e6a4cc6239ab9e7581d42bb36d4307dab3
