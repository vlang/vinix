# Process package-list fixture delivery

Additive selectors `--process-packages` and `serve --process-packages-api`
deliver the RunningAppProcessInfo package-list fixture. Historical selectors,
pins, protocol rejection rules and shared-APK exceptions remain unchanged.
This profile uses distinct runner/APK routes without a shared artifact exception.

All five delivery qualification phases passed: host runner build/self-test,
static ARM runner build, transfer build/self-test. The host runner rejected
5,503 malformed, mixed-profile and failure cases. Static ELF readback confirms
AArch64 EXEC without INTERP/DYNAMIC segments. Transfer tests preserve all
historical cases and add six route/path/hash collision controls. The
[coupled native readback](process-packages-host-2026-11-04.md) also passed.
Actual ARM execution remains pending; no GMS or Maps result is claimed here.

The fixture uses package `org.vinix.bootstrap` and explicit activity
`org.vinix.bootstrap.Main`. Its application process suffix is `:process_packages`:
the intended process name is `org.vinix.bootstrap:process_packages`, while the
native self record's package array must contain `org.vinix.bootstrap`.
Coverage includes the public instance `String[] pkgList` field and null default,
fresh native self records/arrays, mutation isolation, caller package-array
preservation through `getMyMemoryState`, and a plain bounded worker. It does not
establish global process enumeration, GMS module completion or authentication.

Paths use `S=/Users/alex/.local/state/vinix/android`:

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Signed fixture | `process-packages-fixture-2026-11-04-r2/probe.apk` | `db555d086522f003e912e3de5fcf0905d3079025c92397c7b92c6ba714d497e7` |
| ARM runner | `process-packages-api-run-2026-11-04-r1/run` | `725710de6957816c0ece03008c54bf3ca78bc31635d9495c18a04a922f12d21f` |
| Framework JAR | `combined-account-webview-process-packages-framework-2026-11-04-r2/api-impl.jar` | `875f854ddf662dcaf55ebe05df06f5833eb5ca1e15f94066ffdf0fef18e829a8` |
| Native DSO | `current-native-build-2026-11-04-process-packages-r1/native/libvinix-android-native.so` | `b69c62304448c1aa0fd5f0cc660acf81cfdd8614b280dad691f53a07d8abcc5f` |
| Transfer | `process-packages-api-transfer-build-2026-11-04-r1/transfer` | `495ac838ee5bda910c18732fc4739332d836440d037b1fb8f41cca662c3af358` |

The five initial supervised commands passed but omitted the explicit shell
file-size setting. All five were then repeated with zsh `limit filesize 16m`
(reported as 16MB);
both sets of complete logs and guards remain retained. The repeated static
runner matches the initial SHA-256 above. Successful `*-filecap` guards record:

| Phase | Guard ms | Sampled RSS bytes | Observed growth bytes |
| --- | ---: | ---: | ---: |
| Host runner build | 1,358 | 353,009,664 | 2,281,472 |
| Host runner self-test | 1,599 | 37,961,728 | 9,105,408 |
| Static ARM runner build | 1,710 | 381,632,512 | 5,541,888 |
| Transfer build | 1,770 | 416,382,976 | 3,235,840 |
| Transfer self-test | 1,506 | 9,764,864 | 5,287,936 |

Each guard/child exited zero, with empty reason and complete cleanup. Limits
remain 600 MiB RSS, 300 seconds, 512 MiB shared growth, 1 GiB reserve and 4 MiB
supervisor output. Frozen runner and transfer sources match the checkout,
SHA-256 respectively
`a636630735d5155b4540cdcd6ee7401d4a661f91ba363f222b71de9cb7f1cf2c`
and `ec7e2217f467141b620832178a46c63877e6d03654b881ebda184336fc07adf5`.
Complete controls/sources remain in the four `process-packages-api-run`,
`process-packages-api-run-build`, `process-packages-api-transfer-build` and
`process-packages-api-transfer-controls` roots ending `-2026-11-04-r1` below S.
The 27-root, 15,042-entry host seal is
`S/process-packages-host-sealed-2026-11-04-r1/sealed/manifest.json`, SHA-256
`bbb1d713abc911a85bc7628975f4540bb889dd6b6a2c85a5fbd413e17c3da93f`.
Seal and corrected independent fresh readback passed 0/0 with complete cleanup
in 2,654/722 ms, observing 5,341,184/1,314,816 bytes growth under the original
900-second/64 MiB growth seal limits. The first readback used `check --sealed`,
returned 1/1 with complete cleanup and remains preserved; corrected readback
uses the original `check --out ... --pin ...` interface. Preserve all complete
roots, original bundles and historical auditors. This establishes host
qualification/storage integrity; ARM execution remains separate.

Before ARM execution, use unused account `process-packages-probe`, UID/GID10157,
mount `/opt/process-packages-runtime`, and output `/var/lib/process-packages-r1`.
Require unused account/input/output paths and a dedicated read-only runtime
mount with `nosuid,nodev,wxallowed`, without `noexec`.

Start the qualified host transfer only when the guest is ready to fetch:

```text
S=/Users/alex/.local/state/vinix/android
"$S/process-packages-api-transfer-build-2026-11-04-r1/transfer" serve --process-packages-api FRESH_HOST_OUTPUT 55549
```

Fetch `/process-packages-api-run` to `/opt/input/process-packages-run` and
`/process-packages.apk` to `/opt/input/process-packages.apk`. Verify both final
qualified hashes and executable/read permissions before the intended invocation:

```text
/opt/input/process-packages-run --process-packages /opt/process-packages-runtime /opt/input/process-packages.apk 10157 10157 /var/lib/process-packages-r1
```

The exact success marker is:

```text
PROCESS-PACKAGES-PASS public-instance-field default-null actual-self package-not-process fresh-arrays caller-memory-state bounded-worker
```

Require receipt profile `process-packages`, the selected UID/GID, all six exact
input identities, all eleven unchanged checks, sole exact PASS/native READY,
drained EOF and clean exit. Retain 180/20-second deadlines, the 4 MiB child-log
limit and 8,192-byte line limit. Keep guest input idle through export END, retain
the full UART, derive one exact fixture interval and use unchanged zero-removal
reconstruction and child extraction. A failed fixture prevents separate GMS
startup in that run. Release the dedicated mount after validated pass before
separate GMS/Maps execution. Preserve failures without protocol or health waivers.
