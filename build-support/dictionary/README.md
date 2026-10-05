# Offline Dictionary data

Both desktop image builders run `prepare.py` to install an offline lexicon at
`/usr/share/vinix/dictionary/dictionary.vnd`, with `LICENSE.WordNet` beside it.
The guest never downloads dictionary data. The host caches the pinned WordNet
3.0 archive under `build/dictionary`, verifies its SHA-256, and derives the same
147,306 headwords on each build. A failed download or invalid archive fails the
image build instead of installing an empty dictionary.

The source is [WordNet 3.0](https://wordnetcode.princeton.edu/3.0/WordNet-3.0.tar.gz),
used under its [database license](https://wordnet.princeton.edu/license-and-commercial-use).
The archive's complete license is preserved unchanged with the generated data.
Headwords combine the source's noun, verb, adjective and adverb senses. Underscores
become spaces and adjective position markers are removed. Definitions retain
the gloss and related headwords. This is a lexical database, without
pronunciation audio, morphological expansion or encyclopedic articles.

To stage data separately:

```sh
python3 build-support/dictionary/prepare.py --destination build/dictionary/staged
```

`--archive=PATH` accepts only the same verified upstream archive. The format is
`VNXDICT1`: an eight-byte magic followed by four little-endian 32-bit values
(entry count, key byte count, definition byte count, zero reserved field).
Each 16-byte index record contains key offset/length and definition
offset/length relative to their respective payload blocks. The index, sorted
UTF-8 headwords and UTF-8 definitions follow the 24-byte header in that order.
Payload offsets are contiguous; no trailing data is permitted. Files are
bounded to 64 MiB, 200,000 entries, 128 bytes per headword and 64 KiB per
definition. Dictionary validates the index before replacing a loaded source.

The app keeps only index/headword bytes and the current definition in memory.
It uses bytewise sorted lookup with ASCII case folding, word/phrase prefix
suggestions, bounded history, wrapped definition paging and exclusive text
exports. Changed or malformed sources preserve the last successful lookup.
