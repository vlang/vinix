# Browser diagnostic r9 — 2026-10-26

The real WebKit diagnostic still fails before JavaScript DOM completion.
This run is a credential-free local document test; it does not establish
Android WebView integration or Google authentication.

The prepared r11 bundle includes the preconstructed WebKit settings fix
`a118cd965` and libproxy loader-path fix `577a2d8c2`. The guest logged
`cpu-settings=preconstructed policy=never`, and the previous missing
libpxbackend loader error is absent. WebKit 2.48.1 still aborts with
`Could not create surfaceless EGL display: EGL_NOT_INITIALIZED`, followed by
the 30-second JavaScript DOM timeout. The log also retains GLib EBADF and
pidfd waitid EINVAL diagnostics. No rendering success is claimed.

The separate authority fixture passed. Authenticated X11, invalid-cookie
rejection, GLX absence and syscall fault preflight passed. Browser exit was 1;
all seven observed descendants were cleaned up, with zero survivors. Guest
execution ran from 16:18:21 to 16:18:54 UTC. The host requested SIGTERM for
its owned QEMU PID 76358; reconciliation recorded that PID's disappearance.

Preserve the complete bundles under
`/Users/alex/.local/state/vinix/android/`:

| Bundle or receipt | SHA-256 |
| --- | --- |
| `browser-probe-build-2026-10-26-r11/build.json` | `083bbcd1dee90bad2f63630b8daf98bf524cfe447c98fbd45467229b56b25391` |
| `browser-probe-results-2026-10-26-r9-cpu` exported archive | `196d15c07c8beb6f7abca212f5d8ec62e3c3e01d4f2b71e4293e39e80f517a9f` |
| `browser-probe-evidence-2026-10-26-r9-cpu/manifest.json` | `af2ac1d11f8bb343e4ecc357ffdbc603a5b0b566701e2c51df3d5e3c9aaacc22` |

The complete seal covers seven roots and 5,220 entries, including the actual
VM, prepared runtime, collected results, kernel, authority fixture and syscall
regression bundle. Its immediate independent recheck passed. The strict
collector restored 378 entries from the unfiltered UART. Keep all seven roots;
the concise pins above cannot substitute for that complete evidence.

The frozen kernel is revision
`ee0d3b6ff3d2586a0e5f35a27042643afaa298f3`, binary SHA-256
`ac90558eac4f2ea6b74c72c3f519370e98e9f88b0a5384aa82cc386bdd1876ce`.
All preserved boot modules were checked before and after kernel replacement.
