# Launch drafts in the compact Software reader

**Read draft** prepares the current launch draft on entry to the shared report
reader. Disclosure includes installed ID/name, complete literal argument text,
private-data or installed-app working folder, installed file-access permission,
grant count, the current grant's number/path and any unadded file path. It
explains read/write access, explicit path use in arguments, launch-time service
checks, and that reading does not validate or execute a command.

The reader starts at the form's selected grant, or an overview when none is
selected. Previous/Next file, Up/Down and Tab/Shift-Tab traverse all 256 grants
without wrapping or changing form selection/paging. Canonical and compact
pages contain only the current grant, arguments and pending path. Back/Escape
retires both caches, retaining exact argument/file buffers, grants, working
folder, identity, permissions, focus, text selection and status. Re-entry
rebuilds the edited draft. Empty/no-files manifests retain their explanation.

Only read navigation is accepted inside the modal. Form/catalog actions,
application requests, launch/terminal actions and typing/pasting cannot mutate
the draft or start work. Active application workers cannot open the reader;
their existing runtime lease and close protection remain in place. Failed
commands keep both failure diagnostics and draft review available after exit.

Functional fixtures reconstruct text from UTF-8 pages, exercise 4,096-byte
Unicode argument/allowed/pending paths, inspect every one of 256 grants, and
check native rendered lines and geometry at 180×220 and 320×240. They cover
page boundaries/keys, full/compact/tiny anchors, both working folders, empty
drafts, installed permission basis, modal mutation refusal, preserved focus and
selection, fresh re-entry and running-worker refusal. The existing launch
navigation allocation mode adds 1,000 read/file/page/render/resize/ignored-run/
Back/cache-retirement cycles to its 256-file draft and terminal-transfer checks.

This is host UI qualification. Launch protocol, file authorization, service
validation, runtime isolation and running-app close guards are unchanged.
Whole-service/spawned-worker allocation freedom, new guest graphical acceptance
and broader roadmap 14 release acceptance are outside these checks.


## Recorded results, 2026-10-16

All sixteen final focused compile/run checks passed: full Software functional
assertions, nine affected allocation modes, ASan/UBSan functional plus launch
navigation allocation mode, and native font metrics. Both full desktop
architecture typechecks passed. Launch navigation retains zero tracked bytes
over 1,000 reader/form/file/page/render/resize/ignored-run/Back/cache-retirement
cycles in native and sanitizer builds. Sanitizer leak detection was disabled;
whole-service/spawned-worker allocation freedom is outside these checks.

The initial functional run found a 4,097-byte path in the new maximum-length
fixture. It was corrected to 4,096 bytes and both final functional builds passed;
the initial evidence is retained and pinned. No assertion or production limit
was relaxed. The unchanged maintained staging list needs no new filenames and
was not rerun. Frozen compiler, Software/protocol/UI inputs, staged copies,
binaries, generated C, helper sources and logs are pinned. Cache, fallback and
automatic compiler error reporting were disabled. Launch service validation,
authorization, protocol and running-app lease/close guards are unchanged. No
new guest graphical or broader roadmap release acceptance is claimed.

- [focused checks](results/2026-10-16/software-launch-reader-host.json)
- [summary](results/2026-10-16/software-launch-reader-host.txt)
- [functional assertions](results/2026-10-16/software-launch-reader-ui.txt)
- [allocation checks](results/2026-10-16/software-launch-reader-memory.txt)
- [sanitizers](results/2026-10-16/software-launch-reader-asan.txt)
- [desktop architecture checks](results/2026-10-16/software-launch-reader-desktop.txt)
- [execution notes](results/2026-10-16/software-launch-reader-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-16/software-launch-reader-toolchain.json)
