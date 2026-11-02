// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn command(work string, label string, argv []string, quiet bool) ! {
	r := os.exec(argv)
	os.write_file(work + '/' + label + '.json', json2.encode({
		'argv':      json2.Any(argv)
		'exit_code': json2.Any(r.exit_code)
		'output':    json2.Any(r.output)
	}, prettify: true) + '\n')!
	assert r.exit_code == 0, label + ': ' + r.output
	if quiet {
		assert r.output.trim_space() == '', label + ': unexpected diagnostics'
	}
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len == 7, 'V REPO FRESH_OUTPUT BASELINE_SMALI JAVA SMALI_TOOLS'
	compiler, repo := os.real_path(os.args[1]), os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	baseline, java, tools := os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	assert !os.exists(work) && !os.is_link(work) && !work.starts_with(repo + '/')
	os.mkdir_all(work + '/androidtools')!
	provider := repo + '/tests/native-android-tools/androidtools/framework_stable_display.v'
	integration := repo + '/tests/native-android-tools/androidtools/framework.v'
	check := repo + '/tests/native-android-tools/stabledisplaycheck/main.v'
	mut pins := map[string]string{}
	for path in [compiler, java, @FILE, provider, integration, check] { pins[path] = digest(path)! }
	assert os.read_file(integration)!.contains(' framework_intent_extras(smali)!\n framework_stable_display(smali)!\n framework_assemble(')
	os.cp(provider, work + '/androidtools/provider.v')!
	os.cp(check, work + '/check.v')!
	for name in ['android/hardware/display/DisplayManager', 'android/view/Display',
		'android/graphics/Point'] {
		path := baseline + '/' + name + '.smali'
		pins[path] = digest(path)!
		for kind in ['baseline', 'patched'] {
			dest := work + '/' + kind + '/' + name + '.smali'
			os.mkdir_all(os.dir(dest))!
			os.cp(path, dest)!
		}
	}
	for name in os.ls(tools)! {
		if name.ends_with('.jar') { pins[tools + '/' + name] = digest(tools + '/' + name)! }
	}
	command(work, 'compile', [compiler, '-no-parallel', '-gc', 'boehm', '-nocache', '-path',
		'@vlib|' + work, '-cc', 'cc', '-o', work + '/check', work + '/check.v'], true)!
	command(work, 'source', [work + '/check', work], false)!
	for kind in ['baseline', 'patched'] {
		command(work, kind + '-assemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp',
			tools + '/*', 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2',
			work + '/' + kind, '-o', work + '/' + kind + '.dex'], true)!
		assert os.is_file(work + '/' + kind + '.dex') && os.file_size(work + '/' + kind + '.dex') > 112
		command(work, kind + '-disassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp',
			tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2',
			work + '/' + kind + '.dex', '-o', work + '/' + kind + '-roundtrip'], true)!
		assert os.walk_ext(work + '/' + kind + '-roundtrip', '.smali').len == 3
	}
	command(work, 'reassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*',
		'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', work + '/patched-roundtrip',
		'-o', work + '/roundtrip.dex'], true)!
	assert os.is_file(work + '/roundtrip.dex') && os.file_size(work + '/roundtrip.dex') > 112
	command(work, 'second-disassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp',
		tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2',
		work + '/roundtrip.dex', '-o', work + '/second-roundtrip'], true)!
	assert os.walk_ext(work + '/second-roundtrip', '.smali').len == 3
	command(work, 'roundtrip', [work + '/check', work, '--roundtrip'], false)!
	for path, pin in pins {
		assert digest(path)! == pin, 'input changed: ' + path
	}
	for path in os.walk_ext(work, '.v') { pins[path] = digest(path)! }
	for path in os.walk_ext(work, '.dex') { pins[path] = digest(path)! }
	for path in os.walk_ext(work + '/patched-roundtrip', '.smali') { pins[path] = digest(path)! }
	for path in ['check', 'patched/android/hardware/display/DisplayManager.smali'] {
		pins[work + '/' + path] = digest(work + '/' + path)!
	}
	os.write_file(work + '/receipt.json', json2.encode(pins, prettify: true) + '\n')!
	println('STABLE-DISPLAY-CHECK-PASS source-refusals one-native-API API28-assembly three-class-DEX-roundtrip')
}
