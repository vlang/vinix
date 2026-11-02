// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn command(work string, label string, argv []string, quiet bool) ! {
	result := os.exec(argv)
	os.write_file(work + '/' + label + '.json', json2.encode({
		'argv':      json2.Any(argv)
		'exit_code': json2.Any(result.exit_code)
		'output':    json2.Any(result.output)
	}, prettify: true) + '\n')!
	assert result.exit_code == 0, label + ': ' + result.output
	if quiet {
		assert result.output.trim_space() == '', label + ': unexpected diagnostics'
	}
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len == 8, 'V REPO FRESH_OUTPUT BASELINE_SMALI JAVA SMALI_TOOLS NATIVE_BINDINGS'
	compiler, repo := os.real_path(os.args[1]), os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	baseline, java, tools := os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	bindings := os.real_path(os.args[7])
	assert !os.exists(work) && !os.is_link(work) && work != repo && !work.starts_with(repo + '/')
	os.mkdir_all(work + '/androidtools')!
	os.mkdir_all(work + '/checker')!
	os.mkdir_all(work + '/proof/android/util')!
	provider := repo + '/tests/native-android-tools/androidtools/framework_event_log.v'
	checks := repo + '/tests/native-android-tools/eventlogcheck'
	integration := repo + '/tests/native-android-tools/androidtools/framework.v'
	mut pins := map[string]string{}
	for path in [compiler, java, os.real_path(@FILE), provider, integration, bindings,
		os.dir(baseline) + '/sha256.json', os.dir(baseline) + '/api-impl.jar'] {
		pins[path] = digest(path)!
	}
	integration_text := os.read_file(integration)!
	assert integration_text.count(' framework_event_log(smali)!\n') == 1
	assert integration_text.contains(' framework_component_parcel(smali)!\n framework_event_log(smali)!\n framework_assemble(')
	os.cp(provider, work + '/androidtools/provider.v')!
	check_files := os.walk_ext(checks, '.v').sorted()
	assert check_files.map(os.file_name(it)) == ['interpreter.v', 'main.v']
	for path in check_files {
		pins[path] = digest(path)!
		os.cp(path, work + '/checker/' + os.file_name(path))!
	}
	target := '/android/util/EventLog.smali'
	assert os.is_dir(baseline) && os.walk_ext(baseline, '.smali').len == 2116
	assert !os.exists(baseline + target) && !os.is_link(baseline + target)
	mut native_classes := map[string]bool{}
	for line in os.read_file(bindings)!.split_into_lines() {
		if line != '' && !line.starts_with('#') { native_classes[line.all_before('|')] = true }
	}
	assert native_classes.len == 70 && target.trim_left('/').all_before_last('.smali') !in native_classes
	for name in os.ls(tools)! {
		if name.ends_with('.jar') { pins[tools + '/' + name] = digest(tools + '/' + name)! }
	}
	os.write_file(work + '/inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	command(work, 'compile', [compiler, '-no-parallel', '-gc', 'boehm', '-nocache', '-path',
		'@vlib|' + work, '-cc', 'cc', '-o', work + '/check', work + '/checker'], true)!
	command(work, 'source', [work + '/check', work], false)!
	command(work, 'assemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*',
		'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', work + '/proof', '-o',
		work + '/patched.dex'], true)!
	assert os.is_file(work + '/patched.dex') && os.file_size(work + '/patched.dex') > 112
	command(work, 'disassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*',
		'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2', work + '/patched.dex',
		'-o', work + '/patched-roundtrip'], true)!
	command(work, 'reassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*',
		'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', work + '/patched-roundtrip',
		'-o', work + '/roundtrip.dex'], true)!
	command(work, 'second-disassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp',
		tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2',
		work + '/roundtrip.dex', '-o', work + '/second-roundtrip'], true)!
	command(work, 'roundtrip', [work + '/check', work, '--roundtrip'], false)!
	for path, pin in pins {
		assert digest(path)! == pin, 'input changed: ' + path
	}
	assert !os.exists(baseline + target) && !os.is_link(baseline + target)
	os.write_file(work + '/inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	for path in os.walk_ext(work, '.v') { pins[path] = digest(path)! }
	for path in os.walk_ext(work, '.dex') { pins[path] = digest(path)! }
	for kind in ['proof', 'patched-roundtrip', 'second-roundtrip'] {
		for path in os.walk_ext(work + '/' + kind, '.smali') { pins[path] = digest(path)! }
	}
	pins[work + '/check'] = digest(work + '/check')!
	os.write_file(work + '/receipt.json', json2.encode(pins, prettify: true) + '\n')!
	println('EVENT-LOG-CHECK-PASS one-new-class exact-five-writes bounded-input-execution API28 stable-second-DEX unchanged-parent-JAR')
}
