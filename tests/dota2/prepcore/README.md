# Dota preparation controller

The maintained staging workflow lives in V: streamed input hashing, ELF
validation, readonly pin replacement, optional helpers and preloads, runtime
refresh and trimming, native and Steam SDK dependency closure, translator
overlay, launcher construction, fixture compilation plans, archive publication
and kernel/disk staging.

`run.py` retains the public signatures, module documentation, argument parser,
export read observer and live VM supervisor. `_prepare_native.py` binds library
filesystem, process, regex, archive and quoting operations. It returns original
exception objects to the caller. Path strings use hexadecimal WTF-8 transport
to preserve Unicode surrogates and literal POSIX backslashes. Namespace fields
are read when the workflow reaches them; dependency queues mutate the original
list, and preload iterators remain lazy on failure.

Each request owns one native process. Nested cleanup closes its pipes, waits
five seconds before killing and reaping a stalled controller, retires the
outstanding hash stream and restores the caller's interrupt handler. Hashing
exits the original stream manager before returning an earlier read failure.
The manager receives the original exception, may suppress it, and a failing
exit retains its exception context and precedence. Successful exits ignore
their return value. Compiler scratch and the installed controller have
separate temporary owners. The host executable uses V's normal GC; no
kernel allocation or manualfree behavior changes.

Frozen Python comparisons check header boundaries, filesystem bytes/modes/links,
ordered commands, partial queue mutation, complete and repeated preparation,
exception identity, stream failures and child retirement on Darwin ARM64,
actual x86_64 through Rosetta, and ARM ASan/UBSan. Real APFS runtime copies are
also compared. Fixture compilation is controlled in whole-workflow tests;
these checks do not establish a new game launch, rendering result or kernel
build. Source/file inputs must fit the qualified host V array size (under 2 GiB).
