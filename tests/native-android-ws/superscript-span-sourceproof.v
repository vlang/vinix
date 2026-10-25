// SPDX-License-Identifier: GPL-2.0-or-later
// Retain the primary AOSP contract for the focused SuperscriptSpan repair.
module main

import crypto.sha1
import crypto.sha256
import encoding.base64
import json2
import net.http
import os
import time

const self = 'tests/native-android-ws/superscript-span-sourceproof.v'
const compiler = '/Users/alex/code/vinix/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const remote = 'https://android.googlesource.com/platform/frameworks/base'

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
			else { return error('nonregular evidence: ' + key) }
		}
	}
}

fn record(out string, label string, argv []string) !string {
	started := time.utc().str()
	pin := hash(os.real_path(argv[0]))!
	r := os.exec(argv)
	os.write_file(out + '/' + label + '.log', r.output)!
	write_json(out + '/' + label + '.json', {
		'argv': json2.Any(argv)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'executable_sha256': json2.Any(pin)
		'exit_code': json2.Any(r.exit_code)
	})!
	assert hash(os.real_path(argv[0]))! == pin
	assert r.exit_code == 0, label + ': ' + r.output
	return r.output
}

fn contracts(out string) ! {
	span := os.read_file(out + '/SuperscriptSpan.java')!.fields().join(' ')
	for text in [
		'public class SuperscriptSpan extends MetricAffectingSpan implements ParcelableSpan',
		'public SuperscriptSpan() { }',
		'public SuperscriptSpan(@NonNull Parcel src) { }',
		'public int getSpanTypeId() { return getSpanTypeIdInternal(); }',
		'public int getSpanTypeIdInternal() { return TextUtils.SUPERSCRIPT_SPAN; }',
		'public int describeContents() { return 0; }',
		'public void writeToParcel(@NonNull Parcel dest, int flags) { writeToParcelInternal(dest, flags); }',
		'public void writeToParcelInternal(@NonNull Parcel dest, int flags) { }',
		'public void updateDrawState(@NonNull TextPaint textPaint) { textPaint.baselineShift += (int) (textPaint.ascent() / 2); }',
		'public void updateMeasureState(@NonNull TextPaint textPaint) { textPaint.baselineShift += (int) (textPaint.ascent() / 2); }',
		'public String toString() { return "SuperscriptSpan{}"; }',
	] { assert span.contains(text), text }
	utils := os.read_file(out + '/TextUtils.java')!.fields().join(' ')
	assert utils.contains('public static final int SUPERSCRIPT_SPAN = 14;')
	assert utils.contains('case SUPERSCRIPT_SPAN: span = new SuperscriptSpan(p);')
	paint := os.read_file(out + '/TextPaint.java')!.fields().join(' ')
	assert paint.contains('public class TextPaint extends Paint')
	assert paint.contains('public int baselineShift;')
	assert paint.contains('baselineShift = tp.baselineShift;')
}

fn fetch(out string) ! {
	resolved := record(out, 'resolve-aosp', ['/usr/bin/git', 'ls-remote', remote, 'refs/heads/main'])!
	parts := resolved.trim_space().split('\t')
	assert parts.len == 2 && parts[0].len == 40 && parts[1] == 'refs/heads/main'
	revision := parts[0]
	mut downloads := map[string]json2.Any{}
	for name, path in {
		'SuperscriptSpan.java': 'core/java/android/text/style/SuperscriptSpan.java'
		'TextUtils.java': 'core/java/android/text/TextUtils.java'
		'TextPaint.java': 'core/java/android/text/TextPaint.java'
	} {
		url := remote + '/+/' + revision + '/' + path + '?format=TEXT'
		started := time.utc().str()
		response := http.get(url)!
		assert response.status_code == 200, url + ': ' + response.status_code.str()
		os.write_file(out + '/' + name + '.base64', response.body)!
		source := base64.decode(response.body).bytestr()
		os.write_file(out + '/' + name, source)!
		blob := sha1.sum(('blob ' + source.len.str() + '\x00' + source).bytes()).hex()
		if name == 'SuperscriptSpan.java' { assert blob == '561022352ffd7aff3b46ee0bb3ddd02f4f7d5937' }
		downloads[name] = json2.Any({
			'url': json2.Any(url), 'revision': json2.Any(revision),
			'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
			'http_status': json2.Any(response.status_code), 'bytes': json2.Any(source.len),
			'sha256': json2.Any(hash(out + '/' + name)!), 'git_blob_sha1': json2.Any(blob),
		})
	}
	write_json(out + '/downloads.json', downloads)!
	contracts(out)!
	write_json(out + '/contract.json', {
		'SuperscriptSpan': 'MetricAffectingSpan and ParcelableSpan; public empty and Parcel constructors; id14; describeContents0; payload-free parcel methods; toString SuperscriptSpan{}.'
		'updates': 'Both updates add (int)(textPaint.ascent()/2) to baselineShift: floating divide first, then truncate toward zero, preserving prior shift.'
		'TextPaint': 'Public integer baselineShift field, copied by set(TextPaint).'
		'scope': 'Primary source contract only; no ART, shaping, renderer or Maps runtime qualification.'
	})!
}

fn capture(out string) ! {
	assert !os.exists(out) && !os.is_link(out), 'fresh external directory required'
	assert hash(compiler)! == compiler_pin
	os.mkdir_all(out + '/compiler-inputs')!
	os.cp(self, out + '/author.v')!
	os.cp(os.executable(), out + '/bootstrap')!
	before := hash(self)!
	record(out, 'checkout-revision', ['/usr/bin/git', 'rev-parse', 'HEAD'])!
	record(out, 'compiler-version', [compiler, 'version'])!
	closure := record(out, 'compiler-closure', [compiler, '-print-v-files', self])!
	mut inputs := map[string]string{}
	for path in closure.split_into_lines().filter(it.ends_with('.v')) {
		inputs[path] = hash(path)!
		target := out + '/compiler-inputs/' + path.trim_left('/')
		os.mkdir_all(os.dir(target))!
		os.cp(path, target)!
	}
	assert inputs.len > 0
	write_json(out + '/compiler-inputs.json', inputs)!
	os.mkdir_all(out + '/generated-c')!
	os.setenv('VTMP', out + '/generated-c', true)
	record(out, 'compile-author', [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc',
		'-o', out + '/author', self])!
	for path, pin in inputs { assert hash(path)! == pin, path }
	assert hash(self)! == before && hash(compiler)! == compiler_pin
	record(out, 'fetch', [out + '/author', 'fetch', out])!
	write_json(out + '/compiler.json', {'path': compiler, 'sha256': compiler_pin})!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	write_json(out + '/sha256.json', pins)!
	println('SUPERSCRIPT-SPAN-SOURCEPROOF-SEALED ' + hash(out + '/sha256.json')!)
}

fn verify(out string, seal string, receipt string) ! {
	assert !os.exists(receipt) && !receipt.starts_with(out + '/')
	assert hash(out + '/sha256.json')! == seal
	pins := json2.decode[map[string]string](os.read_file(out + '/sha256.json')!)!
	mut actual := map[string]string{}
	inventory(out, '', mut actual)!
	actual.delete('sha256.json')
	assert actual == pins && pins.len > 20, 'complete original bundle required'
	contracts(out)!
	write_json(receipt, {'result': 'PASS', 'manifest_sha256': seal,
		'bundle': out, 'files': pins.len.str()})!
	println('SUPERSCRIPT-SPAN-SOURCEPROOF-READBACK-PASS ' + pins.len.str())
}

fn main() {
	$if prod { panic('requires assertions') }
	assert os.args.len >= 3, 'capture FRESH_OUTPUT | verify BUNDLE MANIFEST RECEIPT'
	match os.args[1] {
		'capture' { assert os.args.len == 3; capture(os.abs_path(os.args[2]))! }
		'fetch' { assert os.args.len == 3; fetch(os.abs_path(os.args[2]))! }
		'verify' { assert os.args.len == 5; verify(os.abs_path(os.args[2]), os.args[3], os.abs_path(os.args[4]))! }
		else { panic('unknown command') }
	}
}
