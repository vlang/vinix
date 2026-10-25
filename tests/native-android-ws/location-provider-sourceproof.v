// SPDX-License-Identifier: GPL-2.0-or-later
// Read back the complete retained location322 source bundle. This proves source
// contracts and a static SDK29 inference, not a runtime SDK observation.
module main

import crypto.sha256
import json2
import os

const seal = '3f50b9053bb437c6c0e525a634104b3a950770a67fcb36c1fc573f18b132b3f7'
const android29 = '57bb140be9e48cf08acba131f7463e461777bb8e'
const android30 = '34a1b9c951c38537ab96b69bc308f6e0884823f5'
const modern = '1cdfff555f4a21f71ccc978290e2e212e2f8b168'

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn inventory(root string, prefix string, mut files []string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut files)! }
			.regular { files << key }
			else { return error('nonregular evidence: ' + key) }
		}
	}
}

fn contains(root string, path string, fragments []string) ! {
	text := os.read_file(root + '/' + path)!.fields().join(' ')
	for fragment in fragments {
		assert text.contains(fragment.fields().join(' ')), path + ': ' + fragment
	}
}

fn main() {
	$if prod { panic('requires assertions; compile without -prod') }
	assert os.args.len == 3, 'RETAINED_BUNDLE FRESH_EXTERNAL_RECEIPT.json'
	root := os.abs_path(os.args[1])
	receipt := os.abs_path(os.args[2])
	assert !receipt.starts_with(root + '/') && receipt != root
	assert !os.exists(receipt) && !os.is_link(receipt)
	assert !os.is_link(root) && os.is_dir(root)
	assert hash(root + '/sha256.json')! == seal
	pins := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	assert pins.len == 30, 'complete original bundle required'
	mut actual := []string{}
	inventory(root, '', mut actual)!
	actual.sort()
	mut expected := pins.keys()
	expected << 'sha256.json'
	expected.sort()
	assert actual == expected, 'missing or extra evidence'
	for path, pin in pins {
		assert !path.starts_with('/') && '..' !in path.split('/')
		assert hash(root + '/' + path)! == pin, path
	}
	assert os.read_file(root + '/before.json')! == os.read_file(root + '/after.json')!
	downloads := json2.decode[map[string]json2.Any](os.read_file(root + '/downloads.json')!)!
	assert downloads.len == 11
	for path, value in downloads {
		item := value.as_map()
		assert item['http_status']!.int() == 200
		assert item['sha256']!.str() == pins[path]!
		text := os.read_file(root + '/' + path)!
		assert text.len == item['bytes']!.int()
		assert text.split_into_lines().len == item['lines']!.int()
		revision := if path.starts_with('29-') { android29 } else if path.starts_with('30-') {
			android30
		} else if path.starts_with('modern-') { modern } else {
			'899eecd41a6bf506766dfa64f9f17173add74cbc'
		}
		assert item['url']!.str().starts_with('https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/' + revision + '/')
	}
	for name, revision in { 'tag29-resolution.json': android29, 'tag30-resolution.json': android30 } {
		tag := json2.decode[map[string]json2.Any](os.read_file(root + '/' + name)!)!
		assert tag['exit_code']!.int() == 0
		assert tag['output']!.str().contains(revision + '\trefs/tags/android-')
	}
	contains(root, '29-LocationManagerService.java', [
		'if (!hasGnssPermissions(packageName) || gnssDataProvider == null) { return false; }',
		'throw new IllegalArgumentException("provider doesn\'t exist: " + name);',
		'LocationProvider provider = getLocationProviderLocked(name); if (provider == null) return null;',
		'if (providerName == null) { // throw NullPointerException to remain compatible with previous implementation throw new NullPointerException(); }',
		'if (provider != null) { provider.sendExtraCommandLocked(command, extras); } mLocationUsageLogger.logLocationApiUsage( LocationStatsEnums.USAGE_ENDED, LocationStatsEnums.API_SEND_EXTRA_COMMAND, providerName); return true;',
	])!
	contains(root, '29-LocationManager.java', [
		'super(handler != null ? handler.getLooper() : Looper.myLooper());',
		'checkProvider(provider); checkListener(listener);',
	])!
	contains(root, '29-Handler.java', [
		'mLooper = Looper.myLooper(); if (mLooper == null) { throw new RuntimeException(',
		'mLooper = looper; mQueue = looper.mQueue;',
	])!
	contains(root, '30-LocationManagerService.java', [
		'return mGnssManagerService != null && mGnssManagerService.registerGnssStatusCallback( listener, packageName, featureId);',
	])!
	contains(root, 'selected/disassembled-318/android/os/Build$VERSION.smali', [
		'"Build.VERSION.SDK_INT"', '"atl.app.class.path"',
		'Landroid/atl/EarlyPackageParser;->parseMinSdkInt(Ljava/io/File;I)I',
	])!
	contains(root, 'selected/disassembled-318/android/atl/EarlyPackageParser.smali', [
		'"uses-sdk"', '"minSdkVersion"',
	])!
	runtime := os.read_file(root + '/selected/native/atlframework/runtime.v')!
	assert runtime.contains('-Datl.app.class.path=%s') && !runtime.contains('Build.VERSION.SDK_INT')
	contains(root, 'maps-apk-badging.txt', ["minSdkVersion:'29'", "targetSdkVersion:'37'"])!
	before := json2.decode[map[string]string](os.read_file(root + '/before.json')!)!
	assert before['/Users/alex/code/vinix/build/android-maps/GoogleMaps.apk']! == '6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2'
	conclusions := json2.decode[map[string]string](os.read_file(root + '/conclusions.json')!)!
	assert conclusions['sdk']!.contains('Inference, not runtime log.')
	assert conclusions['modern']!.contains('modern revision, not Android11')
	// The immutable bundle already retains source bytes authenticated against
	// original315/318 manifests. Do not reinterpret it as a complete build audit.
	selected := json2.decode[map[string]string](os.read_file(root + '/selected-inputs.json')!)!
	assert selected.len == 5
	for path, pin in selected {
		key := if path.contains('/tts-span318-v2-framework-build-2026-10-25/') {
			path.all_after('/tts-span318-v2-framework-build-2026-10-25/')
		} else { path.all_after('/nine-patch-tint315-native-build-2026-10-25/') }
		assert pins['selected/' + key]! == pin
	}
	assert hash(root + '/sha256.json')! == seal
	os.write_file(receipt, json2.encode({
		'result': json2.Any('LOCATION322-SOURCEPROOF-PASS')
		'bundle': json2.Any(root)
		'manifest_sha256': json2.Any(seal)
		'files_checked': json2.Any(pins.len)
		'checker_sha256': json2.Any(hash(os.executable())!)
		'scope': json2.Any('Complete retained source bundle; static SDK29 inference only. No runtime SDK sample, build audit, provider, callback or Maps success claim.')
	}, prettify: true) + '\n')!
	println('LOCATION322-SOURCEPROOF-PASS files=' + pins.len.str())
}
