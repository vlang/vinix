# Unix recvmsg flags

WebKitGTK 2.48.1 receives Unix IPC with `MSG_NOSIGNAL` in its
[ConnectionUnix implementation](https://github.com/WebKit/WebKit/blob/webkitgtk-2.48.1/Source/WebKit/Platform/IPC/unix/ConnectionUnix.cpp).
Vinix previously rejected that flag with `EOPNOTSUPP`. Receiving does not
generate `SIGPIPE`, so accepting it has no further effect.

Build the checks and a static ARM64 guest executable with V:

```sh
/path/to/v run tests/unix-recvmsg-flags/build.v \
  /path/to/vinix /path/to/v /fresh/external/artifact-root
```

The builder extracts the production constants and rejection expression. Its
host test covers all four accepted combinations and each of the other 30 bits
combined with those flags. The old rejection expression is a negative control
and must fail. These checks verify the mask, not guest syscall behavior.
Sources, commands, output, executable hashes and a full inventory are retained.

Run the generated `guest` executable on the Vinix kernel containing the fix.
It exercises real stream, sequence-packet and datagram Unix socketpairs:

- Queued payload receives with `MSG_NOSIGNAL`.
- Empty nonblocking receives, including `MSG_CMSG_CLOEXEC`, return `EAGAIN`
  without setting the descriptor's `O_NONBLOCK` flag.
- An unsupported flag returns `EOPNOTSUPP` and leaves queued data intact.
- Descriptor passing works with and without close-on-exec after closing the
  sender's descriptor; reading the received descriptor verifies its contents.
- Sequence-packet truncation preserves the next record boundary.

Success ends with `UNIX-RECVMSG-FLAGS-PASS all=3`. The fixture deliberately
checks Vinix's unsupported-flag contract and is not a generic host-Linux test.
Building it alone does not constitute a guest pass or browser qualification.
