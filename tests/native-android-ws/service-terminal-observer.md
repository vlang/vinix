# Native service terminal decisions — 2026-10-29

`nativews/headless.v` now writes one bounded numeric record to native stderr
when it decides to fail: `ANDROID-SERVICE-EXIT phase=N reason=N status=1`.
JNI exception checkpoints write it before the existing `ws_failure` description,
because an app crash handler may exit during exception reporting. The record
retains the first failure and suppresses duplicate teardown reports. Successful
service paths remain quiet.

The marker's status is the native failure decision. The actual process status
still requires its wait receipt or ART exit marker. Abrupt app/native exits
outside these paths can bypass this observer. Native writes are best effort;
absence of a record does not prove success. No existing status, exception clear,
teardown, channel decision, ownership or thread policy is changed. The scalar
flag is used only on the service main thread and resets at entry. Its 128-byte
stack buffer is consumed synchronously, with no retained address or allocation.

| Phase | Reason values |
| --- | --- |
| 1: startup | 1 trusted channel; 2 state allocation; 3 UI channel; 4 data directory; 5 authenticator channel; 6 bootstrap; 7 manifest; 8 Application startup; 9 control after startup; 10 Application absent/exception; 11 binding setup; 12 service scheduling |
| 2: binding | 1 control before pump; 2 pump failure; 3 binding state exception; 4 absent/exceptional Binder; 5 control after pump; 6 deadline; 7 control while waiting; 8 control before ready |
| 3: steady service | 1 invalid control input; 2 Looper pump; 3 absent/exceptional binding record; 4 absent/exceptional Binder; 5 account pump; 6 UI pump; 7 control after pump |
| 4: shutdown | 1 stop scheduling; 2 unbind scheduling; 3 pump; 4 unbind state; 5 incomplete unbind |
| 5: manifest JNI checkpoint | 1 package; 2 Application metadata; 3 service metadata; 4 service process |
| 6: Looper JNI checkpoint | 1 exception after the main Looper/web pump |

Host checks used headless source SHA-256
`d22892cc47def3c2e830a6e29873acd5c0eb08b944f68d131e39f4922c1663ff`
on checkout base `23d0826865693ba0145355f03d2d0ab8ac803003`.
The new checker executes the production helpers: success quietness, first cause,
entry reset, and a simulated exception describer that exits 73. The unbuffered
marker survives that exit while the process retains status 73. Five source
mutants are rejected. Existing checks retain all 33 lifecycle cases and 18
behavioral mutants, all 20 binding-timeout cases and two format ABIs, 29 channel
cases, two binding-ABI mutants and 12 startup mutants. Model adapters account
for the observer calls; compiler and behavioral output are checked separately.
Independent review approved the native buffer lifetime, thread use and control
ordering. No ART or Maps execution is established by these host checks.

All four checks passed serialized under 600-MiB RSS, 300-second, 512-MiB
observed shared-volume growth and 1-GiB reserve guards, with zero swaps and
complete cleanup. Sampled peak RSS was respectively 250,019,840 bytes (observer),
243,548,160 (lifecycle), 411,975,680 (binding) and 250,462,208 (channel/startup).
Artifacts, exact source copies, initial compiler-output assertion failures and
passing retry logs remain at
`/Users/alex/.local/state/vinix/android/service-terminal-check-2026-10-29-r1`.
Its complete 49-entry in-place seal and a fresh-process readback passed:
`/Users/alex/.local/state/vinix/android/service-terminal-sealed-2026-10-29-r1/manifest.json`,
SHA-256 `3f3a9910977d8ca01c0c03370cabb5961325295562de2bd18db31d810959d8eb`.
This observer does not establish the earlier broker exit's cause or a successful
Google login.
