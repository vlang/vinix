# Account tools

Users, groups, passwords, the authentication service and sessions.
[`docs/accounts.md`](../../docs/accounts.md) describes the design and the
rules; this page is where things are.

| Path | What |
| --- | --- |
| `accountcore/` | The account database: `model.v` (what is valid), `parse.v` (the three files' text), `store.v` (reading and replacing them), `ops.v` (add, remove, lock ...), `password.v` (scrypt records), `throttle.v` (the wait after wrong passwords). |
| `authproto/` | The frame format on the service's socket. |
| `authcore/` | What the service decides (`service.v`), the action files (`action.v`) and how an allowed action is started (`run.v`). |
| `authclient/` | Connect, send one request, read one reply. |
| `sessioncore/` | `become.v`: a root process turned into an account's, logins and the seat. `launch.v`: starting a session. `manager.v`: the session manager. |
| `actions/` | The action files that ship, installed in `/usr/share/vinix/actions`. |
| `authd.v` | `vinix-authd` |
| `auth.v` | `vinix-auth` |
| `account.v` | `vinix-account` |
| `session.v` | `vinix-session` |
| `system.v` | `vinix-system` |

## Building

    tools/accounts/build aarch64|x86_64 ROOT

builds the five programs statically for a Vinix machine and lays them and
the action files out under `ROOT` as they are installed.

The command is a thin launcher for `build.v`, which invokes the V staging tool.
It keeps `V`/`VINIX_V_COMPILER`, `CC` and `VINIX_AARCH64_SYSROOT` for AArch64,
and `CC_AMD64` for x86_64. Compiler names and paths are literal arguments.
For other cross compilers, invoke staging directly with an explicit argument list:

```sh
V=/path/to/v /path/to/v -path '@vlib|@vmodules|.|tools/accounts' \
  run tools/accounts/stage.v --arch x86_64 --staging /existing/image \
  --cc-argv '["x86_64-linux-musl-gcc"]' --include-session
```

Staging captures the image and destination directories before publication. It
refuses symlinked, replaced, writable or cross-filesystem destination parents,
and aliased existing tool files. A private file is written, synced and atomically
renamed into place; failures before publication preserve the existing tool.
A directory flush failure after rename reports that the new tool was published
and image staging should be retried. Each file is published separately. Binaries
are mode 0755 and action files 0644. The `stagecore/install_test.v` checks cover
path replacements, outside-file preservation, short writes and flush failures.

A system starts using them with, as root and in this order:

    vinix-account init      # at every boot
    vinix-authd &           # before anything that logs in

## Tests

Host tests are beside the modules (`*_test.v`); `v test tools/accounts`
runs them. They cover the parsers with malformed and hostile input, the
password records against RFC 7914's vector, every rule of the service with a
stand-in for starting programs, and the shipped action files.

[`tests/accounts`](../../tests/accounts/README.md) boots a kernel and runs
the real programs as real accounts.

`authproto.text_frame`, `decode` and `read_frame` return owned frames. Call
`Frame.close()` once the result is no longer needed; it erases field bytes,
releases their buffers and resets the frame, including on repeated close.
`Frame.wipe()` keeps the caller's containers and lengths, so it also works on
borrowed requests. `encode` returns caller-owned bytes and `Frame.text` returns
an independent owned string. `write_frame` borrows its input and erases/releases
its own encoded temporary on success or failure. Erasure uses `explicit_bzero`
on Linux and `memset_s` on macOS so a following free cannot eliminate it. See
[authentication frame qualification](../../tests/packages/auth-frame-check.md).

`authclient.transact`, `ask` and `ask_root` borrow the request's field buffers
and erase their contents on every return. The caller retains the buffers and
any explicitly supplied variadic table; the returned frame is owned and needs
`close()`. Failed reply reads retire their internal error before returning the
existing generic service diagnosis. Complete transactions, malformed replies
and root-peer decisions have tracked ownership checks; see
[authentication client qualification](../../tests/packages/auth-client-check.md).

`vinix-session run --isolated USER COMMAND [ARGUMENT...]` is a root-only
application profile. It creates a login attributed to that ordinary account,
drops all supplementary memberships before dropping privileges, verifies the
same IDs/capabilities as a normal session, and waits for the command. It does
not acquire the hardware seat. Normal sessions retain their account groups.
The package service uses this profile for its configured `launch_user`.

Ordinary desktops keep their account memberships. Package launches from those
sessions use the fixed `packages-launch` action (`auth = account`): the kernel
identifies the caller, and `vinix-session package-launch` runs only the installed
package CLI with that account's isolated profile. The helper and supervisor drop
root; existing stdin/stdout/stderr descriptors preserve native-window and terminal
I/O. No password or account selection is involved. See
[qualification](../../tests/packages/isolated-launch-check.md).

## Adding an action

Write a file in `actions/` (the format is at the top of
`authcore/action.v`), and a program for it to run if `vinix-system` or
`vinix-account` does not already do the thing. Keep the program to one
operation with arguments it checks itself: the service checks them too, but
the program is what runs as root. `authcore/shipped_actions_test.v` fails if
a shipped file does not parse or lets someone who merely sits at the machine
change accounts.
