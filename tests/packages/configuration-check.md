# Unambiguous persistent package configuration

The package configuration previously accepted a misspelled `permissons` field,
leaving all default permissions enabled. It also accepted `allowed:null` as an
unrestricted allowlist and let an escaped duplicate `offline` override the first
value. These are local administrator configuration errors, independent of the
signed catalog's schema admission.

`load_config` now uses strict typed decoding and the bounded shared field scanner
before semantic validation. It rejects unknown and duplicate keys, including
equivalent escaped spellings, and checks explicit JSON value kinds. Rejected
fully decoded configurations retire their owned fields; source text is released
after decoding. In-memory service overlays can still borrow configuration data.

Legacy omitted-field defaults remain supported: a configuration with only an
architecture, an omitted or partial policy, omitted format/launch account, and
version pins with omitted range bounds keep their original meaning. Empty
permissions, false booleans and zero reserves remain explicit. Both supported
architecture names, ordinary launch accounts, multiple repositories, unique
escaped field names and whitespace are covered.

Assertions refuse misspelled fields at every object level, nested/escaped
duplicates, null objects/arrays/scalars, invalid collection entries, coerced
booleans/numbers, fractional/negative/overflowing counters and oversized metadata.
Existing architecture, publisher key, permission and launch-account validation
still applies.

The service fixture installs and removes a signed application before changing
configuration. Refresh, reviewed install, rollback, collection, state, review,
offline export and publisher revocation must all refuse the malformed file.
Configuration bytes, active/previous generations, catalog, retained trust history,
cached objects and staged recovery data remain intact. Restoring the file permits
the original reviewed install, verification and rollback. The real CLI requires
exit 1 with useful configuration diagnostics and no panic for the same refusal
paths. It checks persistent bytes and cached object names before restoring and
verifying the installed generation.

The allocation fixture measures only the shared key/type scanner over 1,000
cycles of valid, unknown, duplicate and null-field inputs. It does not claim
allocation-free typed decoder failures or full service lifetimes. Sanitizer
checks cover valid/defaulted and rejected decoded configurations plus service
recovery; leak detection is disabled.

The initial allocation fixture retained the returned errors themselves and
reported 241,000 bytes over 1,000 cycles. The fixture now frees each owned error
and message, following the existing scanner tests. The failed measurement is
retained alongside the before/after configuration reproduction; production
configuration handling was unchanged during this correction.

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -nocache -no-skip-unused -gc none -manualfree \
  -o /tmp/package-configuration tools/packages/pkgcore/configuration_test.v
/tmp/package-configuration
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -nocache -no-skip-unused -gc none -manualfree \
  -d track_heap -o /tmp/package-configuration-memory tools/packages/pkgcore/configuration_test.v
/tmp/package-configuration-memory
```

This qualification covers host filesystem/service/CLI behavior and static target
builds. It does not add guest execution, public publisher enrollment, graphical
login or wider application/runtime acceptance.

Seven affected core runners and the signed CLI contracts passed. The scanner retained **zero tracked bytes** over 1,000 cycles. Configuration/default handling and service recovery passed clang ASan/UBSan with leak detection disabled. Both target services built as static ELF binaries with machine checks; no guest execution is claimed.

- [Host, CLI and build results](results/2026-10-14/configuration-host.txt).
- [Before/after reproduction](results/2026-10-14/configuration-baseline.txt), [sanitizers](results/2026-10-14/configuration-asan.txt).
- [Source/compiler/artifact ledger](results/2026-10-14/configuration-toolchain.json).
