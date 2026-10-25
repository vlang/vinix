# LocaleSpan342 primary-source contract

The V sourceproof captured official AOSP sources on 2026-10-25 and passed a
complete 642-file checksum readback. It adds no framework behavior or runtime
qualification. The retained helper source is SHA256
`71d98fd6d29e346d5c67abbce6c4ac1d5c48d0adca38c10dc42abbc4a72cf84d`;
the checkout baseline at review was `f341119d58cc137329d363ec8412b0f7183aabb9`.

The external bundle is
`/Users/alex/.local/state/vinix/android/locale-span342-contract-2026-10-25`.
Its `sha256.json` is
`899b7ce742983c3c80de73523977b050d1a64b368d3617337e2444d1aa4a84ce`.
The sibling `locale-span342-contract-complete-readback-2026-10-25.json` records
PASS. The bundle retains source and executable, actual V compilation arguments,
compiler hash/version/input closure, generated C, official ref resolution,
download URLs and timestamps, raw Gitiles responses, decoded sources and hashes.

Official main resolved to `1cdfff555f4a21f71ccc978290e2e212e2f8b168`.
[LocaleSpan.java](https://android.googlesource.com/platform/frameworks/base/+/1cdfff555f4a21f71ccc978290e2e212e2f8b168/core/java/android/text/style/LocaleSpan.java)
has Git blob `489ceeaa55429359d9775e7fc1a15ee801337d8f` and SHA256
`8b95d2042c8d63fb049588e635773253bd9349bdd948f7cae233956a0a1c7e5f`.
It accepts a null Locale as an empty list, rejects a null LocaleList, returns
the first locale or null, and sends both paint updates directly to
`Paint.setTextLocales`. Its parcel methods delegate to LocaleList.
[TextUtils.java](https://android.googlesource.com/platform/frameworks/base/+/1cdfff555f4a21f71ccc978290e2e212e2f8b168/core/java/android/text/TextUtils.java)
assigns span id 23 and reads that id using the LocaleSpan parcel constructor.

The official Android 7 and 8 LocaleList sources are identical Git blob
`2dc3bebb2d10a4a0eee9a959c6691c989433dc1e`, SHA256
`a46011071172e31c6386da70621122b634611ad186e0a598cf2afafb4587d4f4`:
[Android 7](https://android.googlesource.com/platform/frameworks/base/+/0813c5aaa9ee870a4bac375e462c296aa28ef6a6/core/java/android/os/LocaleList.java),
[Android 8](https://android.googlesource.com/platform/frameworks/base/+/899eecd41a6bf506766dfa64f9f17173add74cbc/core/java/android/os/LocaleList.java).
Both encode one language-tag string with `writeString` and decode it with
`forLanguageTags(readString())`. This supports equivalent direct encoding in
LocaleSpan while leaving the existing LocaleList parcel stubs unchanged.

The independently reviewed provider and fixture cover the nullable constructors,
ordered list and first-locale getters, span type and range, draw/measure dispatch,
preserved Paint size/color/density, empty-list rejection by existing Paint, both
parcel writers, wire format, roundtrip and independently written parcel input.
The dependency review used sealed338 Paint and LocaleList disassembly; it does
not claim native locale-sensitive text shaping.

Reproduce with the V helper's `capture FRESH_EXTERNAL_DIRECTORY` command. Verify
the complete original bundle using `verify BUNDLE MANIFEST_SHA FRESH_RECEIPT`.
