# Repository Rules

## Feature completion

- Always commit when you implement a feature or fix in this repository; do not
  wait to be asked. Commit each finished change before handing it off.
- Other sessions edit this checkout at the same time. Commit only the files you
  changed (`git commit -- <paths>`), and read each file's `git diff` first so
  no one else's uncommitted edits go in with yours.
- Commits that change Files, Activity Monitor or Settings run
  `.githooks/post-commit`, which cross-compiles the app and publishes it to the
  running QEMU guest (see `desktop/README.md`). Name the app in the subject
  (`Files:`, `Activity Monitor:`, `Settings:`) so the hook picks it up.

## Finding memory leaks in the kernel

The kernel is V built with `-gc none -manualfree`: nothing is freed unless the
code frees it, so every allocation on a repeated path that is not freed grows
the machine's used memory for good. Find leaks by measuring, not by reading.

1. Build the kernel in a git worktree (`git worktree add`, then symlink the
   untracked dependency directories under `kernel/` from this checkout), so
   other sessions' edits stay out of it. Point the harness at it with
   `VINIX_KERNEL_DIR=<worktree>/kernel`.
2. Measure what stays allocated.
   - `tests/desktop-perf/run.py new=<vinix-desktop> --scenarios=ops,churn,cache`
     boots the image in QEMU with no desktop.
   - `ops` does each common kind of system call 200 times (files on tmpfs and
     ext2, renames, sockets, pipes, epoll, /proc reads, mmap, threads, fork...)
     and prints `PERF-OPS` lines: bytes kept per operation, by heap size class.
   - `churn` runs short programs 300 times each: `PERF-CHURN` and `PERF-SLAB`.
   - `cache` shows what the page cache costs.
   - Inside the guest, `/proc/slabinfo` has each size class's live objects
     and `/proc/meminfo` its `Slab` and `Cached`. A class that grows by about
     one object per operation is a leak of that size.
3. Name the call sites. `make ALLOC_TRACK=1` builds in a table of every live
   slab allocation and its call chain (`kernel/c/alloc_track.c`). Reading
   `/proc/allocstart` starts over and `/proc/allocsites` lists what is still
   live. The harness prints them as `PERF-SITE` lines on such a kernel;
   `tests/kernel-allocs/sites.py kernel/bin/vinix < run.log` names the
   functions.
4. Read the generated C (`kernel/obj/blob.c`) for the function at fault. V
   allocates where the source shows nothing (`memdup`,
   `new_array_from_c_array`, `string__substr`, `int__str`), and
   `-warn-about-allocs` in the V the kernel builds with reports little of it:
   - `'${x}'` of a non-string leaks a temporary string per value, even when
     the result is freed. Print with `C.kprintf`, build text with `lib.Text`.
   - `&T{}` is always a heap allocation; a temporary should be a stack value.
   - A concrete value converted to an interface, even implicitly (an
     argument, an assignment, a return), is boxed on the heap, and a
     `resource.Resource` box copies the interface's fields: 384 bytes. Give
     the object one `box` field made once (`boxed()`) and free it with the
     object.
   - A local whose address escapes, or one passed to a `voidptr` parameter
     such as `array.insert()`, is moved to the heap. `unsafe { &x }` or a
     push avoids it.
   - Slicing a fixed array or a string copies it; `[a, b]` allocates and
     `[a, b]!` does not.
   - An array that outgrows its buffer keeps the old one unless it is
     `.noslices` (`arr.flags |= .noslices`) or sized up front.
   - Waiting on `[&e]` allocates a list per wait; use `event.await_one` or
     `event.stack_list`.
5. Free what something may still be reading after a grace period rather than
   at once: `fs.free_after_grace`, and the removed-node queue in
   `kernel/fs/removed.v`. Mark an allocation verified to be freed with
   `@[freed]` on its assignment.
6. Verify.
   - Run `ops` and `churn` again: every class should stay flat.
   - `tests/kernel-allocs/run.sh` checks the allocation sites V reports on
     both architectures against `tests/kernel-allocs/allowed.txt`.
   - Build both architectures (`make ARCH=aarch64` and `ARCH=x86_64`) and
     boot the desktop scenarios (`--scenarios=idle,apps,drag`).
   - Freeing what was never freed is where use-after-free comes from: have
     someone review every new lifetime before committing.
