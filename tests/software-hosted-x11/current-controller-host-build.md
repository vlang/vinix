# Current controller host build

The private controller from
[current-controller-source-preparation.md](current-controller-source-preparation.md)
passed host production compilation as `check-03`. The compiler returned actual
status 0 using the existing strict pointer flags, default collector and retained
generated C. Its log contains ordinary unused/shadow notices. This is a build
result; the controller was not executed for this qualification.

The repository revision before this report was
`868fd9ed33e825da1e3f8f2749950cf559d4afcd`. Complete evidence remains under
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02/native-consumer-tools-01`.
The compiler argv, exit, log, cleanup and build receipt are retained beside
`check-03`. Generated C remains at
`scratch/check-03.80218.42418417875.4493648304.tmp.c`.

The unchanged consumer owner applied its 120-second child limit, sampled
550 MiB free-space floor, inclusive 40 MiB allocated-storage cap and existing
receipt reserve. Its **90 samples** had a largest gap of **1,030,205,542 ns**,
maximum allocated storage of **32,407,552 bytes** and minimum available space of
**31,920,095,232 bytes**. The final consumer allocation was 24,125,440 bytes.
The compiler exited naturally, was reaped and left an empty process group;
the final wait returned ECHILD. No kill, held output pipe or resource refusal
was recorded. All sampled `df` children also completed and were reaped.

Controller source and complete module maps matched before and after; the frozen old-tool
root check passed after the build. Independent generated-C inspection confirmed
the three reviewed host wait boundaries:

| Boundary | Native status storage | Subsequent conversion |
| --- | --- | --- |
| `hwhost.Child.poll` | `i32 status` passed to `waitpid` | Widened to the V `i64` field after return |
| `os.Process.impl_check_pid_status` | `i32 cstatus` passed to `waitpid` | Widened for exit-status decoding |
| `pkgcore.reap_output` | `i32 status` passed through `vinix_package_waitpid` | Result decoded after return; the alias is `waitpid` |

These are static host-C boundary checks, with no process-behavior or guest-ABI
execution claim. Generated C is 4,647,573 bytes; the executable is 1,644,608 bytes.

| Artifact | SHA-256 |
| --- | --- |
| Controller source | `5f72e85d943ade7d8306fe7db1d05f9651613b22270c1bc3e07888a0d40d890a` |
| `check-03` executable | `eb67ac1ece3e91bc7d4fca9372ce40a2355810d827d88f15947311d256b8e811` |
| `check-03.build.json` | `d2019599810b4f5c8ed468f29f8481e80d53734f900643560f028688fccf6807` |
| `check-03.monitor/result.json` | `232a7d3f63d3b1fd7936dd352f5db1d20c17d10d75c51d141a310d487b1ae171` |
| Both complete module maps | `710351295e1be60a49b75f84348493ee85cf1f0777991a8b457ac3f4b83201d4` |
| Retained generated C | `4d6d6f6cc338d07820337300ab650b0483230f1b6496121f13e6f60ac35d4d2d` |

Public API execution, actual complete pre/post checks, compositor imports,
retainer qualification and native runtime acceptance remain separate gates.
This host build establishes none of those acceptance claims.
