# Remaining Python retirement review

The complete retirement is prepared on `codex/python-zero-b59d1939`, with source
commit `66332acaf0e48b281e839b6f1643f01b3e36bff5` and inventory commit
`3779ab44f59b72dcc68488b491fe516ae36ad802`. That isolated snapshot has no
committed `.py` files and Linguist reports zero Python bytes. The main checkout
still has 14 committed Python files; its inventory counts ten of them, totaling
89,440 bytes. Four PSP scripts are excluded by the existing language rules.
An additional iOS Python bridge is staged in the shared index.

The main checkout's pending work was rechecked against inert backups on
2026-10-13. All 15 current Python sources match the saved review snapshot.
Four paths contain concurrent changes and must be coordinated before applying
the retirement:

| Pending path | Native replacement | Behavior already retained |
| --- | --- | --- |
| `tests/ext2-xattr/run.py` | `tests/ext2-xattr/run`, `tests/native-ext2-run/xtcontroller` | Default V fixture, explicit C/prebuilt fixtures, fixture-source and ELF evidence, ACL seeding, both architectures, reboot inspection |
| `tests/ios/run.py` | `tests/ios/run`, `tests/native-ios-run` | Original switches, assets, image mutations, native PSP fetches, guest-init build, archive and VM supervision |
| `tests/ios/_native.py` (staged addition) | Direct native iOS controller | Replaces the newly staged borrowed-object import bridge with the maintained V entry point |
| `tests/linuxkpi/compile-v-fixture.py` | `tests/linuxkpi/compile-v-fixture`, `tests/native-linuxkpi-tools/kpihost` | The additional `rcufixture` module is already in the native producer's accepted module list |

The isolated retirement removes the committed versions of the three existing
pending paths. Applying it to main also requires retiring the staged
`tests/ios/_native.py` addition. The original source and pending edits are saved
as inert `.source` data outside the repository at
`~/.cache/vinix-surface-native-20261013/legacy-retirement`. The isolated branch
preserves the committed originals separately in
`~/.cache/vinix-python-zero-native-20261013/committed-originals`.

The other eleven Python paths have no pending edits, but their dependency
closure overlaps the staged iOS work. That controller loads
`tools/_package_store_native.py`, which uses the shared host adapters; it also
calls the four PSP `.py` fetchers and imports `tests/realtime/run_vm.py`.
The ext2 Python controller imports the kernel-gap Python runner. Deleting the
clean adapters alone would leave these pending controllers with missing inputs.
Retire this connected set together after the coordination decision.

The prepared branch qualified 27 cold builds of nine maintained entry points,
15 cold controller/model builds and 24 Android closure builds across ARM,
Rosetta x86 and ARM ASan/UBSan. Controlled iOS staging and VM ownership,
ext2 C/prebuilt/ACL/error/signal workflows, guest verdict/QMP/UTF-8/signal checks,
300 descriptor/PID retirement cases, pinned PSP download/ZIP/cache/error checks,
300 failed archive constructors and the Android closure pass with the adapters
absent. The ext2 V fixture retains its documented `memdup` build failure;
its C/prebuilt workflows pass. No Python, SDK interpreter initialization,
graphics application or Vinix guest executed in that qualification.

Apply only the retirement paths and related documentation to the current main
tree, preserving subsequent V ports and unrelated staged files. Regenerate the
inventory from the resulting commit instead of copying the older branch's
language totals. Existing implementation-port credit must not be counted twice.
Historical object-bridge modules remain provenance; maintained entry points
invoke V directly.
