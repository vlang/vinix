// SPDX-License-Identifier: GPL-2.0-or-later
// Retain actual observations and manually reviewed root causes. No proprietary
// APKs are copied into the repository and no startup observation becomes a pass.
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	if os.args.len < 4 { panic('usage: retain-suite OUTPUT_DIR REVIEW.json BATCH_DIR...') }
	output := os.args[1]
	reviews := json2.decode[map[string]json2.Any](os.read_file(os.args[2])!)!
	os.mkdir_all(output)!
	mut merged := map[string]json2.Any{}
	for directory in os.args[3..] {
		for value in json2.decode[[]json2.Any](os.read_file(directory + '/results.json')!)! {
			app := value.as_map()
			merged[app['id']!.str()] = value
		}
	}
	mut ids := merged.keys()
	ids.sort()
	mut apps := []json2.Any{}
	for id in ids {
		mut app := merged[id]!.as_map().clone()
		if app['outcome']!.str() == 'harness_failure' || app['outcome']!.str() == 'package_inspection_failed' {
			panic(id + ': unresolved test setup failure')
		}
		serial := app['serial_log']!.str()
		os.cp(serial, output + '/' + id + '.serial.log.gz')!
		app['serial_log'] = id + '.serial.log.gz'
		frame := app['screenshot']!.str()
		os.cp(frame, output + '/' + id + '.png')!
		app['screenshot'] = id + '.png'
		assert digest(output + '/' + id + '.png')! == app['screenshot_sha256']!.str()
		mut metadata := app['metadata']!.as_map().clone()
		// Older first-batch metadata retained the exact manifest lines but did
		// not recognize the new requiredSplitTypes attribute's boolean meaning.
		lines := metadata['split_manifest']!.as_array().map(it.str())
		required := lines.any(it.contains('requiredSplitTypes') || it.contains('com.android.vending.splits.required') || (it.contains('isSplitRequired') && it.contains('true')))
		metadata['split_required'] = required
		app['probe_scope'] = if required || (app['split_apks'] or { json2.Any([]json2.Any{}) }).as_array().len > 0 {
			'base APK startup; split installation is unimplemented'
		} else {
			'standalone APK startup'
		}
		app['metadata'] = metadata
		// A separate, authored review supplies functional verdicts. The
		// collector cannot decide that a framebuffer is a working app.
		for key, value in reviews[id]!.as_map() { app[key] = value }
		apps << json2.Any(app)
	}
	mut artifacts := map[string]json2.Any{}
	for name in ['libvinix-android-native.so', 'libdl_bio.so.0', 'api-impl.jar', 'vinix-desktop',
		'guest-kernel', 'run-android', 'vinix-android-native', 'guest', 'popular-launcher'] {
		artifacts[name] = digest('build/android-native-ws/' + name)!
	}
	os.cp('build/android-native-ws/test-tools.json', output + '/tools-sha256.json')!
	mut sources := map[string]json2.Any{}
	for name in ['suite.v', 'launcher.v', 'guest.v', 'popular-apps.json', 'retain-suite.v'] {
		sources[name] = digest('tests/native-android-ws/' + name)!
	}
	os.write_file(output + '/results.json', json2.encode({
		'date':             json2.Any('2026-10-21')
		'scope':            json2.Any('ARM64 Vinix QEMU/HVF startup probes of popular Google Play app identities. 12 GiB RAM, 16 KiB pages, native WS; no GTK/X11. No Play Store login, account creation or functional certification. Required splits are explicitly identified; base-only probes are not complete-package tests.')
		'applications':     json2.Any(apps)
		'artifacts_sha256': json2.Any(artifacts)
		'sources_sha256':   json2.Any(sources)
	}, prettify: true) + '\n')!
}
