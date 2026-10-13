# C framebuffer ABI checks

```sh
v run tests/framebuffer-c-api/run.v
VINIX_CAPI_KEEP=1 v run tests/framebuffer-c-api/run.v --cross
```

The library and all build/test tooling are V. `client/core.v` is a translated V
fixture compiled without builtins/runtime and including only the public C API
header plus libc headers. It calls the C symbols directly, so its successful
static/shared links and execution validate the ABI independently of the V client
module. No C implementation or Python wrapper is maintained.

The test server publishes a real shared framebuffer, verifies the foreign
client's pixels, and sends acknowledgements, signed pointer fields and a binary
keyboard payload one byte at a time. The consumer checks struct layouts, version,
default/explicit connections, external poll readiness, partial decoding,
pending-frame ownership, null arguments and error output.

`--cross` builds ARM64/x86_64 shared and static SDKs and statically links the
foreign consumer against both guest SDKs. The test prints its temporary artifact
directory; `VINIX_CAPI_KEEP=1` retains it for guest qualification.
