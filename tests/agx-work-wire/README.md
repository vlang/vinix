# G13 work-command conversion

Compile the V runner with the AGX host tools on its import path, then supply
the packaged Asahi Linux checkout. No reference code, firmware or GPU work runs.

```sh
v -cc cc -path 'tools/agx-re|@vlib|@vmodules' -o /external/work-run tests/agx-work-wire/run.v
ASAN_OPTIONS=detect_stack_use_after_return=1 /external/work-run --asahi-linux /external/linux-reference
```

The runner derives both versioned command sizes and a complete common-field
map from the Rust declarations through the existing V layout engine. Matching
recurses into nested records even when their sizes stay equal: compute's second
parameter block replaces its last word with a prefix. The preceding source
gate guards packed pointer/integer, event and tag aliases. Record, padding,
array and software-float representations have explicit guards too. This is a
selected source-layout model, not an independently compiled Rust oracle.

Fragment's two new auxiliary-framebuffer words receive the literal read from
the reference render builder. Their offsets come from the nested source
layouts. All other new fields stay zero; the expected map never reads native
copy ranges or adapts to firmware-module overlays.

The ASan/UBSan fixture executes real converters for 12,000 complete byte images
with nonzero source patterns, five full-width counters and four guarded source
alignments. Every common declared byte, including reserved padding, is checked;
new fields use their modeled defaults and aggregate padding stays zero. Source
bytes and guards must remain unchanged. This verifies conversion, not the allocating native job initializer,
firmware interpretation or actual GPU addresses/lifetimes.

`--kind vertex|compute|fragment` selects one converter; `all` is the default
and `both` retains the earlier vertex/compute selection. `--fw-overlay PATH`
substitutes `vertex.v`, `compute.v` and/or `fragment.v` in a temporary firmware
module copy while keeping the same reference-derived expected map, for exact-old-code counterexamples.
The model always comes from `--asahi-linux` and is not adapted to an overlay.

Retain outputs with `AGX_WORK_WIRE_BINARY`, `AGX_WORK_WIRE_C`,
`AGX_WORK_WIRE_MODEL` and `AGX_WORK_WIRE_REPORT`, all external file paths.
