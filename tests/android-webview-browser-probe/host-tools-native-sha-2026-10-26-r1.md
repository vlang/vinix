The kernel patcher and guest runner now use Darwin CommonCrypto for streaming
SHA256. They still read and hash every input byte and retain all existing
inventory, module, firmware, process ownership and guest lifecycle checks.
Implementation revision: `078162809`.

Both tools were built with the pinned old V compiler and `-prod -cc clang`;
retained compiler commands show `-O3 -flto`. Their existing self-tests pass,
including browser and Maps FAT replacement, bad input pins, module readback,
foreign-process rejection, stopped and disappeared guests, and socket cleanup.
The new digest tests cover empty and `abc` known vectors, SHA256 padding
boundaries and reads around the 1 MiB buffer boundary, compared with V SHA256.
Independent source review found no material issue. Timed self-tests took 2.00
seconds for the patcher and 2.08 seconds for the runner; these small fixtures
are not a full-image throughput benchmark.

The complete audit bundle is outside Git at
`/Users/alex/.local/state/vinix/android/maps-host-tools-native-sha-2026-10-26-r1`.
Its sibling `maps-host-tools-native-sha-2026-10-26-r1-sha256.json` inventories
every child's contents, mode and symlink target; write and check both passed.
Inventory SHA256:
`f710cc58e3d9fe86e9b9df69d34afe6f46e20102423e558dd8b338bfc4459c0c`.
`build.json` SHA256:
`cd89bbe069cca2a144912c0d946c7a9af6ee8a5c14ea03ff93c0cd4088751ada`.

| Tool | Entry source SHA256 | Executable SHA256 |
| --- | --- | --- |
| `patch-kernel` | `2186c55bfc784169d923cd4e83e0e2911850b9f81a32a807d8acc82a2cd9d3a1` | `9e82397448550bac98ab1ebd345191136ff2498a70d8f4a2059dbefe767a6701` |
| `run` | `f8e15d06651efaafee55c0ee92093b577d9f7dfd800c17dee01ebd1fe7b64741` | `5bd202a83f0b049ae00376d93691af4b22fab03837356271883a7d515cabb5c2` |

`host-tool-receipt --native-sha BUNDLE PINNED_OLD_V` checks these exact source
pins, source bytes embedded in each executable, compiler pin, optimization
commands and exactly one native digest regression PASS marker per self-test.
The historical three-tool receipt profile and its exact pins remain supported.
The bundle retains logs, entry sources, recorder and consumed native link
objects. The original complete compiler dependency bundle remains required:
`/Users/alex/.local/state/vinix/android/unix-recvmsg-kernel-x86_64-2026-10-26-r2/compiler/v`,
SHA256 `109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e`.
This receipt does not replace a complete compiler or macOS SDK source closure.

These are host-tool validation results. They establish neither a successful
Maps guest run nor Google account sign-in.
