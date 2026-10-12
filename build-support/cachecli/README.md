# Native cache command policy

`content-key.v`, `staging-cache.v` and `desktop-build-key.v` call this module
directly. `desktop/tools/officenative` shares its argument parser, signal guard
and atomic state publisher. Tree fingerprints and production-source selection
remain in `cachekey`. Commands run through `tools/sourcecommand` with explicit
argv, bounded capture and private process-group retirement.

See [qualification and cache format changes](../../desktop/tools/native-cache-tools.md).
