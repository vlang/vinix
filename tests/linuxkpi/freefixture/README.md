This fixture executes the real V page allocator, cache allocator, RCU backend
and typed public facade. Run it from the repository root with:

```sh
build-support/run-v-tool.sh tests/linuxkpi/deferred_free.v --keep-directory NEW_DIRECTORY
```

The controller uses the selected V compiler for native C generation, with
separate writable compiler caches recommended when other sessions are building.
Production C bodies are copied without alteration and checked byte for byte
against complete generated production modules, including their export thunks,
initialization guards and empty initializers. The three completion operations
are explicit V transport adapters. Original callback heads and public const
signatures are checked against the unchanged Linux headers.

The CPU/thread/IRQ transport is selected from the maintained RCU callback
fixture's unchanged V functions. Its old allocation wrappers, fail-fast generic
owner guards and unrelated test entry point are excluded. New V transport
supplies only physical-page allocation/free observations, an allocation failure
injector and a controllable pause before returning a page. The production
allocator owns prefixes, tags, geometry, cache slots and actual free dispatch.
There is no host implementation of the allocator or RCU queue algorithm.

Both GNU99 and GNU11 production objects compile with strict warnings and
ASan/UBSan. The generated full host fixture is GNU11 because the compiler's
repeated foreign typedef metadata requires C11. Each profile executes immediate
page recovery, mixed ordinary callbacks and deferred frees, callback self-free
and requeue, original free macros, barrier completion after an actual page free,
the barrier's exclusion of later work, and an explicitly joined synchronous
headless call. Offsets 0, 8 and 4088 run under four independently held reader
scopes: preemption pin, disabled IRQs, both, and modeled IRQ depth with IRQs on.
Arming each embedded free leaves the allocation failure injector untouched.

Each profile also runs 18 isolated fatal children. They cover the 4096 offset
limit, misalignment, a head beyond the requested span, a head preceding its
owner, three invalid headless contexts, reserved callback values, three genuine
packed-cache owner cases, an unsupported foreign owner, a corrupted owner tag,
an unaligned owner, a too-small allocation and a reserved small owner pointer.
The fatal spy checks the original head bytes, callback ordinal and page-free
counter before aborting. A sanitizer failure does not count as the expected
validation failure.

This host transport models CPU scope observations and trusted quiescent
boundaries. It does not execute native IRQ gates, scheduler placement or IRET,
and its page counts do not establish retained native kernel allocations. Those
properties require the separate native guest fixture and architecture builds.
No generic vmalloc ownership or working i915 GPU is implied.
