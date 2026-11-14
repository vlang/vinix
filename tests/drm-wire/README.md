# Extensible DRM request framing

Run `v run tests/drm-wire/run.v` with `V_C_ERROR_BUG_REPORT_DISABLED=1`.
The runner executes the production layout selector and copy routines under
address/undefined-behavior sanitizers. It replaces user copies with bounded
host fixtures and injected faults. Set `DRM_WIRE_TEST_BINARY` to retain the
native executable outside Git.

Coverage includes ABI-specific selection with colliding command numbers,
metadata-free legacy-driver fallback, zero extension, rejected nonzero unknown
input, zeroed output tails, short output bounds, overflow and copy faults.
