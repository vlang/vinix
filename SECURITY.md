# Security

Vinix is pre-alpha. It has security mechanisms that are tested, and it has
large parts that nobody has reviewed; [`docs/security.md`](docs/security.md)
says which is which, and [`docs/accounts.md`](docs/accounts.md) says what an
account is and is not protected from. Do not put a Vinix machine anywhere
its being broken into would matter.

## Reporting a vulnerability

Please do not open a public issue with the details of something that can
be used against people running Vinix.

The intended channel is GitHub's private vulnerability reporting on
[vlang/vinix](https://github.com/vlang/vinix) ("Security", then "Report a
vulnerability"). **It was not switched on for the repository when this file
was written** (checked 11 October 2026). Until it is, open an issue that
says only that you have a security report and how you can be reached; a
maintainer will arrange somewhere private.

A report is most useful with:

- the revision (`git rev-parse HEAD`, or the contents of
  `/etc/vinix-release` on a release image) and the architecture;
- what an attacker needs to start from: an account, a confined application,
  a container, a file the victim opens, the local network;
- what they end up with;
- a way to reproduce it. A program for `tests/accounts`' guest or a fuzz
  input for `tests/fuzz` is ideal; a description is fine.

## What counts

Anything that crosses a boundary the documents say exists:

- an account doing what only root may, reading another account's files, or
  using the display or input devices without holding the seat;
- the authentication service running something that is not a listed action,
  running one for someone it should refuse, or accepting a wrong password;
- a confined application (pledge, unveil, a mandatory domain, seccomp)
  getting out of its confinement;
- a container reaching the host;
- a kernel crash, hang or memory corruption that an unprivileged process
  can cause;
- a boot that should have been refused under the verified-boot profile;
- a security record that can be forged, read or erased by someone who
  should not be able to.

Things that are known and written down are not news, but corrections to how
they are written down are welcome: the "what is not done" sections of the
documents above, the residual risks in
[`docs/x86-cpu-mitigations.md`](docs/x86-cpu-mitigations.md), and that the
desktop and everything it starts still run as root.

## What happens to a report

[`docs/security-process.md`](docs/security-process.md) describes how a
report is handled, how a fix reaches users, and how long things are meant
to take. In short: an acknowledgement, a fix developed in private when the
problem is serious, a release that carries it, and an advisory that says
what was wrong and credits whoever found it unless they would rather not be
named.
