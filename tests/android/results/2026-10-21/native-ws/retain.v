// SPDX-License-Identifier: GPL-2.0-or-later
// Hash measured artifacts and retain logs. Workflow verdicts are authored
// separately after inspecting real input actions and framebuffer captures.
module main

import compress.gzip
import crypto.sha256
import json2
import os

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn main() {
	if os.args.len != 2 { panic('usage: retain CHECKS.json (from repository root)') }
	output := 'tests/android/results/2026-10-21/native-ws'
	mut report := json2.decode[map[string]json2.Any](os.read_file(os.args[1])!)!
	mut applications := []json2.Any{}
	for entry in report['applications']!.as_array() {
		mut app := entry.as_map().clone()
		name := app['id']!.str()
		serial_path := app['serial_source']!.str()
		serial := os.read_bytes(serial_path)!
		log := serial.bytestr()
		for failure in ['ANDROID-WS-FAIL', 'ANDROID-WS-DEPENDENCY-FAIL', 'ANDROID-WS-PROCESS-FAIL',
			'UnsatisfiedLinkError', 'JNI DETECTED ERROR', 'NoSuchMethodError', 'NoSuchFieldError'] {
			if log.contains(failure) { panic(name + ': ' + failure) }
		}
		if !log.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
			|| !log.contains('gtk=absent gdk=absent x11=absent') {
			panic(name + ': missing runtime or process map evidence')
		}
		app['apk_sha256'] = digest(app['apk']!.str())!
		app['serial_sha256'] = sha256.sum(serial).hex()
		os.write_file_array(output + '/' + name + '.serial.log.gz', gzip.compress(serial)!)!
		app['serial_log'] = name + '.serial.log.gz'
		mut frames := []json2.Any{}
		for frame in app['screenshots']!.as_array() {
			path := frame.str()
			frames << json2.Any({
				'path':   json2.Any(path)
				'sha256': json2.Any(digest(path)!)
			})
		}
		app['screenshots'] = frames
		applications << json2.Any(app)
	}
	report['applications'] = applications
	mut artifacts := map[string]json2.Any{}
	for path in ['libvinix-android-native.so', 'libdl_bio.so.0', 'vinix-android-native', 'run-android',
		'api-impl.jar', 'vinix-desktop', 'guest-kernel', 'androidfw_c_api.h', 'stb_truetype.h',
		'stb_image.h', 'sqlite3.h'] {
		artifacts[path] = digest('build/android-native-ws/' + path)!
	}
	report['artifacts_sha256'] = artifacts
	mut sources := map[string]json2.Any{}
	for directory in ['build-support/android/nativews', 'build-support/android/wsloader'] {
		for path in os.walk_ext(directory, '.v') { sources[path] = digest(path)! }
	}
	for path in ['build-support/android/native-entry.v', 'build-support/android/native-run.v',
		'build-support/android/nativews/bindings.txt', 'desktop/android_app.v',
		'tests/native-android-tools/androidtools/native_ws.v', 'tests/native-android-ws/guest.v'] {
		sources[path] = digest(path)!
	}
	report['sources_sha256'] = sources
	os.write_file(output + '/apk-workflows.json', json2.encode(report, prettify: true) + '\n')!
}
