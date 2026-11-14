Compile `run.v` with V to an external executable, then run it with
`V_C_ERROR_BUG_REPORT_DISABLED=1`. Set `AGX_COUNTER_TEST_BINARY` to retain the
ASan/UBSan executable outside Git.

The runner extracts production counter reservation and microsequence writers
and uses the actual firmware command encoders. A mixed compute/render sequence
checks the reference's shared counter, independent queues, canceled gaps,
64-bit wrap and agreement between each command header and its start operation.
Monterey start operations must remain byte exact. These checks run with
`-gc none`, injected host atomics/locks and no GPU execution.

The device-wide queue ID allocator starts at two, consumes failed creation
IDs, and preserves the reference's low 32/8-bit firmware projections. Source
gates require every notifier, workqueue and command/start sequence field to
use this identity instead of file-local handles.
