# Complete stored package declarations

The baseline admitted missing `firmware`, `proprietary` and SDK fields and null
permissions in stored generations on both architecture settings. The outer state
envelope was required, but nested manifests still acquired template defaults.
This could turn damaged declarations into a valid-looking installed record.

State admission now uses the complete signed-manifest field and value-kind rules
for nested packages, dependencies and payloads, and requires each installed
provenance field. False flags, empty strings/lists, payload sizes and SDK values
remain explicit. Unknown/duplicate/escaped duplicate fields, malformed Unicode,
null values, coercion and invalid counters refuse admission. `window_protocol`
remains optional at zero, matching format-1 writer compatibility. Canonical
writer bytes, package format and the existing state/closure limits are unchanged.

The [core assertions](../../tools/packages/pkgcore/state_schema_test.v) exercise
omission of every required field at each nesting level, wrong value kinds,
ambiguity, both architecture settings, canonical reproduction and maximum u64
generation/sequence values. Real signed transactions create current/previous
generations. Failure probes compare the complete store tree, configuration and
payload/cache hashes before and after status, verify, plan, review, reviewed
remove, launch admission, rollback and collection as applicable. Restoring the
original records permits reviewed removal, rollback and collection.

The V [guest controller](state-schema-check.v) builds fresh target service and
guest-init executables around retained kernels. The scenario signs and installs
two package versions, damages active and previous declarations, and requires
the real CLI to return exit 1 with a schema diagnostic and no panic. Activation,
generation contents, catalog/history, partial downloads, configuration and
abandoned work must remain unchanged. Restoring original records permits the
original reviewed removal, rollback, collection and cache-only reinstall.
Each receipt retains hashes for the kernel, guest init, package service, serial
log and QMP log; explicit guest shutdown and the required markers are checked.

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' -d track_heap \
  -o /tmp/stored-state tools/packages/pkgcore/state_schema_test.v
/tmp/stored-state
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -nocache \
  -path '@vlib|@vmodules|tests/hardware-platform' \
  -o /tmp/stored-state-guest tests/packages/state-schema-check.v
V=/path/to/v VFLAGS=-nocache V_MACOS_V3_NO_FALLBACK=1 VINIX_HWTEST_TCG=1 \
  /tmp/stored-state-guest --arch aarch64 --kernel /path/to/kernel \
  --state-dir /tmp/stored-state-arm --scenario packages-state-schema --timeout 240
```

Use matching x86_64 inputs for the other target. Heap tracking measures only
owned schema key/type/required-field scanning across 1,000 cycles, not complete
decoding or service lifetime. Sanitizers disable leak detection. These checks
cover local metadata admission and recovery from restored trusted records; an
unrestricted administrator can deliberately rewrite valid records. Initramfs
guests do not qualify persistent-device power cuts. Publisher enrollment, catalog
migration and graphical/runtime acceptance remain separate roadmap gates.

Ten native core runners, the complete signed CLI lifecycle and all three
ASan/UBSan runners passed. The schema scanner retained zero tracked bytes
over 1,000 cycles. Fresh TCG guests passed with explicit QMP guest shutdown: AArch64
in 39.621 seconds and x86_64 in 42.077 seconds.
The first guest assertion expected a narrower error than the service correctly
returned for the string-valued SDK; both targets were rebuilt for final runs.
Initial native/guest fixture calibration is retained separately. The x86_64
boot used an explicitly selected, hash-validated retained Limine cache.


The initial x86_64 guest timed out after startup; its cause was not established.
A repeat with the exact passing kernel/init/service hashes passed in 31.483
seconds. Overlong retry directory names also hit the host Unix socket path limit
before boot; final runs use short names. Failed-attempt logs/inputs remain
retained; disposable media was removed to recover shared disk space. These runs
qualify the exercised metadata paths, not general kernel scheduling reliability.

- [Host/CLI and scanner results](results/2026-10-14/state-schema-host.txt), [sanitizers](results/2026-10-14/state-schema-asan.txt).
- [Baseline and initial calibration](results/2026-10-14/state-schema-baseline.txt).
- [AArch64 receipt](results/2026-10-14/state-schema-aarch64.json), [serial](results/2026-10-14/state-schema-aarch64.serial.txt), [shutdown](results/2026-10-14/state-schema-aarch64.qmp.txt).
- [x86_64 receipt](results/2026-10-14/state-schema-x86_64.json), [serial](results/2026-10-14/state-schema-x86_64.serial.txt), [shutdown](results/2026-10-14/state-schema-x86_64.qmp.txt).
- [Source/compiler/artifact ledger](results/2026-10-14/state-schema-toolchain.json).
