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
| `vinix-session` | root | Turns a root process into a person's: `run USER COMMAND`, a login prompt on the console, and the session manager. |
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
- **`greeter`** is the account a login screen runs as. It can draw and read
  the keyboard while it holds the seat, and nothing else: it cannot check a
  password itself.
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
| `verify` | Their own account; root for any account | Whether the password is right, or how long to wait. |
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
| `account` | A known ordinary account, identified by its kernel peer credentials, without a password. Only explicitly public bounded actions should use this rule. |

Root is always allowed and never asked. Nobody is ever allowed with someone
else's password, and accounts that are not people's are allowed nothing.

The shipped `account` action is `packages-launch`: it starts only the installed
package service as the caller's own account, with all supplementary groups and
capabilities removed. It accepts no command-line parameters or selected account,
and repeats package trust, policy and payload admission as that ordinary user.
Its private socket accepts exactly the caller's three existing standard streams;
both the application session and its completion supervisor drop root before work.
See [launch qualification](../tests/packages/isolated-launch-check.md).

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

### Logins the kernel knows

Before a session stops being root it labels itself as a login: it writes
the account's uid to `/proc/self/loginuid`, as on Linux, and the kernel gives
the login a number (`/proc/self/sessionid`). Both are inherited by everything
the session starts and can never be set again -- not by the session, which
is no longer root, and not by root either: a second write is refused. A
process of the system has no login (uid 4294967295, session 0). Only a
process itself, as root with `CAP_AUDIT_CONTROL` outside any confinement,
can make the label; a container's runtime that writes there is accepted and
ignored, since a login is something the host has.

### The seat

The display, the keyboard, the pointer and sound belong to whoever is at
the machine. The kernel calls that the seat, and one login session holds it
at a time (`/proc/sys/kernel/seat_session`, written by root with
`CAP_SYS_ADMIN`; 0 is nobody). The devices of the seat are `/dev/fb*`,
`/dev/dri/*`, `/dev/pointer`, `/dev/mouse`, `/dev/console`, `/dev/tty<N>`,
`/dev/dsp*`, `/dev/mixer*`, `/dev/input/*`, `/dev/video*`, `/dev/snd/*`, the
display's hot-plug device and the panel backlight.

- **Opening** one is allowed to the session that holds the seat, and to
  root outside any login (the system: init, the session manager, a recovery
  shell). Not to a session in the background, and not to a process that has
  neither a login nor root -- a service that dropped its privileges.
- **Using** a descriptor that is already open is checked again every time:
  read, write, ioctl, a new mapping. A descriptor a session opened works
  while that session holds the seat, stops when another does, and works
  again when the seat comes back; the descriptor is not closed and the
  session is not told. A read that was waiting when the seat moved returns
  an error instead of what was typed for someone else.
- **Inheriting** is not a way around it. The console init opened is handed
  down to everything; for a login session those descriptors work only while
  it holds the seat.

`vinix-session run --seat USER COMMAND` and the console login give the seat
to the session they start and take it back when it ends.

What this does not reach: memory of the framebuffer that a session mapped
while it held the seat stays mapped. That is why the session manager stops
a session it moves into the background.

### The session manager

`vinix-session manager` is what stands between the machine being on and a
person using it:

1. It starts the login screen as the `greeter` account, at the seat, with a
   socket to the manager as descriptor 3.
2. The login screen sends a name and a password. The manager asks the
   authentication service -- as root, which may check anyone's -- and answers
   yes, no, or wait. The login screen is believed about what was typed and
   about nothing else: it cannot name who is logged in.
3. On a yes for a person's account the login screen is ended, with
   everything it started, and that person's session starts: a login the
   kernel knows, the seat, `/run/vinix/session/active`, and a socket to the
   manager as descriptor 3 of its first program.
4. When that program exits, or asks to log out, every process of the login
   is ended -- asked, then killed -- including what left the session's
   process group or terminal, because the kernel's login number is what
   they are found by. Then the login screen again.
5. When it asks to switch, the session is not ended. The seat is taken from
   it and every one of its processes is stopped; the login screen shows.
   When its owner logs in again the seat is given back and the processes are
   continued where they were. Someone else who logs in meanwhile gets a
   session of their own.

A session in the background is therefore stopped, not running: a download
does not go on while someone else is at the machine. That is the price of
not being able to take a mapped display away from a running process.

A new session's credential store is opened with the password that was
typed: the manager hands it to
[`vinix-keyring`](../tools/keyring/README.md), started inside the session as
the account, waits until that service is listening, and then wipes its own
copy. The password goes nowhere else.

The login screen may also ask for the machine to be turned off or
restarted. The requests are frames of the authentication service's format;
`sessioncore/manager.v` lists them.

The programs the manager starts are arguments (`--greeter`, `--desktop`), by
default `vinix-desktop --greeter` and `vinix-desktop`. The desktop can now run
as an ordinary account: its native qualification covers private account
runtime directories, broker and framebuffer access, and an installed
application across reboot. Normal desktop init now starts
`vinix-session graphical --desktop /usr/bin/vinix-desktop` (or its selected
GPU build). This root supervisor imports a valid existing registration, or
runs the exclusive registration screen when there is no person account,
then starts the authentication service and manager. A private root-owned
lock prevents two graphical supervisors from owning the seat.

The greeter runs as its own account and exposes login controls.
It sends bounded requests over inherited descriptor 3 after checking the root
peer and socket type; the descriptor is close-on-exec. Passwords are masked
and explicitly erased after submission, refusal or cancellation. The ordinary
desktop's Start menu offers **Switch user** and **Log out** through the same
manager channel. Power requests also go through the manager.

The [graphical login check](../tests/graphical-login/check.md) drives the real
registration screen, greeter and ordinary desktop on both architectures. It
checks wrong-password refusal, stopped sessions on switch, reauthentication
resuming the same kernel session, complete logout reaping, and a fresh login
with preserved home data. The fixture directly starts the production manager;
normal init wiring is built separately. It does not establish a complete
normal-init, installed-system login qualification.

### Becoming the account

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

Five things it found were open and are closed:

- A hard link to a file the caller could neither read nor write
  (`/etc/shadow` under a name in `/tmp`). The kernel now applies Linux's
  `protected_hardlinks` rule: a file's owner, `CAP_FOWNER`, or someone who
  could read and write it anyway.
- Binding a TCP or UDP port below 1024. Now `CAP_NET_BIND_SERVICE`.
- `SCHED_FIFO`. The check against `RLIMIT_RTPRIO` was there; the limit's
  default was "unlimited". It is now 0, as on Linux, and root is not asked.
- `/dev` itself was mode 0644: without search permission no account could
  reach even `/dev/null`. It is 0755.
- Which uncovered that disks and their partitions were mode 0644 -- any
  account could have read every file on them, whatever the files' own modes
  -- and the console and serial lines too. They are 0600. The sweep now runs
  with a disk attached, which root must be able to open and the account must
  not, and the disk must come out of the run unchanged.

## What is not done

- **Complete installed-system graphical login acceptance remains open.**
  The default graphical manager, ordinary desktop and login/switch/logout
  path are implemented, with bounded paired native fixtures. Broader normal
  init, installed-system, device and recovery workflows still need combined
  qualification. There is no dedicated lock-screen flow.
- **A session in the background is stopped**, for the reason given above.
- **The seat is all or nothing.** Every program of the session at the
  machine can open the display and the pointer. Keeping an application
  from capturing the screen or the keyboard is confinement's job, not the
  seat's.
- **No `sudo`, `su`, `login` or PAM.** Programs that expect them find
  nothing; ports that need to elevate have to be taught the service.
- **The login password and the credential store's are changed separately**
  ([`tools/keyring`](../tools/keyring/README.md#what-it-does-not-do)).
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
| `seat` | pass | pass |
| `sessions` | pass | pass |
| `audit` | pass | pass |
| `keyring` | pass | pass |

and the host tests of `accountcore`, `authproto` and `authcore`. Nothing was
run on a physical machine, and nothing was run with the desktop.

On 12 October the ordinary/isolated account profiles and signed package handoff
were also exercised in QEMU on both targets. The package scenario checks private
data ownership, literal document arguments, missing launch identity, publisher
revocation and uninstall. Its sandbox substitute observes the exec boundary;
it does not extend the GUI/runtime or pledge/unveil qualification above.
