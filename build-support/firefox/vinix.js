// Defaults for Firefox on Vinix. These mirror run-firefox's environment for
// code paths whose sandbox/rendering policy is preference-driven.
pref("security.sandbox.content.level", 0);
pref("security.sandbox.gpu.level", 0);
pref("security.sandbox.rdd.level", 0);
pref("security.sandbox.socket.process.level", 0);
pref("media.rdd-process.enabled", false);
// Vinix has no desktop accessibility bus. Avoid asking GTK to create one.
pref("accessibility.force_disabled", 1);

// Firefox draws with software WebRender: Vinix has no GPU driver for it.
// Keeping GL, EGL, DMA-BUF and VA-API out also keeps Mesa out of the
// browser. Its libgallium links LLVM 19 while the DRI drivers link LLVM 17,
// and musl, which ignores symbol versions, lets one LLVM's code run on the
// other's objects: the parent process crashed in LLVM's constructors
// before it drew a window.
pref("gfx.webrender.software", true);
pref("gfx.x11-egl.force-disabled", true);
pref("layers.acceleration.disabled", true);
pref("webgl.disabled", true);
pref("widget.dmabuf.enabled", false);
pref("widget.dmabuf-textures.enabled", false);
pref("widget.dmabuf-webgl.enabled", false);
pref("media.hardware-video-decoding.enabled", false);
pref("media.ffmpeg.vaapi.enabled", false);
// Content processes otherwise map their JIT code writable and executable at
// once, which Vinix's W^X policy refuses; SpiderMonkey reported that as
// running out of memory and every tab crashed. Flip the pages between
// writable and executable instead, as the parent process already does.
pref("javascript.options.content_process_write_protect_code", true);

pref("browser.shell.checkDefaultBrowser", false);
pref("browser.startup.homepage_override.mstone", "ignore");
pref("browser.startup.homepage", "file:///usr/share/vinix/firefox-smoke.html");
// Vinix can browse normally, but its early pthread/VM implementation is not
// ready for Firefox's periodic classifier/database maintenance workers. Keep
// those optional background jobs off instead of letting them take down an
// otherwise usable browser session.
pref("browser.safebrowsing.phishing.enabled", false);
pref("browser.safebrowsing.malware.enabled", false);
pref("browser.safebrowsing.downloads.enabled", false);
pref("browser.safebrowsing.downloads.remote.enabled", false);
pref("browser.safebrowsing.provider.google.updateURL", "");
pref("browser.safebrowsing.provider.google4.updateURL", "");
pref("browser.safebrowsing.provider.mozilla.updateURL", "");
pref("places.history.enabled", false);
pref("app.update.enabled", false);
pref("extensions.update.enabled", false);
pref("datareporting.healthreport.uploadEnabled", false);
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("toolkit.telemetry.enabled", false);
