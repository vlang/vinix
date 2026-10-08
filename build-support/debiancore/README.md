# Debian package preparation policy

`debian-root.py` retains its public dataclass, function signatures and CLI. This
module owns index and relation parsing, dependency resolution, hash and download
policy, lazy ar member traversal, extraction policy and the six-worker staging
workflow. The shared Android host bridge supplies interpreter/library calls and
retains caller-owned objects and original exceptions; no resolver or extraction
algorithm remains in the bridge.

Ar names, sizes, slices and offsets stay opaque interpreter objects. Public
iteration remains lazy, including malformed, negative and custom wide integer
cases. Extraction selects the first data archive and preserves the original
path guard, hard-link copying, mode policy and archive-associated read streams.
Entered output and tar owners retire in the original nested order. The transport
retires outstanding owners with `ExitStack` after unexpected controller exit.
Manager suppression, exception replacement and intentional traceback changes
are retained; IPC and replay frames are additional, so exact traceback frame
lists are not promised.

The source was frozen at `4627fe6397cc66043d83e12dd1375ebfbbbe3c4f`:
10,017 bytes / 251 lines. The port moves 7,901 bytes / 175 lines of policy and
removes a net 4,957 Python bytes / 122 lines after counting 829 bytes of shared
primitive additions. First-party Python bindings remain counted by Linguist.

Qualification compares the frozen implementation and production V core on
ARM64, actual x86-64 and ARM64 ASan/UBSan: 242 policy/workflow/error controls,
21 CLI/live-curl/FD/interrupt controls and seven abrupt-exit/spawn controls per
profile. The unchanged Vulkan staging suite is run against a committed Mesa
baseline. Shared Android and Alpine regressions and cold native installation
also qualify the binding closure. These are host workflow checks; they do not
claim a full game build, guest boot or physical device validation.

Machine-local evidence is in
`~/.cache/vinix-python-to-v/debian-root-20261009/`. The root migration record pins
the committed receipt and source revision; no machine-local binary is maintained
source.
