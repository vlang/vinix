Independent pipesize lifetime review: PASS

Reviewed the native-page pipe capacity normalization and effective CAP_SYS_RESOURCE growth check against frozen baseline `faec863268ebe028ee9c20df03ff31c720bdff2b`. The normalization change is committed separately as `320b50a86`. The final source, both completed production builds, generated C, explicitly pinned preflight4 builds, original/intermediate/final native probe captures, actual Linux 6.12.51 references and seven-case native receipts below were independently consumed. No lifetime blocker remains. Desktop and general performance qualification are outside this review.

The normalizer rejects requests strictly above 2^31 before rounding and starts at the native page size. Its scalar power-of-two loop is bounded by 2^31 and allocates nothing. The setter checks growth above both the existing capacity and the 1 MiB ceiling while holding Pipe.l; effective CAP_SYS_RESOURCE is read synchronously from the running process. Refusal releases the lock and sets EPERM before changing capacity, charges, storage or readiness. Same-capacity requests and shrinking an already oversized pipe remain allowed after the capability is cleared. The largest successful requested capacity exercised here is 2 MiB. Exactly 2^31 is exercised only without the capability, and values strictly above it exercise EINVAL without allocation.

The retained FD and Handle acquired by fd_from_fdnum keep the underlying Pipe alive throughout fcntl's synchronous capability call. The unchanged stack capability wrapper does not escape to the backend, event or allocator. Every method that dereferences the ring storage owns Pipe.l; available/room expose scalar amounts rather than a backing pointer, and Pipe.mmap exposes no backing mapping. A resize reserves the new charge and allocation before copying both old readable spans. It frees the old allocation under that same lock, installs the new pointer and offsets, adjusts readiness, then releases the lock and triggers the Pipe's existing event while the caller still owns the Handle. Grow failure preserves the old ring; allocation failure returns the newly reserved charge before returning ENOMEM. This unchanged rollback was source-reviewed, without budget-failure injection. The accepted maximum keeps capacity-times-two arithmetic within u64.

Independent V assertions compare complete production C. Removing only normalized_capacity's body leaves original and normalization-only C byte-identical on each architecture. Removing normalized_capacity and set_pipe_capacity bodies leaves original/final and intermediate/final C byte-identical, including their unchanged prototypes. The final setter body exactly equals the original after deleting only the new permission guard. The final normalizer exactly equals the intermediate after deleting only the relocated ceiling check. Allocation, copy/free, lazy storage, ownership, descriptor lookup, capability dispatch, syscall word decoding and event code therefore retain their original production C. The new guard introduces no heap box or asynchronous borrower.

The final fixture has sixteen explicit alloca sites, fixed arrays and one mmap/munmap pair; generated C contains no malloc, memdup, V array mutator or bounded-index helper. The parent Bank is zero-initialized before setup and retained through all four sequential fork/read/wait cohorts. Each child has its forked address-space copy and synchronously borrows Bank, Counts, stat, capability header/data, rlimit, ioctl and slab scratch. Capability structs are consumed before their creating functions return. Counts members are initialized before qualification; the same sizeof(Counts), 88 bytes on these ABIs, governs the single atomic result write and parent read. A short result never exposes uninitialized Counts to reporting. Parent aliases remain open until each child completes; temporary duplicates and slab observers close before returning from their successful or nonfatal failure paths. Fatal setup paths exit through existing process cleanup.

The eight-page mapping belongs to positive() and bounds every synchronous memset/read/write/byte comparison. No kernel operation retains its user pointer. Its fresh anonymous pipe, duplicate reader and inherited named FIFO are used sequentially. Successful cleanup closes the three fresh descriptors and unmaps the scratch before returning to the Counts transfer; no later code uses the pointer. The positive data checks grow an actual wrapped QRST stream, reject shrinking a full ring with EBUSY while preserving bytes/capacity, then drain to one occupied page and shrink successfully. They restore capacity and drain the final Q byte. These controls do not qualify fragmented occupied-ring shrinking under Linux's page-slot model.

Each capability-bearing cohort performs [1000,722,194,28,48] controls; each cohort without it performs [1000,722,240,28,48]. Root and UID/GID 1000 each run with effective bit 24 set and cleared, totaling 8,060 controls per architecture. Coverage includes native page rounding, invalid unsigned requests, real nonpipe/bad-FD EBADF, five upper-register patterns and libc calls, read/write and named-FIFO aliases, lowered soft limits 8/0, descriptors 64/65 and reused descriptor 66, capability drop on an existing 2 MiB pipe, retained metadata/flags/cursors/queued bytes and the final 80-slot vector. Original baselines fail exactly 3,144 ARM and 1,404 x86 controls. Normalization-only kernels fix every normalization/overflow row but still fail exactly 376 capability controls per architecture. Final native and actual Linux references pass every row. Native pages are 16 KiB ARM and 4 KiB x86; both supplied Linux kernels use 4 KiB pages.

All four final native credential/capability cohorts perform 32 warmups and 200 measured duplicate/resize/query/close cycles, with thirteen-second settling intervals around snapshots. The cycles resize both populated anonymous pipes and FIFOs through native-page, twice-page and 64 KiB capacities; capable cohorts also grow to 2 MiB and restore 64 KiB. The queued AB/CD/GH bytes remain unchanged. Independent checks require every one of the 18 ARM / 14 x86 slab classes in each cohort, reject duplicate/missing rows, and require exact before/after live counts. Every class stays flat. Large pages are 75/75 ARM and 198/198 x86 in every cohort. The seven final native receipt entries (pipesize, pipecmd, fcntlabi, keepcaps, capset, open, runtime) all exit zero, and their source, ELF, ISO and staged kernel hashes were independently checked.

Preflight4 explicitly pins V and VINIX_V_COMPILER. Its raw generated C and ELF are byte-identical to native preview/before/intermediate/final inputs on each architecture; actual Linux uses that same probe ELF. Preflight3 raw C is separately retained: its only difference is the exact unused stderr helper block. Replacing only that block makes the entire C equal, and there are no calls to those helpers outside their definitions. Preflight3 ELF is also identical. The first ARM bounded-index preparation failure, the initially unstaged intermediate build, prezero-Bank p2 captures and the preflight3 helper drift remain diagnostics; none is substituted for the final semantic baseline.

Independent inline V assertion checks were run without -prod. The deliberately false assertion exited 1 with `pipesize independent review assertion control`. A passing Linux reference supplied as the failing ARM baseline exited 1 at the exact failure-count assertion (`failures=0` versus `failures=435`). The final passing native ARM capture was separately supplied to that unchanged baseline checker and failed at the same assertion with exit 1. The successful source/C, count, storage, identity and receipt checks completed with exit 0. An initial overstrict raw preflight3 C equality assertion exposed the helper-only drift described above; the corrected check restricts normalization to that exact block and uses preflight4 for raw identity.

Qualification remains bounded to these native musl ELF64 calls and inherited descriptors. Per-user Linux pipe page quotas, mutable pipe sysctls, watch queues, fragmented page occupancy, allocation/budget failure injection, concurrent close/reuse/resize/capability stress, blocked writer wakeup behavior, GNU libc, translated/foreign and ELF32 paths remain unqualified. No broad section 15 completion gate is asserted.

SHA-256 pins were independently recomputed after the relevant producers completed. Paths below are relative to `/Users/alex/.cache/vinix-linux-compat/pipesize-20261014`, except repository paths explicitly beginning with `kernel/` or `tests/`. Common rows require exact byte identity.

| File | SHA-256 |
| --- | --- |
| `kernel/pipe/pipe.v`, `candidate-pipe.v`, `kernel-arm/kernel/pipe/pipe.v`, `kernel-x86/kernel/pipe/pipe.v` | `2ad825ae805ce9a9c8dfbc18d176424746cc32bdfa71491c3c427463dfd0a1c7` |
| `middle-pipe.v` | `8fb9b6a0e22c9dcad2adf90114516161083ef55e9c83fd4882019f8b30230f6c` |
| `kernel-arm/kernel/file/file.v`, `kernel-x86/kernel/file/file.v` | `bb05660fb6b07f7ae2e63d96fc4682f2581ebf350e2baa09cab5c3fbed204672` |
| `kernel-arm/kernel/resource/cache.v`, `kernel-x86/kernel/resource/cache.v` | `4a34a2f02113c56b7ea915d73959e03ab89ea3b25f55333b0e4ee366de5c6945` |
| `tests/linux-compat/pipesizefixture/core.v` | `fa3d6f719992719626ebb7947466b09d7b5bb9baa5422ec4a715e2892f2f2120` |
| `tests/linux-compat/pipesize-reference.v` | `d6750825ea14c556dacd9aad815e62fd9b248ad3e56fd4f61cf77eeae8575d3b` |
| `tests/linux-compat/pipesizereferenceinit/core.v` | `c858296fa434ea66dbaba8b2e51cc174be234947c52ff0ba35b7b52267408f62` |
| `tests/linux-compat/run.v` | `cab23ceff1a7bdcc39e406a94e468a487f6bcacf726ba205a73bc75cd95526d1` |
| `before-arm.c` | `52fb5ed79122e34e9003ea844c4273511a91c311552311b7c0624acd374a63c0` |
| `middle-arm.c` | `464df140a33c5e54ea56331cd2cbe5a3194489a902cad8dade78f3759c501689` |
| `after-arm.c` | `09263cfd1d125a7a56e80db0df68917949d10d66aa0fb4d08ba76f2437242e70` |
| `before-x86.c` | `14f3e167f079b0e13806b49b3951097e488217d0421f8156bbe1c763ebd38f31` |
| `middle-x86.c` | `9763a98f2c7c32e58c985dd0e3e4b1fb4d52c47d3e0d0559a101a5b653046e07` |
| `after-x86.c` | `f93c239c4cafe335140245961e3bf96e25fa044166406973f9ba3c98b6e631b2` |
| `preview-arm.c`, `preview-x86.c`, `states/preflight4-pipesize-{arm,x86}/fixture.c`, `states/p3-{before,middle,after}-{arm,x86}/pipesize/fixture.c` | `aadc0a0109f42f189287d5a99f69cf5acea8e328f636e67a382621cad0b18664` |
| `states/preflight3-pipesize-{arm,x86}/fixture.c` | `0b5ce15d998317905b08dcfc2df75a39e7e3aa637639ceee472095375863c049` |
| `states/preflight{3,4}-pipesize-arm/init`, `states/p3-{before,middle,after}-arm/pipesize/init`, `states/p3-reference-arm/probe` | `ec02a5ee54c273907ad938bc1a37997d995a8127d87ca1ec1d1e53fc272b7d3d` |
| `states/preflight{3,4}-pipesize-x86/init`, `states/p3-{before,middle,after}-x86/pipesize/init`, `states/p3-reference-x86/probe` | `819be40372d4efbc933e4a166a451f102e7620d8d9e9f7ecef142966bef7c721` |
| `states/p3-before-arm/kernel/bin/vinix` | `87c01668ac74b4079f2fde71434bdd418e70d6d2f12824ebaa0aa8606ae7c103` |
| `states/p3-middle-arm/kernel/bin/vinix` | `8f1c1988f091fca90043de17e5f3f33bd5642c608ed07108374396d49352d715` |
| `kernel-arm/kernel/bin/vinix`, `states/p3-after-arm/kernel/bin/vinix` | `faf19c208a2d71cf9b041f4c044726a889fe02efe0a9879c3305bd64b06fc5d8` |
| `states/p3-before-x86/kernel/bin/vinix` | `f69fe98b8b6d2716101bef79dd640eb12eab44f575288c7a5551251fcfcc4c71` |
| `states/p3-middle-x86/kernel/bin/vinix` | `b3e4ca7041150deb113d9d628af3281648f642bc6e771ad2dd880609592d8524` |
| `kernel-x86/kernel/bin/vinix`, `states/p3-after-x86/kernel/bin/vinix` | `e325facb3df22d6e78385d0518c5f33c18b76a9319b459e740e72c6eefb50e65` |
| `states/p3-before-arm/pipesize/serial.log` | `51dc5570610957182ee378a0a38216603fb29a9d9d47cb43b06737e012ad91c3` |
| `states/p3-middle-arm/pipesize/serial.log` | `1c62c67d416ef2d7619ae6639b4402866ae87e96b027ced694688e0544f91326` |
| `states/p3-after-arm/pipesize/serial.log` | `baedc3121f0b46a8d9552ae442803107bb41016a09b09c537bb893faa697bb07` |
| `states/p3-before-x86/pipesize/serial.log` | `52121e3170167d7adfbb3c2d7d1d9f62bcaab1ef858da1944b33257312944e6c` |
| `states/p3-middle-x86/pipesize/serial.log` | `aea326ddfbc9b3faefde1ad5c866e91a73b902be7d79c64eeb7acbfca44bf955` |
| `states/p3-after-x86/pipesize/serial.log` | `962f18b76f25b3281e427d9e37fcd732b7300f5d3bd6bc186b4de2d61862420a` |
| `states/p3-before-arm/receipt.json` | `9f4b8fd1fd1e037ec30cc1b374829364e68d395b651e019fbea11550edc52040` |
| `states/p3-middle-arm/receipt.json` | `d83e17d65709216a5cb41fa33fdf86ed442a3ce19f15407e5f9da83d67e317f5` |
| `states/p3-after-arm/receipt.json` | `898f9d826e6cc4c114c1f7def117afb05422237da4f4a3be1bf59350b396377e` |
| `states/p3-before-x86/receipt.json` | `4c1542c4d2c1cd7ffa68b84d91c3cfb596718c056bbb39c6e10a33c1886a4eaf` |
| `states/p3-middle-x86/receipt.json` | `1633b3c57326e0c868faa7da8f56d0a86a9ce9a3ff078cd1d038d880dce347a5` |
| `states/p3-after-x86/receipt.json` | `0e8963e607b9111da844388350bde8d32c9599f4bbaaee20779595e1647d612f` |
| `states/p3-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p3-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p3-reference-arm/serial.log` | `7ff8a406698d90c407900254decde9421121fd713db7022b7e25a7849f6b5b18` |
| `states/p3-reference-x86/serial.log` | `eac956c4ac1fc1bed604422b924f15ab1e9ed20d75d717afa7ae7918fa42b8b8` |
| `states/p3-reference-arm/receipt.json` | `0f503bb885529255ac131c17ecc0e11d22085a48b96cd758d7e5738c777dde18` |
| `states/p3-reference-x86/receipt.json` | `ce1cf54c80139242fc680b3cf188de256a94eb1278024ea0895311225620df12` |
