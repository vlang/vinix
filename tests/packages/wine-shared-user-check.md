# Wine shared user data and private dispatcher, 2026-11-12

Source baseline: `b96bff645`, plus the implementation and qualification sources
in this checkpoint. This continues [offline bootstrap](wine-bootstrap-check.md)
and the [shared-file alias diagnostic](wine-shared-pages-check.md).

The pinned Wine runtime now maps its private KUSER section as a coherent
16 KiB shared object. Its Windows fixed reader stays at `0x7ffe0000` and
read-only. Wine's per-process syscall dispatcher moves from `0x7ffe1000` to
a separate 16 KiB private mapping at `0x7ffe4000`. Windows' ordinary page size
and the package's permissions are unchanged.

Simply enlarging KUSER overlaps Wine's original private dispatcher page.
The retained failed candidates show why allocation success is insufficient:
one had different fixed/writer contents, and writing the old dispatcher
location corrupted the translated process. The final adaptation changes seven
guarded four-byte instruction operands in the exact original binaries:

| Component | File offset | Purpose |
| --- | --- | --- |
| wineserver | `0x1deac` | Shared section size |
| wineboot.exe | `0x62d2` | Writable initialization view size |
| ntdll.so | `0x5e517` | Fixed shared-data reservation size |
| ntdll.so | `0x5ce35` | Fixed read-only shared mapping size |
| ntdll.so | `0x3c3f9` | Private dispatcher mapping size |
| ntdll.so | `0x3c410` | Private dispatcher mapping address displacement |
| ntdll.so | `0x3c424` | Dispatcher pointer store displacement |

All operands become `0x4000`. The 237 generated ntdll.dll syscall stubs and
426 win32u.dll stubs call the relocated dispatcher. The patch checks every
byte of each numbered stub before changing its address byte, inventories
every old dispatcher literal, and preserves the unrelated WOW64 debug-breakin
sentinel. Original full-file SHA-256 pins, unique instruction guards and
whole-group validation precede mutation. Producer and independent layout
admission derive the complete adapted files from the original inputs.
Existing prefix, NLS, W^X, unwind, graphics and offline-bootstrap adaptations
remain composed and checked. This is a local binary adaptation, without a
complete corresponding-source or redistribution claim.

The real signed Win64 probe opens the server's named section and maps two
writable aliases. On all four 4 KiB subpages, it checks bidirectional writes
against both aliases and the fixed reader, checks isolation of the other
subpages, restores the original scratch words, and checks read-only fixed
protection. It then writes a nonce in unused dispatcher-page space and starts
a second copy of its signed application. The child must see fresh private
storage, write a different nonce and exit successfully; the parent's nonce
must remain unchanged. This runs after the existing exception probes.

The child uses the SDK's admitted immutable application directory and the
prefix's existing Z: mapping. An earlier probe used GetModuleFileNameA; on
translated startup it returned Wine's internal `unix\var\...` form, which
CreateProcess could not reopen. The failed file-not-found attempt is retained;
this fixture correction does not claim to repair that API's general behavior.

The remaining child startup error `731` was traced, rather than waived:
`native-arm-debug-04` records the second `fork()` returning `ENOMEM` in a
1 GiB guest, followed by exit status 1. A separate early-child attempt fails
before the exception probes too. With an explicit 3 GiB ARM guest,
`native-arm-09` passes the complete signed console probe, including coherent
shared data, private child isolation, exception recovery and natural exit.
`native-x86-09` passes at 1 GiB. The kernels, translator and sandbox policy
are unchanged; temporary process/syscall tracing is removed.

The harness keeps its 1 GiB default, accepts explicit workload RAM, and saves
literal structured QEMU arguments. Wine console and GUI qualification request
3 GiB on ARM and 1 GiB on x86. Both retainers require the selected memory
argument and bind that command file into their artifact receipts. All thirteen
harness unit suites pass, including both architectures' memory selection and
invalid-size refusals.

Normal, production and ASan/UBSan byte checks pass all **44 refusals**, exact
seven-field and 663-stub output checks, unchanged input/extent checks and the
preserved sentinel. Full runtime composition passes **30 refusals** and the
existing unwind audit; bootstrap composition passes **10 refusals**. Independent
layout admission passes original/copied baselines and **15 executable/symlink
refusals**. Both fresh console runs pass independent retention and preserve
491 admitted actual parsed sources each.

Complete independent native evidence checks pass all **73 x86 and 82 ARM
refusals**, with original/copied baselines and verified disjoint four-shard
coverage per architecture. New controls restore each shared-data component,
the dispatcher location or either PE stub address while resealing output
receipts, omit either new execution marker, and change the recorded VM memory.
They must fail at their intended admission gates.

Fresh `gui-arm-01` and `gui-x86-01` runs both pass signed USER32 painting,
authenticated ordinary X11 display access, real XTest pointer arithmetic
`13 + 29 = 42`, natural close and fixture process retirement. Both preserve
168 admitted parsed GUI sources. Both pass independent GUI retention and
all **twelve targeted GUI refusals** each, including a changed-memory command.

Raw successful and failed attempts remain at
`/Users/alex/.cache/vinix-wine-shared-user-20261112`, including original input
and output receipts, literal commands, generated C, all PE producers, guarded
patch checkers, dispatcher inventories and diagnostic source variants.
Original namespaces and the complete pinned dependency bundle remain required.
The earlier sealed workspaces remain intact. These local results do not
establish general partial-host-page shared mapping support, WOW64 support,
desktop embedding or completion of roadmap section 14.
