// SPDX-License-Identifier: GPL-2.0-or-later
// Run the isolated Global string-writer helper and API-28 preservation checks.
module main

import crypto.sha256
import json2
import os

const target = 'android/provider/Settings$Global.smali'
const sdk_manifest = '4a354ead173048b39fb26cce709922f8954e27e53e2d3a5d92ecdf427db0645d'
const sdk_jar = '875f854ddf662dcaf55ebe05df06f5833eb5ca1e15f94066ffdf0fef18e829a8'
const original_class = '871ce221551cfe2690de98ff93b68c2464aa7a35bbbb3ec3245be43bfa833456'
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

fn main() {
	$if prod { panic('live assertions required') }
	assert os.args.len == 7, 'V REPO FRESH_OUTPUT BASELINE_SMALI JAVA SMALI_TOOLS'
	compiler, repo := os.real_path(os.args[1]), os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	baseline, java, tools := os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	assert !os.exists(work) && !os.is_link(work) && work != repo && !work.starts_with(repo + '/')
	assert os.real_path(os.dir(work)) == os.dir(work), 'canonical external parent required'
	provider := repo + '/tests/native-android-tools/androidtools/framework_settings_global.v'
	checks := repo + '/tests/native-android-tools/globalsettingsstringcheck/main.v'
	driver := repo + '/tests/native-android-tools/global-settings-string-source-check.v'
	integration := repo + '/tests/native-android-tools/androidtools/framework_classes.v'
	bindings := repo + '/build-support/android/nativews/bindings.txt'
	manifest := os.dir(baseline) + '/sha256.json'
	jar := os.dir(baseline) + '/api-impl.jar'
	assert os.file_name(baseline) in ['smali', 'new-dex']
	assert digest(manifest)! == sdk_manifest, 'exact process-package SDK manifest required'
	files := json2.decode[map[string]string](os.read_file(manifest)!)!
	assert files[os.file_name(baseline) + '/' + target]! == original_class
	assert digest(baseline + '/' + target)! == original_class, 'exact original Global class required'
	assert digest(jar)! == sdk_jar, 'exact process-package SDK JAR required'
	assert digest(bindings)! == bindings_pin, 'exact native declarations required'
	assert digest(os.real_path(@FILE))! == digest(driver)!, 'compiled driver source differs from checkout'
	assert os.walk_ext(baseline, '.smali').len == 2117
	mut native_classes := map[string]bool{}
	for line in os.read_file(bindings)!.split_into_lines() {
		if line != '' && !line.starts_with('#') { native_classes[line.all_before('|')] = true }
	}
	assert native_classes.len == 70 && 'android/provider/Settings$Global' !in native_classes
	assert os.read_file(integration)!.count(' framework_settings_global(smali)!\n') == 1
	provider_text := os.read_file(provider)!
	assert provider_text.count('pub fn framework_settings_global_put_string_method() string {') == 1
	assert provider_text.count('pub fn framework_settings_global_put_string_source(original string) !string {') == 1
	assert !provider_text.contains('global_settings_string_check_apply'), 'test adapter must not shadow production'
	mut pins := map[string]string{}
	for path in [compiler, java, os.real_path(os.executable()), os.real_path(@FILE), driver,
		provider, checks, integration, bindings, manifest, jar, baseline + '/' + target] {
		pins[path] = digest(path)!
	}
	tool_names := os.ls(tools)!.filter(it.ends_with('.jar')).sorted()
	assert tool_names.len > 0, 'smali tool JAR inputs required'
	for name in tool_names {
		path := tools + '/' + name
		assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular, 'regular tool JAR required'
		pins[path] = digest(path)!
	}
	os.mkdir_all(work + '/androidtools')!
	os.cp(provider, work + '/androidtools/provider.v')!
	os.write_file(work + '/androidtools/adapter.v', 'module androidtools\n\n' +
		'// Exercise the actual private ordinary-SDK integration, not a duplicate writer.\n' +
		'pub fn global_settings_string_check_apply(smali string) ! {\n framework_settings_global(smali)!\n}\n')!
	os.cp(checks, work + '/check.v')!
	os.cp(driver, work + '/driver-source.v')!
	os.cp(integration, work + '/integration-source.v')!
	for pair in [[provider, work + '/androidtools/provider.v'], [checks, work + '/check.v'],
		[driver, work + '/driver-source.v'], [integration, work + '/integration-source.v']] {
		assert digest(pair[0])! == pins[pair[0]] && digest(pair[1])! == pins[pair[0]],
			'exact frozen source copy required'
	}
	assert os.ls(work + '/androidtools')!.sorted() == ['adapter.v', 'provider.v']
	for kind in ['baseline', 'proof'] {
		path := work + '/' + kind + '/' + target
		os.mkdir_all(os.dir(path))!
		os.cp(baseline + '/' + target, path)!
		assert digest(path)! == original_class, 'exact frozen baseline copy required'
	}
	os.write_file(work + '/tool-membership.json', json2.encode(tool_names) + '\n')!
	os.write_file(work + '/inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	listing := command(work, 'checker-source-list', [compiler, '-no-parallel', '-gc', 'boehm', '-nocache',
		'-cc', 'cc', '-print-v-files', '-path', '@vlib|' + work, work + '/check.v'], false)!
	selected := listing.split_into_lines().map(it.trim_space())
	assert selected.filter(it.starts_with(repo + '/tests/native-android-tools/androidtools/')).len == 0,
		'the checker must not compile the whole production module'
	assert selected.filter(it.starts_with(work + '/androidtools/')).sorted() ==
		[work + '/androidtools/adapter.v', work + '/androidtools/provider.v'].sorted(),
		'exact isolated helper and private-integration adapter required'
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
	assert os.ls(tools)!.filter(it.ends_with('.jar')).sorted() == tool_names, 'tool JAR membership changed'
	assert os.ls(work + '/androidtools')!.sorted() == ['adapter.v', 'provider.v'], 'isolated module changed'
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
	println('GLOBAL-SETTINGS-STRING-CHECK-PASS one-class retained-eleven-methods isolated-helper atomic-refusals String-values exact-catch-boundary API28 stable-second-DEX native70-excluded')
}
