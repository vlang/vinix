# SMB2.1 filesystem

The implementation is `kernel/fs/smb2.v` (VFS/socket adapter) and
`kernel/fs/smb2/` (borrowed-buffer wire client, parsers and NTLMv2 crypto).
The filesystem registers as `smb2` in the VFS filesystem table.

## Mount contract

Use filesystem type `smb2`, source `//<IPv4>/share`, and options
`user=<user>,domain=<domain>,password=<password>` or `guest`. Optional `ro`
and the VFS read-only mount flag prevent mutations. Only direct TCP port 445
and SMB dialect 2.1 are supported. Credentials are never logged. The disposable
qualification fixture uses `//10.0.2.2/share`, user `m17a`, domain `WORKGROUP`;
its public test credential is in `tests/smb2/guest.v`.

Authentication uses SPNEGO NTLMv2 with unpredictable kernel-generated nonces,
server timestamps where supplied, and MIC/AV_FLAGS handling. VERSION occupies
its eight-byte slot, zero when not negotiated; MIC is at byte 72. See
[MS-NLMP AUTHENTICATE_MESSAGE](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-nlmp/033d32cc-88f9-4483-9bf2-b273055038ce)
and the [published NTLMv2 messages](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-nlmp/bc612491-fb0b-4829-91bc-7c6b95ff67fe).
NTLMv1, Kerberos-only policy, SMB3 encryption, guest signing, reparse points,
hard links and symlinks are unsupported. The first rejected NTLM token emits
an explicit mechanism-policy diagnostic. Authenticated requests use SMB2.1
HMAC-SHA256 signing; response signatures and message/session/tree identities
are checked. Invalid framing kills the connection.

## VFS and lifetime limits

The adapter implements lookup/population, refreshed stat/permissions, file
read/write/append/truncate, create, directory enumeration, rename, unlink,
basic timestamp/read-only attribute updates and flush. Every reopen of a known
resource validates its inode and directory type with QUERY_INFO on that same
opened FileId before using it, including directory population and refresh.
A replacement fails closed (EBUSY on an identity mismatch) rather than reading
or modifying the replacement. Host in-place edits with the same inode remain
visible to retained VFS descriptors. Append
is serialized within this client, without a cross-client atomicity guarantee.
POSIX uid/gid/mode fidelity and open-after-unlink semantics are unsupported.
Descriptors reopen by path rather than retaining a server handle: deletion
can fail with ENOENT and replacement fails closed. Known cached aliases of a
rename source cause rename to fail EBUSY; a successful rename updates cached
descendant paths. Server inode reuse cannot be distinguished by this check.

There are four boot-lifetime session slots, reserved before network I/O.
Failed mounts release their slot. Equivalent source, uid, credential hash and
read-only policy mounts reuse an established published server session. This
does not force fresh authentication on remount: an old password can still
match the cached credential hash after server-side revocation while the
established session remains valid. This is session reuse, not evidence of a
new server authentication or acceptance of the revoked password.
Each session owns bounded buffers and at most 512 lifetime nodes (including
roots for cached mounts); limits fail with ENOSPC. Create/delete churn, remote
directory churn and repeated cached mounts can exhaust this lifetime budget.
This experimental mission intentionally retains a strict bounded boot cache,
in the same lifetime style as 9P, rather than claiming general reclamation.
Unmount does
not reclaim published sessions/nodes; they remain owned by the bounded boot
cache. No transparent reconnect or slot eviction is implemented. Removed
bindings keep their node allocation pinned using `mount_covered`, preventing
the generic removed-node reaper from freeing nodes still referenced by this
cache. The pin must not be removed without a complete ownership repair.
Inode replacements fail EBUSY.
`TREE_CONNECT.MaximalAccess` controls inferred server read-only behavior.
Private destruction explicitly erases the credential hash, session signing
key and transmit/receive/scratch buffers with `krandom.explicit_bzero`.
Mount-local credential/nonces and the options descriptor are explicitly
erased on exit as best effort; borrowed option strings and compiler or
protocol stack temporaries are not all owned or erased by this facade.
No constant-time or complete stack-erasure guarantee is made.
`InetSocket.unref()` owns the concrete socket and its `resource.Resource` box;
the adapter frees its separate `sockpub.Socket` interface box afterward.

The client validates unused NEGOTIATE security-buffer and CREATE-context
offsets/lengths as well as consumed buffers. Unrequested CREATE contexts are
rejected. SPNEGO requires bounded, minimal definite DER and accepts an NTLM
challenge only from NegTokenResp.responseToken, never byte scanning.

## Host checks and qualification boundary

Run with an existing host-capable V compiler and writable scratch directory:

```sh
"$V" -gc none -cc clang run tests/smb2/protocol/run.v
"$V" -gc none -cc clang run tests/smb2/privacy/run.v
```

The runner copies the production SMB2 module files unchanged to scratch.
Only `krandom.sha256_digest` is replaced by a standard `crypto.sha256` fixture
with the same interface. It tests RFC 1320 MD4, RFC 1321 MD5, RFC 2202 HMAC-MD5,
RFC 6229 RC4, MS-NLMP response-key and complete published NTLMv2-response
vectors; MIC/zero-version and header HMAC behavior; malformed challenge,
directory, DER, negotiate/context offsets; options and fake transport framing.
Scratch is removed on completion. This does not test the kernel SHA256
implementation, actual TCP transport, full-kernel compilation or guest VFS.

An optional `--samba` argument runs the actual production protocol over host
TCP against the disposable Samba fixture described in `tests/smb2/README.md`.
This is not a guest mount receipt. Full kernel builds and actual guest VFS
qualification use `tests/smb2/rig.v` and `tests/smb2/guest.v`. See
`tests/smb2/README.md` for the required serial receipts and host checks.
