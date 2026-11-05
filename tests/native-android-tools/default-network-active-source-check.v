// SPDX-License-Identifier: GPL-2.0-or-later
// Isolated predecessor-preservation and API-28 DEX checks for the activity hint.
module main

import crypto.sha256
import json2
import os

const target = 'android/net/ConnectivityManager.smali'
const compiler_pin = '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe'
const sdk_manifest = 'cadfaa0105eb24580f1cdcef590f707e52aab334e9d7bf164524a403f1b43cbc'
const sdk_jar = '9207dab7a6a37e09fb049bb636ba6ebad3e63e43bfe7fd95821f67fc2aebeeb7'
const original_class = '1fd6af85766920db5576fec29ced1331db5b20d914a8909819299116e9c30ec3'
const bindings_pin = '2264b7af0bf4a5b39da876e2ef82a291983d7ea9bd2c5f7374d8448b4f1a03ba'
const original_integration_pin = '41058a6edb1dbf080b5839e6a10db9353b47e4fa9d55774af2d7bba9fb7f9a83'
const connectivity_generator_pin = '5242c03651154fb9ccac393b5d51cfe8906fad3515b79cfb11d54916247fa000'
const replacement_source_pin = '2db0cbc1f4c7f391c995e5fcd024d6a7a9b47d7ea46fa2db875042ad496a9f32'

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

fn production_replacer(source string) !string {
	marker := 'pub fn framework_replace_method(source string, name string, declaration string) !string {'
	assert source.count(marker) == 1, 'unique production replacement function required'
	start := source.index(marker) or { return error('production replacement function missing') }
	end := start + (source[start..].index('\n}\n') or { return error('production replacement function unterminated') }) + '\n}\n'.len
	return 'module androidtools\n\n' + source[start..end]
}

fn main() {
	$if prod { panic('live assertions required') }
	assert os.args.len == 7, 'V REPO FRESH_OUTPUT BASELINE_SMALI JAVA SMALI_TOOLS'
	compiler, repo := os.real_path(os.args[1]), os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	baseline, java, tools := os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	assert !os.exists(work) && !os.is_link(work) && work != repo && !work.starts_with(repo + '/')
	assert os.real_path(os.dir(work)) == os.dir(work), 'canonical external parent required'
	provider := repo + '/tests/native-android-tools/androidtools/framework_default_network_active.v'
	checks := repo + '/tests/native-android-tools/defaultnetworkactivecheck/main.v'
	driver := repo + '/tests/native-android-tools/default-network-active-source-check.v'
	integration := repo + '/tests/native-android-tools/androidtools/framework_classes.v'
	generator := repo + '/tests/native-android-tools/androidtools/framework_connectivity.v'
	replacement_source := repo + '/tests/native-android-tools/androidtools/framework.v'
	network_info := baseline + '/android/net/NetworkInfo.smali'
	bindings := repo + '/build-support/android/nativews/bindings.txt'
	manifest := os.dir(baseline) + '/sha256.json'
	jar := os.dir(baseline) + '/api-impl.jar'
	assert digest(compiler)! == compiler_pin, 'pinned V compiler required'
	assert os.file_name(baseline) in ['smali', 'new-dex']
	assert digest(manifest)! == sdk_manifest, 'exact Global string SDK manifest required'
	files := json2.decode[map[string]string](os.read_file(manifest)!)!
	assert files[os.file_name(baseline) + '/' + target]! == original_class
	assert digest(baseline + '/' + target)! == original_class, 'exact ConnectivityManager predecessor required'
	assert digest(network_info)! == files[os.file_name(baseline) + '/android/net/NetworkInfo.smali']!,
		'exact unrelated NetworkInfo seed for the actual connectivity generator required'
	assert digest(generator)! == connectivity_generator_pin && digest(replacement_source)! == replacement_source_pin,
		'exact actual connectivity writer and replacement implementation required'
	assert digest(jar)! == sdk_jar, 'exact Global string SDK JAR required'
	assert digest(bindings)! == bindings_pin, 'exact native declarations required'
	assert digest(os.real_path(@FILE))! == digest(driver)!, 'compiled driver source differs from selected source'
	assert os.walk_ext(baseline, '.smali').len == 2117
	mut native_classes := map[string]bool{}
	mut target_bindings := []string{}
	for line in os.read_file(bindings)!.split_into_lines() {
		if line != '' && !line.starts_with('#') {
			native_classes[line.all_before('|')] = true
			if line.starts_with('android/net/ConnectivityManager|') { target_bindings << line }
		}
	}
	assert native_classes.len == 70 && 'android/net/ConnectivityManager' in native_classes
	assert target_bindings == [
		'android/net/ConnectivityManager|nativeGetNetworkAvailable|return ws_network_available()',
		'android/net/ConnectivityManager|nativeGetNetworkState|return ws_network_state()',
	], 'both native queries must remain unchanged'
	provider_text := os.read_file(provider)!
	assert provider_text.count('pub fn framework_default_network_active_method() string {') == 1
	assert provider_text.count('pub fn framework_default_network_active_source(original string) !string {') == 1
	assert provider_text.count('fn framework_default_network_active(smali string) ! {') == 1
	assert !provider_text.contains('default_network_active_check_apply'), 'test adapter must not shadow production'
	integration_text := os.read_file(integration)!
	assert integration_text.count(' framework_connectivity(smali)!\n framework_default_network_active(smali)!\n') == 1,
		'ordinary SDK must add the activity hint after connectivity generation'
	assert integration_text.count(' framework_default_network_active(smali)!\n') == 1
	assert sha256.sum(integration_text.replace(' framework_default_network_active(smali)!\n', '').bytes()).hex() == original_integration_pin,
		'ordinary SDK integration must preserve every prior byte except its one added call'
	mut pins := map[string]string{}
	for path in [compiler, java, os.real_path(os.executable()), os.real_path(@FILE), driver,
		provider, checks, integration, generator, replacement_source, network_info, bindings, manifest, jar, baseline + '/' + target] {
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
	os.cp(generator, work + '/androidtools/connectivity.v')!
	os.write_file(work + '/androidtools/replacement.v', production_replacer(os.read_file(replacement_source)!)!)!
	os.cp(replacement_source, work + '/replacement-source.v')!
	os.write_file(work + '/androidtools/adapter.v', 'module androidtools\n\n' +
		'// Exercise the actual directory adapter; validation must precede its write.\n' +
		'pub fn default_network_active_check_apply(smali string) ! {\n framework_default_network_active(smali)!\n}\n' +
		'// Exercise the real ConnectivityManager writer rather than copied generated text.\n' +
		'pub fn default_network_active_check_generate(smali string) ! {\n framework_connectivity(smali)!\n}\n')!
	os.cp(checks, work + '/check.v')!
	os.cp(driver, work + '/driver-source.v')!
	os.cp(integration, work + '/integration-source.v')!
	for pair in [[provider, work + '/androidtools/provider.v'], [checks, work + '/check.v'],
		[driver, work + '/driver-source.v'], [integration, work + '/integration-source.v'],
		[generator, work + '/androidtools/connectivity.v'], [replacement_source, work + '/replacement-source.v']] {
		assert digest(pair[0])! == pins[pair[0]] && digest(pair[1])! == pins[pair[0]],
			'exact frozen source copy required'
	}
	module_files := ['adapter.v', 'connectivity.v', 'provider.v', 'replacement.v']
	assert os.ls(work + '/androidtools')!.sorted() == module_files
	assert os.read_file(work + '/androidtools/replacement.v')! == production_replacer(os.read_file(replacement_source)!)!
	os.mkdir_all(work + '/generator-input/android/net')!
	os.cp(network_info, work + '/generator-input/android/net/NetworkInfo.smali')!
	assert digest(work + '/generator-input/android/net/NetworkInfo.smali')! == pins[network_info]!
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
		module_files.map(work + '/androidtools/' + it).sorted(),
		'exact isolated helper, real writer, replacement and directory adapters required'
	freeze_inputs(work, 'checker-source', listing, mut pins)!
	command(work, 'compile', [compiler, '-no-parallel', '-gc', 'boehm', '-nocache', '-keepc',
		'-dump-files', work + '/checker-all-inputs.txt', '-path', '@vlib|' + work, '-cc', 'cc',
		'-o', work + '/check', work + '/check.v'], true)!
	freeze_inputs(work, 'checker-all', os.read_file(work + '/checker-all-inputs.txt')!, mut pins)!
	command(work, 'source', [work + '/check', work], false)!
	for row in [['baseline', 'baseline'], ['patched', 'proof'],
		['ordinary-baseline', 'ordinary-baseline'], ['ordinary-patched', 'ordinary-proof']] {
		kind, directory := row[0], work + '/' + row[1]
		command(work, kind + '-assemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp',
			tools + '/*', 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', directory,
			'-o', work + '/' + kind + '.dex'], true)!
		assert os.is_file(work + '/' + kind + '.dex') && os.file_size(work + '/' + kind + '.dex') > 112
		command(work, kind + '-disassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp',
			tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2',
			work + '/' + kind + '.dex', '-o', work + '/' + kind + '-roundtrip'], true)!
		assert os.walk_ext(work + '/' + kind + '-roundtrip', '.smali').len == 1
	}
	for row in [['', 'patched-roundtrip', 'roundtrip.dex', 'second-roundtrip'],
		['ordinary-', 'ordinary-patched-roundtrip', 'ordinary-roundtrip.dex', 'ordinary-second-roundtrip']] {
		command(work, row[0] + 'reassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*',
			'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', work + '/' + row[1],
			'-o', work + '/' + row[2]], true)!
		command(work, row[0] + 'second-disassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp',
			tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2',
			work + '/' + row[2], '-o', work + '/' + row[3]], true)!
	}
	command(work, 'roundtrip', [work + '/check', work, '--roundtrip'], false)!
	assert os.ls(tools)!.filter(it.ends_with('.jar')).sorted() == tool_names, 'tool JAR membership changed'
	assert os.ls(work + '/androidtools')!.sorted() == module_files, 'isolated module changed'
	for path, pin in pins { assert digest(path)! == pin, 'input changed: ' + path }
	os.write_file(work + '/inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	for path in os.walk_ext(work, '.v') { pins[path] = digest(path)! }
	for path in os.walk_ext(work, '.dex') { pins[path] = digest(path)! }
	for kind in ['baseline', 'proof', 'baseline-roundtrip', 'patched-roundtrip', 'second-roundtrip',
		'ordinary-baseline', 'ordinary-proof', 'ordinary-baseline-roundtrip', 'ordinary-patched-roundtrip', 'ordinary-second-roundtrip'] {
		path := work + '/' + kind + '/' + target
		pins[path] = digest(path)!
	}
	for path in os.walk_ext(work + '/ordinary-generation', '.smali') { pins[path] = digest(path)! }
	pins[work + '/generator-input/android/net/NetworkInfo.smali'] = digest(work + '/generator-input/android/net/NetworkInfo.smali')!
	pins[work + '/check'] = digest(work + '/check')!
	os.write_file(work + '/receipt.json', json2.encode(pins, prettify: true) + '\n')!
	println('DEFAULT-NETWORK-ACTIVE-CHECK-PASS one-class retained28-methods four-fields native-declarations2 isolated-helper actual-connectivity-generation atomic-refusals API28 canonical-and-ordinary stable-second-DEX no-idle-monitor-policy native70-consumed')
}
