// SPDX-License-Identifier: GPL-2.0-or-later
// Retain immutable Android10 permission contracts and selected existing policy.
module main

import crypto.sha256
import json2
import net.http
import os

const self = 'tests/native-android-ws/activity-permissions-sourceproof.v'
const revision = 'dff3deab5d25f8bbfd49abfb423043c9be47b7db'
const tag_object = '358c5b9caf1671d3ca8f395fe46fc83341e5e8d4'
const tag = 'refs/tags/android-10.0.0_r47'
const baseline = '/Users/alex/.local/state/vinix/android/tts-span318-v2-framework-build-2026-10-25'
const baseline_seal = '869d22f75a01c7ffd88604a04a73b67cc012daca9651a571e5eab30aafd0594c'
const paths = {
	'Activity.java':       'core/java/android/app/Activity.java'
	'PackageManager.java': 'core/java/android/content/pm/PackageManager.java'
	'ActivityThread.java': 'core/java/android/app/ActivityThread.java'
}
const selected = ['android/app/Activity.smali', 'android/content/pm/PackageManager.smali',
	'android/os/Handler.smali', 'android/os/Looper.smali']

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular entry: ' + key) }
		}
	}
}

fn contracts(root string) ! {
	activity := os.read_file(root + '/Activity.java')!.fields().join(' ')
	for text in [
		'public final void requestPermissions(@NonNull String[] permissions, int requestCode)',
		'if (requestCode < 0)',
		'throw new IllegalArgumentException("requestCode should be >= 0");',
		'if (mHasCurrentPermissionsRequest)',
		'onRequestPermissionsResult(requestCode, new String[0], new int[0]);',
		'getPackageManager().buildRequestPermissionsIntent(permissions)',
		'public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions,',
		'mHasCurrentPermissionsRequest = false;',
	] {
		assert activity.contains(text), text
	}
	negative := activity.index('if (requestCode < 0)') or { panic('negative validation missing') }
	overlap := activity.index('if (mHasCurrentPermissionsRequest)') or { panic('overlap branch missing') }
	intent := activity.index('getPackageManager().buildRequestPermissionsIntent(permissions)') or { panic('permission intent missing') }
	assert negative < overlap && overlap < intent
	pm := os.read_file(root + '/PackageManager.java')!.fields().join(' ')
	assert pm.contains('if (ArrayUtils.isEmpty(permissions))')
	assert pm.contains('throw new IllegalArgumentException("permission cannot be null or empty");')
	activity_thread := os.read_file(root + '/ActivityThread.java')!.fields().join(' ')
	assert activity_thread.contains('ActivityClientRecord r = mActivities.get(token);')
	assert activity_thread.contains('deliverResults(r, results, reason);')
	base := os.read_file(root + '/selected/android/app/Activity.smali')!
	assert base.contains('requestPermissions([Ljava/lang/String;I)V') && base.contains('): not handled')
	assert !base.contains('.method public onRequestPermissionsResult(')
	assert base.contains('isDestroyed()Z') && base.contains('->destroyed:Z')
	policy := os.read_file(root + '/selected/android/content/pm/PackageManager.smali')!
	for text in ['ATL_UGLY_ENABLE_LOCATION', 'android.permission.ACCESS_FINE_LOCATION',
		'android.permission.ACCESS_COARSE_LOCATION', 'android.permission.READ_EXTERNAL_STORAGE',
		'android.permission.WRITE_EXTERNAL_STORAGE'] {
		assert policy.contains(text)
	}
}

fn inputs() !map[string]string {
	mut pins := map[string]string{}
	for path in [os.abs_path(self), os.executable(), '/usr/bin/git', baseline + '/sha256.json'] {
		pins[path] = hash(path)!
	}
	for relative in selected {
		path := baseline + '/disassembled-318/' + relative
		pins[path] = hash(path)!
	}
	return pins
}

fn capture(out string) ! {
	assert !os.exists(out) && !os.is_link(out), out
	assert hash(baseline + '/sha256.json')! == baseline_seal
	pins := json2.decode[map[string]string](os.read_file(baseline + '/sha256.json')!)!
	before := inputs()!
	os.mkdir_all(out + '/selected')!
	write_json(out + '/before.json', before)!
	os.cp(os.abs_path(self), out + '/author.v')!
	os.cp(os.executable(), out + '/author')!
	os.cp(baseline + '/sha256.json', out + '/baseline-sha256.json')!
	for relative in selected {
		assert before[baseline + '/disassembled-318/' + relative]! == pins['disassembled-318/' + relative]!
		os.mkdir_all(os.dir(out + '/selected/' + relative))!
		os.cp(baseline + '/disassembled-318/' + relative, out + '/selected/' + relative)!
	}
	argv := ['/usr/bin/git', 'ls-remote', 'https://android.googlesource.com/platform/frameworks/base',
		tag, tag + '^{}']
	r := os.exec(argv)
	write_json(out + '/tag-resolution.json', {
		'argv':      json2.Any(argv)
		'exit_code': json2.Any(r.exit_code)
		'output':    json2.Any(r.output)
	})!
	assert r.exit_code == 0, r.output
	assert r.output.contains(tag_object + '\t' + tag + '\n')
	assert r.output.contains(revision + '\t' + tag + '^{}')
	mut downloads := map[string]json2.Any{}
	for name, path in paths {
		url := 'https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/' + revision + '/' + path
		response := http.get(url)!
		assert response.status_code == 200, url
		os.write_file(out + '/' + name, response.body)!
		downloads[name] = json2.Any({
			'url':         json2.Any(url)
			'http_status': json2.Any(response.status_code)
			'bytes':       json2.Any(response.body.len)
			'sha256':      json2.Any(hash(out + '/' + name)!)
		})
	}
	write_json(out + '/downloads.json', downloads)!
	contracts(out)!
	after := inputs()!
	assert before == after, 'inputs changed'
	write_json(out + '/after.json', after)!
	write_json(out + '/scope.json', {
		'contract':  'Android10 tag authentication and immutable primary full contents; selected318 Activity/PM/Handler/Looper bytes authenticated against original framework manifest.'
		'policy':    'Existing PM decisions preserved. Fine/coarse location denied without ATL_UGLY_ENABLE_LOCATION. No grant, permission UI, provider or real GPS added.'
		'lifecycle': 'Existing destroyed field checked by deferred result. No destroyed-Activity runtime fixture or recreation remapping claim.'
		'overlap':   'AOSP overlap cancellation is inline; normal deferred result runs on main Handler. Negative code validation precedes overlap, which precedes null/empty array validation.'
	})!
	mut manifest := map[string]string{}
	inventory(out, '', mut manifest)!
	write_json(out + '/sha256.json', manifest)!
	println('PERMISSIONS-SOURCEPROOF-SEALED ' + hash(out + '/sha256.json')!)
}

fn verify(root string, seal string, receipt string) ! {
	assert !os.is_link(root) && os.is_dir(root)
	assert !os.exists(receipt) && !os.is_link(receipt)
	assert !receipt.starts_with(root + '/') && receipt != root
	assert seal.len == 64 && hash(root + '/sha256.json')! == seal
	pins := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	actual.delete('sha256.json')
	assert pins.len == 15 && actual == pins, 'complete original bundle required'
	assert hash(root + '/baseline-sha256.json')! == baseline_seal
	origin := json2.decode[map[string]string](os.read_file(root + '/baseline-sha256.json')!)!
	for relative in selected {
		assert pins['selected/' + relative]! == origin['disassembled-318/' + relative]!
	}
	assert os.read_file(root + '/before.json')! == os.read_file(root + '/after.json')!
	before := json2.decode[map[string]string](os.read_file(root + '/before.json')!)!
	assert before.len == 8
	assert before[os.abs_path(self)]! == pins['author.v']!
	// os.executable() names this checker, not the retained capture executable.
	assert pins['author']! in before.values()
	tag_receipt := json2.decode[map[string]json2.Any](os.read_file(root + '/tag-resolution.json')!)!
	assert tag_receipt['exit_code']!.int() == 0
	args := tag_receipt['argv']!.as_array().map(it.str())
	assert args == ['/usr/bin/git', 'ls-remote',
		'https://android.googlesource.com/platform/frameworks/base', tag, tag + '^{}']
	assert tag_receipt['output']!.str().contains(tag_object + '\t' + tag + '\n')
	assert tag_receipt['output']!.str().contains(revision + '\t' + tag + '^{}')
	downloads := json2.decode[map[string]json2.Any](os.read_file(root + '/downloads.json')!)!
	assert downloads.len == 3
	for name, path in paths {
		item := downloads[name]!.as_map()
		assert item['url']!.str() == 'https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/' + revision + '/' + path
		assert item['http_status']!.int() == 200
		assert item['bytes']!.int() == os.read_bytes(root + '/' + name)!.len
		assert item['sha256']!.str() == pins[name]!
	}
	contracts(root)!
	write_json(receipt, {
		'result':          'PASS'
		'bundle':          root
		'manifest_sha256': seal
		'files':           pins.len.str()
	})!
	println('PERMISSIONS-SOURCEPROOF-READBACK-PASS ' + pins.len.str())
}

fn main() {
	$if prod {
		panic('requires assertions; compile without -prod')
	}
	assert os.args.len >= 3, 'capture FRESH_OUTPUT | verify BUNDLE MANIFEST_SHA FRESH_EXTERNAL_RECEIPT'
	match os.args[1] {
		'capture' {
			assert os.args.len == 3
			capture(os.abs_path(os.args[2]))!
		}
		'verify' {
			assert os.args.len == 5
			verify(os.abs_path(os.args[2]), os.args[3], os.abs_path(os.args[4]))!
		}
		else { panic('unknown command') }
	}
}
