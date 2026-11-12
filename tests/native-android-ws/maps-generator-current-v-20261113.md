# Native generator with current V

Parent 7b8ed3db9. Available V 0.5.2 6f888d6 failed to compile the native
generator because four direct split loops emitted calls to an undefined
string__split_next. Materializing their split results preserves the existing
parsing and ordering. The native producer also explicitly selects the current
compiler, serial compilation, nocache and the host C compiler when building
the generator, avoiding implicit compiler fallback.

Evidence is under `/Users/alex/.local/state/vinix/android/`:

- current-native-build-20261113-r1/r2 retain the compiler failures; r3 retains
  a local variable collision corrected before the successful r4 build.
- current-native-build-20261113-r4 passed generator compilation, full JNI C
  generation and AArch64 linking under the original guard: exit 0/0, complete
  cleanup, 15125 ms, peak sampled RSS 475299840 bytes, growth 63115264 bytes.
  Its native context guard is a separate change awaiting ARM validation.
- generator-module-checks-20261113-r1 compiled the existing module_test.v
  directly with current V and the same caps: exit 0/0, cleanup complete,
  4395 ms, RSS 460947456 bytes, growth 4636672 bytes. Executing the resulting
  binary passed all five existing tests, covering scalar declaration conflicts,
  readonly prototype metadata, whitespace, path resolution and literal names.
- The directory-wide test command, generator-split-checks-20261113-r1, failed
  while bootstrapping V's test tool with the same undefined split helper. It
  did not execute the suite. The focused binary above avoids that bootstrap;
  this is not a claim that the directory-wide command passed.

Source copies and hashes are retained in generator-split-inputs-20261113-r1.
No V checkout or compiler pin was changed.
