// SPDX-License-Identifier: GPL-2.0-or-later
// This replaces only the desktop's sample launcher, never the APK.
module main

import os
import time

fn main() {
 os.setenv('VINIX_ANDROID_TRACE_SURFACE_FIELDS', 'b.b.b.0.e.t.j,b.b.b.0.e.t.w,b.b.b.0.e.t.c,b.b.b.0.e.t.m,b.b.b.0.e.t.n,b.b.b.0.e.t.o,b.b.b.0.e.t.p,b.b.b.0.e.t.q,b.b.b.0.e.t.r,b.b.b.0.e.t.s,b.b.b.0.e.t.t,b.b.b.0.e.t.u,b.b.b.0.e.t.y,b.b.b.0.e.t.z,b.b.b.0.e.t.f,b.b.b.0.e.t.v', true)
 os.setenv('VINIX_ANDROID_TRACE_VIEW_ADDS', 'com.google.android.material.progressindicator.CircularProgressIndicator', true)
 os.setenv('VINIX_ANDROID_TRACE_OBJECT_CLASS', 'avpv,avpt,avpy,avos,avhu,nfk', true)
 os.setenv('VINIX_ANDROID_TRACE_OBJECT_ROOT', 'bA.a', true)
 os.setenv('VINIX_ANDROID_TRACE_TLS', '1', true)
 os.setenv('VINIX_ANDROID_TRACE_TREE', '1', true)
 os.setenv('VINIX_ANDROID_TRACE_SURFACE_DUMP', 'tI', true)
	os.setenv('VINIX_ANDROID_TRACE_THREADS', '1', true)
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
