# Removed-node and memory-retention qualification

Build tracking kernels in isolated worktrees, with their untracked dependencies
linked from the main checkout as described in AGENTS.md. Enable `ALLOC_TRACK=1`
and `LIMINE_MP=1` for AArch64. The runner uses an already-built kernel.

```sh
python3 tests/memory-retention/run.py --arch aarch64 --kernel-dir /work/arm/kernel --state-dir /tmp/retention-arm
python3 tests/memory-retention/run.py --arch x86_64 --kernel-dir /work/x86/kernel --state-dir /tmp/retention-x86
```

Use fresh state directories. The default is four CPUs, 4096 MiB and a 600-second
timeout. The fixture requires `RETENTION PASS` and rejects `RETENTION FAIL`,
panics and fatal exceptions. AArch64 uses the static musl sysroot under
`build-aarch64-userland/sysroot`; x86 uses `x86_64-linux-musl-gcc`.

The guest checks removed directory descriptors, `fchdir`, cwd inheritance,
unlinked children, rename over an open directory and `..` traversal after a
removed subtree loses its last pathname. It waits beyond the five-second
reader grace before accessing each retained directory. Creating files,
directories, symlinks, hard links or FIFOs through a removed directory must
fail with `ENOENT`. PTY hard-link unlink and rename exercise a final resource
callback that removes another pathname.

After warmup, three cohorts each run 600 filesystem cycles, four concurrent
private `CLONE_FS` views, concurrent `O_CREAT` opens and 100 fork/exec/exit
cycles. Each filesystem cycle creates two directories, replaces one by rename,
creates hard and symbolic links, renames and unlinks an open file, removes its
parent and writes through the surviving descriptor. Every live slab class must
stay flat against the same observer's immediate diagnostic control. Failure
prints allocation-tracker sites before terminating.

Also run the desktop harness's `ops,churn,cache` and `idle,apps,drag` scenarios,
the process/SMP, job-control, scheduler/QoS, kernel-resource, resource-group,
paging-pressure and EXT2 sparse-file guests on both architectures. See
[the implementation and qualification record](../../docs/memory-retention.md)
for the measured scope and remaining audit limits.
