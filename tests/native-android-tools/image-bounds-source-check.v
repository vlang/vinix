// SPDX-License-Identifier: GPL-2.0-or-later
// Validate the production ImageView provider in an isolated V module and DEX.
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn command(work string, label string, argv []string, quiet bool) ! {
	result := os.exec(argv)
	os.write_file(work + '/' + label + '.json', json2.encode({
		'argv': json2.Any(argv), 'exit_code': json2.Any(result.exit_code), 'output': json2.Any(result.output)
	}, prettify: true) + '\n')!
	assert result.exit_code == 0, label + ': ' + result.output
	if quiet { assert result.output.trim_space() == '', label + ': unexpected diagnostics' }
}

fn main() {
	$if prod { panic('live assertions required') }
	assert os.args.len == 7, 'usage: image-bounds-source-check V REPO FRESH_OUTPUT BASELINE_SMALI JAVA SMALI_TOOLS'
	compiler, repo := os.real_path(os.args[1]), os.real_path(os.args[2])
	work := os.abs_path(os.args[3])
	baseline, java, tools := os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	assert !os.exists(work) && !os.is_link(work) && work != repo && !work.starts_with(repo + '/')
	os.mkdir_all(work + '/androidtools')!
	os.mkdir_all(work + '/proof/android/widget')!
	provider := repo + '/tests/native-android-tools/androidtools/framework_image_bounds.v'
	checks := repo + '/tests/native-android-tools/imageboundscheck/main.v'
	integration := repo + '/tests/native-android-tools/androidtools/framework.v'
	input := baseline + '/android/widget/ImageView.smali'
	styleable := baseline + '/com/android/internal/R$styleable.smali'
	mut pins := map[string]string{}
	for path in [compiler, java, @FILE, provider, checks, integration, input, styleable] { pins[path] = digest(path)! }
	assert os.read_file(integration)!.contains(' framework_platform_fragments(smali)!\n framework_image_bounds(smali)!')
	attrs := os.read_file(styleable)!
	assert attrs.contains('.field public static final ImageView_maxWidth:I = 0x3\n')
	assert attrs.contains('.field public static final ImageView_maxHeight:I = 0x4\n')
	os.cp(provider, work + '/androidtools/provider.v')!
	os.cp(checks, work + '/check.v')!
	os.cp(input, work + '/proof/android/widget/ImageView.smali')!
	for name in os.ls(tools)! { if name.ends_with('.jar') { pins[tools + '/' + name] = digest(tools + '/' + name)! } }
	command(work, 'compile', [compiler, '-nocache', '-path', '@vlib|' + work, '-cc', 'cc', '-o', work + '/check', work + '/check.v'], true)!
	command(work, 'source', [work + '/check', work], false)!
	for kind in ['baseline', 'patched'] {
		directory := work + '/' + kind + '-smali'
		os.mkdir_all(directory + '/android/widget')!
		from := if kind == 'baseline' { input } else { work + '/proof/android/widget/ImageView.smali' }
		os.cp(from, directory + '/android/widget/ImageView.smali')!
		dex := work + '/' + kind + '.dex'
		assert !os.exists(dex)
		command(work, kind + '-assemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', directory, '-o', dex], true)!
		assert os.is_file(dex) && os.file_size(dex) > 112, 'fresh DEX required'
		command(work, kind + '-disassemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2', dex, '-o', work + '/' + kind + '-roundtrip'], true)!
	}
	command(work, 'roundtrip', [work + '/check', work, '--roundtrip'], true)!
	for path, pin in pins { assert digest(path)! == pin, 'input changed: ' + path }
	for path in ['check.v', 'androidtools/provider.v', 'check', 'baseline.dex', 'patched.dex', 'proof/android/widget/ImageView.smali'] { pins[work + '/' + path] = digest(work + '/' + path)! }
	os.write_file(work + '/receipt.json', json2.encode(pins, prettify: true) + '\n')!
	println('IMAGE-BOUNDS-CHECK-PASS exact-property-delta default-and-XML-init malformed-rejection API28-DEX-roundtrip')
}
