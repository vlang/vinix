// Defaults for Firefox on Vinix. These mirror run-firefox's environment for
// code paths whose sandbox/rendering policy is preference-driven.
pref("security.sandbox.content.level", 0);
pref("security.sandbox.gpu.level", 0);
pref("security.sandbox.rdd.level", 0);
pref("security.sandbox.socket.process.level", 0);
pref("media.rdd-process.enabled", false);
pref("layers.acceleration.disabled", true);
pref("gfx.webrender.software", true);

pref("browser.shell.checkDefaultBrowser", false);
pref("browser.startup.homepage_override.mstone", "ignore");
pref("browser.startup.homepage", "file:///root/firefox-smoke.html");
pref("datareporting.healthreport.uploadEnabled", false);
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("toolkit.telemetry.enabled", false);
