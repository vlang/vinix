# Account handoff diagnostics

Source: `2f04664ffdb4256574b618dc08f9117f3dc0f2c3`.

The broker now reports the progress of interactive account requests through a
finite numeric record, including handled terminal errors that previously left
no public diagnostic:

```text
ANDROID-ACCOUNT-HANDOFF stage=N operation=N event=N code=N
```

| Stage | Meaning |
| --- | --- |
| 1 | Authenticated request admitted |
| 2 | Authenticator command queued |
| 3 | Authenticated interaction callback received |
| 4 | Public interaction ticket queued for the caller |
| 5 | Original caller's one-shot redemption accepted |
| 6 | Native UI begin accepted |
| 7 | Native UI attachment ready |
| 8 | Authenticator launch command queued |
| 9 | Terminal response queued |
| 10 | Native UI begin failed |
| 11 | Pending UI request ended |
| 12 | Native UI transport tick failed |
| 13 | Native UI closed |

Operations are add-account `2`, redemption `3`, and token request `4`. Terminal
events are result `1` with code `0`, or failure `2` with code `1..9`; malformed,
missing, duplicate, mistyped and extension error codes become `-1`. Other
stages have event/code `0`. Queries and token invalidation produce no records.
Queue milestones establish enqueueing; they do not establish authenticator
execution, client receipt, a displayed login page, or successful authentication.

No request/session IDs, identities, options, ticket values, targets, credentials
or error messages enter records. The shared `accounthandoff` parser accepts
only canonical records and rejects added fields with a fixed generic error.
Its successful source path scans fixed arrays and bytes without string splitting
or integer formatting. Request routing, authority and lifetime rules are unchanged.

Host validation passed: all 58 permitted schema combinations, malformed/private
extensions, real add-account and token offer/redemption/result flows,
wrong-caller rejection, original-request pending state, bounded terminal codes
and quiet query operations. Independent source review approved the producer and
parser. Native UI stages remain source-reviewed; no ART or Google login result
is claimed by these tests.

Final builds/checks used a 600 MiB process-group RSS limit, 300 second deadline
and 1 GiB disk reserve. Maximum measured process RSS was 375,242,752 bytes;
maximum sampled process-group RSS was 332,103,680 bytes. All measured commands
reported zero swaps.

Complete evidence, source snapshots, binaries and guard receipts are retained at
`/Users/alex/.local/state/vinix/android/account-handoff-diagnostics-2026-10-28-r1`.
The full 68-file seal and independent readback passed. Manifest SHA-256:
`832da0aba71e25c16f1590dac1f6a40513e89cb1adc3717e2dfd4f31c606e08d`.

The checker is [check-account-handoff.v](check-account-handoff.v). Its retained
binary accepts `check EXTERNAL_DIR`; build/run argument vectors and resource
measurements are retained in the bundle. Seal/readback controls are outside the
sealed directory at
`/Users/alex/.local/state/vinix/android/account-handoff-checker-controls-2026-10-28-r1`.
