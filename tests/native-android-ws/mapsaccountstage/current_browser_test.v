// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

fn test_browser_engine_manifest_changes_only_the_selected_file_digest() {
	previous, selected := '1'.repeat(64), '2'.repeat(64)
	original := 'vinix-android-browser-launch-v1\nexclusive-principal\t10013\t10013\t/var/lib/vinix/apps/10013/data\n' +
		'root\t/opt/vinix-google-browser\nengine\tbin/webview-engine\nxvfb\tusr/bin/Xvfb\n' +
		'file\t' + previous + '\tbin/webview-engine\nexternal\t' + previous + '\t/usr/bin/bwrap\n'
	updated := browser_engine_manifest(original, previous, selected)!
	assert updated == original.replace('file\t' + previous + '\tbin/webview-engine\n',
		'file\t' + selected + '\tbin/webview-engine\n')
	assert updated.contains('external\t' + previous + '\t/usr/bin/bwrap\n')
	assert updated.contains('exclusive-principal\t10013\t10013\t/var/lib/vinix/apps/10013/data\n')
	for invalid in [original.replace('engine\tbin/webview-engine\n', ''),
		original + 'engine\tbin/webview-engine\n', original.replace('root\t/opt/vinix-google-browser\n', ''),
		original + 'file\t' + previous + '\tbin/webview-engine\n',
		original + 'file\t' + selected + '\tbin/webview-engine\n',
		original.replace('file\t' + previous, 'file\t' + selected)] {
		mut rejected := false
		browser_engine_manifest(invalid, previous, selected) or { rejected = true }
		assert rejected
	}
	for invalid in ['', 'A'.repeat(64), '3'.repeat(63), '3'.repeat(65)] {
		mut rejected := false
		browser_engine_manifest(original, previous, invalid) or { rejected = true }
		assert rejected
	}
}
