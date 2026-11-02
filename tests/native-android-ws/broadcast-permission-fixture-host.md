# Receiver-permission broadcast fixture host qualification

This signed fixture exercises actual `Context.sendBroadcast(Intent,String)`
delivery to a process-local dynamic receiver and the primary APK's manifest
receiver. Both validate action and sequence payloads and record callback counts;
the dynamic callback also verifies its dedicated HandlerThread looper. A direct
one-argument legacy control, null receiver-permission calls and the fixture's own
declared/requested signature permission must deliver. Unknown, unrequested
signature, normal, dangerous and tree permission cases must leave both counts
unchanged. A FakeContext and PackageManager explicitly return granted results for
the unknown permission, then its broadcast must still be denied.

Each send is checked after a queued barrier on the dynamic receiver's handler,
including every denial. All barrier waits share one eight-second deadline.
Callback errors are retained and rethrown by the checker. Cleanup unregisters the
receiver, quits and joins the thread within one second and preserves the original
failure if cleanup also fails. Null Intents must raise NullPointerException for
null, allowed and unknown permissions before delivery or permission selection.

After verified-package construction, MetadataState saves the actual primary
package's public requested-permission list and PermissionInfo fields. It removes
the positive request, renames and changes its owner/protection level, requests
the previously unrequested signature permission and promotes the normal
permission to signature. Original eligibility must remain unchanged: the captured
positive still delivers and the new candidates remain denied. A separate helper
restores and verifies all modified public metadata in a finally path. No private
authority set is read or written. Final positive/null-permission deliveries run
after restoration. Exact cumulative dynamic and manifest counts finish at seven.

The APK contains seven fixture classes: Main, DynamicReceiver, ManifestReceiver,
Barrier, FakeContext, GrantPM and MetadataState. It supplies no platform class,
Google permission, policy service, account or network behavior. Registration's
sender-permission argument, category/data matching, exported-receiver rules and
cross-process routing remain outside this fixture's scope. These host checks do
not establish ARM delivery, GMS, Maps or authentication.

The first builder compile passed. Its production attempt stopped at API-28
assembly because DEX rejects overlapping catch-all handlers with different
targets in one method. That complete failed r1 pair is retained. Moving metadata
mutation/finally into its own method kept both metadata restoration and outer
thread cleanup while separating their DEX ranges. Fresh r2 compile and production
passed every original check: API-28 assembly, two disassemblies around reassembly,
all seven canonical classes equal, live reference assertions, exact membership,
compiled manifest declarations, v3 APK signature and signed DEX extraction.
Production and signed DEX match; canonical roundtrip DEX has its separate pin.
All source/tool inputs were rehashed afterward and match their frozen copies.
Independent source and generated-artifact reviews passed.

The successful r2 compile/production guards and children exited zero, reasons
empty, cleanup complete and swaps zero under the unchanged 600 MiB aggregate RSS,
300-second, 512 MiB observed-growth, 1 GiB reserve, 4 MiB output and shell file-size
16777216 limits. Compile elapsed 1.294 seconds, sampled RSS 307,576,832 bytes and
detailed maximum 373,506,048 bytes. Production elapsed 5.813 seconds, sampled RSS
109,772,800 bytes and detailed maximum 108,625,920 bytes. The failed production
record remains exit 1/1 with cleanup complete, without an APK. No limit was
relaxed. The compiler/Java lane was released after actual completion.

Paths below use `S=/Users/alex/.local/state/vinix/android`.

| Artifact | SHA-256 |
| --- | --- |
| `S/broadcast-permission-fixture-2026-11-02-r2/probe.apk` | `0219961f053e02b8d4435b87e86acec64e56d57eb2b68d2f175638016eda37b5` |
| Build receipt | `a2fa842f2df8bf23229140479c512952d24b268e7b4d2091841ee0d61fe2b09a` |
| Production / signed-extracted DEX | `c06c5c128e7d63e93de3cacbd01ef473091231bacbb360a66828468e015beb9d` |
| Canonical roundtrip DEX | `7e74806fd85a29acdd33ee5ae98fa27927cdb835c3a0b2ea1efb39fde595fcdd` |
| Both canonical Main classes | `79c7bee85065f2191020fadb0397bfc1076f68eadf06df7c863af89ef9c3575d` |

Complete r1/r2 artifacts and inputs remain in their fixture directories and
matching `broadcast-permission-fixture-controls-2026-11-02-r1` / `-r2` roots.
The successful build records source revision
`0b00959bc20d3dd9e6e6804b9a60393949d29a94`. Its exact success marker is:

```text
BROADCAST-PERMISSION-PASS actual-delivery signature-owned null-legacy denied-permissions fake-grants immutable-authority metadata-restored async-barriers
```
