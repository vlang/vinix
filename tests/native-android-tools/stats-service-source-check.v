// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the unsupported-service provider without inventing a stats backend.
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
	assert os.args.len == 7, 'V REPO FRESH_OUTPUT BASELINE_SMALI JAVA SMALI_TOOLS'
	compiler, repo := os.real_path(os.args[1]), os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	baseline, java, tools := os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	assert !os.exists(work) && !os.is_link(work) && work != repo && !work.starts_with(repo + '/')
	os.mkdir_all(work + '/androidtools')!
	provider := repo + '/tests/native-android-tools/androidtools/framework_stats_service.v'
	checks := repo + '/tests/native-android-tools/statsservicecheck/main.v'
	integration := repo + '/tests/native-android-tools/androidtools/framework.v'
	mut pins := map[string]string{}
	for path in [compiler, java, os.real_path(@FILE), provider, checks, integration] {
		pins[path] = digest(path)!
	}
	assert os.read_file(integration)!.count(' framework_stats_service(smali)!\n') == 1
	assert os.read_file(integration)!.contains(' framework_unmanaged_queries(smali)!\n framework_stats_service(smali)!\n framework_assemble(')
	os.cp(provider, work + '/androidtools/provider.v')!
	os.cp(checks, work + '/check.v')!
	target := '/android/app/ContextImpl.smali'
	pins[baseline + target] = digest(baseline + target)!
	assert !os.exists(baseline + '/android/app/StatsManager.smali') && !os.is_link(baseline + '/android/app/StatsManager.smali')
	for kind in ['baseline', 'proof'] {
		os.mkdir_all(os.dir(work + '/' + kind + target))!
		os.cp(baseline + target, work + '/' + kind + target)!
	}
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
			1
		} else {
			2
		}
	}
	command(work, 'reassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*',
		'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', work + '/patched-roundtrip',
		'-o', work + '/roundtrip.dex'], true)!
	assert os.is_file(work + '/roundtrip.dex') && os.file_size(work + '/roundtrip.dex') > 112
	command(work, 'second-disassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp',
		tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2',
		work + '/roundtrip.dex', '-o', work + '/second-roundtrip'], true)!
	assert os.walk_ext(work + '/second-roundtrip', '.smali').len == 2
	command(work, 'roundtrip', [work + '/check', work, '--roundtrip'], false)!
	for path, pin in pins {
		assert digest(path)! == pin, 'input changed: ' + path
	}
	os.write_file(work + '/inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	for path in os.walk_ext(work, '.v') { pins[path] = digest(path)! }
	for path in os.walk_ext(work, '.dex') { pins[path] = digest(path)! }
	for kind in ['proof', 'patched-roundtrip', 'second-roundtrip'] {
		for name in ['android/app/ContextImpl.smali', 'android/app/StatsManager.smali'] {
			pins[work + '/' + kind + '/' + name] = digest(work + '/' + kind + '/' + name)!
		}
	}
	pins[work + '/check'] = digest(work + '/check')!
	os.write_file(work + '/receipt.json', json2.encode(pins, prettify: true) + '\n')!
	println('STATS-SERVICE-CHECK-PASS memberless-type typed-null API28-assembly retained-fallbacks stable-second-DEX')
}
