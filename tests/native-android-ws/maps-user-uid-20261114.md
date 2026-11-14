# UserHandle UID conversion, 2026-11-14

Source baseline: 75d0067fe, following the bitmap/route work in 7796d94ba and
1f7af2db4. The headless EGL repair passed the full signed ARM suite in r95.
Actual Google services progressed past eglGetDisplay to its authenticator's
ANDROID-SERVICE-READY marker. It then failed in highpool[3] with
NoSuchMethodError for UserHandle.getUserHandleForUid(int), followed by
System.exit(10) at 18:52:02. The controller reported "GMS broker exited; inspect
private broker.log", status failed, empty cleanup survivors (0). No Maps or
account UI was launched in this run. This corrects the live description that
it failed before authenticator readiness.

The new [documented API](https://developer.android.com/reference/android/os/UserHandle#getUserHandleForUid(int))
returns the UserHandle associated with a UID. The V framework generator delegates
to the existing getUserId arithmetic and constructs the existing immutable
UserHandle value. The signed regression covers 13 UID values: user boundaries,
application UIDs, signed integer extremes and existing negative-UID arithmetic;
it checks identifiers, equality, hashing, Parcelable round trips and unchanged
process UID. The new method adds no native binding; generated native bindings
compare identical to the preceding SDK build.

External state root: `/Users/alex/.local/state/vinix/android`.
Current compiler: /Users/alex/code/v/v, V 0.5.2 cbfc1be, SHA256
9bde2851cedea03c3e488b0793a356aeb90644d13cf49e10fae6bf5518fff000.
All successful build guards used RSS 629145600, wall 300000 ms,
reserve 1073741824, growth 536870912, output 4194304 bytes,
exit/child 0/0 and cleanup_complete true.

| Check | Evidence stem | Time ms | Peak sampled RSS | Observed growth |
| --- | --- | ---: | ---: | ---: |
| Full SDK assembly, UserHandle DEX readback, seven missing/duplicate/already-present declaration refusals | framework-user-uid-20261114-r1 | 6342 | 479543296 | 33058816 |
| Full native producer with the new SDK, generated C, AArch64 GCC -Werror link | user-uid-native-20261114-r1 | 35537 | 583696384 | 3678208 |
| Signed API fixture assembly and signature verification | current-api-user-uid-20261114-r1 | 1979 | 192266240 | 2973696 |

| Candidate artifact | SHA256 |
| --- | --- |
| framework-user-uid-20261114-r1/classes.dex | f7b6ac3aad35097596c3b838d639aaa2caf1c7abbd2518e18e2eee61f2d7e12b |
| user-uid-native-20261114-r1/native/libvinix-android-native.so | 501814d6fe6c2f6aa9ac1d1bb35b4a6328c3640290e56fb9ef8b91207775af14 |
| current-api-user-uid-20261114-r1/probe.apk | e29b7a679cda3137a36c0983c76a431cd849f10d69af7aa4d257d50d2475a248 |

Use these three artifacts together. Existing broker/controller,
ART, core/TLS jars, data-volume probe, observer and API runner selections are
unchanged from r95. No historical compiler is required. Full Maps, imagery,
sustained responsiveness and Google authentication remain unqualified.

## Signed ARM qualification in r96-api

The full signed API suite passed with source change 6672e3774 in fresh
`maps-current-20261114-r96-api`. The runner observed child exit 0 and closed
input after readiness/pass. The retained child log contains USER-UID-PASS,
BITMAP-BUFFER-PASS, EGL-SHARED-DISPLAY-PASS and CURRENT-API-PASS. All 13 UID
vectors, parcel round trips and the unchanged-process-UID assertion executed
on ARM. Deployed native library, SDK DEX and signed APK hashes match the table
above.

This was an API-only guest with VINIX_CURRENT_APP_DATA_DISK=0: no 8-GiB
account-data disk was created and no broker/account session was started.
The existing initial automatic Maps launch was refused for its single-link
preflight, and its failed window was closed before the API run. Persistent
volume/account guards were unchanged. Guest resources remained 12 GiB / four
CPUs with HVF. Staging passed under the original guard: 7941 ms, sampled RSS
36388864, observed disk growth 120819712 bytes, exit/child 0/0 and complete
cleanup.

The complete signed API export reconstructed without removals: 22695 bytes,
45 chunks. Snapshot, plan, reconstruction and child extraction passed their
600-MiB / 300-second / 1-GiB reserve / 64-MiB growth / 4-MiB output guards.
The complete archive, exported receipt and child log were verified on the host
before stopping owned QEMU43097. PID absence and no open boot/firmware handles
were then verified. The stopped boot image hash also passed its guard.

| ARM evidence under the external state root | SHA256 |
| --- | --- |
| maps-user-uid-api-uart-20261114-r1/full.log | 0c00d3c2f6ac0017be43be94c333964f326db04c284aab2cb1ec5a0dd5e7dc64 |
| maps-user-uid-api-readback-20261114-r1/archive.json | ceb518a3415558c14e8018fa65d7605aed02f30f08acb44dbc98cd1fa0738a74 |
| Same API readback/exported-receipt.json | e249140b887199dc620e11066fc9a9442cf47466ad56a71979a7aedee153c08a |
| maps-user-uid-api-child-20261114-r1/child.log | f4536b87bf357360741cf6b970febf63800dce2f54ef8954ff0a3edb18b40e2e |
| maps-current-20261114-r96-api/boot.img | ff9c3845c57fc98d35e7f8a18ec5067f8861415b71c41a66c383f22a8f459f2b |

The next full Google services/account retry remains pending; the API-only
pass does not establish Google authentication or complete Maps support.

## r95 evidence and cleanup

The complete private results and signed API run were synced to the checked
persistent ext2 volume (UUID b9f7681d6b8445549a615c8c5e99e22e) before stopping
owned QEMU62036. The copy terminal's mount check, copied receipt and shell
prompt were observed first. PID absence and no open boot/data image handles
were verified before read-only debugfs extraction. Read-only e2fsck passed
under the original caps. The private broker hash matches its retained manifest;
the private API child log compares identical to the successfully reconstructed
signed API child. The storage watch is partial because the guest was stopped
after the service failure. All r91-r95 guests and the ART builder are stopped.

Private bundle:
`maps-current-20261114-r95/private-readback/r95-private/results`.
Its broker.log SHA256 is
3054ada815a1f5d9e23689d29b3368f5d6999eda234da4a3e45e8196e17a1ea0;
receipt.json is
1355e56233be2242b0d90616a71cfe243aafda8a9ef706cf88330448c38a5ad4;
private-log-sha256.json is
ece2dd32ab01337768b34823bf805e8bd02886c3ed28f282ceba39eee558dfbf.

The original Maps UART interval remains retained at
maps-headless-egl-account-uart-20261114-r1/interval.log, SHA256
94c8b4988e7c4d23a14ff4ab0e8a1678483ef75f2cdc40b9a52756bf90700d5f.
Its BEGIN/END advertised 1427024 bytes/2788 chunks, but the unmodified strict
no-removal checker rejected noncanonical frame fields. No successful public
Maps reconstruction is claimed; the private full bundle is retained. The r95
signed API UART reconstruction passed separately before this interval.

## Next runtime attempt

The host remains active. Three read-only 15-second quiet-window probes, with
600-MiB RSS, 1-GiB reserve, 300-second wall, 4-MiB output and a stricter 64-MiB
shared-growth limit, stopped on growth after 3069/4942/4148 ms. Observed growth
was 200224768/92749824/67637248 bytes respectively. Their receipts are
headless-egl-host-quiet-20261114-r1/r2/r3.guard.json. These are quiet-window
checks, not failed original-profile SDK builds; the original-profile builds
above passed. At that handoff free host space fluctuated around 11-13 GiB.
During r96-api it fell from about 11 GiB to about 9.5 GiB. The API-only run
could proceed without the large account-data image; a quieter host and roughly
20 GiB free are still needed for the full bounded VM/account attempt. The
owned test guests, including r96-api, are stopped.
