# Canonical Asahi wire definitions and flat packets

Build the V runner with the tool module path, then run it against the packaged
Linux-Aurora checkout and a fresh external result directory:

```sh
v -cc cc -path 'tools/agx-re|@vlib|@vmodules' -o /external/agx-packet-run tests/agx-packet/run.v
V=/path/to/v /external/agx-packet-run --asahi-linux /path/to/linux-aurora --state-dir /external/fresh-packet-run
```

The runner checks the generated definitions, then compiles a V oracle against
the actual C header. Every record size and every field offset is compared,
including nested types, arrays and padding. The native C compile removes only
the `__user` address-space annotation and supplies 64-bit host-width constants;
the upstream headers are retained unmodified. It never executes upstream scripts.

The parser fixture runs under address/undefined-behavior sanitizers. It covers
64 mixed hardware commands, synthetic attachment state, independent subqueue
barriers, zero-extended short records, nonzero unsupported tails, unknown
commands and malformed lengths. The reader uses caller-owned immutable bytes
and fixed-size values; it allocates no kernel objects.

These are protocol components. Device registration and scheduling must use
them before the native driver can advertise the new ABI. Passing this test
does not certify full driver parity or GPU execution.
