// SPDX-License-Identifier: GPL-2.0-or-later
// Run the actual narrow helper, preservation controls and API-28 DEX roundtrips.
module main

import crypto.sha256
import json2
import os

const target = 'android/app/ActivityManager\$RunningAppProcessInfo.smali'
const enclosing = 'android/app/ActivityManager.smali'
const sdk_manifest = 'bffa5dedc87d80979b09d517fcfb752b470d7f9e76a8e44bc24452f152d42025'
const original_class = '463deb6a989fa710d924675882aa47466a184be4a7bf8cb59caf095d96cc10d5'
const enclosing_class = 'fc4affd416f68eb810ee3a5eb6433770e05aaf94a3a293a13e9950a97e441db4'
const sdk_jar = 'dd3af0444459410f28d20f04928e37a19eb6b076d433498b05eac9a922b49f0e'
const bindings_pin = '2264b7af0bf4a5b39da876e2ef82a291983d7ea9bd2c5f7374d8448b4f1a03ba'

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn command(work string, label string, argv []string, quiet bool) !string {
	result := os.exec(argv)
	os.write_file(work + '/' + label + '.json', json2.encode({
		'argv': json2.decode[json2.Any](json2.encode(argv))!
		'exit_code': json2.Any(result.exit_code)
		'output': json2.Any(result.output)
	}, prettify: true) + '\n')!
	assert result.exit_code == 0, label + ': ' + result.output
	if quiet { assert result.output.trim_space() == '', label + ': unexpected diagnostics' }
	return result.output
}

fn freeze_inputs(work string, label string, listing string, mut pins map[string]string) ! {
	mut captured := map[string]string{}
	for line in listing.split_into_lines() {
		path := line.trim_space()
		assert os.is_abs_path(path) && os.norm_path(path) == path, 'absolute normalized compiler input required'
		assert os.lstat(os.real_path(path))!.get_filetype() == .regular, 'regular compiler input required'
		pin := digest(path)!
		if prior := pins[path] { assert prior == pin, 'input changed before source snapshot' }
		pins[path] = pin
		captured[path] = pin
		destination := work + '/input-copies/' + path.trim_left('/')
		if !os.exists(destination) { os.mkdir_all(os.dir(destination))!; os.cp(path, destination)! }
		assert digest(destination)! == pin && digest(path)! == pin, 'compiler input copy mismatch'
	}
	assert captured.len > 0
	os.write_file(work + '/' + label + '-inputs.json', json2.encode(captured, prettify: true) + '\n')!
}

fn helper_module(source string) !string {
	anchor := 'fn process_packages_methods('
	assert source.count(anchor) == 1
	start := source.index(anchor) or { return error('actual process package helper tail missing') }
	return 'module androidtools\n\n' + source[start..]
}

fn main() {
	$if prod { panic('live assertions required') }
	assert os.args.len == 8, 'V REPO FRESH_OUTPUT BASELINE_SMALI JAVA SMALI_TOOLS NATIVE_BINDINGS'
	compiler, repo := os.real_path(os.args[1]), os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	baseline, java, tools := os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	bindings := os.real_path(os.args[7])
	assert !os.exists(work) && !os.is_link(work) && work != repo && !work.starts_with(repo + '/')
	assert os.real_path(os.dir(work)) == os.dir(work), 'canonical external parent required'
	provider := repo + '/tests/native-android-tools/androidtools/framework_activity_manager.v'
	checks := repo + '/tests/native-android-tools/processpackagescheck/main.v'
	driver := repo + '/tests/native-android-tools/framework-process-packages-sourcecheck.v'
	integration := repo + '/tests/native-android-tools/androidtools/framework.v'
	full_generator := repo + '/tests/native-android-tools/androidtools/framework_classes.v'
	manifest := os.dir(baseline) + '/sha256.json'
	jar := os.dir(baseline) + '/api-impl.jar'
	assert digest(manifest)! == sdk_manifest, 'exact original SDK manifest required'
	files := json2.decode[map[string]string](os.read_file(manifest)!)!
	assert os.file_name(baseline) in ['smali', 'new-dex']
	assert files[os.file_name(baseline) + '/' + target]! == original_class
	assert files[os.file_name(baseline) + '/' + enclosing]! == enclosing_class
	assert digest(baseline + '/' + target)! == original_class, 'exact original process info class required'
	assert digest(baseline + '/' + enclosing)! == enclosing_class, 'exact original enclosing ActivityManager required'
	assert digest(jar)! == sdk_jar, 'exact TrafficStats SDK JAR required'
	assert digest(bindings)! == bindings_pin, 'exact native declarations required'
	assert digest(os.real_path(@FILE))! == digest(driver)!, 'compiled driver source differs from checkout'
	mut pins := map[string]string{}
	for path in [compiler, java, os.real_path(@FILE), driver, provider, checks, integration, full_generator,
		bindings, manifest, jar, baseline + '/' + target, baseline + '/' + enclosing] { pins[path] = digest(path)! }
	assert os.walk_ext(baseline, '.smali').len == 2117
	mut native_classes := map[string]bool{}
	for line in os.read_file(bindings)!.split_into_lines() {
		if line != '' && !line.starts_with('#') { native_classes[line.all_before('|')] = true }
	}
	assert native_classes.len == 70
	assert 'android/app/ActivityManager\$RunningAppProcessInfo' !in native_classes
	assert 'android/app/ActivityManager' in native_classes
	provider_text := os.read_file(provider)!
	assert provider_text.count('framework_process_packages_source(info_text)!') == 1
	assert provider_text.count('pub fn framework_process_packages_source(') == 1
	assert os.read_file(full_generator)!.count(' framework_activity_manager(smali)!\n') == 1
	os.mkdir_all(work + '/androidtools')!
	os.cp(provider, work + '/provider-source.v')!
	os.write_file(work + '/androidtools/provider.v', helper_module(provider_text)!)!
	os.cp(checks, work + '/check.v')!
	os.cp(driver, work + '/driver-source.v')!
	for kind in ['baseline', 'proof'] {
		path := work + '/' + kind + '/' + target
		os.mkdir_all(os.dir(path))!
		os.cp(baseline + '/' + target, path)!
	}
	for name in os.ls(tools)! { if name.ends_with('.jar') { pins[tools + '/' + name] = digest(tools + '/' + name)! } }
	os.write_file(work + '/inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	listing := command(work, 'checker-source-list', [compiler, '-no-parallel', '-gc', 'boehm', '-nocache',
		'-cc', 'cc', '-print-v-files', '-path', '@vlib|' + work, work + '/check.v'], false)!
	freeze_inputs(work, 'checker-source', listing, mut pins)!
	command(work, 'compile', [compiler, '-no-parallel', '-gc', 'boehm', '-nocache', '-keepc',
		'-dump-files', work + '/checker-all-inputs.txt', '-path', '@vlib|' + work, '-cc', 'cc',
		'-o', work + '/check', work + '/check.v'], true)!
	freeze_inputs(work, 'checker-all', os.read_file(work + '/checker-all-inputs.txt')!, mut pins)!
	command(work, 'source', [work + '/check', work], false)!
	for kind in ['baseline', 'patched'] {
		directory := work + '/' + if kind == 'baseline' { 'baseline' } else { 'proof' }
		command(work, kind + '-assemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp',
			tools + '/*', 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', directory,
			'-o', work + '/' + kind + '.dex'], true)!
		assert os.is_file(work + '/' + kind + '.dex') && os.file_size(work + '/' + kind + '.dex') > 112
		command(work, kind + '-disassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp',
			tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2',
			work + '/' + kind + '.dex', '-o', work + '/' + kind + '-roundtrip'], true)!
		assert os.walk_ext(work + '/' + kind + '-roundtrip', '.smali').len == 1
	}
	command(work, 'reassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*',
		'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', work + '/patched-roundtrip',
		'-o', work + '/roundtrip.dex'], true)!
	command(work, 'second-disassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp',
		tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2',
		work + '/roundtrip.dex', '-o', work + '/second-roundtrip'], true)!
	command(work, 'roundtrip', [work + '/check', work, '--roundtrip'], false)!
	for path, pin in pins { assert digest(path)! == pin, 'input changed: ' + path }
	os.write_file(work + '/inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	for path in os.walk_ext(work, '.v') { pins[path] = digest(path)! }
	for path in os.walk_ext(work, '.dex') { pins[path] = digest(path)! }
	for kind in ['baseline', 'proof', 'baseline-roundtrip', 'patched-roundtrip', 'second-roundtrip'] {
		path := work + '/' + kind + '/' + target
		pins[path] = digest(path)!
	}
	pins[work + '/check'] = digest(work + '/check')!
	os.write_file(work + '/receipt.json', json2.encode(pins, prettify: true) + '\n')!
	println('PROCESS-PACKAGES-SDK-CHECK-PASS one-class pkgList source-refusals preservation API28 stable-second-DEX nested-native-excluded enclosing-native-bound membership-only')
}
