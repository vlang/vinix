# Native Roblox Windows runner

The maintained entry point is now [`../run`](../run). Its implementation in
`tests/native-vm-tools/vmhost/roblox_*.v` owns downloads, manifests, ZIP staging,
layers, XWD/PNG conversion, concurrent uploads, reports and PTY/FIFO retirement
directly. It requires no Python object binding.

The older `host_query.v`, `robloxhost` and `robloxguest` files record the prior
borrowed-object policy port. The maintained command no longer invokes those
queries or their former interpreter adapters.

The independent frozen original controls cover both host ABIs and ARM
address/undefined-behavior sanitizers, local HTTP exchanges, real PTY/FIFO
ownership, caller overrides and exceptions. This port does not claim a new
kernel build, proprietary client download, Wine observation or hardware test.
Completed legacy public-stop/close failures retain the original master/FIFO
cleanup boundary; the shared transport recovers unreaped children. Broken
transport and newly guarded post-fork setup retire their acquired owners.

The compiler path follows `build-support/find-v.sh` through `run-v-tool.sh`.
See [native qualification](../../native-vm-tools/README.md) for the direct
controller's current checks.
