# Extensible DRM request framing

Run `v run tests/drm-wire/run.v` with `V_C_ERROR_BUG_REPORT_DISABLED=1`.
The runner executes the production node ioctl, layout selector and copy routines under
address/undefined-behavior sanitizers. It replaces user copies with bounded
host fixtures and injected faults. Set `DRM_WIRE_TEST_BINARY` to retain the
native executable outside Git.

The node fixture also injects allocator exhaustion, counts live request
buffers on every exit, and checks error-output copying and fault precedence.
It uses `-gc none` to match the kernel buffer allocator.

The production core registration supplies the binary and timeline WAIT
layouts. The fixture checks the 32- and 40-byte requests that predate
`deadline_nsec`, plus the full layouts and extended requests. The core
handler stub reads the deadline and writes `first_signaled` through the
production UAPI structures. The `drm-syncobj-wait` suite tests the actual
wait handlers separately.

Coverage includes ABI-specific selection with colliding command numbers,
metadata-free legacy-driver fallback, direction intersections, kernel buffer
sizing, zero extension, preserved unknown read/write tails, zeroed read-only
output tails, short output bounds, overflow and copy faults. These follow the
packaged Linux DRM core's ioctl rules; nested Asahi command records enforce
their separate unsupported-field rules.
