# Native desktop source staging

`stage_query.v` owns both staging workflows. The V modules select and normalize
sources, remove example entry points and unused embedded views, render translation
and canonical icon data, filter ui2 module declarations and apply the existing
ui2 compatibility substitutions. Public Python entrypoints retain their signatures,
module docstrings, constants and CLI output.

`_stage_native.py` binds the caller's filesystem and generic stdlib regex engine.
Patterns and staging decisions are maintained in V. UTF-8 hex transport preserves
surrogates and literal POSIX backslashes; regex offsets are converted to byte
positions before V slices source text. Source/array sizes below 2 GiB are qualified.
The Python bridge retains original exception objects and text-mode newline handling.
Its regex engine uses the caller's Unicode tables.

The original `open(w)` before example/manifest transformation is preserved with an
explicit stream owner. A close failure supersedes an earlier transformation/write
failure. The parent closes any still-owned stream after an abrupt controller exit,
reaps the child on stream errors and restores its signal handler after retirement.
Compiler selection uses `build-support/find-v.sh`. A copied entrypoint requires its
complete maintained native source closure, as the package-store fixture provides.

Validation compares frozen originals at the same private paths: complete generated
bytes and symlink targets, ordered errors, Unicode and surrogate inputs, live
checkout staging, actual loopback HTTP snapshots, cold installation and repeated
exact descriptor baselines on ARM and x86 hosts, plus native sanitizers. The generated
icon ABI/header text is unchanged and earns no C translation credit. These host
checks establish no fresh kernel build, desktop compilation or QEMU rendering.
