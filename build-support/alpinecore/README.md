The maintained command is now `build-support/alpine-resolve`, which compiles
`alpine-resolve.v` and invokes this module directly. It has no Python runtime,
JSON controller or borrowed-object dependency. All maintained shell and V build
callers use it; staging cache keys include the entrypoint and both policy files.

The parser preserves strict UTF-8 reads, universal newlines, Unicode whitespace
and line splitting, repeated-field behavior and empty package names. The resolver
preserves repository order, real-name preference over virtual providers, first
provider selection, FIFO traversal, cycle/name deduplication, ignored shell and
conflict dependencies, Unicode name sorting and tab-separated APK manifests.
Version constraints remain stripped rather than evaluated. Errors produce no
partial manifest. CLI help and syntax/read diagnostics are native text; statuses
remain 0 for success, 1 for resolution/read errors and 2 for argument errors.

Run the native checks with:

```sh
v -cc cc -o /tmp/alpine-resolve build-support/alpine-resolve.v
VINIX_ALPINE_TOOL=/tmp/alpine-resolve v -cc cc test build-support/alpinecore
```

`VINIX_ALPINE_REPO=/path/to/vinix` additionally checks the cached Java, Go and
QEMU package manifests against their unpacked indexes without downloading or
changing anything. Qualification passed on ARM and Rosetta x86 hosts and with
ARM ASan/UBSan, including all three cached manifests and a 1,000-package closure.
The Debian controller still compiles against the shared whitespace/line helpers.
No Python was run for this standalone stage, and no guest or full-image build is
claimed. The frozen benchmark runner remains historical source at its recorded
revision; it is not a maintained caller.

The earlier callback-controller qualification below describes the superseded
entrypoint. At that stage, the public Python entry retained argparse and the
immutable Package API, and standard-library primitives and caller-owned objects
used the shared runtimebuild bindings.

Frozen source at 8aaf12979e5d2c704e34782921cd82c30250ab83 was 2,946 bytes/97 lines. This stage replaces 2,174 original policy bytes/56 lines; after the additional generic bindings, the net Python reduction is 606 bytes/22 lines. Third-party libraries and independent fixtures remain unchanged.

Qualification used V0.5.2 6d549c2f095d5e3e97963e55a2ebf1dc2810db46 on actual ARM and x86 hosts plus ARM address/undefined sanitizers: 172 frozen/native parser and resolver pairs, 15 callback exception identity pairs, seven exact CLI pairs, EOF/spawn/group interrupt controls and 100 requests with stable descriptors per profile. The complete 1,000-record native workflow took 0.38/0.47/0.80 seconds on ARM/x86/sanitizer versus about 0.003 seconds for the frozen Python; output was exact. Cold source installation passed on ARM and x86.

The shared query_call extraction also passed 112 original/native Android builder controls, 13 retirement controls, 45 unchanged Android fixtures, five CLI pairs, three actual curl transfers and grouped Ctrl-C per profile. The parent owns pipes, retained values and original exception objects; its bounded controller retirement closes resources before returning. No archive ownership is introduced here. _pack and _unpack are unchanged. Python3.9 traceback frame lists include bridge/replay frames, so frame-list equivalence is not claimed.

Machine-local evidence: /Users/alex/.cache/vinix-python-to-v/alpine-resolver-20261009/qualification.json, SHA256 8e77dbe90ab4b46ce8011569ebcc5cb92a4e97ce4dbc27a46fcac0ba22a8ad4c. The committed sources and this record are durable; the receipt and frozen originals are local evidence. This is a host resolver port, without new kernel, guest or device validation claims.
