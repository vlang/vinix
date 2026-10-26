# Launch-option compact navigation and draft lifetime

Software's Launch options form provides Arguments, Add file, Files, Folder and
Run pages in windows down to 180×220, including 320×240. A failure adds a Failure
page. Back and Status remain visible; the Run page includes Run in Terminal and
Read draft. Prev/Next buttons and unfocused Left/Right or Page Up/Page Down keys
change pages. Explicit page navigation blurs editing. Smaller windows retain the
draft and Back access. The full form keeps its existing controls.
Resize does not change arguments, explicit file grants,
working folder, field focus, selection or file-page position. Escape leaves a
focused field and clears its selection; from an idle form it returns to the
catalog and discards the draft.
Pasted Escape, Enter, editing controls, invalid UTF-8 and oversized replacements
are rejected without changing the field, focus or navigation.

Running batch workers keep their runtime leases and existing close guard.
Back, Escape, repeated launch, file/editor, catalog and external launch actions
cannot change or interrupt them. The compact view explains how to return after
the app exits. Failure diagnostics and the exact draft remain available after
exit for correction, retry or transfer to Terminal. Launch still uses installed
name/kind/permissions, including an explicitly empty installed permission set.
Service arguments, quoting, authorization, file access and protocol are unchanged.

Compact Files shows one grant at a time, with previous/next file controls and
selection before removal. Its scroll position is shared with the full form,
whose existing five-row paging stride remains unchanged. All 256 permitted
grants remain reachable; Read draft retains complete long-path access.

The maintained [fixture](software_launch_navigation_fixture.v) holds real child
workers behind stdin barriers. It checks compact/full controls, resize stability,
file paging/removal, keyboard versus paste behavior, invalid/unsubmitted input,
protected worker success/failure, exact Unicode/space/metacharacter arguments,
empty quoted arguments, distinct file grants and installed working folder,
failure navigation, retry and exact Terminal vector transfer. Catalog query,
filter and selection are preserved when the draft is discarded. Installed
permission checks also cover a pending candidate that advertises extra access.

The `launch-navigation-memory` mode measures 1,000 cycles after warmup under
`-gc none -manualfree -d track_heap`: a 256-file draft, count-bound refusal,
full/compact rendering, file removal/readdition, rejected paste, Escape blur,
failure presentation, Terminal vector transfer and retirement, and idle Back.
The live status is cleared before sampling. The Software-only Terminal stub
checks command ownership and transfer; these checks do not measure real PTY,
whole-service or worker-process allocation freedom.

These are host headless UI checks. Existing [launch-option qualification](launch-options-check.md)
and [terminal qualification](terminal-check.md) retain their scope. Ordinary
graphical sessions, release publisher/catalog migration and broader runtime
acceptance remain separate release gates.


## Recorded results, 2026-10-15

All 28 focused compile/run checks passed: the complete Software functional
fixture and twenty-three allocation modes, plus ASan/UBSan functional and launch
navigation allocation checks. The maintained Software-only distribution driver
passed independently with all twenty-three allocation modes. Navigation retained
zero tracked bytes over 1,000 256-file draft/full/compact/paging/paste/blur/
failure/Terminal-transfer/retirement cycles, including idle Back, after clearing
the live status before sampling. Sanitizer leak detection was disabled. These
checks do not measure real PTY, whole-service or worker-process memory freedom.

The initial allocation run retained 24,862,000 bytes over 1,000 cycles in the
Software-only Terminal stub, which grew its command array without releasing
replaced buffers. The stub now reserves the complete vector and uses the same
array ownership flag as production Terminal, which already did so. The failed
measurement is retained separately; final runs retained zero tracked bytes.

Both full desktop architecture typechecks passed. Compiler, Software/protocol/UI
inputs, staged sources, binaries and logs are pinned. Service, command vectors,
installed permissions, ordinary-account authorization and protocol are unchanged.
No new guest graphical or broader release acceptance is claimed.

- [focused checks](results/2026-10-15/software-launch-navigation-host.json)
- [summary](results/2026-10-15/software-launch-navigation-host.txt)
- [Software and maintained driver](results/2026-10-15/software-launch-navigation-ui.txt)
- [allocation modes](results/2026-10-15/software-launch-navigation-memory.txt)
- [sanitizers](results/2026-10-15/software-launch-navigation-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-launch-navigation-desktop.txt)
- [initial attempts](results/2026-10-15/software-launch-navigation-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-launch-navigation-toolchain.json)

## Recorded compact-form results, 2026-10-26

The new `launch-compact` mode passed in normal, production and ASan/UBSan host
headless builds. The complete historical Software fixture also passed in its
normal build. Focused checks use explicit refusals in production, where V removes
assertions. They cover usable controls at 320×240 and 180×220, non-overlapping
page controls, all 256 grants, both resize directions with focused drafts and
selection, shared scroll and the existing full-form five-row stride, installed
permission refusals, actual Run and Terminal dispatch, failure/retry and a real
child held behind a stdin barrier while worker guards refuse mutation and close.
Terminal transfer uses the maintained stub; no real PTY or new allocation result
is claimed. Sanitizer leak detection was disabled.

The maintained `software-compact-launch-check.v` copies and pins its project/UI
inputs and binds its embedded source and sourcecommand closure to captured bytes.
Each subprocess has an owned private process group, a synchronous observer,
a 240-second build or 120-second run deadline and a sampled 16 MiB log limit.
The observer retains the leader through group retirement and the sole final reap;
every final phase receipt records the absent group and ECHILD. The captured UI
overlay only excludes native mounted-control helpers from the headless backend;
pristine and overlaid inputs are both retained. Selected executable and source
pins do not freeze imported vlib, third-party headers or linker transitive inputs;
this is not a hermetic toolchain qualification.

The external state root is
`/Users/alex/Library/Caches/vinix-codex/section14/compact-launch-20261026`.
Final host evidence is `attempt02`; the earlier `attempt01` is retained unchanged.
It failed because the new fixture initially checked the wrong Status-reader
field, before starting its service worker. Its initial driver also lacked the
owned group cleanup used by the final driver, so it supplies no bounded ownership
PASS claim. The original error and both bootstrap bundles remain available.

Source revision `bff87f34bbeda82173f2949797309afd0d4ec354` identifies the worktree
base. `attempt02/sources.json` binds the actual captured edits, rather than
claiming those edits existed in the base revision. SHA-256 pins:

| Input or receipt | SHA-256 |
| --- | --- |
| `desktop/software_app.v` | `407a33a665d0fd6d9b4c94cd892f05b366ee25f8d387d14e9c37ac04f86467ba` |
| `desktop/software_launch.v` | `5e37b1f9d586867d6ede737416203127b542a3071e2a1efd52f704a1e6dfaa44` |
| `desktop/software_launch_navigation.v` | `41fdec1ad0ca9591447ae5ac394a21094cddef9708f031134d318c5107544450` |
| `software-compact-launch-check.v` | `4010fbb5c703d0dda3545028f84b6371d728f4ccb05a4cc7e3b8be4daf824603` |
| V executable | `ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5` |
| Clang executable | `4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8` |
| `attempt02/result.json` | `ec30dcbb0b3381f806c306cb141902d1637faba29e6902e4f492c53c9be626ec` |
| `attempt02/sources.json` | `122b9d9ffed4a43c6a7366ff75827aab5641209320365a8adcf664f70474e86f` |
| `attempt02/artifacts.json` | `d934f2ecbe6f462afb7f50c2da3a361db9b973544a021dbc1b3abcdd4febfca6` |
| `qualification-artifacts.json` | `37da2ff7817f238bf7ae7df1a511a67d3117f12562599a6dfbd2e1f1835b1209` |

The last receipt inventories both host attempts and bootstrap roots, including
hidden entries and literal symlinks. Complete metadata seals using the unchanged
`tests/kernel-allocs/frame-page-seal.v` are retained under
`host-complete-seals01`, one manifest per immutable root. Raw generated sources,
binaries and logs remain outside Git. A separate reviewer ran the unchanged
original complete checker against all four host manifests; each returned zero
with `FRAME-PAGE COMPLETE STATE CHECK PASS`.

| Original complete manifest | SHA-256 |
| --- | --- |
| `host-complete-seals01/attempt01/inventory.json` | `8f8f742cc0fe888c2cb07fd9002285d9c1e697fd58f4b09f21c9132040bda695` |
| `host-complete-seals01/attempt02/inventory.json` | `22926cf2aa332c31436ebe0fb3fe2e268316e0c4fda4e1d351d9c32e74a22365` |
| `host-complete-seals01/bootstrap/inventory.json` | `e057fec383945d2736d3b9c776c68db833a84f2462b770ac670ccb3dc9ad732b` |
| `host-complete-seals01/bootstrap02/inventory.json` | `7e0bf24bfc9bc1982e19bf7686bd01849a7603d97820bf75859c9d3916239a9d` |

Both complete compositor static cross-links passed for aarch64 and x86_64 in
`targets01/bundle`, followed by the unchanged target-bundle checker. The existing
recipe retains its historical `release-save-policy` five-source named scope;
the new outer `software-compact-target-check.v` additionally checks exact byte
equality for all three compact-form production files in its captured inputs,
the recipe's before/after source inventories, copied source and both staged
architecture apps. This establishes build coverage for the compact edits without
changing the historical checker or claiming native guest graphics acceptance.

The target owner separately compiles and directly executes the existing recipe.
Its three owned phases have 240/1800/240-second deadlines, sampled 16 MiB log
limits and a sampled 768 MiB inclusive state budget across `targets01` and
`target-bootstrap01`, including hidden entries and link/directory sizes. The
largest observed phase sample was 209,164,032 bytes. All three phase receipts
record exit zero, absent private group, sole reap and ECHILD. Complete original
metadata seals are retained separately under `target-complete-seals01`.
A separate reviewer ran the unchanged original complete checker on both target
roots; each returned zero with `FRAME-PAGE COMPLETE STATE CHECK PASS`.

| Target input or receipt | SHA-256 |
| --- | --- |
| `software-compact-target-check.v` | `05b5501febb39535704a1ef23db44187d0203a01b559a14d840690dae7b4710c` |
| `target-bootstrap01/owner` | `e262b80af07f70ed7c9ce4293cc1d9821f0316dd5d0e9dda10ec908131a2be55` |
| `targets01/result.json` | `20de01cb531c509205af9afc6e6a833ab709f622c78bc46df876d1b4f6de0832` |
| `targets01/owner-inputs-before.json` | `2871e3e3b0032bea111b832c6abe269134cddbf6bf6541c56da1981519702117` |
| `targets01/bundle/bundle.sha256` | `d22fbbc8a6c60c11a87ed0f6da7d2fb962fea3a194862f34857588a7e37d1e24` |
| `targets01/bundle/aarch64/vinix-desktop` | `af06d199fe1f13e2e15bed79799a311038dc10a6a52a38a9a5a42d173a2a3533` |
| `targets01/bundle/x86_64/vinix-desktop` | `9b201c79aeb6b636a711c47a225d4604b3ae2b91b14e87f34a5f3b16833f9d07` |
| `target-complete-seals01/targets01/inventory.json` | `271fb27fe2e51547576037beac3151abe93d3f3a9d4cdcb8815797491ec9bdf4` |
| `target-complete-seals01/target-bootstrap01/inventory.json` | `c7066640974bb7a2f61c307f3797c6a77a61f416b18e2f231c7cfe591a7b7d61` |
