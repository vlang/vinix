// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

const targets = ['android/content/res/Resources.smali', 'android/atl/ATLLoadedApp.smali']

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn command(work string, label string, argv []string, quiet bool) !string {
	result := os.exec(argv)
	os.write_file(work + '/' + label + '.json', json2.encode({
		'argv': json2.decode[json2.Any](json2.encode(argv))!,
		'exit_code': json2.Any(result.exit_code),
		'output': json2.Any(result.output),
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
		canonical := os.real_path(path)
		assert os.lstat(canonical)!.get_filetype() == .regular, 'regular compiler input required: ' + path
		pin := digest(path)!
		if prior := pins[path] { assert prior == pin, 'input changed before source snapshot: ' + path }
		pins[path] = pin
		captured[path] = pin
		destination := work + '/input-copies/' + path.trim_left('/')
		if !os.exists(destination) {
			os.mkdir_all(os.dir(destination))!
			os.cp(path, destination)!
		}
		assert digest(destination)! == pin && digest(path)! == pin, 'compiler input copy mismatch: ' + path
	}
	assert captured.len > 0
	os.write_file(work + '/' + label + '-inputs.json', json2.encode(captured, prettify: true) + '\n')!
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
	os.mkdir_all(work + '/androidtools')!
	provider := repo + '/tests/native-android-tools/androidtools/framework_boot_classpath.v'
	checks := repo + '/tests/native-android-tools/frameworkbootcheck/main.v'
	driver := repo + '/tests/native-android-tools/framework-boot-sdk-sourcecheck.v'
	integration := repo + '/tests/native-android-tools/androidtools/framework.v'
	assert digest(os.real_path(@FILE))! == digest(driver)!, 'compiled driver source must match current tracked driver'
	mut pins := map[string]string{}
	for path in [compiler, java, os.real_path(@FILE), driver, provider, checks, integration, bindings,
		os.dir(baseline) + '/sha256.json', os.dir(baseline) + '/api-impl.jar'] { pins[path] = digest(path)! }
	integration_text := os.read_file(integration)!
	assert integration_text.count(' framework_boot_classpath(smali)!\n') == 1
	assert integration_text.contains(' framework_webview_package(smali)!\n framework_boot_classpath(smali)!\n framework_assemble(')
	os.cp(provider, work + '/androidtools/provider.v')!
	os.cp(checks, work + '/check.v')!
	os.cp(driver, work + '/driver-source.v')!
	assert os.walk_ext(baseline, '.smali').len == 2117
	mut native_classes := map[string]bool{}
	mut selected_bindings := []string{}
	for line in os.read_file(bindings)!.split_into_lines() {
		if line != '' && !line.starts_with('#') {
			native_classes[line.all_before('|')] = true
			if line.starts_with('android/content/res/Resources|') || line.starts_with('android/atl/ATLLoadedApp|') { selected_bindings << line }
		}
	}
	assert native_classes.len == 70 && 'android/content/res/Resources' in native_classes && 'android/atl/ATLLoadedApp' in native_classes
	assert selected_bindings.len == 2
	for target in targets {
		pins[baseline + '/' + target] = digest(baseline + '/' + target)!
		for kind in ['baseline', 'proof'] {
			path := work + '/' + kind + '/' + target
			os.mkdir_all(os.dir(path))!
			os.cp(baseline + '/' + target, path)!
		}
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
		assert os.walk_ext(work + '/' + kind + '-roundtrip', '.smali').len == 2
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
	for target in targets {
		for kind in ['baseline', 'proof', 'baseline-roundtrip', 'patched-roundtrip', 'second-roundtrip'] {
			path := work + '/' + kind + '/' + target
			pins[path] = digest(path)!
		}
	}
	pins[work + '/check'] = digest(work + '/check')!
	os.write_file(work + '/receipt.json', json2.encode(pins, prettify: true) + '\n')!
	println('FRAMEWORK-BOOT-SDK-CHECK-PASS exact2-existing-loader-sites unchanged104-method-membership no-new-state atomic-semantic-prewrite API28 stable-second-DEX fresh-coupled-native-required')
}
