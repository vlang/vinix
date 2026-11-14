# AMD64 boot/input validation — 2026-11-12

Tested source: `554908ef42328f35076e848c0c95a34cf8494994` plus the
`vinix-default-qemu-source.patch` retained in the evidence archive. Its SHA-256
is `ef5a9712d4bd03912399aeaa092eaace7db2a1d54423c126e03f03c11b89926d`.
The patch contains the implementation and regression tests in this commit.
Userspace comes from `iso-2026-11-12`, release target
`40f802e9575fbb89912518e6b6908ffffc8933fe`.

Host tools: QEMU 10.2.1, V 0.5.2 (`7d4bed6`), Clang 21.0.0, Linux x86_64.

| Check | Result |
| --- | --- |
| Default QEMU, 2 GiB, desktop cursor movement and typing | Pass |
| BIOS KVM, one CPU, no HPET | Pass |
| UEFI q35 KVM, two CPUs, SATA installation and subsequent disk boot | Pass |
| USB mouse/keyboard with i8042 disabled | Pass |
| Pointer ABI, immediate motion, five buttons, keyboard and wheel; default TCG, four-CPU q35, single-CPU KVM | Pass |
| Five decoder unit tests, V formatting, diff whitespace and shell syntax | Pass |

The original release kernel fails immediate input in the tiny fixture. With
a 500 ms delay it passes movement/buttons/keyboard but fails scrolling;
single-CPU KVM still loses input. The fixed fixture also exercises repeated
1 ms sleeps to detect timer starvation. Physical hardware, VirtualBox,
suspend/resume and arm64 were not tested.

Evidence archive (release and fixed ISOs, kernels, fixture, source patch,
build logs, boot logs, screenshots and command lines):
`/home/pancake/vinix-artifacts/default-qemu-2026-11-12/evidence.tar.gz`

SHA-256: `c8e44a7a013a55ce49f42c972d26ae449f1324ac2d8e5534da39642efd25e761`

Rebuilt desktop ISO:
`/home/pancake/vinix-artifacts/default-qemu-2026-11-12/vinix-amd64.iso`

SHA-256: `ce87553119c1464ca81ac9497aa660ce8478429b7242ecd768f1c6fc20ce499b`
