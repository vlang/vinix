Run `tests/native-host/stdio-test` to compile and qualify the real native query.
`VINIX_NATIVE_STDIO_QUERY` retains the original executable override.
An existing query and a retained evidence directory can also be supplied:

```sh
tests/native-host/stdio-test /path/to/native-query /path/to/evidence
```

The V test preserves all 27 combinations of open, closed and close-on-exec
standard descriptors, nested callbacks, saved error object identity and EOF.
It also checks 100 failed spawns, then performs 500 calls and four workers with 100 calls each, requiring
unchanged descriptors and a retired PID after every call. A real SIGINT checks
the same final retirement boundary. Device and inode numbers retain all 64 bits.

`qualify.v COMPILER NEW_EVIDENCE arm|x86|san` cold-builds the test, unchanged
query, numeric-token tests and existing archive/reader regressions. It checks
build status, assertions, sanitizer diagnostics and the final evidence receipt.
Qualification executes no Python or Vinix guest.
