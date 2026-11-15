# ValueCallback interface candidate, 2026-11-15

Status: prepared source and signed-fixture generator, not compiled or qualified.
The build guard refused to start tooling because the host cannot cover the
retained disk reserve and growth budget. Do not deploy or claim this candidate
passed ARM until its checks run successfully.

The [WebView loader adapter](maps-webview-loader-20261115.md) in 38730c57d passed
the full signed ARM suite in r102 and the real flow progressed beyond the
loader call. GMS then failed during account fragment creation: class attt
implements non-interface class android.webkit.ValueCallback. The actual retained
ValueCallback.smali contains only a concrete class and empty constructor.
The SDK cookie callback already uses invoke-interface for onReceiveValue.

Android defines [ValueCallback<T>](https://developer.android.com/reference/android/webkit/ValueCallback)
as an interface with onReceiveValue(T). The existing ATL Java patch already
states the correct interface, but the retained SDK input predates that patch.
This V adapter accepts either that exact legacy empty class or the correct
interface input, then writes the generic interface with erased
onReceiveValue(Object)V. The new SDK builder checks legacy/correct input,
idempotence, twelve refused mutations, full assembly and DEX readback. These
checks are implemented but have not run.

The signed fixture implements the interface from an application DEX. It checks
reflection shape, generic type parameter and erased return type, real interface
dispatch, the existing VinixCookieCallback wrapper's true/false forwarding and
worker-thread invocation. It does not perform a cookie operation or synthesize
an authentication result. Fixture compilation and ARM execution remain pending.

External evidence root: /Users/alex/.local/state/vinix/android.
Source parent: 38730c57d. Current compiler remains /Users/alex/code/v/v,
V 0.5.2 cbfc1be; no historical compiler requirement is added.

With all owned guests stopped, the read-only 15-second quiet probe
value-callback-host-quiet-20261115-r1 was stopped after 13525 ms with
121544704 bytes observed shared disk growth. Its read-only growth cap was
67108864 bytes; exit/child 125/137, cleanup complete. This is a pressure probe,
not a failed run under the larger build growth allowance.

The original build profile remains RSS 629145600, wall 300000 ms, reserve
1073741824, growth 536870912, output 4194304. Attempt
value-callback-tools-20261115-r1 was refused before launch: initial free
1177317376 bytes, reason "disk growth budget", exit 125, child -1, pid 0 and
no supervised groups. Its cleanup_complete=false does not describe a live
child: no command started. The empty output directory and guard receipt are
retained. No SDK, native library or signed APK for this repair exists yet.

After a quiet window and restored free space, compile the V tooling to a fresh
external tool directory, build against framework-webview-loader-20261115-r1,
rebuild the current native producer and signed shared-display fixture, then run
a fresh signed ARM qualification and full protected account retry. Retain all
original caps, manifests, single-use guards and checked-volume export steps.
All owned test guests are stopped; Google Maps and authentication remain incomplete.
