# Maps333: explicit Attractions replay and incomplete collection

Maps333 uses the exact full Native332 and Framework332 payloads qualified in
[Maps332](maps332.md). It starts from source revision
`c159fc577e74783a9b184245402f4838d8464731`, without new framework changes.
Skip, map rendering and Paris search worked. An explicit Attractions selection
reproduced the empty lower sheet. This attempt is **not a completed 600-second
qualification**: final collection failed with host storage exhaustion, and no
final classifier result or canonical manifest was written.

External paths below are relative to
`/Users/alex/.local/state/vinix/android/`; timestamps are UTC on 2026-10-25.

## Launch and observations

The unchanged recorded wrapper, runner and prelaunch gate selected the same six
full-build pins as Maps332. Generation passed its existing 1,536-MiB checkpoints;
preparation and the read-only launch check passed their unchanged gates.
All three nine-file stage receipts passed complete readback independently by
root and the preparation agent. The runner itself has no additional free-space
gate after preparation. No threshold or checker was changed for this attempt.

| Input | SHA256 |
| --- | --- |
| Generated `maps333-generation-2026-10-25/maps333-run.v` | `a2aa42361e7a8433d3fe70415f20d72c02c49436f8a5680af21922c9d3f7dca4` |
| `build/android-maps/maps333-run-recorded` | `6a8dbc60fd8d999a477b0419350a80c1aa07ce93850cf6d4fece3a68d5ec1eeb` |
| `build/android-maps/maps333/launch-pins.json` | `2b2087bd230111f7acf03dcbf20e2d0f9897bb6d4e5741b410ba2b688d68b7c1` |
| `maps333-2026-10-25/prelaunch-sha256.json` | `55af9e0f9a9f3d2b8479a41800fa9ba120c4a47b17b8703d8ebd8f5a199a7b67` |
| Generation receipt manifest | `b9e9141c7cab36e253079c07bb897fa652b5de33ff97711c628e20a1b786b386` |
| Preparation receipt manifest | `d0868fcef0abca33eac79f41aed391459c9242fb5e1ce8e32859f76ac151a47c` |
| Check receipt manifest | `731e63d785225d3940dc629a5a9d1754bd82181784648da9c1326b9848734d40` |

The run envelope started at 14:23:43 and suite launch at 14:23:52. Its startup
receipt records 50 environment entries, forbidden keys `[]` and the pinned
wrapper SHA256 from Maps332. No diagnostic flags or location override were used.
The existing `maps-interact-unique258` controlled QMP input and captured real
1024×768 PNGs. Pixel probes selected timing only; screenshots were reviewed.

| UTC | Observation |
| --- | --- |
| 14:24:19–14:24:33 | Skip leaves onboarding; North America map tiles display. |
| 14:25:17 | Paris suggestions display after typing into the focused search field. |
| 14:25:49–14:25:55 | One Paris result click opens a place card with map, photos and action buttons. |
| 14:26:13–14:26:20 | One explicit Attractions chip click changes the query and map; the lower sheet is blank. |
| 14:26:59 | After 46 seconds the lower sheet still has no results. |
| 14:27:09–14:27:37 | Close changes map zoom, but the Attractions label and empty sheet remain visible. |
| 14:28:14 | Search-field click is accepted by QMP; no later screenshot establishes its result. |

## Collection failure and retained evidence

The terminal returned exit 1 with `failed to open file` for the run envelope's
`sha256.json`, errno 28. This terminal-origin error was retrieved at 14:50:22;
that retrieval time is not the exit time. The inner launch receipt, final
classifier result and canonical manifest are absent. Buffered child output was
not retained in the empty outer stdout/stderr files. Serial output ends during
the run and cannot prove a complete observation window. A capture attempted at
14:50:14 failed because the guest socket was absent; its command logs are kept.

The failure-preservation tool retains all available partial canonical inputs,
working VM/module state, application output, screenshots, incomplete envelope
and generation evidence. It compares complete typed inventories before and
after cloning, then verifies every retained entry. It does not reconstruct a
successful verdict or relax an existing checker.

The preserved root is `maps333-failure-preserved-2026-10-25`, with SHA256 manifest
`4a5b6bf13966544509d37d693be4fb147ddf222f2953b448263037f48045a9d4`
and 23,482 typed entries (including mode records). Full readbacks passed using
the frozen retained tool, independently by root and a second reviewer. Their
logs are external siblings named `maps333-failure-preserved-{root,peer}-readback-2026-10-25.log`.
The preservation receipt is `maps333-failure-preserved-2026-10-25-receipt.json`,
SHA256 `aa6fbf8744e1fc2b96ce501e733aec476acdc83f5a7fe91eeda43fc0bfd65ddc`.
The original incomplete run roots remain unsealed.

The V [preserver](maps333-failure-preserve.v) compiled without warnings using
the pinned `v_old276` compiler. Its source SHA256 is
`e8d40e5f86e64533cd8870062738ba3fa56a72793f876b54ebb616eeea785c61`;
the retained binary SHA256 is
`f3edd1534c935528581c7f288ddb1f71f40ab45bc96b80bc404f3332555104b7`.
Readback: `tooling/preserve verify ROOT MANIFEST_SHA256`.

Real screenshots are retained under the preserved root's
`working-attempt/google-maps/` directory:

| PNG | SHA256 |
| --- | --- |
| [Paris place card](/Users/alex/.local/state/vinix/android/maps333-failure-preserved-2026-10-25/working-attempt/google-maps/paris-place-before-attractions.png) | `948cac5a0d9872789923cfc914add228566ecce3ee29bc97a54f98d1655a0573` |
| `attractions-initial.png` | `a303310bf75415579d7d07490be21e0c5998b77302b7b19c070d7a9e82fe599b` |
| `attractions-after-wait.png` | `169178077dad662a466bcd8c8b3fd3976e28b3ea29bad42ce63c544a1b63aa0d` |
| `category-close-recovery.png` | `35581f6f2ec8465432f0e817fc9a0a588a8e4af6ffeee14c33f0b138762c8c5b` |

The successful map/search/route qualification and route-preview PNG remain in
the independent sealed [Maps332 bundle](maps332.md). Attractions remains
unresolved. GMS warnings alone do not identify its cause. A separate diagnostic
run must distinguish pending transition state, suppressed layout and absent
result data before changing framework behavior.

The frozen Native332 already includes `diagnostic_objects.v` / `queue219.v`:
`VINIX_ANDROID_TRACE_TREE=1`, `VINIX_ANDROID_TRACE_THREADS=1` and
`VINIX_ANDROID_TRACE_OBJECT_CLASS=1` in a separately identified diagnostic
launcher can sample `MapsActivity.bB.b` and log
`ANDROID-WS-TRANSITION-FUTURE done=...`. These flags must reach the ART child at
launch. Queue snapshots stop after 12 samples and thread dumps after 300 seconds,
so the category interaction must occur early. Existing surface-field diagnostics
stop after three visits and may be exhausted during onboarding. This follow-up
was inspected only; it was not launched as part of Maps333.
No further guest was started after collection failed: available host storage
continued to fluctuate below the existing generation threshold. Complete
evidence was retained without deleting prior bundles or lowering that gate.
