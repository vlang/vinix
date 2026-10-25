# SuperscriptSpan for Google Maps styled text

Maps345 uses qualified TouchDelegate344, feature revision `4daf1e4fb`, and reaches
the Paris map, Attractions results and a place details sheet. Later rendering
fails with `NoClassDefFoundError: android.text.style.SuperscriptSpan`, at
`ashh.<clinit> → ashh.a → atze.a → bgzb.h`. The selected actual caller constructs
only `SuperscriptSpan()` for a `*` inside a SpannableStringBuilder, then copies
that text into a SpannableString. The [actual caller report](superscript-span346-callers.md)
records its authenticated DEX evidence.

The repair adds one generic SuperscriptSpan class. It extends MetricAffectingSpan,
supports the empty Parcel ABI and span type 14, and adds half the virtual paint
ascent, truncated toward zero, to the existing TextPaint baseline shift. Both
paint updates save the previous shift before invoking `ascent()`, preserving Java
compound-assignment behavior even when an override changes that field. The
[official source proof](superscript-span346-contract.md) records the verified
contract. Native text rendering is unchanged; this test does not establish
visible superscript positioning or successful Maps replay.

One signed three-class APK runs on actual ART against both frameworks. Its first
operation constructs the exact class missing in Maps, before any success marker.
The fixed checks cover inheritance and Parcelable interfaces, public/internal
type IDs, underlying span identity, diagnostic string, builder range/flags and
copying. Paint checks cover negative and positive fractional ascent, truncation,
zero, repeated and wrapped updates, virtual dispatch with a field-changing
override, preserved text size/color/density, real negative native font ascent,
and null paint. Both Parcel writers must preserve an independent sentinel and
data position; Parcel construction must consume no payload, including null
Parcel inputs.

The runner derives the complete frozen compiler, V closure, C inputs and assets
from qualified344. Preparation passed on its first attempt with the same 640 V
input pins before and after compilation. Complete generated DEX comparison adds
only SuperscriptSpan, increasing the class count from 2069 to 2070; all 2069
existing classes are identical after disassembly. The duplicate-application
guard rejects a second application without mutation. The framework JAR is the
only guest runtime delta.

Prepared artifacts are retained at
`/Users/alex/.local/state/vinix/android/superscript-span346-2026-10-25`:

| Artifact | SHA-256 |
| --- | --- |
| Baseline344 framework JAR | `12c5d03030f5f081415bda5c51e32279e70a17aead822c06925512ed6226ef8f` |
| Fixed346 framework JAR | `b33472257a59c9b8dffca155c2f1ecd77e0f10c3dae230a23a3afafee9e7c840` |
| Same signed three-class fixture APK | `0af6331dc48538a4e2f070bc56d0001457ea48c86e6537067963a2a9f324b3c1` |
| Executed checked runner | `6bf7a622c4ac9c908ca531c0410657dd77f8698f454595d45bd9e1fe47231ed7` |
| Executed frozen runner source | `d1b40b6e899ad4c522e72558865c6154af21c1bca182e6d424fb670b15253662` |

Both actual ART runs pass their semantic checks. The old framework fails exactly
once at class construction with the expected activity-start wrapper and no
success markers. The fixed framework prints all four success markers and remains
alive through the 35-second observation window, with no failure markers. Both
runs use the same signed APK. The old raw serial SHA-256 is
`43903189fbd7ba94bbb1f06f64635a71b6642ff4044394e292ad68873942630d`;
the fixed raw serial is
`cef76c230e8c4f95c6b77e6d5c86799d355a1b379134cb2c97465aad389eafee`.

The final bundle contains 8,551 files, sealed by `sha256.json` with SHA-256
`6d5205fce48faea0c406efb68ec9134c039aa106e591d20e4501f2826d65064b`.
Complete readback passed independently for the runner, root review, and peer
review. Their receipts are retained beside the bundle as
`superscript-span346-complete-readback-2026-10-25.json`,
`superscript-span346-root-readback-2026-10-25.json`, and
`superscript-span346-peer-readback-2026-10-25.json`.
