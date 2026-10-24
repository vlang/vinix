# Android application scheduling regression

Production source revision: `1f21a7e0e72d5a092bf14b6d682bdf67c470f511`.
The launcher admits Android's nice range with `RLIMIT_NICE=40/40`, sets
`RLIMIT_RTPRIO=0/0`, and verifies both after dropping credentials.

The aarch64 guest regression passed all 18 cases: three successful launches
and 15 rejected configurations. Successful launches verified real, effective
and saved UID/GID 10000, no supplementary groups or capabilities,
`no_new_privs=1`, denied root recovery, and accessible application inputs.
Scheduling checks covered the full nice range -20 through 19, restoration from
a background priority, rejection with a zero nice allowance, hard-limit raises,
a different user's process, and enforcement after lowering the hard limit.
Disabled identity preserved both inherited scheduling limits. The host
configuration tests also passed.

The retained guest kernel returns `ENOSYS` for FIFO scheduling. Each successful
case records `fifo=unsupported-ENOSYS`; this run does not establish FIFO
permission enforcement. The initial test which required `EPERM` failed and is
retained in full alongside the corrected run. The corrected run also verifies
a zero real-time priority allowance and rejection of attempts to raise it.

The complete archive is
`/Users/alex/.local/state/vinix/android/identity-priority256-2026-10-24`.
It retains both runs, original boot inputs, exact fixture sources, pre-execution
compile/QEMU arguments and tool identities, actual tool binaries, the frozen
production launcher and its four-source build receipts, and host logs.
Manifest SHA-256:
`e645c0b94ede70036714f1fd42096dcd42637e444d5e26ff0ed6e8862d0afbf1`.

The assertion-enabled [checker](identity-priority-evidence.v) checks every
retained entry, source, tool and receipt, as well as exact guest result counts.
Validation includes rejection of an authentic partial archive and a wrong
manifest pin. Its production build exits before reading inputs because V's
`-prod` mode disables the required assertions. Run from the repository root:

```sh
v -cc clang -cflags -O2 -o /external/identity-priority-evidence tests/native-android-ws/identity-priority-evidence.v
/external/identity-priority-evidence check /external/restored-bundle MANIFEST_SHA256
```
