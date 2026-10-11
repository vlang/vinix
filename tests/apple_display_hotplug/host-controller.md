# Native display-hotplug command

`run.sh` executes `run.v` directly. It replaces argument parsing, compiler and
module calls, manifests, full status/stdout/stderr comparisons and guest
supervision with V. The Python import API and borrowed-object query/controller
are retired. The independent fixture and production hotplug algorithms retain
their exact bytes and all 47 original checks and line tags.

Default work honours writable `TMPDIR`, `TEMP` or `TMP`, with standard fallback
directories. Retained state must be fresh; literal Unix backslashes and newlines
remain filename bytes. `--arch` requires retained state; `--build-only` allows
building without a kernel/guest directory. CLI errors return 2, runtime errors
return 1, and SIGINT returns 130 after retiring its direct child and private work.

Module generation uses the existing native producer with the original flags,
warning exceptions and PIC policy. The combined object allocator ban remains
unchanged. Native builds retain their entry/serial objects, original or V
fixture, compiler inputs and manifest fields. Host executions retain the
180-second limit and exact three-part parity; guests retain their marker,
negative `check failed` policy, no networking and 300-second deadline.

Source and symbol text have an explicit strict UTF-8/newline contract; fixture
goldens, independent original C and environment values preserve raw bytes.
There is no remaining Python callback-object or traceback contract. New host
golden and guest results are in
[qualification](../apple-protocols/mailbox-hotplug.md).
