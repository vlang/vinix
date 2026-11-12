# GL string queries without a current context

Parent 55cbee1c6. r65-r67 failed at null address 0x898 with GL_EXTENSIONS
(0x1f03) in registers x19/x20. The adapter unconditionally called Mesa's
glGetString dispatch stub, which loads slot 0x898 from the current dispatch
table. On a thread with no current context that table can be null. Disassembly
of the retained libglapi.so.0 shows `ldr x1, [x0, #0x898]` after dispatch lookup.
The r67 snapshot was too late to map its fault PC; identifying this exact
instruction as the GMS failure remains an inference, not a captured backtrace.

The JNI adapter now returns null before entering GL dispatch when the calling
thread has no current EGL context. This matches the
[Android no-context string lookup](https://android.googlesource.com/platform/frameworks/native/+/18c754e18499acce28e8be58846879075ade72a7/opengl/libs/EGL/egl.cpp).
It does not create a context, borrow another thread's context, fabricate an
extension string, or consume GL/EGL errors. Existing bound-context calls still
use the provider unchanged. Native callers that bypass this JNI entrypoint
are outside this fix.

The signed EGL regression now checks both GLES20 and GL10/GLImpl string queries
before binding and after eglReleaseThread. It also runs these queries on a
joined worker while the original thread owns a real context. The original
thread subsequently verifies its GL version, invalid-enum handling and rendered
pixels, so returning null unconditionally or clearing its context cannot pass.
Worker exceptions are captured and rethrown after join.

All evidence is under `/Users/alex/.local/state/vinix/android/`. Available
V 0.5.2 6f888d6 and unchanged guard limits produced:

| Artifact | Elapsed ms | Peak sampled RSS bytes | Shared growth bytes |
|---|---:|---:|---:|
| current-native-build-20261113-r4 | 15125 | 475299840 | 63115264 |
| current-api-fixture-20261113-r1 | 2386 | 180486144 | 35659776 |
| maps-current-20261113-r69 staging | 13064 | 38174720 | 216678400 |

Each exited 0/0 with complete cleanup. Native ELF SHA256:
0d23f78a1c776a0175a7b79dcbbf576cb5c8eab908c9f842b0725c0330382712.
Signed fixture APK: 21b6e257a484ec08fa578d696b389b0d83b2ad259d64a61d5df623fdc6d41373.
The native producer retains all native V inputs, generated C, headers and link
logs; the changed probe sources and hashes are unbound-gl-inputs-20261113-r1.

Fresh r69 retains the current decor SDK, memory-qualified controller r4 and
paired protocol/launcher r2, mandatory core/TLS jars, 12 GiB/4 CPUs and 8 GiB
app-data volume. Volume identity 9b60555550d549fc9d5b0874638b174a, read-only
e2fsck and initial image hash passed before boot. The full signed regression
passed on ARM as UID/GID 10160: ready/pass once, drained EOF and exit 0.
Snapshot unbound-gl-api-uart-20261113-r1 full SHA256:
63e26ebe973b414fab9fad41f9da9510e1479fb85de7b09c178465b63b5fba7d;
receipt 79ec427fa310e942216c47c92416a97d79246a00a0219b69397daa4b919d3456.
Plan/readback r1 reconstruct the unchanged export with zero removals,
archive 2ac8fef6e3f61f27eed59d4f968b33985c19564bf9445b334e6717a1ec614bf1.
This is byte-export evidence, not a claim that the historical strict importer
passed. Real account-flow retry and map geometry remain pending.
