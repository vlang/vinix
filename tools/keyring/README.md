# The credential store

`vinix-keyring` keeps an account's secrets -- passwords for networks and
sites, tokens, keys -- in a file nothing can read without the account's
password. `keyringcore/core.v` is the format and the cryptography;
`keyring.v` is the service that holds the store open for a session and the
commands that ask it.

    vinix-keyring status
    vinix-keyring init                       # prints the recovery key, once
    vinix-keyring set SERVICE ACCOUNT        # the secret on standard input
    vinix-keyring get SERVICE ACCOUNT
    vinix-keyring list
    vinix-keyring delete SERVICE ACCOUNT
    vinix-keyring lock | unlock
    vinix-keyring change-password            # the old password, then the new
    vinix-keyring recover                    # the recovery key, then a new password

    tools/keyring/build aarch64|x86_64 ROOT  # installs ROOT/usr/bin/vinix-keyring

## How it is protected

Every secret is encrypted with one random 256-bit key, the store key, using
XChaCha20-Poly1305 with a random nonce. The service and account an item is
for are inside the encryption with the secret: the file says how many items
there are and nothing about what they are for.

The store key is never written down. The file holds it wrapped twice:

- under a key made from the **password** with scrypt (N = 2^15, r = 8,
  p = 1, a salt of its own -- not the login record's);
- under a key made from the **recovery key**, 160 random bits shown as
  eight groups of four characters when the store is made and never stored.

Either opens the store. Each line of the file is sealed together with what
it is -- a slot, the check, the item with this id -- so a line cannot be
moved to stand for another, and a wrapped key from another store does not
open this one.

| Event | What happens |
| --- | --- |
| Login | The session manager hands the password that was typed to `vinix-keyring daemon --unlock-stdin`, started inside the new session as the account, and waits until it is listening before the session's first program starts. The store is open by the time anything asks. |
| The password is changed | `change-password` re-wraps the store key. No secret is touched. It asks for the old password even when the store is open. |
| An administrator sets a new password | The store does not open with it: the administrator never knew the old one, and that is the point. `recover` opens it with the recovery key, sets the new password, and replaces the recovery key -- one that has been typed somewhere is used up. |
| Password and recovery key both lost | The secrets are gone. There is no other way in, by design. |
| Logout | The service is a process of the login and ends with it. The key was only ever in its memory. |

The service marks itself undumpable, so no other process of the account can
read the key out of it through `/proc`, asks for its memory not to be
swapped, answers only its own account, and makes wrong passwords wait.

## What it does not do

- **It does not keep the account's programs apart.** Any program of the
  account can ask for any secret, as with most desktop keyrings. Which
  application may read which item needs applications to have identities,
  which needs confinement by default.
- **No hardware.** The store key is not sealed to a TPM or a secure enclave;
  Vinix has no driver for either. A copy of the file and the password is
  the store, on any machine.
- **The login password and the store password are two records.** They are
  the same string because the same thing sets both, not because one is
  derived from the other: `vinix-auth passwd` changes the login,
  `vinix-keyring change-password` the store, and until something does both
  a login after only the first leaves the store locked (the service says so
  and stays up; `vinix-keyring unlock` with the old password opens it).
- **Nothing makes a store.** `init` is a command someone runs; a login does
  not create one, because the recovery key has to be shown to a person and
  there is no login screen to show it.
- **No certificates.** The system's trusted certificates are the package's
  bundle in `/etc/ssl/certs`; there is no tool to add, distrust or list
  them, and no per-account trust.
- **Root is outside the model.** Root can read the memory of the service.
  The file protects secrets at rest and from other accounts, not from the
  system's administrator while the store is open.
- **Not reviewed** by anyone but its author, and the scrypt and
  XChaCha20-Poly1305 it relies on are V's own implementations.

## Tests

`keyringcore/core_test.v`: the whole life of a store, that the file gives
nothing away, wrong keys of every kind, a password change that touches no
secret, recovery after a password the store never saw, tampering (lines
exchanged, a character changed, a slot from another store), and a strict
parser. The `keyring` scenario of
[`tests/accounts`](../../tests/accounts/README.md) runs the service and the
commands as an account on a booted kernel, checks what other accounts and
root see, and logs in through the session manager.
