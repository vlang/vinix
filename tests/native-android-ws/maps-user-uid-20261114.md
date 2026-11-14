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

The signed UID cases have not executed on ARM. The next fresh guest is r96;
use these three candidate artifacts together. Existing broker/controller,
ART, core/TLS jars, data-volume probe, observer and API runner selections are
unchanged from r95. No historical compiler is required. Full Maps, imagery,
sustained responsiveness and Google authentication remain unqualified.

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
above passed. Free host space fluctuates around 11-13 GiB. A quieter host and
roughly 20 GiB free are needed for the next bounded VM/account attempt.
