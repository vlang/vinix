// SPDX-License-Identifier: GPL-2.0-or-later
// Freeze production providers and run focused source and four-class DEX checks.
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn command(work string, name string, argv []string, quiet bool) ! {
	r := os.exec(argv)
	os.write_file(work + '/' + name + '.json', json2.encode({
		'argv':      json2.Any(argv)
		'exit_code': json2.Any(r.exit_code)
		'output':    json2.Any(r.output)
	}, prettify: true) + '\n')!
	assert r.exit_code == 0, name + ': ' + r.output
	if quiet {
		assert r.output.trim_space() == '', name + ': unexpected diagnostics'
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
	mut pins := map[string]string{}
	provider := repo + '/tests/native-android-tools/androidtools/framework_pending_intent_successor.v'
	integration := repo + '/tests/native-android-tools/androidtools/framework_pending_intent.v'
	helper := repo + '/tests/native-android-tools/androidtools/framework.v'
	check := repo + '/tests/native-android-tools/pendingintentcheck/main.v'
	for path in [compiler, java, @FILE, provider, integration, helper, check] {
		pins[path] = digest(path)!
	}
	assert os.read_file(integration)!.contains(' text = framework_pending_intent_source(text)!\n os.write_file(path, text)!')
	os.cp(provider, work + '/androidtools/provider.v')!
	os.cp(check, work + '/check.v')!
	// Compile the exact production method replacer, not a copied test substitute.
	source := os.read_file(helper)!
	start := source.index('pub fn framework_replace_method(') or { panic('missing production replacer') }
	end := start + (source[start..].index('\n}\n') or { panic('unterminated production replacer') }) + 3
	os.write_file(work + '/androidtools/replace.v', 'module androidtools\n' + source[start..end])!
	for name in ['PendingIntent', 'PendingIntent$VinixToken', 'PendingIntent$VinixCreator',
		'PendingIntent$CanceledException'] {
		path := baseline + '/android/app/' + name + '.smali'
		pins[path] = digest(path)!
		if name == 'PendingIntent' {
			assert pins[path] == '84a6c096009bf0173f7dd70461c7d97337a9b5a3a2785402dc818a3638b8a38a', 'pinned deployed predecessor required'
		}
		for kind in ['baseline', 'patched'] {
			dest := work + '/' + kind + '/android/app/' + name + '.smali'
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
		assert os.walk_ext(work + '/' + kind + '-roundtrip', '.smali').len == 4
	}
	command(work, 'reassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*',
		'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', work + '/patched-roundtrip',
		'-o', work + '/roundtrip.dex'], true)!
	assert os.is_file(work + '/roundtrip.dex') && os.file_size(work + '/roundtrip.dex') > 112
	command(work, 'second-disassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp',
		tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2',
		work + '/roundtrip.dex', '-o', work + '/second-roundtrip'], true)!
	assert os.walk_ext(work + '/second-roundtrip', '.smali').len == 4
	command(work, 'roundtrip', [work + '/check', work, '--roundtrip'], false)!
	for path, pin in pins {
		assert digest(path)! == pin, 'input changed: ' + path
	}
	for path in os.walk_ext(work, '.v') { pins[path] = digest(path)! }
	for path in os.walk_ext(work, '.dex') { pins[path] = digest(path)! }
	for path in os.walk_ext(work + '/patched-roundtrip', '.smali') { pins[path] = digest(path)! }
	for path in ['check', 'patched/android/app/PendingIntent.smali'] {
		pins[work + '/' + path] = digest(work + '/' + path)!
	}
	os.write_file(work + '/receipt.json', json2.encode(pins, prettify: true) + '\n')!
	println('PENDING-INTENT-CHECK-PASS source-refusals API28-assembly four-classes stable-roundtrip')
}
