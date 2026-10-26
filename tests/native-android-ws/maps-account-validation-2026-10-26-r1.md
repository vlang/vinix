# Maps account deployment: first guest run

The real Maps/GMS controller stopped before starting Google Play Services:
`/var/run` is a symlink in the guest, and its protected-directory check correctly
rejected it. No credentials were supplied and this run does not establish Google
login. Controller fix `e9273eb11` uses `/run` directly and adds host regressions
rejecting both a symlink alias and a writable directory. Its host self-test passed;
the corrected guest controller requires a separate fresh-image run.

The original sealed `maps-account-r1` was preserved. Only the verified clone
`maps-account-vm-r1` was kernel-patched and booted. See
[staging provenance](maps-account-stage.md) for the original complete inventory,
request and clone pins. Runtime inputs were framework r3, account r5, JNI r15,
launcher r12, Maps controller r3, browser deployment r7, token APK r5 and token
controller r1. The kernel was the frozen recvmsg AArch64 r3 build, source
`ee0d3b6ff3d2586a0e5f35a27042643afaa298f3`, SHA-256
`ac90558eac4f2ea6b74c72c3f519370e98e9f88b0a5384aa82cc386bdd1876ce`.

| Actual guest check | Result |
| --- | --- |
| Maps/GMS controller, 16:33:55–16:37:16 UTC | Failed on `/var/run`; service readiness false, no broker started, zero cleanup survivors |
| Headless service fixture | Passed real ART/JNI service lifecycle and clean exit; exact controller PASS marker once |
| Existing account UI fixture | Failed, controller exit 139; three `double string.free() detected` messages followed by SIGSEGV; zero cleanup survivors |
| Synthetic token cache fixture | Failed before ART startup with `ANDROID-SERVICE-FAIL authenticator channel`; controller reported `account ui disconnected` |

The token fixture ran as UID/GID 10014 with its fresh target-traversable output
at `/opt/account-cache-r1`. It emitted no success archive. Its bounded service log
was mirrored to the retained UART, and the actual desktop failure is retained as
`token-running.png`. This is distinct from the old UI fixture's controller crash.
Neither failure is treated as a passing account transport test.

Complete evidence remains outside Git below
`/Users/alex/.local/state/vinix/android/`. QEMU PID 26519 was stopped through the
owned lifecycle runner and confirmed absent. The complete UART was preserved in
each strict range bundle before collecting these three independent protocols:

| Protocol | Half-open UART byte range | Collected entries | Archive SHA-256 |
| --- | --- | --- | --- |
| Maps account | `[41012, 2259565)` | 16 | `8ff519a0514d42f04359c811a7020486bb8258e854d786ae3ba8fd8501e79860` |
| Headless | `[2260733, 4534799)` | 33 | `93a10567c1b8c07aef78f3c50cb58bfea48b23221ff4e7249eb109abe133b8ab` |
| Account UI | `[4535296, 4554070)` | 16 | `630bd47d67f40a005101cc3213451e70a193509bcab23c08ec22487887cc0b45` |

Range bundles use `maps-account-vm-r1-{maps,headless,account-ui}-range` and result
bundles use the corresponding `-results` names. The unchanged strict collector
passed every selected protocol and still rejects mixed-protocol input. The
evidence seal binds these complete roots, both original and booted images, all
selected runtime/build bundles, the UI replay, frozen kernel, request, clone
receipt and range tool. The complete seal is
`maps-account-evidence-2026-10-26-r1/manifest.json`, SHA-256
`59b28a0fecc0007b6a8ae6474e3b805ffbadee3b8cf99a5dff7f3473b740ee5f`.
The sealer's complete recheck passed: 22 roots and 26,898 entries.
