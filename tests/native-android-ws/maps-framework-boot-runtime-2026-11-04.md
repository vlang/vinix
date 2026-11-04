# Framework boot ARM bootstrap failure

The prepared framework boot-classpath pair booted successfully, but the signed
ARM fixture failed at `ANDROID-WS-FAIL load JNI backend`, before its assertions.
No success receipt, GMS run, manual Maps launch, imagery or account result is
established. The complete child log and stopped VM are preserved.

Source base `d97a10485` includes core `992b426c3`, SDK `a16baf6c3`, fixture
`63ba81754`, delivery `133c69c0a` and the [qualified pair](framework-boot-pair-2026-11-03.md).
The user replied **continue** directly to the concrete 64 GiB coexistence
request. The [qualified runner](../android-webview-browser-probe/coexist-64g-2026-11-04.md)
admitted separate CI PID 6395 and launched owned VM PID 49058 at 12:13 UTC.
Both launch snapshots retain the 64 GiB/half-host allowance, 44 GiB aggregate
declared guest RAM, 128 GiB host RAM, 18 logical CPUs and normal pressure.
This is snapshot admission, not continuous monitoring. CI was never modified,
connected to or signalled. The mode has a live launch/stop observation;
fixture and Maps functionality remain separate.

Paths use `S=/Users/alex/.local/state/vinix/android`. Complete roots are
`maps-framework-boot-runtime-audit-2026-11-04-r3` (`A`), matching live controls
(`C`), `maps-framework-boot-vm-2026-11-04-r1` (`VM`) and
`bootclasspath-api-transfer-live-2026-11-04-r1`. Four original clone sidecars
remain at sibling paths and are copied into `A/clone-sidecars`. Historical
complete bundles and original auditors remain required.

UID/GID 10154, account and paths were unused before provisioning. The mount
was verified read-only with `nosuid,nodev,wxallowed` and without `noexec`.
Both downloads matched their pins; transfer completed exactly two HTTP 200
responses. After its input prechecks, the runner reached bootclasspath BEGIN,
then reported `ONBOARDING-API-RUN-FAIL child failure marker: -FAIL`. It produced
no success receipt or automatic service-query export. None of its eleven
receipt checks or fixture assertions is claimed as passed on ARM.

The full private log is `A/failed-fixture-decoded/child.log`, 5,943 bytes,
SHA-256 `082414c7d64af258242136ed82f4f307c898ade5bc1d99e04f61dbdd68c79211`.
The separately captured guest length/hash and complete canonical base64 export
passed the unchanged decoder and fresh retained-decoder readback. UART interval
SHA-256 is `4d0affb6635bfd6cebcd888a2b68b42263a392cb8691d5d0a6f023436ae68fdd`;
diagnostic receipt is
`9d42304b4a32ce96a9d31b8e44d73bd377fb9128723bfcb696bdd4e17eef910a`.
This establishes preservation integrity only. Both guards/children exited zero
with complete cleanup under original 600 MiB RSS, 300-second, 64 MiB growth,
1 GiB reserve and output/file caps. The child timestamps end at 12:16:55 UTC
with JNI backend failure; this is not a startup-deadline result.

The mount was released and a guest process inventory showed no ART child.
Exactly one owned-VM SIGTERM succeeded; `gone.json` records PID 49058 absent
at 12:23:30 UTC, and QEMU records signal 15. Only CI PID 6395 remained.
A subsequent `cleanup-gone` correctly refused a requested disappearance;
no mutation occurred, and QEMU had already removed its socket. Final UART
is 103,775 bytes, SHA-256
`476f798265abe146c93df7c9aa64339ecea9402c499e1ccb3366c773cb150e4a`,
equal to the immutable final full snapshot byte-for-byte.

The four roots passed a 515-entry seal and fresh readback at
`S/maps-framework-boot-runtime-sealed-2026-11-04-r1/sealed/manifest.json`,
SHA-256 `98ed3835f33f1045b1db57e6933cfb92ca703d1db78ffc12d52a0cc2fb311b65`.
Both guards/children exited zero with complete cleanup in 8,074/2,702 ms,
observing 66,314,240/64,811,008 bytes shared growth under the unchanged
64 MiB cap. These roots are closed; future output needs fresh roots.

Source tracing identifies a target-SDK guard in the chosen
`Runtime.load(String, ClassLoader)` overload. The class-based
`load0(Class, String)` validates an absolute filename and uses the defining
class's loader without that guard. Its successor native fix and qualification
are separate work; the original failure and assertions remain intact.
