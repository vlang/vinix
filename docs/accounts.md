# Accounts, sessions and privilege

Vinix has user accounts in the Unix sense: `/etc/passwd`, `/etc/group` and
`/etc/shadow`, numeric ids the kernel checks on every file and process
operation, and sessions that run as the person who logged in and not as
root. This page says what exists, how the pieces fit, and what is not done.
The record of what was run is at the end.

The code is in [`tools/accounts`](../tools/accounts/README.md); the tests
that boot a kernel are in [`tests/accounts`](../tests/accounts/README.md).

## The pieces

| Piece | Runs as | What it is for |
| --- | --- | --- |
| `accountcore` (module) | — | Reads, checks and writes the three files; password records; the wait after wrong passwords. |
| `vinix-account` | root | The administrator's tool: accounts every system has, add, remove, lock, password, administrator on/off. No authentication of its own. |
| `vinix-authd` | root | The authentication service: the one reader of `/etc/shadow` and the one way from an account to something done as root. |
| `vinix-auth` | anyone | Asks the service from a terminal or a script. |
| `vinix-session` | root | Turns a root process into a person's: `run USER COMMAND`, and a login prompt on the console. |
| `vinix-system` | root | The privileged halves of what a desktop does for the person at it: power off, restart, sleep, host name. |

There are no set-user-id programs. The kernel does not honour the bit, and
nothing here needs it: a process that is not root gets something done as
root by asking `vinix-authd` over a socket, and in no other way.

## Accounts

- **Root** exists and has no password (`*` in `/etc/shadow`): nobody logs
  in as root. The recovery shell init falls back to is root's, on the
  console, and is the way in when no account works.
- **People** have uids from 1000, a primary group of their own, membership
  of `users`, and a home in `/home/<name>` that is mode 0700.
- **Administrators** are the people in the group `wheel`. Being one changes
  nothing about what their processes may do; it changes what the
  authentication service will do for them when they give their own
  password. The last administrator who can still log in cannot be removed,
  locked or demoted.
- **`greeter`** is the account a login screen runs as. It can ask the
  service to check anyone's password and can do nothing else.
- **`nobody`** (65534) is what programs that should be no one run as.

`vinix-account init` adds whatever of this a system lacks and is safe to run
at every boot. On a system that was registered with the desktop before there
were accounts, it turns the registration record (`/root/.vinix-user`) into
the first administrator: same name, same password -- the scrypt record is
converted, the password is never known -- and the same files. Homes such a
system kept in `/root/home` are mounted at `/home`, because nobody but root
can pass through `/root`.

### The files

Parsing is strict. A line with the wrong number of fields, a uid written
`00` or `+0` or larger than 32 bits, a password in `/etc/passwd`, a control
character, a file that does not end in a line break: each fails the whole
file. The database is then checked as one thing -- unique names and ids,
every primary group present -- and refused if anything is off, because a
file that fails was not written by these tools. A file that is a link, is
not root's, or that anyone but root can write is not read at all, and
`/etc/shadow` is not read if anyone else can read it.

Each change replaces the files whole (written beside, synced, renamed) under
a lock, in an order that is safe at every step: the password file first, so
an account can exist without a password record (nobody can log in to it) but
not with someone else's.

### Passwords

A password is stored as scrypt over it and a 16-byte random salt, in the
format passlib calls `scrypt`:

    $scrypt$ln=15,r=8,p=1$<salt>$<key>

The cost is in the record, so it can be changed (`/etc/vinix/auth.conf`,
`scrypt_ln` and `scrypt_p`) without locking anyone out: an old record is
checked at its own cost and, if that was less, replaced at the next
successful login. The file is there to ask for more work; it accepts less,
down to N = 2^10, for the tests and for a machine on which the default would
make a login take minutes.
The default, N = 2^15 with p = 1, is 32 MiB and about half a second per
guess on an M1. It is less work than the parameter sets OWASP's password
storage guidance lists (p = 3 at that N): V's scrypt is several times slower
than an optimised one, and the guidance's figure would make every login and
unlock wait three times as long.

A new password must be 8 to 256 bytes, not one character repeated and not
the account's name. That is a floor, not a strength estimate.

Wrong passwords make the next tries for that account wait: nothing after the
first three, then 2, 4, 8 ... seconds up to five minutes, forgotten after an
hour without a failure. The account is never locked for good by guessing --
that would let anyone at the keyboard lock its owner out. A name that does
not exist costs a guesser the same time as one that does.

## The authentication service

`vinix-authd` listens on `/run/vinix/auth.sock`, which anyone may connect
to. The kernel says who is on the other end (`SO_PEERCRED`); the request
cannot. One connection is one request and one reply, handled in a process of
its own that exits afterwards. A request has ten seconds to arrive and 150
to finish; at most 16 are in progress at once and four from one user, and
what is over that is refused, not queued.

| Request | Who may | Answer |
| --- | --- | --- |
| `info` | anyone | Their own name, whether they are an administrator, whether they are the person at the machine. |
| `verify` | Their own account; root and `greeter` for any account | Whether the password is right, or how long to wait. |
| `change password` | Their own account, with the old password; root without | Done, or why the new password will not do. |
| `describe` | anyone | What an action is, and whether this caller could run it and would need a password. |
| `run` | See below | The action's exit status and the first 32 KiB of what it printed. |

### Actions

An action is a file in `/usr/share/vinix/actions`, which only root can
write. It names one program, its fixed arguments, what the caller may add,
and who may ask:

    description = Change the name of this computer
    auth = admin
    exec = /usr/sbin/vinix-system
    arg = hostname
    param = hostname

| `auth` | Who is allowed |
| --- | --- |
| `admin` | An administrator, with their own password. |
| `session` | The person at the machine, without a password; anyone else as `admin`. |
| `self` | Any person, with their own password. |

Root is always allowed and never asked. Nobody is ever allowed with someone
else's password, and accounts that are not people's are allowed nothing.

A caller's argument must be what its `param` line says -- an account `name`,
a `hostname`, a `number`, one line of printable `text` that does not start
with a hyphen, or one of a `choice:` list -- and the count must match. A
password for the program (a new account's, say) goes to its standard input
through `input = secret`, never on a command line. The program is started
with a fixed environment, no descriptors but its own three, in a session of
its own; it must be a regular file that root owns and nobody else can write,
as must the action file and its directory. An action file with a line that
is not understood is not an action.

The actions that ship:

| Action | `auth` | Does |
| --- | --- | --- |
| `power-off`, `restart`, `suspend` | `session` | `vinix-system power ...` |
| `hostname-set` | `admin` | Sets the host name and `/etc/hostname`. |
| `account-add`, `account-remove`, `account-password`, `account-admin`, `account-lock`, `account-rename` | `admin` | `vinix-account ...` |

"The person at the machine" is the uid in `/run/vinix/session/active`,
written by whatever started the session and believed only if it is root's
file.

Every decision is a line in `/var/log/vinix/auth.log` (mode 0600): the
time, the caller's pid and uid, what was asked, and what came of it. No
password is ever written there.

## Sessions

`vinix-session run USER COMMAND` and the console login both end in the same
step (`sessioncore.become`): drop every capability from the bounding set,
clear the ambient set, set the account's supplementary groups, then all
three group ids, then all three user ids, clear what capability sets remain,
and set `no_new_privs`. The result is then read back -- ids, groups,
capability sets, and that `setresuid(0, 0, 0)` fails -- and the process
exits rather than go on if anything is not as it should be. A session is
never root's: asking for one is an error.

The session gets `HOME`, `USER`, `LOGNAME`, `SHELL` and
`XDG_RUNTIME_DIR=/run/user/<uid>` (a directory of its own, mode 0700), the
rest of the environment as init fixed it minus anything that named root's
places, and starts in its home.

`vinix-session console` asks for a name and a password on the terminal,
checks them through the service like everything else, runs the account's
shell as a session until it exits, and asks again.

## What the kernel refuses an ordinary account

The kernel already had the credentials, the capability sets and the
permission checks; a system where everything ran as root had simply never
used them. The sweep in `tests/accounts` runs some sixty attempts as an
ordinary account after `become` and requires every one to be refused:
mounting and unmounting, the host and domain name, the clock, device nodes,
`chroot`, taking uid 0 or new groups back, giving files away, changing the
account files or their modes, signalling or reading the memory, environment
or mappings of someone else's process, writing `/sys/power/state` or
`/proc/sys`, opening any disk, raising a hard resource limit, `ptrace`,
turning the machine off, low ports, raw sockets, negative nice and real-time
scheduling. The same calls are first made as root, where the harmless ones
must succeed.

Three things it found were open and are closed:

- A hard link to a file the caller could neither read nor write
  (`/etc/shadow` under a name in `/tmp`). The kernel now applies Linux's
  `protected_hardlinks` rule: a file's owner, `CAP_FOWNER`, or someone who
  could read and write it anyway.
- Binding a TCP or UDP port below 1024. Now `CAP_NET_BIND_SERVICE`.
- `SCHED_FIFO`. The check against `RLIMIT_RTPRIO` was there; the limit's
  default was "unlimited". It is now 0, as on Linux, and root is not asked.

## What is not done

- **The desktop is still root's.** Init starts the compositor as root, and
  the compositor starts every application as root. The tools above are what
  a session manager and a login screen are built from, and neither exists
  yet; nor does a lock screen or switching between users. Until then the
  accounts protect what runs through `vinix-session`, and nothing else.
- **Device nodes are mode 0666.** `/dev/fb0`, `/dev/pointer`, `/dev/dsp` and
  the terminals can be opened by any account. Who may use the display and
  the input devices has to follow who is at the machine, which the kernel
  does not know yet.
- **No `sudo`, `su`, `login` or PAM.** Programs that expect them find
  nothing; ports that need to elevate have to be taught the service.
- **No per-user limits** beyond what a session inherits, no login records
  (`utmp`/`wtmp`), no password ageing (the fields are kept, not acted on),
  no password recovery other than an administrator or the recovery shell
  setting a new one.
- **The service trusts the files it reads to be root's.** That is checked
  (owner, mode, not a link) but rests on the root file system being intact;
  see [the verified root](security.md#authenticated-uefi-images).
- **Raw sockets and `ptrace` do not exist** in the kernel, so the sweep's
  refusals for them are "no such call", not a permission decision.

## Record

11 October 2026, on an M1 MacBook Air under QEMU 11.1.1, kernels built from
the commit that added this page:

| Test | AArch64 (HVF) | x86-64 (TCG) |
| --- | --- | --- |
| `accounts` | pass | pass |
| `elevation` | pass | pass |
| `unprivileged` | pass | pass |

and the host tests of `accountcore`, `authproto` and `authcore`. Nothing was
run on a physical machine, and nothing was run with the desktop.
