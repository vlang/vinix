# Framework APK descriptor sharing

Following 757407a57, r89 ran the signed-API-qualified r88 native adapter and
the new descriptor observer. Its ARM self-test and seven live inventories
completed. Both process identities were stable across every inventory.
Descriptor enumeration is non-atomic; unavailable readlinks are retained.

| Process / phase | Listed fds | Unavailable | APK targets | framework-res.apk targets |
| --- | ---: | ---: | ---: | ---: |
| GMS 16497 / early | 287 | 1 | 127 | 83 |
| GMS / later | 262 | 0 | 127 | 83 |
| GMS / account window | 401 | 2 | 223 | 147 |
| Maps 29824 / early | 192 | 1 | 112 | 72 |
| Maps / onboarding | 313 | 2 | 115 | 73 |
| Maps / account | 333 | 0 | 116 | 73 |
| Maps / Explore | 348 | 0 | 115 | 73 |

The retained limits report a soft open-file limit of 1024 and hard limit of
1048576. r89 did not reproduce r88's EMFILE failure in Maps; no uncaught Maps
exception or EMFILE text appears in its private log. These observations show
many duplicate framework APK descriptors, not the ownership of every handle
at r88's failure. No descriptor limit was raised.

The account window again showed a Google communication error before any
credential form. Closing that window and selecting Skip left Maps alive and
rendering real map tiles. The unchanged 15-minute controller budget ended at
16:33:49 during search, with bounded-session-ended-no-authentication-claim,
empty controller error and one cleanup survivor. No search result or route
was validated. The readiness line had been interleaved with kernel console
output; a literal-line search missed it. Protected receipt/session state was
already ready. Buffering was not established; a speculative flush edit was
withdrawn before commit or deployment, with its trial build retained.

The storage watch completed 600105 ms, minimum available data volume
7943086080 bytes, minimum guest MemFree 3912896 KiB. Before export, the copy
terminal again checked the selected volume. Export BEGIN/END agree on
1429221 bytes and 2792 chunks. Empty-removal reconstruction passed without
repair. Private results were copied to that volume and synced at the prompt;
owned QEMU19515 was then stopped and confirmed absent, including open-image
checks, before read-only extraction. Private log digests match their manifest;
the private receipt equals the reconstructed exported receipt. Read-only
e2fsck passed under the original guard. r87, r88 and r89 are stopped.

Evidence below is relative to /Users/alex/.local/state/vinix/android:

| Artifact | SHA256 |
| --- | --- |
| maps-fd-account-uart-20261114-r1/full.log | 9fc4c16e8cd70ba402d30a4dbd94bd48d7327c9e5e882a9e007069cb03ccf454 |
| maps-fd-account-readback-20261114-r1/archive.json | d02885804efaaa6aaf2112d965bfce942e231e8e08364df66006e3560485ea59 |
| Same readback, exported-receipt.json | c941f2d9913f97a89999fcb662ed6c57e5da40b56ab23b1e1c9069497fc910e5 |
| maps-current-20261114-r89/private-readback/descriptor-inventories.sha256 | 3e7651ca1f37a8b6d10529b4cfbf3d0fe13909e70e7f5a72c664b5496f074d82 |
| Same private directory, results/maps.log | 045fdd052fd84d788837e57d337e64f5077851f14fcecdeb0c2882c82603a517 |
| Same private directory, results/broker.log | d9fabfe0752dcc2d80a74c1d5afea684a21fec7cd733bc024349cc72fdc9dc9e |
| Same private directory, storage-watch.log | 03c42c3e4ca20c1ce0ac7b00d29a7cf6a71bc7efad16e75d94b18511c1ec6311 |

## Cache candidate

The native adapter now shares the selected runtime's exact framework-res.apk
handle when stat/statvfs prove a root-owned regular file on a read-only mount.
Device, inode, size, mtime and ctime including nanoseconds must match. A mutex
serializes cache reads and fills; stamps must also agree before/after loading.
Failed loads and changing inputs are not published. Other files and directory
providers retain their existing behavior. Java resource-manager lock scopes
are unchanged.

The C facade exposes const APK handles without a release API. Existing managers
borrow those process-lived objects. This change shares one such object; it
does not free old handles, managers, string pools or themes. Replacement inputs
get a fresh object while prior borrowers remain valid. It reduces duplicate
framework descriptor pressure, without claiming to repair every resource leak
or the Google check-in timeout.

Using available V 0.5.2 cbfc1be, framework-apk-cache-checks-20261114-r5 passed
production-extracted code with real pthreads, eight concurrent callers, mutable
path/read-only/owner/type guards, all seven stamp fields, changing inputs and
failed loads. Eight hundred concurrent cache accesses produce one load and
one bounded private cache-hit marker. Five compiled negative mutations were
rejected. Guard: 0/0, complete cleanup, 6130 ms, sampled RSS 193462272 bytes,
growth 76496896 bytes.
The full ARM adapter build framework-apk-cache-native-20261114-r4 passed 0/0,
complete cleanup, 15927 ms, sampled RSS 579076096 bytes, growth 23298048 bytes,
under the original caps. Its DSO SHA256 is
2497acb8091247a0eeb5ff5d128e0c52440cb9c7273fc44eb96c0d0dd4071848;
public defined symbol names and four DT_NEEDED libraries match the prior DSO.

The historical check-resource-locks checker refused the current tree because
its fixed file list excludes the already committed asset_locales.v. Its failure
is retained in framework-apk-lock-checks-20261114-r1; the checker was not relaxed,
and no historical-compiler replay was invoked. Inspection confirms the existing
resource lock scopes remain unchanged. Early cache attempts retain a model-name
collision and const-pointer link errors; explicit casts fixed the latter without
disabling -Werror. Guest cache-hit behavior and the full signed ARM regression
with this candidate remain pending. Google authentication is not qualified.
