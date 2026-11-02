# Unmanaged ownership/profile queries fixture host qualification

Host qualification passed on 2026-11-02; ARM execution is pending. This signed,
one-class fixture exercises the real Context service lookups and the bounded
GMS-like `getDeviceOwner` → `isManagedProfile` → `getApplicationRestrictions`
query sequence for the current unmanaged, single-user guest.

The build started at revision `2f68a5daadbafd4caf64b61ba232f55923b11688`.
Exact source copies and hashes are retained in the external bundle:

| Source | SHA-256 |
| --- | --- |
| `unmanagedqueriesfixture/main.v` | `589155e4bbb58817a1a7573138263741fe5608af9f44b853396b205c10a96f4c` |
| `unmanagedqueriesfixture/sources.v` | `38069d9694536d4b3eb75ab189df57555789621aec6ce9b1ff72b39112ff4a6a` |

Complete evidence is outside Git:

- `/Users/alex/.local/state/vinix/android/unmanaged-queries-fixture-2026-11-02-r1/`
- `/Users/alex/.local/state/vinix/android/unmanaged-queries-fixture-controls-2026-11-02-r1/`

| Artifact | SHA-256 |
| --- | --- |
| Signed `probe.apk` | `dcea26199cfb0bfc2b0b44126b45923c717893b3670f1788b60c4038d4213400` |
| `build.json` | `81511dac6f9ba5d99ce5ca284669a9dbf4cd17601403ee1dc6b424db471ab7b2` |
| Production and signed-extracted `classes.dex` | `108092cc14b59ea0b8b6824356cb4147d9d89bd0d31fc1ed21b89fb6e476411b` |

The Activity and its application context each run three ownership/profile/
restriction cycles. Device owner package and retained owner-component queries
must return null. `isManagedProfile`, `isDeviceManaged` and `isDeviceOwnerApp`
must return false. String/class DevicePolicyManager lookups must share the
existing cached instance; UserManager lookups require the exact SDK class and
matching behavior, without a caching assumption.

Application restriction snapshots must be nonnull and empty. The actual GMS
key `enableWorkAccountAdmin` must be absent, with implicit/explicit false
defaults and an explicit true-default positive control. Reads must leave the
Bundle empty. A caller-owned true mutation must survive later queries while
all three query results remain distinct and later snapshots remain empty.
Three fresh profile-list results must contain only the current Android user;
clearing one returned list must preserve other live snapshots, later query
results and the false managed-profile state. Only returned snapshots are
mutated; no device/user policy state or administrator is created.

All assertions and UI setup precede the sole success marker:

```text
UNMANAGED-QUERIES-PASS owner-null profile-false service-lookups restrictions-defaults snapshots repeated-queries
```

The failure marker is `UNMANAGED-QUERIES-FAIL`; package/Activity are
`org.vinix.bootstrap` and `org.vinix.bootstrap.Main`. The fixture requires the
new two-method Java SDK batch. It does not exercise managed enrollment,
administrator privileges, shared-preference overrides, accounts, network or
Google authentication. Historical fixture sources and APKs remain unchanged.

Host checks passed: exact two-source/one-class and tool-directory membership,
error-free API-28 Smali assembly, two canonical DEX roundtrips, v3 signature,
package/activity badging, duplicate/single-DEX archive checks, signed DEX
extraction equality and final input readbacks. Independent source review passed.
Compilation took 1.614 seconds with a 348,340,224-byte reported peak RSS;
production took 5.762 seconds with a 92,585,984-byte reported peak RSS. Both
exited zero with complete cleanup and zero swaps. Original guards remain
600 MiB aggregate RSS, 300 seconds, 512 MiB disk growth, 1 GiB reserve,
4 MiB output and `ulimit -f 16777216`.
