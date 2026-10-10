The disk-no-sync controller delegates debugfs argv/result joining, inode field
selection, all eight disk checks, post-power-cut reporting and step/environment
policy to run_native.v. The original independent guest fixture is unchanged.

Python retains argument and path ownership, archive creation through the actual
upstream tarfile owner, subprocess capture/text decoding, regular expressions,
PTY fork/exec, wait/read capture and the original power-cut process-group stop.
The sequential finally still stops the guest before closing the PTY and printing
its raw transcript. V reporting starts only after that finally has completed.
The archive function is byte-for-byte original; tar headers, buffering and close
error precedence receive no translation credit. Raw filesystem arguments travel
as hex to preserve POSIX backslashes and surrogateescape. Full inode numbers
travel as decimal text. Spawn captures run in the invoking interpreter, retaining
its stdin, locale decoding, stream order and closed standard descriptors.

Private synchronous callback errors are call-scoped: their table is cleared after
controller stdin/stdout and process retirement. Separately held actual exception
and traceback aliases retain their ownership. No exception attributes, contexts
or tracebacks are changed to break cycles. The shared host controller builds a
private query unless VINIX_DISK_NO_SYNC_QUERY names an existing executable.

Host paired fixtures and real small PTY children validate controller policy and
shutdown order. They do not establish a fresh kernel build, QEMU disk persistence
or physical storage behavior. Arbitrary private helper replacement and native
bridge traceback layout are outside the migration boundary.
