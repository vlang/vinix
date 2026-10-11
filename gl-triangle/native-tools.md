# Native GL generators and runners

`compile-v` and `stage` compile maintained V directly. Generation preserves the
three module names, target flags, ordered source/header SHA256, generated C
prefix and target architecture selection. Staging merges the original module
trees and carries the native generator, SDK headers and complete helper source
closure, so a copied example can regenerate without the repository checkout.
Build scripts, guest rebuild commands, image checks and content-key inputs use
the native fronts; cache keys include the helper modules' actual source trees.

`tests/gl-triangle/run` preserves the independent EGL/GL/framebuffer C fixtures,
allocation-symbol check, all eight EGL modes, GLUT/legacy modes, framebuffer
depths and software/Apple renderer assertions. Those fixtures remain independent
test data and receive no implementation translation credit.

`tests/gl-triangle/run-vm` prepares the exact Mesa dependency closure and immutable
launch script, then invokes the existing eight-case marker policy with a native
PTY child. The child performs only SDK signal, directory and exec calls after
fork; arguments and environment are allocated beforehand. Native launches use
`waitid(WNOWAIT)` to reserve an exited leader's identity until its group has been
retired and its child reaped. SIGINT/SIGTERM return 130/143 after cleanup. Legacy
borrowed Python launch callers retain their previous path while that separate
AGX controller family is migrated.

The x86 sanitizer qualification exposed the existing EGL extension function
pointer's missing `const` parameter type. `vkg_egl_int` is an SDK type alias for
`const EGLint`; the V signature now matches the independent fixture and EGL ABI.
It adds no C implementation.

Qualification uses V 0.5.2 `4eb8f2b`, macOS ARM and Rosetta x86, plus ARM
ASan/UBSan. All four tools build cold on every profile. All rendering fixtures
pass, and standalone staged generators reproduce exactly for both target
architectures on every profile. Final CLI builds check help, choices, required
arguments and operational error statuses; all public shell fronts compile V.
The native PTY owner runs 100 complete lifecycles in one process per profile
with flat descriptor counts. Exited-leader/surviving-descendant, SIGINT and
SIGTERM cases retire their full owned groups. Image preflight checks pass,
including changed-source rejection. The actual ARM Mesa executable, PID 1 and
runtime archive also cross-build successfully from the native preparation path.

Original receipts, helper sources, command logs and prepared artifact hashes
are retained under `~/.cache/vinix-gl-native-20261012`. Build executables and
guest preparation trees on the scratch volume are disposable outputs. The
four original Python files are frozen unchanged and pinned to Git blobs in
`native-translation.json`; no Python was executed or changed. There is no new
kernel build, QEMU rendering result or physical AGX claim in this qualification.
The shared QEMU package service is the next dependency being migrated before
the desktop performance runner's full boot path is qualified.
