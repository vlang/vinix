# Experimental XNU allocator translation

Source: apple-oss-distributions/xnu at f6217f891ac0bb64f3d375211650a4c1ff8ca1ea, osfmk/kern/zalloc.c (blob 0d79c2dd58f8eed4e8f80834fa1e3b9b43675eff).

This commit publishes the previously delivered bitmap, metadata-buddy, and magazine/depot translations. It does not enable them as the kernel heap. The original notices are retained in every translated file. The exact upstream APPLE_LICENSE is included alongside the code. Translation changes are marked 2026-09-11. These files remain under APSL 2.0, not GPL; this experimental branch makes no claim that a combined distribution is license-compatible.

This is not the complete XNU allocator. Kernel integration and additional zone state-machine tests are separate commits. Host CI downloads a checksum-pinned V toolchain and runs debug and production V tests. A workflow recipe is not a successful test result. No production readiness or performance improvement is claimed.
