# Native account caller authority

This module supplies a caller boundary and a narrow request transport for an
account broker running in its own process. It grants no Android permission,
discovers no authenticator, stores no account and forwards no GMS request.
The existing shared ART process
cannot become a privileged broker through a Java `Context` or package string.

An administrator may opt a native APK launch into registry verification with
`VINIX_ANDROID_ACCOUNT_REGISTRY=/absolute/registry`. The existing explicit
`VINIX_ANDROID_UID`, `VINIX_ANDROID_GID`, data and home configuration remains
required. Invalid or empty registry configuration stops the launch before the
UID drop, library installation and ART startup. Omitting the registry retains
the existing launch behavior and provides no broker authority.

Registered Unix UIDs must be reserved exclusively for their registered package.
The administrator must route **every** launch under these UIDs through registry
verification. Legacy launches without the registry can otherwise execute another
APK under a registered UID and impersonate that package at the socket boundary.
Opt-in policy relies on this provisioning invariant; it cannot protect against
Unix root deliberately bypassing verification or reusing a registered UID.

The registry format is UTF-8 text with a final newline. Its first line is
`vinix-android-account-authority-v1`; each following line has seven tab-separated
fields: package name, Unix UID, Unix GID, absolute APK path, lowercase APK SHA-256,
lowercase signing certificate SHA-256, and allowed service/action selectors. The
last field is `-` for none or up to 16 comma-separated exact
`fully.qualified.Service@fully.qualified.ACTION` pairs; nested service classes may
contain `$`. There are no wildcard selectors. It admits at most 64 entries and
64 KiB. Each package, UID, GID, APK path and APK digest must be unique. IDs are
within `10000..19999`. There are no comments or escape sequences.

The administrator must verify APK signatures before provisioning the registry.
The certificate digest records that administrator's attestation bound to the
exact APK digest. This module hashes APK bytes; **it does not parse or verify
APK signing blocks or certificates**. Do not generate a trusted registry from
unverified app-supplied metadata.

The registry and all APK files must be regular files owned by Unix root, have
one hard link and no write permission bits (for example, `0444`). Every path
component is opened from a pinned root dirfd using `openat`, `O_NOFOLLOW` and
`O_DIRECTORY` where appropriate. Ancestors must be root-owned directories
without group or world write permission. Symlinks, writable ancestors, FIFOs,
oversized files, duplicate identities and digest mismatches fail. No file is
reopened by pathname while hashing. The loaded registry is a fixed snapshot;
administrative updates require restarting its consumer. Unix root remains the
trusted provisioner and can replace these inputs.

`Registry.authenticate(fd, claims)` obtains kernel credentials from a connected
Unix stream socket. Linux uses `SO_PEERCRED`; the macOS host-test adapter uses
`getpeereid` and `LOCAL_PEERPID`. It returns the registered UID/GID's package,
PID and pinned digests. Optional claimed package, UID and PID must agree with
those values. Supplying no claims still requires a registered kernel peer.
Socket family, type, connected state, credential size and positive PID are
checked. It never derives identity from a Java object, environment option or
request payload. Companions loaded in a primary package's process have that
primary process's authority, and cannot claim their own distinct package.

The broker must consume this result for each request, overwrite identity
options before authenticator dispatch, and keep its privileged role on a
separate administrator-provisioned process/channel. Exporting this socket helper
does not itself make a private service accessible. APKs which still run as Unix
root or share a UID are deliberately ineligible for this registry.

The headless host form is `run-android APK --service-fd N`, with exactly those
arguments, the protected registry, explicit target UID/GID and prepared data/home
directories. The inherited connected Unix stream must have a kernel-authenticated
root peer. The launcher preserves it across exec and performs the same complete
credential/capability drop as a graphical launch, omitting only the surface check.
The receiver must call `verify_service_frame` before any APK code and set
`FD_CLOEXEC` before starting the service runtime.

The root peer sends exactly one ASCII, tab-separated frame followed by newline:
`vinix-android-service-host-v1`, package, fully qualified service class, action,
and APK SHA-256. Parsing has a 4096-byte limit and one monotonic five-second
deadline. The package, APK digest and exact service/action pair must match the
registry, and real/effective UID/GID must match the selected registered IDs.
There are no UID, permission, credential or account fields in this protocol.
Queued extra bytes, multiple frames and a closed controller fail. The receiver
keeps the descriptor for the host lifetime; subsequent bytes are a protocol
failure and EOF requests orderly teardown. This is a bounded service lifecycle
control channel, not an authenticator RPC or account-creation channel.

Run host tests with `v test build-support/android/nativeaccountauth`. These test
registry parsing, authority decisions, launch failure behavior, file metadata
policy and real host socket credentials. They do not establish separate-process
GMS operation or Google account sign-in.

`tests/native-android-ws/account-authority-build.v REPOSITORY FRESH-EXTERNAL-OUTPUT`
freezes the full module and fixture sources, records command/tool/source/output
hashes, and cross-builds a static AArch64 executable. The fixture requires root
on Linux/Vinix, creates a fresh protected directory directly under `/`, checks
writable inputs, ownership, symlinks, hard links and digest changes, then forks a
UID/GID 10000 Unix socket client and rejects forged package/UID/PID claims. It
cleans up its own child and directory with bounded waits. Its APK bytes are
synthetic and carry no actual signer or account authority.

Build evidence from source revision `dcb2d755f95404cf9abaeae19d532a0f0fff1236`
plus the frozen change is retained outside Git at
`/Users/alex/.local/state/vinix/android/account-authority-build-2026-10-26-r1`.
`inputs.json` pins every changed source; `build.json` and per-command receipts pin
the static binary, tools and commands. Host tests passed (2/2), and both the
fixture and launcher cross-compiled for AArch64. That original build was not
executed. A later frozen build, described below, passes on Vinix; neither build
establishes GMS or Google sign-in success.

## Narrow request transport

Commit `958b97f8a` adds a versioned, bounded binary request on a separate
connected Unix stream. It accepts `get_accounts` and `add_account`, nullable
types, bounded features and scalar options. It rejects caller identity and
response capability keys supplied as options. The receiver authenticates the
socket's kernel peer against the protected registry and returns that immutable
caller with the decoded request. The client verifies its root peer before
sending. One monotonic deadline covers framing and the mandatory write-half
close; delayed trailing frames are rejected. Both endpoints protect the
descriptor against inheritance.

The four host test suites pass, including fragmented requests, delayed and
coalesced extra frames, malformed fields, forged identity options and deadline
failures. The module also cross-compiles into the static AArch64 authority
fixture. This transport has no account dispatcher, response protocol or account
store yet. Its stream must never be substituted for the service lifetime
channel described above.

## Vinix authority verification

The credential-free authority fixture passed in an isolated AArch64 Vinix guest
on 26 October 2026. The exact `ACCOUNT-AUTHORITY-PASS` marker covers protected
launch, wrong UID, writable registry/APK/ancestors, ancestor and file symlinks,
hard links, digest and owner changes, real Unix peer credentials, the child UID,
and forged package/UID/PID claims. Its synthetic APK bytes grant no account
authority. The independent browser phase stopped before starting WebKit because
an existing guest helper could not be replaced; that failure does not change
the separately recorded authority result.

The tested frozen build is retained at
`/Users/alex/.local/state/vinix/android/account-authority-build-2026-10-26-r5`.
Its receipt records source revision
`d3d9ccf7b86442d2671a1e11d7bff4a2fc6881c3` plus the complete frozen source
inventory (SHA-256
`4d105cc4287ec710962eb672b4e3ebc2848b3aa5d48c1ead90e82731482f81f1`).
The executed static binary SHA-256 is
`8b4eacffb316404965280e4056eccb5bcbd8ab545bfdbce5f068f9b247c5c5c2`.

The complete guest export was restored at
`/Users/alex/.local/state/vinix/android/browser-probe-results-2026-10-26-r1`.
Its strict collector verified all nine entries and the 131,804-byte archive
(SHA-256
`5d8e307ba3e5c31dc7aa4c2ba6a36cc682107d12f9f8dc31af6a4d371103e771`).
`results/authority.log` retains the exact marker and `results/guest.json` records
exit zero, no timeout and zero cleanup survivors. The original serial log and
guest media remain in
`/Users/alex/.local/state/vinix/android/browser-probe-vm-2026-10-26-r1`.
