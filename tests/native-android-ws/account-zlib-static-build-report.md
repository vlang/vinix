# Account metadata zlib construction

The retained producer in `build-account-zlib.v` was committed as `c3c501754` and
built from repository revision `8f700726447c1f901faff30071069a621152b86f`.
It builds the pinned upstream zlib 1.3.1 archive as AArch64 musl PIC objects.

- Bundle: `/Users/alex/.local/state/vinix/android/account-zlib-static-build-2026-10-26-r1`
- `sha256.json` seal: `f2652acfdf8963998d51d767990ac72daae4c54a9ee6e956327cdf2ee462272f`
- Source archive: `d9e270d46252734aa49770fbc544125391617956266f220bd63216c834f3a522`
- `lib/libz.a`: `40238b02e19ba4776180f997828faadddc5347f379b70b031ef8629b6e75fee0`
- `native/zlib.h`: `8a5579af72ea4f427ff00a4150f0ccb3fc5c1e4379f726e101133b1ab9fc600c`
- `native/zconf.h`: `f5134250a67d57459234b63858f0d9d3ef8dcc48e9e1028d3f4fdcf6eae677ae`

Host compilation and `--self-test` passed, including malformed archive/ELF/export
rejection, frozen dependency checks, and archive/header inventory drift tests.
The producer passed all 15 source compilations, before/after dependency checks,
exact archive member/object comparisons, and static/shared whole-archive links.
The static probe has no dynamic dependencies; the shared probe requires no
dynamic zlib. Both probes were linked only. Independent source review found no
material correctness issue.

The bundle retains the source archive and extracted source, provenance receipt,
builder source/binary, compiler and binutils, headers and link resources, compile
arguments, dependency closures, archive members and command logs. Core compiler
inputs/specs are pinned to the retained headless service r5 receipt; additional
cross tools and headers are captured and checked before/after this build.

Recheck the complete bundle with its retained executable:

```text
BUNDLE/builder --check BUNDLE f2652acfdf8963998d51d767990ac72daae4c54a9ee6e956327cdf2ee462272f
```

The retained `--check` passed for this seal. It verifies inventory integrity.
Consumers must also check the producer
kind, source/compiler pins, AArch64/PIC metadata and exact three output digests.
Host loader libraries remain environmental inputs. This construction provides
no guest execution or Google account sign-in evidence.
