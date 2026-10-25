# Maps335: map rendering and Paris search

Maps335 passed onboarding, rendered the map, and opened Paris search results.
The application remained alive through the original 600-second observation.
Attractions still displayed a loading sheet; this replay does not qualify
that feature or claim complete Maps compatibility.

Paths below are relative to `/Users/alex/.local/state/vinix/android/`.
Times are UTC on 2026-10-25. The derivation tool is committed at `9a49b841d`.
[Maps334](maps334.md) documents the unchanged diagnostic launcher, framework,
native payload, media and full build provenance. Maps335 changes attempt
labels and destinations, retaining the exact Maps333 classifier. It uses
the old kernel and Framework332; the subsequent PIE placement and virtual
parent layout fixes were not present in this run.

Preparation ran 15:45:30–15:48:14. The recorded run envelope ran
15:48:35–16:00:57; its suite ran 15:49:16–16:00:29. Both envelopes completed
with exit 0, unchanged input pins, 50 clean environment entries and no
forbidden environment keys. The retained result reports `window_observed`,
`backend_ready=true`, `native_maps_observed=true`, `process_exited=false`,
`qemu_alive_before_capture=true`, `observation_elapsed_seconds=600`, and
`failure_markers=[]`. `functional_passed` remains `null`: collection success
and a live window are not an automated functional verdict.

The real QMP screenshots and input command receipts are under
`maps335-2026-10-25/results/attempt335/google-maps/`:

| Time | Observation | PNG | SHA256 |
| --- | --- | --- | --- |
| 15:51:54 | After Skip, rendered North America map, search bar and Explore tabs | `map.png` | `1ee4a389395f06745f5ca37ee697a50d223ed7c2cfbc9b2134a1d60284532f87` |
| 15:53:41 | Paris map and Paris, France place sheet after selecting a search suggestion | `paris-place-settled.png` | `6635df76749cca859ec78cd237d80febf560be219a24ef21aab0ebebb9fb7dd5` |
| 15:56:18 | Attractions loading sheet still blank, 102 seconds after the 15:54:36 click | `attractions-after-105-seconds.png` | `0c2a4d324de57ae4eef5d864783ffbcf4083b32ab162e0e77eeb2bda7b160ca1` |

The last filename overstates the delay by three seconds; `interaction.log`
records the actual timestamps. Place photos remained placeholders in this
attempt. Closing the category at 15:56:31 changed the search/map state, but
the 15:56:52 capture still showed a blank lower sheet.

The retained `serial.log` records result-UI construction through
`avos.a → avhu.b → avhw.q/k → avho.P` at lines 19439–19477. Selected smali
identifies the no-error search-completion path; this establishes delivery
into result UI construction, not nonempty results or completed binding.
Lines 23976–23996 show a visible loading subtree with a 608-high `nvv`, a
60-high header and `CircularProgressIndicator`; no RecyclerView appears
inside that shallow subtree. Drawing stacks at 21082 and 23013 and advancing
render timing at 24570 show continued UI-thread activity.

The transition Future changes from pending at 20702 to done at 22051,
22923 and 24266 without its failure marker. Smali shows that this Future
tracks a scheduling Runnable, not final animation completion. Tree sampling
is render-driven, limited to twelve samples and depth sixteen; rectangles
omit translation, alpha and clipping. These observations do not distinguish
unfinished binding, transition state or a network-dependent loading path.
No specific photo or category failure is established by the recurring GMS
errors. The separate parent-dispatch regression must not be treated as a
proven cause of this Maps behavior.

| Retained artifact | SHA256 |
| --- | --- |
| Generated `maps335-run.v` | `6880dc6ac36750d71c1939a87988e6606359cda305b25e1a13548da3c644fe2d` |
| Recorded runner | `9cf3cddaf1ff2d4ba300d9cc79ae895b321aeb2941d540de877e3030c2a73ae5` |
| Launch pins | `fc25ec432c17c70652c7d8efbf0df716c22766eb05bc931872ff98016a902e69` |
| Prelaunch typed manifest | `8d493e4588b6b3af87316824809f902bb50aac577b0e58e95d435ae02f2e137a` |
| Preparation envelope manifest | `022f8c62ddb6d09b058ff3ad26cecfcc056f5b30a22ee08508dd51ca9a9b6980` |
| Run envelope manifest | `27f886173749ace724cea3d3d0cece279f6b3c6301358a8513dcbca3e947040e` |
| Canonical `maps335-2026-10-25/sha256.json` | `95ed4311798dee9ab35c3d77bb34f239e632707eda7b39bfc59229025e8bba84` |

The complete canonical bundle retains runtime logs, PCAP, PNGs, postrun
media, original inputs and build closures. Root and peer independently
passed the recorded runner's complete typed readback of 24,718 entries and
the existing flat checker's nine-file readback of each envelope. External
receipts are `maps335-final-{root,peer}-readback-2026-10-25.log`,
`maps335-wrapper-{root,peer}-readback-2026-10-25.json`, and
`maps335-preparation-{root,peer}-readback-2026-10-25.json`. Earlier evidence
and historical checkers remain unchanged.
