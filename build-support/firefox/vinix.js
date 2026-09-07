// Defaults for Firefox on Vinix. These mirror run-firefox's environment for
// code paths whose sandbox/rendering policy is preference-driven.
pref("security.sandbox.content.level", 0);
pref("security.sandbox.gpu.level", 0);
pref("security.sandbox.rdd.level", 0);
pref("security.sandbox.socket.process.level", 0);
pref("media.rdd-process.enabled", false);
pref("layers.acceleration.disabled", true);
pref("gfx.webrender.software", true);
pref("gfx.x11-egl.force-disabled", true);
// Vinix has no desktop accessibility bus. Avoid asking GTK to create one.
pref("accessibility.force_disabled", 1);

pref("browser.shell.checkDefaultBrowser", false);
pref("browser.startup.homepage_override.mstone", "ignore");
pref("browser.startup.homepage", "file:///root/firefox-smoke.html");
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
