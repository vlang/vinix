# Fuzzing

A mutation fuzzer for the parsers that read bytes someone else chose and
can be built on the host: the account files, the authentication service's
frames and action files, the security event stream, and two of the kernel's
own (`posix_acl`, `fdtstrings`). It is V, runs anywhere V and a C compiler
do, and needs nothing installed.

    tests/fuzz/run                                   # every target, 20000 inputs each
    tests/fuzz/run --list
    tests/fuzz/run --target passwd --iterations 2000000 --seed 7
    tests/fuzz/run --target passwd --seed 7 --only 4711   # one input again
    tests/fuzz/run --keep /tmp/findings              # write a finding's input to a file

Exit status 0 when nothing was found, 1 when something was.

## What a target is

A name, a few inputs that are valid or nearly so, and a function given
bytes (`targets.v`). The function must do one of two things with any bytes
at all: refuse them, or accept them and have what it accepted hold together
-- it returns an error when it does not. It must never crash, hang, or read
outside the buffer. Most of the value is in the second half: "accepted text
formats back to the same bytes", "a decoded frame encodes to the bytes it
came from", "a database that passes validation has one account per uid", "a
second pass over the same snapshot writes nothing".

| Target | Reads | What must hold of what is accepted |
| --- | --- | --- |
| `passwd`, `group`, `shadow` | `tools/accounts/accountcore` | Formats back to the same bytes; no separator inside a name; one account per uid after validation; a locked record never counts as a password. |
| `password-record` | one scrypt record | Is a scrypt record, within the cost bounds. Scrypt itself is never run. |
| `registration` | the desktop's old registration record | A name of 1 to 48 bytes, a record that is one, a login name that is valid. |
| `action` | an action file | An absolute program, a description, no line break in a fixed argument; a caller's `-rf` is accepted for no parameter that is not a choice. |
| `auth-frame` | a frame on the service's socket | Encodes to the bytes it was decoded from; at most 12 fields. |
| `event-snapshot` | `/proc/security_events` | Header and records agree; numbers count up; the collector writes each record once and nothing on a second pass. |
| `event-log` | the end of a collector's log, and its settings | No white space in a boot identity; settings within their bounds. |
| `posix-acl` | `kernel/posix_acl`: a list from userspace, or from an ext2 disk | A mode within a mode; access to nothing always allowed; survives conversion to disk and back. |
| `fdt-strings` | `kernel/fdtstrings`: a device tree string list | No empty string, no NUL inside one, no more characters out than bytes in. |

## How it works

Every input is made from three numbers: the run's seed, the target's name
and the iteration. The first inputs are the seeds as they are; the rest are
a seed with one to four blunt changes -- a bit flipped, a byte replaced, a
byte that text formats give meaning to put in, a stretch deleted or
repeated, the input cut short, the head of one seed joined to the tail of
another, digits turned to nines. Nothing is random in the sense of not
being repeatable: a finding is reported as the command that makes that one
input again.

A target runs in a process of its own, 256 inputs at a time. When that
process dies or sits for 20 seconds, the fuzzer runs those 256 again one
process each and reports the one that did it. `fuzzcore/fuzz_test.v` checks
this with targets that complain, crash and hang on purpose.

This is not coverage-guided: it does not see which inputs reach new code,
so it will not find what needs a long chain of coincidences. It finds what
blunt changes to nearly-valid input find, which in parsers written without
a fuzzer is usually something.

## Adding a target

1. Write `fn fuzz_<name>(data []u8) !` in `targets.v`: parse, and check
   what must hold of an accepted input. Do not call anything slow (scrypt)
   or anything that touches files.
2. Add a `fuzzcore.Target` to `targets` with at least one valid input.
3. If the parser is in a directory the launcher does not already look in,
   add it to `-path` in `run`.
4. Run it for a few million inputs before trusting the parser, and note the
   run in the table below.

A parser that cannot be built on the host -- the ELF loader, ext2, the
initramfs reader, the system call layer -- is not reachable from here. See
"What is not fuzzed".

## Record

| Date | Revision | Run | Result |
| --- | --- | --- | --- |
| 11 October 2026 | the commit that added this page | every target, 200 000 inputs, seed 1, macOS on an M1 | One finding on the first run, fixed in the same commit: `parse_group` accepted any second field and wrote it back as `x`, so a group file with a password in it was read as valid and silently changed. Clean afterwards. |

## What is not fuzzed

- **The kernel's parsers of hostile input that only exist in a kernel**:
  ELF images, ext2 metadata, the initramfs tar, FAT, the device tree as a
  whole, ACPI tables (uACPI), USB and network packets (lwIP), virtio
  devices. None of these has a host build or a harness.
- **The system call interface.** There is no syscall fuzzer; `tests/accounts`
  has a sweep of privileged calls, which checks refusals, not robustness.
- **The desktop**: the application protocol (`decode_app_tree`), image and
  font decoders, the calendar and archive readers.
- **Anything third-party**: Mesa, Wine, browsers, the packages.

These are listed in [`docs/security-process.md`](../../docs/security-process.md#review)
as review work that is still to do.
