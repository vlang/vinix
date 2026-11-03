// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

const baseline = '/Users/alex/.local/state/vinix/android/current-native-build-2026-11-03-webview-package-r2'
const baseline_manifest = '1434754497efa741ddb2b378cbb693862ee96eb04cb304d9cbeeae5cc98b4dc0'
const bootstrap_before = '2214cb26fd0ea9cd31041e1eca250c347793b6306b1ef9440ae991f764270469'
const runtime_before = '145c627c5d069c907fcb649650132e17e378508c122a18f22d0a37e3a8d3b1de'
const helper_pin = 'ff3112e26b87e83ce58d52011d41567dad9c011d30ed58bd945f5319d1f575b5'

fn digest(path string) !string {
	if os.real_path(path) != path || os.lstat(path)!.get_filetype() != .regular
		|| os.file_size(path) > 16 * 1024 * 1024 { return error('bounded canonical regular source required: ' + path) }
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn compiler_digest(path string) !string {
	if path != '/Users/alex/code/v-tccbin-bootstrap-20261026/v' || os.real_path(path) != path
		|| os.lstat(path)!.get_filetype() != .regular || os.file_size(path) > 32 * 1024 * 1024 {
		return error('bounded qualified compiler required')
	}
	pin := sha256.sum(os.read_bytes(path)!).hex()
	if pin != '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe' {
		return error('qualified compiler pin differs')
	}
	return pin
}

fn replace_once(source string, before string, after string) !string {
	if source.count(before) != 1 { return error('unique exact source anchor required') }
	return source.replace(before, after)
}

fn helper(source string) !string {
	start := source.index('fn ws_boot_classpath(') or { return error('actual helper missing') }
	end := source.index('\n// Shared ART,') or { return error('helper boundary missing') }
	if start >= end || source.count('fn ws_boot_classpath(') != 1 { return error('unique complete helper required') }
	actual := source[start..end]
	if sha256.sum(actual.bytes()).hex() != helper_pin { return error('reviewed helper bytes differ') }
	return actual
}

fn verify(before_boot string, before_runtime string, after_boot string, after_runtime string) ! {
	if sha256.sum(before_boot.bytes()).hex() != bootstrap_before
		|| sha256.sum(before_runtime.bytes()).hex() != runtime_before {
		return error('exact frozen before sources required')
	}
	actual_helper := helper(after_boot)!
	prefix := '// SPDX-License-Identifier: GPL-2.0-or-later\n@[translated]\nmodule atlframework\n\n'
	comments := '// Android framework types belong to the boot loader: isolated module loaders\n' +
		'// deliberately use that loader as their only platform parent. Keep the pinned\n' +
		'// ART libraries in their existing order, followed by the framework DEX. The\n' +
		'// resource-only APK stays on the system class path: ART boot resources come\n' +
		'// from loaded DexFiles. An explicit path also prevents BOOTCLASSPATH from\n' +
		'// suppressing the standalone ART fork\'s append-only fallback.\n'
	mut expected_boot := replace_once(before_boot, prefix, prefix + comments + actual_helper + '\n')!
	buffer := '\t\tbuffer := &char(C.alloca(49152))\n'
	insert := '\t\t// Eleven entries still fit for a full PATH_MAX-sized root. This buffer\n' +
		'\t\t// lives through VM creation without allocating retained startup memory.\n' +
		'\t\tboot_classpath := &char(C.alloca(65536))\n' +
		'\t\tif !ws_boot_classpath(root, boot_classpath, 65536) {\n' +
		'\t\t\tC.puts(c\'ANDROID-WS-FAIL boot class path\')\n\t\t\treturn nil\n\t\t}\n' +
		'\t\t// ATLPaths reads the API JAR from the first system class-path entry.\n' +
		'\t\t// The resource-only framework APK must also remain system-visible.\n'
	expected_boot = replace_once(expected_boot, buffer, buffer + insert)!
	old_options := '\t\tmut args := WsVmArgs{ version: 0x10006, count: 12, options: options }\n' +
		'\t\ttrace_tls := C.getenv(c\'VINIX_ANDROID_TRACE_TLS\')\n' +
		'\t\tif trace_tls != nil && trace_tls[0] == `1` {\n' +
		'\t\t\toptions[12] = WsOption{c\'-Dwolfjsse.debug=true\', nil}\n' +
		'\t\t\toptions[13] = WsOption{c\'-Dwolfssljni.debug=true\', nil}\n' +
		'\t\t\targs.count = 14\n\t\t}\n'
	new_options := '\t\toptions[12] = WsOption{boot_classpath, nil}\n' +
		'\t\tmut args := WsVmArgs{ version: 0x10006, count: 13, options: options }\n' +
		'\t\ttrace_tls := C.getenv(c\'VINIX_ANDROID_TRACE_TLS\')\n' +
		'\t\tif trace_tls != nil && trace_tls[0] == `1` {\n' +
		'\t\t\toptions[13] = WsOption{c\'-Dwolfjsse.debug=true\', nil}\n' +
		'\t\t\toptions[14] = WsOption{c\'-Dwolfssljni.debug=true\', nil}\n' +
		'\t\t\targs.count = 15\n\t\t}\n'
	expected_boot = replace_once(expected_boot, old_options, new_options)!
	if after_boot != expected_boot { return error('bootstrap has changes outside exact helper/boot option/TLS delta') }
	old_load := '\targs := [Value{ l: ws_string(e, c\'vinix-android-native\') }, Value{ l: loader }]!\n' +
		'\tcall(e, runtime, c\'java/lang/Runtime\', c\'loadLibrary\', c\'(Ljava/lang/String;Ljava/lang/ClassLoader;)V\', unsafe { &args[0] })\n'
	new_load := '\t// BootClassLoader has no findLibrary implementation. Load the qualified\n' +
		'\t// absolute path directly and associate JNI with the defining framework\n' +
		'\t// loader; ART normalizes BootClassLoader to its native boot-loader identity.\n' +
		'\targs := [Value{ l: ws_string(e, path) }, Value{ l: loader }]!\n' +
		'\tcall(e, runtime, c\'java/lang/Runtime\', c\'load\', c\'(Ljava/lang/String;Ljava/lang/ClassLoader;)V\', unsafe { &args[0] })\n'
	if after_runtime != replace_once(before_runtime, old_load, new_load)! {
		return error('runtime has changes outside exact absolute Runtime.load delta')
	}
}

fn command(work string, label string, argv []string, pass bool) ! {
	result := os.exec(argv)
	os.write_file(work + '/' + label + '.json', json2.encode({
		'argv': json2.Any(argv), 'exit_code': json2.Any(result.exit_code),
		'output': json2.Any(result.output),
	}, prettify: true) + '\n')!
	if pass && result.exit_code != 0 { return error(label + ': ' + result.output) }
	if !pass && (result.exit_code == 0 || !result.output.contains('Assertion')) {
		return error('boundary mutation escaped actual-helper harness: ' + label)
	}
}

fn main() {
	$if prod { panic('live assertions required') }
	assert os.args.len == 4, 'V REPO FRESH_EXTERNAL_OUTPUT'
	compiler, repo := os.real_path(os.args[1]), os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	assert work.starts_with('/Users/alex/.local/state/vinix/android/')
	assert !os.exists(work) && !os.is_link(work)
	assert digest(baseline + '/sha256.json')! == baseline_manifest
	files := json2.decode[map[string]string](os.read_file(baseline + '/sha256.json')!)!
	assert files['native/atlframework/bootstrap.v'] == bootstrap_before
	assert files['native/atlframework/runtime.v'] == runtime_before
	before_boot := os.read_file(baseline + '/native/atlframework/bootstrap.v')!
	before_runtime := os.read_file(baseline + '/native/atlframework/runtime.v')!
	boot_path := repo + '/build-support/android/nativews/bootstrap.v'
	runtime_path := repo + '/build-support/android/nativews/runtime.v'
	harness_path := repo + '/tests/native-android-ws/frameworkbootcheck/main.v'
	after_boot, after_runtime := os.read_file(boot_path)!, os.read_file(runtime_path)!
	verify(before_boot, before_runtime, after_boot, after_runtime)!
	os.mkdir_all(work)!
	mut pins := map[string]string{}
	for path in [compiler, os.real_path(@FILE), repo + '/tests/native-android-ws/framework-boot-source-check.v', harness_path, boot_path, runtime_path,
		baseline + '/sha256.json', baseline + '/native/atlframework/bootstrap.v',
		baseline + '/native/atlframework/runtime.v'] { pins[path] = if path == compiler { compiler_digest(path)! } else { digest(path)! } }
	os.write_file(work + '/inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	for name, value in {'bootstrap-before.v': before_boot, 'runtime-before.v': before_runtime,
		'bootstrap-after.v': after_boot, 'runtime-after.v': after_runtime} {
		os.write_file(work + '/' + name, value)!
	}
	boot_mutants := [
		after_boot.replace('count: 13,', 'count: 12,'), after_boot.replace('args.count = 15', 'args.count = 14'),
		after_boot.replace('options[12] = WsOption{boot_classpath', 'options[15] = WsOption{boot_classpath'),
		after_boot.replace('options[13] = WsOption{c\'-Dwolfjsse', 'options[12] = WsOption{c\'-Dwolfjsse'),
		after_boot.replace('options[14] = WsOption{c\'-Dwolfssljni', 'options[13] = WsOption{c\'-Dwolfssljni'),
		after_boot.replace('16 * sizeof(WsOption)', '14 * sizeof(WsOption)'),
		after_boot.replace('C.alloca(65536)', 'C.alloca(8192)'),
		after_boot.replace('-Djava.class.path=%s/usr/lib/java/dex/android_translation_layer/api-impl.jar:%s/usr/lib/java/dex/android_translation_layer/framework-res.apk', '-Djava.class.path='),
		after_boot.replace('-Datl.app.class.path=%s', '-Datl.app.class.path=other'),
		after_boot.replace('-Djava.library.path=%s/usr/lib/art', '-Djava.library.path=/other'),
		after_boot.replace('-Xcheck:jni', '-Xcheck:other'),
		after_boot.replace('usize(written) < capacity', 'usize(written) <= capacity'),
	]
	runtime_mutants := [
		after_runtime.replace("c'load',", "c'loadLibrary',"),
		after_runtime.replace('ws_string(e, path)', "ws_string(e, c'vinix-android-native')"),
		after_runtime.replace('Value{ l: loader }', 'Value{ l: unsafe { nil } }'),
		after_runtime.replace("c'(Ljava/lang/String;Ljava/lang/ClassLoader;)V'", "c'(Ljava/lang/String;)V'"),
		after_runtime.replace('fn C.poll(voidptr, usize, i32) i32', 'fn C.poll(voidptr, usize, i64) i32'),
	]
	for mutant in boot_mutants {
		assert mutant != after_boot
		mut rejected := false
		verify(before_boot, before_runtime, mutant, after_runtime) or { rejected = true }
		assert rejected
	}
	for mutant in runtime_mutants {
		assert mutant != after_runtime
		mut rejected := false
		verify(before_boot, before_runtime, after_boot, mutant) or { rejected = true }
		assert rejected
	}
	actual_helper := helper(after_boot)!
	for kind in ['actual', 'inclusive-boundary', 'one-byte-overrun'] {
		directory := work + '/' + kind
		os.mkdir_all(directory)!
		os.cp(harness_path, directory + '/main.v')!
		mut body := actual_helper
		if kind == 'inclusive-boundary' { body = body.replace('usize(written) < capacity', 'usize(written) <= capacity') }
		if kind == 'one-byte-overrun' { body = body.replace('C.snprintf(buffer, capacity,', 'C.snprintf(buffer, capacity + 1,') }
		assert kind == 'actual' || body != actual_helper
		os.write_file(directory + '/helper.v', 'module main\n\n' + body)!
		command(work, kind + '-compile', [compiler, '-new-compiler', '-gc', 'boehm', '-nocache',
			'-cc', 'cc', '-o', directory + '/check', directory], true)!
		command(work, kind + '-run', [directory + '/check'], kind == 'actual')!
	}
	for path, pin in pins {
		actual := if path == compiler { compiler_digest(path)! } else { digest(path)! }
		assert actual == pin, 'source input changed: ' + path
	}
	os.write_file(work + '/inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	os.write_file(work + '/receipt.json', json2.encode({
		'source_controls': json2.Any(boot_mutants.len + runtime_mutants.len),
		'helper_cases': json2.Any(27), 'helper_mutations': json2.Any(2),
		'helper_sha256': json2.Any(helper_pin), 'baseline_manifest_sha256': json2.Any(baseline_manifest),
		'inputs_sha256': json2.decode[json2.Any](json2.encode(pins))!,
	}, prettify: true) + '\n')!
	println('FRAMEWORK-BOOT-SOURCE-PASS complete-two-file-delta controls=' + (boot_mutants.len + runtime_mutants.len).str() + ' actual-helper27 boundary-controls2 boot11 original-system-resource-path counts13-15 slots12-14 capacity16 absolute-Runtime.load')
}
