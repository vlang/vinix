# Native Roblox Windows runner

`host_query.v` compiles the maintained V download, manifest, ZIP staging,
layer preparation, XWD/PNG, upload handler and report policies. The public
Python module retains its caller ABI, parser and stdlib objects, and performs
synchronous borrowed library calls through the existing package-store binding.
`robloxguest` owns PTY serial/FIFO, deadline and retirement policy using the
shared isolated-guest transport. Managers and entered values remain separately
owned until explicit exit or post-controller fallback.

The independent frozen original controls cover both host ABIs and ARM
address/undefined-behavior sanitizers, local HTTP exchanges, real PTY/FIFO
ownership, caller overrides and exceptions. This port does not claim a new
kernel build, proprietary client download, Wine observation or hardware test.
Completed legacy public-stop/close failures retain the original master/FIFO
cleanup boundary; the shared transport recovers unreaped children. Broken
transport and newly guarded post-fork setup retire their acquired owners.

Override only the native executable with `VINIX_ROBLOX_HOST_QUERY` and
`VINIX_ROBLOX_GUEST_QUERY`; the default compiler path follows
`build-support/find-v.sh` through `run-v-tool.sh`.
