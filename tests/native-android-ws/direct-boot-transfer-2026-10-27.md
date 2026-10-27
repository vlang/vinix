The fixture transfer tool has an explicit `serve --direct-boot` profile for the
new signed fixture and strict ARM runner. The original service-query profile
and shared transfer guards are unchanged. Selection snapshots exactly three
pinned inputs before listening on `127.0.0.1`.

| URL | Original input under external Android state | SHA256 |
| --- | --- | --- |
| `/direct-boot-run` | `direct-boot-run-2026-10-27-r1/run` | `8caab5559b73dbe1ffc9645006e899fd82dfbe5cfac810df4f189db9eb152a60` |
| `/client.apk` | `direct-boot-fixture-2026-10-27-r1/client/probe.apk` | `a77c25679d47032a8bac73a8ec7751dae271f7828973a8f9b722f004a0ad0c02` |
| `/disabled.apk` | `direct-boot-fixture-2026-10-27-r1/disabled/probe.apk` | `91e209b043a1f65379ecf16107263d513681bb56bbf25bbce11022d0824f9af5` |

Both implementer and independent read-only reviewer directly hashed all three
files and checked producer receipts. Keep their complete original producer
bundles and the direct-boot framework; this small host audit does not replace
their provenance.

The existing GET-only allowlist, 32 MiB input cap, 64 KiB streaming buffer,
8 KiB header cap, five-second accepted-client read deadline, absolute 600-second
service deadline and 12-request limit remain enforced. Serving exits after all
three unique files transfer. `ready.json` records the selected
`vinix-direct-boot-http-v1` profile, exact input and snapshot identities;
`result.json` records every request result. Retain both with guest evidence.

Use the retained host tool with a fresh external directory:

```sh
/Users/alex/.local/state/vinix/android/direct-boot-transfer-build-2026-10-27-r1/service-query-transfer serve --direct-boot /Users/alex/.local/state/vinix/android/direct-boot-transfer-live-2026-10-27-r1 18765
```

After `SERVICE-QUERY-HTTP READY`, root can download into a fresh protected guest
directory using the already confirmed `/usr/bin/wget`:

```sh
wget -O /var/lib/direct-boot-input-r1/run http://10.0.2.2:18765/direct-boot-run
wget -O /var/lib/direct-boot-input-r1/client.apk http://10.0.2.2:18765/client.apk
wget -O /var/lib/direct-boot-input-r1/disabled.apk http://10.0.2.2:18765/disabled.apk
chmod 755 /var/lib/direct-boot-input-r1/run
chmod 644 /var/lib/direct-boot-input-r1/client.apk /var/lib/direct-boot-input-r1/disabled.apk
```

The runner requires `--direct-boot RUNTIME CLIENT_APK DISABLED_APK 10117 10117
FRESH_OUTPUT`, provisioned guest UID/GID and a fresh protected output directory.
Root alone manages VMs. Actual new-profile transfer, ART execution and Maps
sign-in remain runtime validation work.

The V host build and complete shared HTTP self-test passed, including new profile
assertions, exact binary transfer across multiple buffers, hash/symlink/output
guards, protocol/body/URL restrictions and deadline/request exhaustion.
Accepted-client stalls and trailing-body socket cases remain outside those tests.
Independent source review passed the narrow profile delta and unchanged shared
guards.

Build: 18.34 seconds, 238,190,592 bytes maximum RSS; self-test: 0.57 seconds,
5,537,792 bytes maximum RSS; zero swaps each. The compiler was
`/Users/alex/code/v-tccbin-bootstrap-20261026/v`, SHA256
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`,
with `-new-compiler -prod -gc boehm -d net_nonblocking_sockets`.
Source SHA256 `c75e3bd348c48c32091453ae15ed6b760c0f59b07b6c7fe6e30d71d33a33eaa2`
and executable SHA256
`2b0ebe6b29c766614abbe6729d65b1f46c155b633829fe10cef79feb6225b15f`
identify the tested bytes. The source parent was
`aebf5a280d2c4c7e3e1761fa22fc3ef3c1d8e7b3`.

Complete host build and self-test outputs are retained under
`/Users/alex/.local/state/vinix/android/direct-boot-transfer-build-2026-10-27-r1`
and sibling `direct-boot-transfer-selftest-2026-10-27-r1`. Both are sealed by
`direct-boot-transfer-audit-2026-10-27-r1`, two roots and 15 entries, manifest
SHA256 `6e5a49f64ef6e4ef4042f65e46504bb8e1edcdd222c492465e6841e9ff603f75`.
Creation, internal verification and separate unchanged-sealer check passed.
