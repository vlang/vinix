# Empty Software clipboard events

Policy paths, launch arguments and pending file grants, administrator passwords
and native-window fields previously treated an empty clipboard event as field
replacement when text was selected. The event cleared the field and selection.
Native input also became dirty even without selection, so an otherwise untouched
field could block buttons or closing until explicitly committed or discarded.

These four paste handlers now return before changing state for empty input.
The entered bytes, backing storage, focus and selection remain unchanged.
Administrator password masking stays intact; native input retains its existing
clean/edited state. Nonempty paste validation, byte limits, keyboard commands,
service arguments, reviewed intent, authorization and SDK protocols are unchanged.

The maintained [Software fixture](software_fixture.v) checks empty/populated
administrator fields with both focus/selection states at the actual credential
prompt. It checks clean/dirty native fields, including an already empty field,
through the root paste dispatcher. Empty input preserves passwords, masks,
worker identity, status, native frame sequence, focused ID and close state.
The existing successful password submission, masking, cancellation and wiping
checks remain in place.

The native application child also receives an explicit empty text event after
keyboard deletion and Enter, validates it against its protocol-2 frame and
acknowledges it with a new empty frame. Empty clipboard handling does not prevent
intentional clearing. Existing Escape discard, stale-control refusal and close
acknowledgement remain regression checks.

[Launch navigation](software_launch_navigation_fixture.v) exercises arguments
and empty/populated file drafts, unfocused/focused and selected/unselected,
preserving allowed-file count, paging/selection, application ID and working
folder. [Policy navigation](software_policy_navigation_fixture.v) covers empty
and populated paths with both focus/selection states, preserving pages and status.
Existing exact launch argv, separate file grants, frozen policy confirmation and
protected worker checks remain in the functional suite.

Launch, policy, administrator and native-window allocation modes add these cases
to 1,000 existing render/retirement cycles. The full Software suite, twenty-five
allocation modes, independent maintained driver, ASan/UBSan affected modes,
native font metrics and both desktop architecture typechecks qualify this
change. Sanitizer leak detection is disabled; the measurements do not establish
whole-service or spawned-worker allocation freedom. Guest graphical sessions and
broader roadmap 14 publisher/catalog/runtime release acceptance remain open.


## Recorded results, 2026-10-15

All 35 focused compile/run checks passed: the complete Software functional
fixture, all twenty-five allocation modes, ASan/UBSan functional plus policy
navigation, launch navigation, administrator and native-window allocation
modes, and the existing native font metrics check. The maintained Software-only
distribution driver passed independently with all twenty-five allocation modes
and the font check. The four extended allocation modes retain zero tracked
bytes over 1,000 input/render/retirement cycles. Sanitizer leak detection was
disabled; these measurements do not establish whole-service or spawned-worker
allocation freedom. Both full desktop architecture typechecks passed.

An initial sanitizer launch referenced an absent unretained helper executable
and returned shell status 127 before running a compiler or test. The phase was
then run through the frozen compiler; its complete suite passed with unchanged
source and assertions. The launch note is pinned with the final compiler,
Software/protocol/UI inputs, staged sources, binaries and logs. Invocations use
-nocache with compiler fallback and automatic error reporting disabled. No
service arguments, reviewed intent, authorization or SDK protocols changed.
No new guest graphical or wider publisher/catalog/runtime release acceptance
is claimed.

- [focused checks](results/2026-10-15/software-empty-paste-host.json)
- [summary](results/2026-10-15/software-empty-paste-host.txt)
- [Software and maintained driver](results/2026-10-15/software-empty-paste-ui.txt)
- [allocation modes](results/2026-10-15/software-empty-paste-memory.txt)
- [sanitizers](results/2026-10-15/software-empty-paste-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-empty-paste-desktop.txt)
- [execution notes](results/2026-10-15/software-empty-paste-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-empty-paste-toolchain.json)
