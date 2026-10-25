// SPDX-License-Identifier: GPL-2.0-or-later
// Retain the primary AOSP contract for Android media exception linkage.
module main

import crypto.sha1
import crypto.sha256
import encoding.base64
import json2
import net.http
import os
import time

const self = 'tests/native-android-ws/media-codec-exceptions-sourceproof.v'
const compiler = '/Users/alex/code/vinix/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const remote = 'https://android.googlesource.com/platform/frameworks/base'
const revision = '1cdfff555f4a21f71ccc978290e2e212e2f8b168'

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
	codec := os.read_file(out + '/MediaCodec.java')!.fields().join(' ')
	for text in [
		'public final static class CodecException extends IllegalStateException',
		'CodecException(int errorCode, int actionCode, @Nullable String detailMessage)',
		'public boolean isTransient() { return mActionCode == ACTION_TRANSIENT; }',
		'public boolean isRecoverable() { return mActionCode == ACTION_RECOVERABLE; }',
		'public int getErrorCode() { return mErrorCode; }',
		'public @NonNull String getDiagnosticInfo() { return mDiagnosticInfo; }',
		'final String sign = errorCode < 0 ? "neg_" : "";',
		'"android.media.MediaCodec.error_" + sign + Math.abs(errorCode);',
		'public static final int ERROR_INSUFFICIENT_RESOURCE = 1100;',
		'public static final int ERROR_RECLAIMED = 1101;',
		'private final static int ACTION_TRANSIENT = 1;',
		'private final static int ACTION_RECOVERABLE = 2;',
		'public final static class CryptoException extends RuntimeException implements MediaDrmThrowable',
		'public CryptoException(int errorCode, @Nullable String detailMessage)',
		'this(detailMessage, errorCode, 0, 0, 0, null);',
		'public CryptoException(String message, int errorCode, int vendorError, int oemError, int errorContext, @Nullable CryptoInfo cryptoInfo)',
		'public @Nullable CryptoInfo getCryptoInfo() { return mCryptoInfo; }',
	] { assert codec.contains(text), text }
	crypto := os.read_file(out + '/MediaCryptoException.java')!.fields().join(' ')
	for text in [
		'public final class MediaCryptoException extends Exception implements MediaDrmThrowable',
		'public MediaCryptoException(@Nullable String detailMessage)',
		'this(detailMessage, 0, 0, 0);',
		'public MediaCryptoException(String message, int vendorError, int oemError, int errorContext)',
		'public int getVendorError() { return mVendorError; }',
		'public int getOemError() { return mOemError; }',
		'public int getErrorContext() { return mErrorContext; }',
	] { assert crypto.contains(text), text }
	drm := os.read_file(out + '/MediaDrm.java')!.fields().join(' ')
	for name, value in {
		'ERROR_NO_KEY': 1, 'ERROR_KEY_EXPIRED': 2, 'ERROR_RESOURCE_BUSY': 3,
		'ERROR_INSUFFICIENT_OUTPUT_PROTECTION': 4, 'ERROR_SESSION_NOT_OPENED': 5,
		'ERROR_UNSUPPORTED_OPERATION': 6, 'ERROR_INSUFFICIENT_SECURITY': 7,
		'ERROR_FRAME_TOO_LARGE': 8, 'ERROR_LOST_STATE': 9,
	} {
		assert codec.contains('public static final int ' + name + ' = MediaDrm.ErrorCodes.' + name + ';'), name
		assert drm.contains('public static final int ' + name + ' = ' + value.str() + ';'), name
	}
}

fn fetch(out string) ! {
	mut downloads := map[string]json2.Any{}
	for name, path in {
		'MediaCodec.java': 'media/java/android/media/MediaCodec.java'
		'MediaCryptoException.java': 'media/java/android/media/MediaCryptoException.java'
		'MediaDrm.java': 'media/java/android/media/MediaDrm.java'
	} {
		url := remote + '/+/' + revision + '/' + path + '?format=TEXT'
		started := time.utc().str()
		response := http.get(url)!
		assert response.status_code == 200, url + ': ' + response.status_code.str()
		os.write_file(out + '/' + name + '.base64', response.body)!
		source := base64.decode(response.body).bytestr()
		os.write_file(out + '/' + name, source)!
		blob := sha1.sum(('blob ' + source.len.str() + '\x00' + source).bytes()).hex()
		expected := {
			'MediaCodec.java': '0bea5a98afff7fe2210304be19080e9961ca95a0',
			'MediaCryptoException.java': '2a472fbfdfc3d357a9a1486d12be2247e998fd84',
			'MediaDrm.java': '6593533a843afae2cfc98fc89d708ecfa8737100',
		}
		assert blob == expected[name]!, name
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
		'CryptoException': 'Final RuntimeException; public (int,String) constructor; message/error state; getErrorCode. Modern source also implements MediaDrmThrowable and extended constructor/accessors.'
		'CodecException': 'Final IllegalStateException; package-private (int,int,String) constructor; isTransient action1, isRecoverable action2; getErrorCode; diagnostic prefix plus neg_ for negative codes plus Math.abs(int). Constants1100/1101.'
		'MediaCryptoException': 'Final checked Exception with public String constructor; modern source also implements MediaDrmThrowable with extended constructor/accessors.'
		'scope': 'Primary source contract only. Focused legacy exception repair does not implement modern MediaDrmThrowable, extended DRM constructors/accessors, codecs or playback. No ART or Maps runtime qualification.'
	})!
}

fn capture(out string) ! {
	assert !os.exists(out) && !os.is_link(out), 'fresh external directory required'
	assert hash(compiler)! == compiler_pin
	os.mkdir_all(out + '/compiler-inputs')!
	os.cp(self, out + '/author.v')!
	os.cp(os.executable(), out + '/bootstrap')!
	before := hash(self)!
	cc_before := hash(os.real_path('/usr/bin/cc'))!
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
	assert hash(os.real_path('/usr/bin/cc'))! == cc_before
	record(out, 'fetch', [out + '/author', 'fetch', out])!
	write_json(out + '/compiler.json', {'path': compiler, 'sha256': compiler_pin,
		'cc_path': os.real_path('/usr/bin/cc'), 'cc_sha256': hash(os.real_path('/usr/bin/cc'))!})!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	write_json(out + '/sha256.json', pins)!
	println('MEDIA-CODEC-EXCEPTIONS-SOURCEPROOF-SEALED ' + hash(out + '/sha256.json')!)
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
	println('MEDIA-CODEC-EXCEPTIONS-SOURCEPROOF-READBACK-PASS ' + pins.len.str())
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
