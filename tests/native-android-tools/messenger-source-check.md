# Messenger Binder and Message parcel contract

The previous Messenger returned a null Binder and ignored the Binder constructor
argument. It now exposes the Handler's cached endpoint, resolves supplied local
or proxy endpoints, compares endpoint identity, and supports Parcelable and null
parcel helpers. The old private `Messenger$1` no-op implementation becomes the
fieldless Parcelable creator; the complete baseline reference scan proves its
only external reference was the replaced Messenger constructor.

The implementation follows the [API 28 Messenger contract](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r3/core/java/android/os/Messenger.java),
the [oneway IMessenger interface](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r3/core/java/android/os/IMessenger.aidl),
and [Handler's sender capture before enqueue](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r3/core/java/android/os/Handler.java#L808).
Stub/Proxy use the real descriptor, token, transaction, presence marker and
Message parcel payload. The proxy recycles in a finally path and propagates
transport exceptions; Android 28's ignored `transact` boolean is preserved.
Handler delivery remains queued through the existing implementation.

[Message's API 28 wire fields and rejection rules](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r3/core/java/android/os/Message.java#L534)
include Parcelable objects, Bundle, reply endpoint and sending UID. The UID is
initialized/reset to -1, copied by both copy operations, and overwritten with
`Binder.getCallingUid()` before enqueue. Callbacks and non-Parcelable objects
are rejected; the typed ClassCastException boundary includes object writing.

One combined generator preflights five changed classes and three additions
before writing. Handler, Binder and Parcel remain byte-identical. All targets
are outside the retained native map's 70 classes. This uses the existing local
Binder transport and Parcel object-reference table; it adds no remote transport
or remote credentials. Full SDK/native equality and ARM/live behavior remain
separate checks.

Focused proof passed with 24 malformed/collision refusals before writes and 24
independent semantic controls. API-28 baseline and patched assembly plus two DEX
roundtrips passed, including exact method/member deltas, raw preservation and
stable second-roundtrip bytes. The first attempt retained a compiler notice;
the second retained equivalent apostrophe-escape rejection. The successful
third attempt normalizes only that const-string encoding, with an explicit
equivalence control. No guard or diagnostic requirement was relaxed.

Evidence: `/Users/alex/.local/state/vinix/android/messenger-source-check-2026-11-02-r1`,
including frozen sources, complete failed attempts, successful `proof-check-r3`,
generated C, input pins, guarded receipts and both DEX roundtrips. Receipt SHA-256:
`14123007cd04d2852d23684dcd6cc8dbf7480a0bcce797ac6700ece4657b622f`.
Proof source parent: `ec67fa1cb65d9c0ebc1d6374aab9ae85db024d79`.
Parent SDK `combined-account-webview-usage-inactive-framework-2026-11-02-r1`
manifest/JAR SHA-256: `bfadac214671937539a4732b3ca6be22d561c366b96a72a9de045fc362aba1fe` /
`d7b6d8c37d5d09d200c19b429f07cf6666ed6d8cf5a1a1b4d29c0dfd27cd632b`.

Successful proof: guard/child exit 0, cleanup complete, 7.155 seconds,
262,619,136 bytes sampled aggregate RSS, 178,405,376 detailed RSS and zero
swaps. Split compiler sampled/detailed maxima: 255,098,880/278,708,224 bytes.
Original limits remain 600 MiB RSS, 300 seconds, 512 MiB observed shared-volume
growth, 1 GiB reserve, 4 MiB output and file cap 16777216.
