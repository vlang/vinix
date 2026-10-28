# Maps imagery hold and account handoff, 2026-10-28

The fresh `maps-application-restrictions-vm-r5` guest reached search and route
planning. Eiffel Tower to Paris displayed a driving route and a 22-minute
estimate. The map remained beige, with route geometry visible, after 65 seconds
without input. Sign in opened the account dialog; choosing Add account returned
to onboarding without opening a login window. Authentication remains unverified.

This extends the [application restrictions runtime evidence](application-restrictions.md).
Artifact paths below are relative to `/Users/alex/.local/state/vinix/android/`.
The immutable input stage is `maps-application-restrictions-r2`, source revision
`162167810273d02450e30aa2342d84579ba31687`, inventory SHA-256
`d8507cb61499306398adecaae7fb9e1fe34ac9f1ccc9c9e42f1232b29c49623a`.
The guest retained its framework, native libraries and launchers; the public
controller receipt pins deployment build SHA-256
`14b1907be12ce988a4c5b36e449aa690843035966c4545543bcb1b9b327b67c8`.

## Observations

The broker was ready before launching Maps through the desktop. At 12:58:18 UTC,
Sign in opened the account dialog. Add account at 12:58:28 dismissed it to
onboarding. Private log inspection showed the authenticator handling the request,
but did not establish its terminal result. A background exception was present;
its relationship to the account failure is unproven. Empty initialization-failure
lists in the public receipt do not cover every handled account-request failure.

Skip advanced to the main screen. Paris search and Directions worked. The last
route input was at 13:01:20; the route was visible at 13:01:32, and
`maps-application-restrictions-vm-r5/route-held-01.png` at 13:02:25 still showed
no map imagery. There was no intervening input. This rules out a brief loading
delay for this observation, but does not distinguish networking, decoding or
texture delivery. A bounded exception-header search of Maps' private log found
no matching exception header. That search does not prove the absence of errors.

Public screenshot SHA-256 values:

- `route-held-01.png`: `0b4b8e0d5aa8f82622db4997095bbfbb990be42aecd9439998bc0a0a74398258`
- `add-account-01.png`: `e0cbab00bb58ea5c9c7ee09e41b749db1c119cf68c55441dea49a82019928983`

## Export and shutdown

The controller ran from 12:54:22 to 13:04:19 UTC and recorded
`user-stopped-no-authentication-claim`, service ready, no preparation error and
broker exit 137 after the explicit stop. Its `cleanup_survivors: 2` field means
two tracked identities remained visible at the cleanup deadline. The receipt
does not distinguish zombies from running workers, so clean controller cleanup
is unverified. No credentials were supplied. The VM used one 12 GiB, four-CPU
configuration. A sampled QEMU RSS of
12,754,496 KiB includes process overhead and is not a full-run peak measurement.

Canonical UART export completed before VM shutdown: 1,441,928 bytes in 2,817
chunks, archive SHA-256
`f5498554f3c800a23ff5bd1d85be5fdffdfacaea21571d766cdae488b78a8c9b`.
Strict collection passed under
`maps-application-restrictions-runtime-audit-2026-10-28-r4/maps-strict-results`.
Its public `results/receipt.json` SHA-256 is
`a7af08d3682b49ae3e7ce54e57f9638b5559a3849d64eb6e0c8a23c6a422b617`.
The collector guard exited zero with complete cleanup and 29,376,512 bytes
sampled process-tree RSS, under 600 MiB RSS, 300 seconds, 64 MiB growth and a
1 GiB disk reserve.

Owned VM PID 5857 received SIGTERM at 13:05:12. The runner reported a transient
ownership mismatch after signaling; reconciliation confirmed its absence at
13:05:31. `stop.json` SHA-256 is
`65f2c6bb65dba5baf59ce9a23e2df31c3b485620f1b9c6295c274d3a1932714c`;
`gone.json` is
`c5afaa7d69570243062566bf6f2f82f8c586f9de8bfaa893d851e872c67f34fd`.

The closed audit root and VM root are bound by
`maps-application-restrictions-runtime-sealed-2026-10-28-r4/manifest.json`,
SHA-256 `e510f0aa3c283b6cd2bf9f6262eb86542a850ece9ac92c46bc32002d3c1c81c5`.
All 382 entries passed fresh-process full readback. Seal/check guards both exited
zero with complete cleanup and zero swaps, taking 7.550/3.225 seconds and
23,969,792/13,910,016 bytes sampled RSS. Evidence remains outside Git, including
the original private logs and screenshots; this report does not replace it.

The next account run needs finite broker handoff stages in the public receipt to
separate dispatch, interaction delivery, redemption and UI launch from terminal
failure. Imagery still needs a bounded transport/decode investigation. Successful
Google login and usable map imagery have not been demonstrated.
