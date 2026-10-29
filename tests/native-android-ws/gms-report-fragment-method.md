# Exact GMS report-fragment methods, 2026-10-29

The validated [lifecycle audit](gms-lifecycle-class-audit.md) identifies the
original NPE receiver: the result of `findFragmentByTag`, not the Activity or
nullable saved-state Bundle. The deployed FragmentManager returns null for
every tag; FragmentTransaction.add also ignores its tag argument.

This follow-up disassembles only the actual `peb` ReportFragment and its `pdy`
injector. No application, callback, SDK, authentication or trust behavior was
patched. It consumes no guest logs or account data.

- `pdy.b(Activity)` checks the report-fragment tag and, if absent, creates `peb`,
  calls `beginTransaction().add(fragment, tag).commit()`, then
  `executePendingTransactions()`. This path also runs on SDK 29+, after its
  separate callback registration.
- `peb.onActivityCreated(Bundle)` first invokes
  `Fragment.onActivityCreated(Bundle)`, then dispatches `ON_CREATE`.
- Start, resume, pause, stop and destroy invoke matching Fragment superclass
  callbacks and lifecycle events. Start/resume additionally notify the optional
  listener. Below SDK 29, event dispatch requires a nonnull `getActivity()`.

The current Fragment base has no `onActivityCreated(Bundle)` method, so a tag
lookup fix alone leaves another required API missing. Generic transaction
application and lifecycle catch-up must satisfy these real calls.

All 15 retained DEX class-definition listings identify exactly one owner for
both classes: `classes4.dex`, SHA-256
`3bb1dcbb9fe4e2550f09b220757c8f1351983b896988a2e2d9b88ecbf927ea6b`.
The initial limited `classes.dex` candidate exited zero and emitted no class;
its receipt/output remain preserved and do not validate an extraction.

Let `S=/Users/alex/.local/state/vinix/android`.

- Selected files: `S/gms-report-fragment-method-2026-10-29-r1/selected-peb/peb.smali`
  and `selected-pdy/pdy.smali`.
- SHA-256: `peb` = `17d6c5d30b33f4b875a0b1f846e3937358590ba18ac7723bf1fd6d997b251e20`;
  `pdy` = `a38d2a4bd029b6858fc6cd505088a6a4e038fe7fdd8a7e4fe7a8ba01f8ff00ec`.
- Commands, class-definition listings, outputs and guards:
  `S/gms-report-fragment-method-controls-2026-10-29-r1`.
- Complete three-root streamed seal and fresh readback:
  `S/gms-report-fragment-evidence-2026-10-29-r1/sealed`, **672 entries**, manifest
  `5466262e277246c2f07a65420b46dcdbd159ec376d3405967fe68527a6368184`.

The seal binds selected evidence, all controls and the complete prior frozen
audit, including verified DEX/tools/baseline. Limited extraction used pinned
Java, a 256 MiB heap, two processors and baksmali `--classes` with code offsets.
Every guard passed with exit 0, complete cleanup and zero swaps, retaining
600 MiB RSS, 300 seconds, 512 MiB growth and 1 GiB reserve. Final seal/readback
used a 64 MiB growth limit. Peak extraction RSS was 104,235,008 bytes.
These static findings do not establish runtime success.
