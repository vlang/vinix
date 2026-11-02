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
	providers := ['framework_messenger.v', 'framework_message_parcel.v']
	checks := repo + '/tests/native-android-tools/messengercheck/main.v'
	integration := repo + '/tests/native-android-tools/androidtools/framework.v'
	mut pins := map[string]string{}
	for path in [compiler, java, os.real_path(@FILE), checks, integration, bindings] {
		pins[path] = digest(path)!
	}
	integration_text := os.read_file(integration)!
	assert integration_text.count(' framework_message_parcel(smali)!\n') == 0
	assert integration_text.count(' framework_messenger(smali)!\n') == 1
	assert integration_text.contains(' framework_usage_inactive(smali)!\n framework_messenger(smali)!\n framework_assemble(')
	for name in providers {
		path := repo + '/tests/native-android-tools/androidtools/' + name
		pins[path] = digest(path)!
		os.cp(path, work + '/androidtools/' + name)!
	}
	os.cp(checks, work + '/check.v')!
	targets := ['android/os/IMessenger.smali', 'android/os/Messenger.smali',
		'android/os/Messenger$1.smali', 'android/os/Handler$MessengerImpl.smali',
		'android/os/Message.smali', 'android/os/Handler.smali', 'android/os/Binder.smali',
		'android/os/Parcel.smali']
	mut native_classes := map[string]bool{}
	for line in os.read_file(bindings)!.split_into_lines() {
		if line != '' && !line.starts_with('#') { native_classes[line.all_before('|')] = true }
	}
	assert native_classes.len == 70
	for target in targets {
		assert target.all_before_last('.smali') !in native_classes
		pins[baseline + '/' + target] = digest(baseline + '/' + target)!
		for kind in ['baseline', 'proof'] {
			path := work + '/' + kind + '/' + target
			os.mkdir_all(os.dir(path))!
			os.cp(baseline + '/' + target, path)!
		}
	}
	// The obsolete private anonymous implementation has one external owner.
	refs := os.exec(['rg', '-l', '-F', 'Landroid/os/Messenger$1;', baseline])
	assert refs.exit_code == 0
	assert refs.output.trim_space().split_into_lines().sorted() == [
		baseline + '/android/os/Messenger$1.smali',
		baseline + '/android/os/Messenger.smali',
	]
	assert os.read_file(baseline + '/android/os/Messenger.smali')!.count('Landroid/os/Messenger$1;-><init>(Landroid/os/Messenger;)V') == 1
	os.write_file(work + '/anonymous-references.json', json2.encode({
		'argv':   json2.Any(['rg', '-l', '-F', 'Landroid/os/Messenger$1;', baseline])
		'output': json2.Any(refs.output)
	},
		prettify: true
	) + '\n')!
	for name in os.ls(tools)! {
		if name.ends_with('.jar') { pins[tools + '/' + name] = digest(tools + '/' + name)! }
	}
	os.write_file(work + '/inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	command(work, 'compile', [compiler, '-no-parallel', '-gc', 'boehm', '-nocache', '-path',
		'@vlib|' + work, '-cc', 'cc', '-o', work + '/check', work + '/check.v'], true)!
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
		assert os.walk_ext(work + '/' + kind + '-roundtrip', '.smali').len == if kind == 'baseline' {
			8
		} else {
			11
		}
	}
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
	os.write_file(work + '/inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	for path in os.walk_ext(work, '.v') { pins[path] = digest(path)! }
	for path in os.walk_ext(work, '.dex') { pins[path] = digest(path)! }
	for directory in ['proof', 'patched-roundtrip', 'second-roundtrip'] {
		for path in os.walk_ext(work + '/' + directory, '.smali') { pins[path] = digest(path)! }
	}
	pins[work + '/check'] = digest(work + '/check')!
	os.write_file(work + '/receipt.json', json2.encode(pins, prettify: true) + '\n')!
	println('MESSENGER-CHECK-PASS five-changed three-added retained-Handler-Binder-Parcel outside-native70 API28-wire stable-second-DEX')
}
