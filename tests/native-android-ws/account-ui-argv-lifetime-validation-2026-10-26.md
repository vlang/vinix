# Account UI helper argument lifetime validation

The `start_helper` argument array recursively frees its string elements. The
previous cleanup explicitly freed its three fd strings before freeing the
array, and the array also borrowed the controller's helper/socket strings.
The fix gives the array its own cloned config strings and releases it once.

Source base: `5534dc6289631432f8c45081c9bf3a78713e8a7f` (last change to
`build-support/android/accountuifd/control.c.v` before this fix). The retained
manifest pins the exact fixed source and checker used for this run.

`account-ui-argv-lifetime.v` extracts the actual production argument/defer
block and compiles it with the production account compiler
`/Users/alex/code/v-tccbin-bootstrap-20261026/v`, `-gc none -manualfree`, host
Clang and AddressSanitizer. Results:

- 256 fixed invocations pass with no lifetime diagnostics, including cleanup
  of the shared controller config after all invocations. The unchanged literal
  arguments are included in this test.
- Restoring the old numeric frees produces V's runtime
  `double string.free() detected` diagnostic. V suppresses the repeated libc
  free in this case, so this variant does not require an ASAN abort.
- Removing the config clones produces an ASAN double-free and nonzero exit.

Run from the repository root with a fresh external destination:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v run tests/native-android-ws/account-ui-argv-lifetime.v /Users/alex/code/v-tccbin-bootstrap-20261026/v /absolute/fresh/state
```

Complete sources, generated test programs, three binaries, build/run logs and
checksums are retained outside Git at
`/Users/alex/.local/state/vinix/android/account-ui-argv-lifetime-2026-10-26-retained`.
`SHA256SUMS` SHA-256:
`d45b91f23a68240b52b9c2098edd9175a6f1ceac3adbe4ebe0ad92571d9607fd`.
ASAN used `detect_leaks=0`; this check establishes the argument lifetime fix,
not whole-process leak freedom. It does not boot a guest or establish Google
account sign-in.
