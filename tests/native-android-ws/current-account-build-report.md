# Current account transport library, 2026-10-26

The retained-source AArch64 account transport build passed. This is build and
client-behavior evidence; it does not establish a successful Google login.

The source builder is `build-current-launch.v --account FRESH_OUTPUT`, introduced
in `519a8d26f`. The client interaction getter and Activity-bound redemption are
from `2f71f6ada`. The separate SQLite input extension is `b8846798b` and is not
part of this pre-store library snapshot.

The complete audit bundle is outside Git:

`/Users/alex/.local/state/vinix/android/current-account-build-2026-10-26-r3`

- `sha256.json`: `17b59e4cf22443d10f78f9dcd4b356b707ae63553d5c8edcc2e3ef6edfaa61c5`
- `lib/libvinix-android-account.so`: `4970a7b4533a01a4e596510d31a56711fb05e45a1c238754eb4b4156ebe3f89e`
- Source revision: `519a8d26f75bf203569a793ef477284ce4239509`.
- Compiler: `0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`,
  selected from the retained `current-launch-build-2026-10-26-r9/tools/v`.

`current-inputs.json` identifies every captured source, including the then-pending
authenticator operation/account-response exports. These additions are retained
in the bundle even though they were not yet committed at capture time. The
snapshot contains no account store module or SQLite dependency.

The builder preserves its own source/compiler closure and recompiles the
retained builder before capturing and compiling the account module. It checks
the frozen source membership, PIC header dependencies, compiler tools and link
inputs against retained or sealed inputs. The generated C compiled with
implicit-declaration and integer-conversion errors enabled; the shared link
used `-z defs`. ELF validation passed for little-endian AArch64 ELF64 shared
output without an interpreter. All 41 public functions declared by the captured
account client sources are defined text symbols, including the new interaction
getter, redemption entry point and authenticator UI authority check. This is
ABI completeness verification, not an assertion that no other symbols exist.

Client validation also passed the maintained `check-account-client.v` checker,
its generated actual-source program under no-GC AddressSanitizer, and the
accountclient unit suites. The checker bundle is retained at:

`/Users/alex/.local/state/vinix/android/account-client-redemption-check-r1-2026-10-26`

The checks cover ticket identity, a distinct redemption request ID, empty
acknowledgement keeping the original future pending, final result ordering,
errors, cancellation, timeouts, reentry and reference cleanup. An interaction
without an Activity fails explicitly because this backend cannot export the
originating service's Intent graph across processes.

Install the transport as
`/opt/vinix-android-aarch64/usr/lib/libvinix-android-account.so`, together with a
JNI library built after `2f71f6ada`; the older JNI r13 snapshot does not perform
client redemption. Deployment must use a separate additive overlay and preserve
the frozen headless staging baseline. Guest execution, Maps interaction and
Google credentials were not exercised by this build.
