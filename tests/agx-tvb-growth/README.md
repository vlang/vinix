Compile `run.v` with V to an external executable, then run it with
`V_C_ERROR_BUG_REPORT_DISABLED=1`.
Set `AGX_TVB_TEST_BINARY` to retain the native sanitizer executable outside Git.

The runner extracts the production TVB initializer, extension and cleanup. It uses the real
firmware layouts and count updater, with bounded host backing, fallible
metadata allocation, GPU block allocation and page-table mapping fault injection.
Each failure position must leave both published tables and counters unchanged
and release every staged block. Success checks complete publication and the
preservation of firmware-owned Info counters for both supported ABIs.
The fixture rejects any firmware-control flush during GPU-only block growth.
This exercises allocation ownership and publication, without GPU execution.

Initialization checks the default eight-block allocation before any scene
exists. It injects failures at each shared-buffer allocation, UAT table or block
allocation, mapping, and metadata allocation in turn. Cleanup must release
the complete unpublished graph on both firmware ABIs. The fixture models
backing ownership and detects firmware flush calls on the host.

Bound and dormant VMs build and release the initial TVB without a firmware
range flush for GPU-only blocks. The teardown fixture preserves a cached PTE
across cleanup retries, then releases it after first bind and a successful
cache flush. Set
`AGX_TVB_MANAGER_SOURCE` to supply an alternate GPU manager source for the
teardown negative control.
