// SPDX-License-Identifier: GPL-2.0-or-later
// This replaces only the desktop's sample launcher, never the APK.
module main

import os
import time

fn main() {
os.setenv('VINIX_ANDROID_TRACE_VIEW_LOOKUP', '1', true)
os.setenv('LOOKUP_EXPECT_TRACE', '1', true)
	id := os.read_file('/opt/android-test/popular-id')!.trim_space()
	println('APK-SUITE-BEGIN id=${id} backend=vinix-ws')
	mut app := os.new_process('/usr/bin/run-android')
	app.set_args(['/opt/android-test/application.apk'])
	app.run()
	mut observed := false
	mut contaminated := false
	for app.is_alive() {
		maps := os.read_file('/proc/${app.pid}/maps') or { '' }
		if maps.contains('libvinix-android-native.so') {
			if !observed {
				println('APK-SUITE-MAPS id=${id} pid=${app.pid} native=present')
				observed = true
			}
			if maps.contains('libgtk') || maps.contains('libgdk') || maps.contains('libX11') {
				println('APK-SUITE-DEPENDENCY-FAIL id=${id}\n${maps}')
				contaminated = true
				app.signal_term()
			}
		}
		time.sleep(100 * time.millisecond)
	}
	app.wait()
	println('APK-SUITE-EXIT id=${id} code=${app.code} native_observed=${observed} gtk_x11_absent=${!contaminated}')
	exit(if contaminated { 1 } else { app.code })
}
