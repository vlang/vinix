Run `V_C_ERROR_BUG_REPORT_DISABLED=1 v run tests/agx-tvb-growth/run.v`.
Set `AGX_TVB_TEST_BINARY` to retain the native sanitizer executable outside Git.

The runner extracts the production TVB extension function. It uses the real
firmware layouts and count updater, with bounded host backing, fallible
metadata allocation, GPU block allocation and UAT flush fault injection.
Each failure position must leave both published tables and counters unchanged
and release every staged block. Success checks complete publication and the
preservation of firmware-owned Info counters for both supported ABIs.
This exercises allocation ownership and publication, without GPU execution.
