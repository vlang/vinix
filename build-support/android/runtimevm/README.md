# Android runtime guest preparation

`tests/android/run-runtime-vm.py` retains the command-line parser and early
validation. This module owns runtime/probe staging, dependency closure,
initramfs construction, provenance records, architecture launch plans and the
existing guest marker/result policy. Upstream tool invocations and fixture
sources are unchanged.

The synchronous `_boot_native.py` bindings borrow actual Python paths,
callbacks, mappings, streams and exceptions. Archive managers are distinct
from their entered values, consumed before exit, and honor suppression and
cleanup precedence. Temporary digest input and hasher references retire after
the corresponding expression under the incoming caller context while actual aliases returned by a callback
remain alive. The module uses the host collector, independently of the
kernel's manual allocation discipline.

Host qualification compares frozen original workflows on native ARM,
Rosetta x86 and ARM with ASan/UBSan. Guest markers and deadlines are preserved;
host plan checks alone do not establish a fresh kernel, Android runtime build
or QEMU guest result.
