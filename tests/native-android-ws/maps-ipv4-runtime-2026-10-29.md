# Maps IPv4-only backend comparison, 2026-10-29

Disabling IPv6 in QEMU's user-network backend did not restore Maps imagery or
account login. The fresh guest still attempted global IPv6 connections from a
link-local source address, and Add account still ended with error 1 before an
interaction offer. This qualifies the explicit diagnostic profile, not a fix.

Artifacts below are relative to `/Users/alex/.local/state/vinix/android/` (`S`).
The VM is `maps-account-handoff-vm-r2` (`VM`) and its controls/results are
`maps-account-handoff-runtime-audit-2026-10-29-r2` (`A`). It uses the same immutable
`maps-account-handoff-r5` stage and frozen kernel as the
[default-network run](maps-account-handoff-runtime-2026-10-29.md): stage source
revision `05bf1b764ffb09587112fb61dc4adc6209dd071e`, inventory SHA-256
`256b9c62ad2c6c83668cac756697941c8cdba6e6eae9a31543016d6f85b90e7a`.

The runner change is commit `f9e6601ee`. Executable SHA-256
`06cdf596adae105d363a99792b732808deb611db72fe4d87af1a5bc8500fb0fd`
was launched with `start-ipv4`; `VM/launch.json` records
`network.mode=ipv4-only` and the actual `-netdev user,id=net0,ipv6=off` argument.
The launch retained the single 12 GiB, four-CPU HVF configuration.

## Results

The broker reached readiness before desktop Maps was opened. Sign in at
12:39:15 UTC opened the account dialog; Add account at 12:39:28 returned to
onboarding. The public receipt again contains untruncated handoff records:
stage 1 / operation 2, stage 2 / operation 2, then stage 9 / operation 2 /
event 2 / code 1. No interaction offer is recorded. A generic exception caught
by the framework and an explicit authenticator `onError(1)` remain
indistinguishable from these records.

Paris search and Eiffel Tower-to-Paris driving directions worked. The last route
input was at 12:43:52; route geometry was visible at 12:44:14. The held screenshot
at 12:45:01, 69 seconds after the last input without intervening input, still
shows no map imagery and displays a 24-minute estimate.

The private `ipv4-retry-private-01.png` screen shows Maps retrying
`mobilemaps.googleapis.com/2001:4860:4802:38::87` on port 443 from
`fe80::5054:ff:fe12:3456%eth0`, failing with `ECONNABORTED`. The prior run's
`fec0` source is absent from this captured failure, but IPv6 attempts continued.
These exceptions may describe a final failed fallback; they do not establish
IPv6-only address selection. After the complete result export,
a separate guest `getent ahosts mobilemaps.googleapis.com` probe listed
`216.239.38.135` before the IPv6 address (`ipv4-address-list-01.png`). That native
resolver output does not establish Android/Maps resolver ordering or fallback.
The failing connection does not by itself identify every imagery, decoding or
texture-delivery issue.

A later read-only metadata check of the same closed packet capture confirms an
IPv4 SYN/SYN-ACK/ACK handshake with `216.239.38.135:443`, followed by TCP payload
in both directions at 12:38:24. The exact bounded command was `tcpdump -nn -r
VM/network.pcap -c 24 'host 216.239.38.135 and tcp port 443'`; its output contains
packet metadata, without payload dumps. This proves IPv4 TCP exchange with that
address, without establishing TLS, HTTP or Maps request success. The IPv6
exception alone therefore cannot identify the full connection-attempt sequence.

The controller ran from 12:35:26 to 12:45:25 with TLS tracing enabled and
onboarding tracing disabled. It recorded service ready, no preparation error,
`user-stopped-no-authentication-claim`, broker exit 137 following explicit stop,
and two cleanup survivors. Their running-versus-zombie state is not established.
No credentials were supplied. Empty initialization/pump-failure lists do not
establish authentication success.

## Retained checks

Kernel installation passed under 600 MiB aggregate RSS, 900 seconds, 4 GiB
observed growth and a 1 GiB reserve: exit zero with complete cleanup, 68.366
seconds, peak sampled RSS 31,227,904 bytes. Strict collection of the complete UART
export also passed with exit zero and complete cleanup under 600 MiB RSS,
300 seconds, 64 MiB growth and a 1 GiB reserve; peak sampled RSS was 28,000,256
bytes. The exact 2,241,433-byte UART interval has SHA-256
`b03d51885b0083197f6cef34360084d7bf717262f7c7f5b5ce0ec79f2521cf40`.

Owned VM PID 2416 received the SIGTERM request at 12:46:50. A transient ownership
mismatch followed signaling; reconciliation confirmed absence at 12:47:02.

| Retained artifact | SHA-256 |
| --- | --- |
| `VM/launch.json` | `16f79e291dc827e71843ce24e239ecdb881dcbbb17c758f8fdf9b7cd9f179632` |
| `VM/kernel-patch.json` | `4fd3589e940c5d0bf59161cb348bb4b179def93d70f99f9c413e4bfe8f6250a5` |
| `A/maps-strict-results/results/receipt.json` | `1fe8ce2f641ea4774a02cfdcdd2f7c8d60433c62a75d7be2f7de549f9b67044e` |
| `VM/ipv4-route-held-01.png` | `0cf12371284abe973e5f429cf82583284d02ef04ad0bdd3cd73529f097b5dbf7` |
| `VM/ipv4-retry-private-01.png` | `9c2960d52a34ef274a7322ffba93ffea90813683fc5759960d5ebe40061da8dc` |
| `VM/ipv4-address-list-01.png` | `f6f515b8b789bb421a1c5dafbf9ee9a50727f78aed4f1c613d894ea592e31bf7` |
| `VM/stop.json` | `41ea361ac9452db1a63affdb317496940f30108fe541bb4097fbe73399189763` |
| `VM/gone.json` | `0baa1c7e9adf40bbdfa190879151488c1e3bd8e8ded8ba850ab6a2480ba9c149` |

Both closed roots are preserved by
`S/maps-ipv4-runtime-sealed-2026-10-29-r2/sealed/manifest.json`, SHA-256
`20381d9bf91d4c8df3d7c9481e13007f63682a39b5a66829c702564eee3c879c`.
The seal and independent fresh-process complete readback passed for two roots
and 344 entries. Both guards exited zero with complete cleanup and zero swaps
under 600 MiB RSS, 900 seconds, 64 MiB observed shared-volume growth and a 1 GiB
reserve. Elapsed times were 4.921/2.827 seconds; peak sampled RSS was
23,478,272/13,352,960 bytes. The complete bundle, including private screenshots
and original UART, remains external; this report does not replace it.

The separate metadata check is retained at
`S/maps-network-metadata-2026-10-29-r1`, including its exact guard argv, output
and plain tool/source-PCAP/log/guard hashes in `inputs.sha256`. The command exited
zero with complete cleanup under 600 MiB RSS, 300 seconds, 64 MiB growth and a
1 GiB reserve. This root's seal and independent complete readback both passed,
under 600 MiB RSS, 900 seconds, 64 MiB growth and a 1 GiB reserve, at
`S/maps-network-metadata-sealed-2026-10-29-r1/sealed/manifest.json`, SHA-256
`e08a6d4a5c9a207f403134f3d6fbfb9d328400a5403adadb683c3670b6d66d7f`.
The original closed R2 roots were not changed.
