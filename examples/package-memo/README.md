# Signed native memo example

This static V application uses application context 1 and native window protocol
2. Its single-line memo accepts at most 256 UTF-8 bytes. Click the field, edit,
and press Enter to send a replacement; Escape discards a local edit. Save writes
the committed value in this app's ordinary-account private data directory.
Closing keeps the last saved value. No document, network, process, device or X11
access is granted.

Build a publisher workspace for both architectures with a reviewed V compiler,
`aarch64-linux-musl-gcc` and `x86_64-linux-musl-gcc`:

```sh
V=/path/to/v /path/to/v run examples/package-memo/build.v /tmp/memo-repository
```

The builder includes SDK, V and musl notices. `VINIX_MUSL_COPYRIGHT` can select the
matching toolchain's musl notice. Sign/export with
[`publish-release`](../../tools/packages/SDK.md#build-and-publish), then enroll
the reviewed publisher key through your authenticated channel, refresh and
install `org.vinix.memo`. Software, Start and Quick Launch choose the installed
manifest's protocol automatically. The builder creates no trust key or account.
