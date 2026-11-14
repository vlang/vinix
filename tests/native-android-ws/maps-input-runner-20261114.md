# Paced guest input with current V

r78's loaded guest dropped characters from terminal commands sent at the
runner's fixed 30 ms pace. --hold affects mouse/switch actions and did not
change typing. The runner now accepts --key-delay SECONDS for type, retaining
0.03 seconds by default. Negative and non-finite delays are rejected before
connecting. This controls event delivery pace; callers still need to observe
the guest's actual prompt before changing focus.

For example, after rebuilding android-run:

```text
android-run input type 'command' --socket QMP_PATH --key-delay 0.15
```

Current V exposed two existing compatibility problems while qualifying this
change. The QMP poll declaration now matches the platform's nfds_t and the
other imported native declarations. The metadata JSON reader explicitly
encodes lone surrogates as its existing internal WTF-8 representation instead
of relying on rune.str(), which now normalizes non-scalar values. Strict text
boundaries still reject invalid UTF-8. No historical assertion was removed.

The complete primitive suite passed, including QMP event/error precedence,
UTF-8 rejection, wide values, deadlines/EOF, descriptor cleanup, archive and
PNG checks. A new mock QMP peer checks the actual a-down/a-up/b-down/b-up
events and observes at least 100 ms between characters selected at 120 ms;
negative delay rejection is checked before connection. JSON regressions cover
lone high/low surrogates, adjacent high surrogates, following ASCII and valid
pairs. The full runner also built and its input help displays the new option.

Sources are androidrun/input.v, qmp.v, json.v and test-primitives.v in this
commit, following 49a0790dc. Builds used the available V 0.5.2 9a38ec5 at
`/Users/alex/code/v/v`, SHA256
f52821ef2d15507ef5238e36a5237c909dfbdbc09786671c5d87a3feb1ed843c.
Generated C and native compilation were separate guarded phases; the native
link includes V's signal-stack runtime and stb source. Every completed phase
retained RSS 629145600 bytes, wall 300000 ms, reserve 1073741824 bytes, growth
536870912 bytes and output 4194304 bytes, with exit 0/0 and complete cleanup.

Evidence remains under `/Users/alex/.local/state/vinix/android/`:

| Phase / external receipt prefix | Elapsed ms | Peak sampled RSS bytes | Shared growth bytes |
| --- | ---: | ---: | ---: |
| maps-input-primitives-emit-20261114-r6 | 15469 | 518569984 | 17276928 |
| maps-input-primitives-cc-20261114-r6 | 4002 | 198574080 | 8974336 |
| maps-input-primitives-run-20261114-r2 | 754 | 7979008 | 0 |
| maps-input-runner-emit-20261114-r1 | 14407 | 523911168 | 426594304 |
| maps-input-runner-cc-20261114-r1 | 4298 | 205471744 | 0 |

Each prefix has its .log and .guard.json. Complete generated C and test data
remain in maps-input-checks-20261114-r6 and
maps-input-primitives-results-20261114-r2. The usable runner, emitted C and
copies of changed source inputs remain in maps-input-runner-20261114-r1.
SHA256:

| Artifact | SHA256 |
| --- | --- |
| android-run | 530cbc0ac3a22bbfb30c3183f594822bf21c3c9a317180111f2a10cd1290c4cb |
| primitives | 415730d0b12ea7b40f03fdbea28b9f645a185308d9d5e658e72f96b8db236716 |
| Primitive run log | dc45e9f70de0ce86ec9dace7d8e277be3a70e78a12eac29a0b74ebeae704574d |
| Primitive run guard receipt | 964c6673d60b8fee3c380651613d4a8a10c2c318b8346b253de1f79b78208836 |

Earlier failed evidence remains intact: the original poll declaration failed
current-V compilation; the first executable exposed the existing surrogate
assertion failure. Combined primitive build r2 and native compile r3 were
stopped for shared growth of 550887424 and 625938432 bytes respectively.
Native link r4 lacked the signal-stack runtime, which the successful final
link includes. None of these is counted as a qualification pass.

The next Maps retry must use the paced runner and wait for broker readiness
explicitly. These host checks do not qualify map tiles, routes or sign-in.
