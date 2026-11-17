Compile `run.v` with V to an external executable, then run it with
`V_C_ERROR_BUG_REPORT_DISABLED=1`.
Set `AGX_TVB_TEST_BINARY` to retain the native sanitizer executable outside Git.

The runner extracts the production TVB initializer, extension and cleanup. It uses the real
firmware layouts and count updater, with bounded host backing, fallible
metadata allocation, GPU block allocation and UAT flush fault injection.
Each failure position must leave both published tables and counters unchanged
and release every staged block. Success checks complete publication and the
preservation of firmware-owned Info counters for both supported ABIs.
This exercises allocation ownership and publication, without GPU execution.

Initialization checks the default eight-block allocation before any scene
exists and failure at every shared-buffer, UAT-table/block, metadata and flush
position. The actual cleanup must release the complete unpublished graph on
both firmware ABIs. These services use bounded host memory; they do not model
firmware execution or UAT invalidation transport.

An unbound VM builds and releases the initial TVB without a firmware range
flush. The teardown fixture preserves its cached PTE through a retained
cleanup, then retries after first bind and a failed cache flush. Set
`AGX_TVB_MANAGER_SOURCE` to supply an alternate GPU manager source for the
teardown negative control.
