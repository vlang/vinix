# Platform Fragment ARM runtime checkpoint, 2026-10-30

The standalone platform Fragment regression passed on the pinned ARM pair.
Maps then opened onboarding and its Add account chooser. Host disk exhaustion
interrupted the account-window handoff; Google login and map imagery remain
unverified on this pair. No credentials were supplied.

This run uses source through `f1d2cb425`, including platform Fragment behavior
from `05fbcfa9d` and native exception restoration from `59879ee0b`. The
[framework/native stage](maps-platform-fragments-stage.md),
[fixture runner](platform-fragments-fixture-run.md), and
[qualified media tools](maps-platform-fragments-uncached-tools-2026-10-30.md)
retain their complete producer evidence and checks.

Paths below are relative to `/Users/alex/.local/state/vinix/android` (`S`):

- Prepared image: `maps-platform-fragments-r2`.
- Preparation controls: `maps-platform-fragments-prepare-2026-10-30-r2`.
- Interrupted guest: `maps-platform-fragments-vm-r1` (`VM`).
- Runtime controls and derivations:
  `maps-platform-fragments-runtime-audit-2026-10-30-r1` (`A`).
- Completed transfer: `platform-fragments-api-transfer-live-2026-10-30-r1`.

| Artifact | SHA-256 |
| --- | --- |
| Prepared `sha256.json` | `1a079687d54ed8eae5ab881be3f0459d37ce8e69533bc12df48874cf7335199a` |
| Framework JAR | `6970582da55b15dd30391491d2be2213abe665fe0256167f45cccdd3de25bcd4` |
| Native DSO | `613c6b2c7b1e816a5d7b0694d626a52a5b4df19604a6a224df99ad13055aa74c` |
| Signed fixture APK | `f2e08f444782607a408bd25766da399100e908cf2b99edeebcfb80d267dc21de` |
| Exported fixture receipt | `1dafcbd79692fe9832c42e4d2bfe2ea28444eead99bf8654724eb115a7c29b7a` |
| Extracted fixture child log | `4d673b7bda8b13e350897b2b315417ac6c4149743417242ebb3967194580f889` |

Preparation, clone and frozen-kernel installation passed their unchanged guards.
Preparation took 227.439 seconds with 70,352,896 bytes sampled aggregate RSS;
the time report recorded zero swaps. The preceding current-day preparation
attempt crossed its 512 MiB shared-volume growth cap during final input
rechecking; that partial image and failed controls remain retained. The successful
retry used the original 4 GiB outer allowance, with the stager's internal 512 MiB
write budget, 1 GiB reserve and complete input verification preserved.

One four-CPU, 12 GiB guest ran with default QEMU user networking, runner
`06cdf596adae105d363a99792b732808deb611db72fe4d87af1a5bc8500fb0fd`
and frozen kernel
`a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151`.
Both fixture downloads returned HTTP 200. The protected standalone fixture ran
as UID/GID 10117; its receipt records `wait_status=0`, unchanged input pins,
one exact pass marker and one native readiness marker. It covers stable managers,
tagged pending transactions, FIFO delivery once, application injection, lifecycle
order, late addition, host isolation and callback identity. Its mount was released
before broker startup.

The unchanged zero-removal UART planner, historical diagnostic reconstructor and
child extractor passed on interval
`1528a825b45288d26aa968830dab66db3195d21bfaf1d0383831c0b05ee3de2f`.
The derived archive is
`e0642b8f0ddc8bdf8af7abc966dfa4427e9539383df1539ac8fa7ee5c8983a41`.
`A/fixture-diagnostic/diagnostic.json` explicitly records diagnostic scope and an
original strict-collection failure. No strict UART import is claimed.

Saved captures show Maps' Add account chooser at 22:52:44 UTC and the chooser
closed after its Add account click at 22:52:48. The latter capture still shows
onboarding. The recovered operator transcript reports ENOSPC on the subsequent
capture and while recording the normal stop command. No intact `stop.json` or
after-Maps controller export was retained. This interruption supplies no reliable
account-activity outcome and does not establish that its prior crash is fixed.

On resumption, the original runner's `observe-gone` action independently found
recorded PID 74297 absent at 2026-10-30 10:16:30 UTC. `VM/gone.json`, SHA-256
`95f193f863f7916300c788a03cb66767a65c860371c44a68e4665a6fbae5d83e`,
records unknown exit status and unobserved cause; this action sent no signal.
Its `stop_requested=false` describes the observation path, not a denial of the
earlier transcript's failed stop-recording attempt. The QMP socket and pidfile
were already absent. `A/runtime-closure.md` retains these provenance limits.

All eleven original roots are closed to writes: the successful preparation and
controls, preceding failed preparation and partial image, VM, runtime audit,
transfer and four clone sidecars. The unchanged qualified streaming sealer
(`b12a4d0b2b133714da6876a0ed5cda623984dc72284c482d8e3ae57975304e77`)
sealed 597 entries; its internal check and separate fresh-process full readback
passed. The complete manifest is
`S/maps-platform-fragments-runtime-sealed-2026-10-30-r1/sealed/manifest.json`,
SHA-256 `8444da0144db782cc083e6881eace9696f697fb685040ed01a68989e869b7510`.
Seal/readback took 17.522/6.061 seconds, sampled 28,262,400/22,937,600 bytes RSS,
and both exited zero with complete cleanup and zero swaps under unchanged
600 MiB RSS, 900-second, 64 MiB shared-growth and 1 GiB reserve caps. Original
evidence and historical auditors remain required; this report does not replace
them. A fresh retry must use a separately named clone of immutable prepared r2.
