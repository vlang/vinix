# Account and privilege tests

Boots a built kernel in QEMU with the account tools in its root file system
and a V test program as init, and judges what that program prints on the
serial port. The controller is the hardware tests'
([`tests/hardware-platform`](../hardware-platform/README.md), module
`hwhost`); `run.v` here is the suite: the scenarios, the programs and the
files. Nothing here is Python.

The [authentication frame check](../packages/auth-frame-check.md) adds repeated
allocation and interrupted-wire fixtures as root and UID 1000. Its qualification
also runs this suite's `elevation` scenario with freshly built account tools.

    tests/accounts/run --arch aarch64 --kernel kernel/bin/vinix
    tests/accounts/run --arch x86_64 --kernel build-amd64-kernel/bin/vinix --scenario elevation

The options are the hardware tests'. Two environment variables help when a
scenario hangs: `VINIX_ACCOUNTS_ECHO=1` makes the guest repeat on the serial
port what the programs it runs print, and `VINIX_ACCOUNTS_TIMEOUT=<seconds>`
shortens the wait.

The guest (`guest/`) is init and also what the scenarios run *as an
account* to see what that account can do: `/sbin/init probe <what>`. The
image has no shell.

The separate [package runtime controller](../packages/runtime-check.md) reuses
the `packages-enforced` guest scenario with the production native sandbox. It
adds real pledge/unveil permission checks, a signed runtime dependency, payload
tamper refusal and maintenance of a running app's leased generation. The ordinary
accounts controller keeps the `packages` sandbox substitute so the identity
handoff can be diagnosed independently of the production enforcer.

The [dynamic Linux package controller](../packages/linux-runtime-check.md) uses
`packages-linux` with a target musl loader, shared V library and signed static
runner. It checks prepared-root import, ordinary sandboxed execution,
missing-library diagnostics, runtime rollback and clean uninstall.

The [persistent package controller](../packages/persistence-check.md) reuses
`packages-crash-staged`, `packages-crash-published` and `packages-crash-activated`.
Each case SIGKILLs QEMU at its transaction checkpoint and reboots the same ext2
volume, then verifies cached upgrade, rollback, uninstall, registration and
personal-file retention through the real package CLI.

| Scenario | What must hold |
| --- | --- |
| `packages` | Signed local installation through the real package CLI; a root launch re-executes it as the configured ordinary account with empty supplementary groups, empty capabilities, no new privileges and login attribution. A sandbox substitute checks the exec boundary and passes the literal document to the signed native payload, which writes private data as the user and exits with status 37. Missing launch identity fails, publisher revocation is rechecked by the ordinary child, and removal retains personal data. This checks the session handoff, not the real pledge/unveil enforcer or graphical runtime. |
| `accounts` | A registration record written the way the desktop wrote it becomes the first administrator, with the same password and the files that were kept for it under `/root/home`, now reached through `/home`. `vinix-account` adds an administrator and an ordinary account; `/etc/shadow` is 0600 and root's; homes are 0700 and their owners'. As the ordinary account: no reading or listing another home, even of a file whose own mode would allow it; no reading `/etc/shadow`; no writing `/etc`, the action directory, a program or `/home`; reading and writing its own home and `/tmp`. The administrator's account is refused the same things. `vinix-session run` gives a process with the account's three uids and gids, its groups, empty effective, permitted and bounding capability sets, `no_new_privs`, its home as directory and environment, and a private `/run/user/<uid>`; it refuses a session for root, and refuses to run for anyone but root. Locking keeps the password and stops it matching; a short password, demoting the last administrator and `vinix-account` run by an account are refused; removing an account removes its group, memberships, password record and home. |
| `elevation` | With `vinix-authd` running: each account is told its own name and whether it administers; a password is checked for its own account, for root asking and not for another account asking, right or wrong. `hostname-set` is refused to the ordinary account and to a wrong password, changes the host name and `/etc/hostname` for the administrator, and refuses an argument that is not a host name and an action that is not listed. An action is run as uid 0 with a fixed `PATH` and `HOME` and the asker's name; input for it arrives on its standard input. A `session` action is refused to an account that is not at the machine, allowed without a password to the one that is, and the file that says who is at the machine is not believed when others can write it and cannot be written by an account. An account is added through the service by the administrator and not by anyone else. One's own password is changed with the old one and not someone else's. After five wrong passwords the right one must wait, another account is not slowed, and the wait ends. The log and the failure counts cannot be read by an account; the log names who did what and holds no password. Four kinds of malformed request and six connections that say nothing do not take the service down or keep another account out. A console login refuses a wrong password, then gives a session that is the account's, with the session file naming it and gone afterwards; root cannot log in. |
| `unprivileged` | The sweep: about sixty privileged operations attempted by an ordinary account, each of which must be refused with `EPERM` or `EACCES` (or not exist at all, for the few the kernel does not have), after the harmless ones among them were seen to succeed as root. The machine has a disk, which root must be able to open and the account must not, for reading or writing; the display, the pointer and the console must be refused too. Afterwards the host name, the account files, `/tmp` and the other accounts' processes are as they were, and the controller finds every byte of the disk as it made it. |
| `seat` | Init has no login. A process without root and without a login, and a login session that does not hold the seat, are refused the display, the pointer and the console. Two sessions of one account are two logins; a session can neither relabel itself nor give itself the seat; root labels itself once and is refused the second time. With one session at the machine holding the display open: a second session that takes the seat can open the devices, the first one's read on its open descriptor and a fresh open are both refused while it does not hold the seat, both work again when root gives the seat back, and the seat is given up when each session ends. |
| `sessions` | `vinix-session manager` with stand-ins for the login screen and the desktop that speak its protocol. The login screen runs as `greeter`, as a login of its own, holding the seat; a request that is none, a wrong password, the `greeter` account and root are all refused a session. Sam logs in: a session with Sam's uid, a login number of its own, the seat, and Sam marked as the person at the machine. Sam asks to switch; Alex logs in and gets a different login and the seat. Meanwhile Sam's first process and one that left its process group and terminal session are both stopped, and neither is gone. Alex logs out; Sam logs in again and is continued in the same process and the same login, with the seat. When Sam's session ends, what it left running ends with it, nobody is marked as at the machine, and the login screen -- shown four times in all -- holds the seat again. |
| `audit` | After an account in a login session ran the sweep and gave a wrong password, and an administrator ran an action: the kernel's stream holds a refused `policy` record for the host name, restart, mount and the clock, and refused `network`, `signal`, `identity`, `seat` and `file` records, each with the account's uid, its login uid and a login session that is not the system's; the refused port is 80 and the signalled process is 1; three logins are recorded; root outside any login is recorded as allowed to set the host name; the authentication service's refusal and its run of an action are there as `service` records in the callers' logins. An account can read neither stream nor the log directory, and its attempt to report a record of its own is refused and leaves nothing. The collector writes every record once to a 0600 log in a 0700 directory, adds nothing on a second pass, and after 600 refusals between two passes writes exactly one gap whose numbers match the kernel's count; with a small size and two kept, more records leave exactly the log and two set-aside logs. |
| `keyring` | As an account in a login session, with the service running: no store, then one made (a 39-character recovery key; a second `init` refused), a secret set, read back, listed; locked, when reading is refused; a wrong password refused and the right one accepted; the password changed, the old one then refused, and a change with the wrong old password refused; a wrong recovery key refused, the right one opening the store, setting a new password and being replaced, after which the old recovery key is refused; the socket 0600 in a 0700 directory. On disk the store is the account's, 0600, one item, and holds neither the secret, the names it is stored under nor any of the passwords. Another account cannot read it; root is told it has no store. Then two logins through the session manager: the account with a store finds it open, with its secret, as soon as its session's first program asks; the account without finds none and none is made; and no keyring service is left when the sessions are over. |

## What this does not cover

No desktop and no login screen: the scenarios test the tools and the kernel
under them. The seat is tested with the framebuffer and the pointer QEMU
gives the machine and with reads; mappings, sound and a keyboard read that
is waiting when the seat moves are not. Timing is not tested beyond the
throttle's first wait.
