// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the qualified370 independent comparator, adding the exact371 getter contract.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/maps372-prelaunch-composition-2026-10-26'
const generator = state + '/maps372-generator-composition-b-2026-10-26/maps372-generate.v'
const generator_pin = '47741733ef500bc4a62b3fa9f303978ef4987bb1e7b71853e9e0a2a9d24fe121'
const original = repo + '/tests/native-android-ws/maps370-prelaunch-review.v'
const original_pin = '16665b939253625039bca65822d964af49809a3d4b12e290562e5f4979e89a93'
const source = root + '/maps372-prelaunch-review.v'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const build_root = state + '/maps372-prelaunch-review-build-2026-10-26'

fn hash(path string) !string {
	assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular
	return sha256.sum(os.read_bytes(path)!).hex()
}
fn once(text string, before string, after string) !string {
	assert text.count(before) == 1, 'unique replacement required: ' + before
	return text.replace(before, after)
}
fn block(text string, version string) string {
	begin := '\n// BEGIN SHARED FRAMEWORK' + version + ' CONTRACT\n'
	end := '\n// END SHARED FRAMEWORK' + version + ' CONTRACT\n'
	assert text.count(begin) == 1 && text.count(end) == 1
	return text.all_after(begin).all_before(end)
}
fn derive(before string, generated string) !string {
	mut text := before
	for label in ['maps370', 'Maps370', 'MAPS370', "'370'"] {
		text = text.replace(label, label.replace('370', '372'))
	}
	text = text.replace('review 370 PRELAUNCH_SHA', 'review 372 PRELAUNCH_SHA')
	text = once(text, block(text, '369'), block(generated, '369'))!
	text = once(text, "const generator_reference = '/Users/alex/code/vinix/tests/native-android-ws/maps372-generate.v'",
		"const generator_reference = '" + generator + "'")!
	text = once(text, "const generator_source_pin = 'b3b7cc8a7f669c0b302c1b7d842c88915c655df7173b805339ab8301a8599633'",
		"const generator_source_pin = '" + generator_pin + "'")!
	text = once(text, "generator_commit + ':tests/native-android-ws/maps372-generate.v'",
		"generator_commit + ':tests/native-android-ws/maps370-generate.v'")!
	text = once(text, 'assert sha256.sum(committed_generator.bytes()).hex() == generator_source_pin',
		"assert sha256.sum(committed_generator.bytes()).hex() == 'b3b7cc8a7f669c0b302c1b7d842c88915c655df7173b805339ab8301a8599633'\n\tderived_generator := os.read_file(generator_reference)!\n\tfor version in ['359', '361', '365', '367'] {\n\t\tassert shared_contract(derived_generator, version) == shared_contract(committed_generator, version)\n\t}")!
	text = once(text, 'shared_contract(committed_generator, version),', 'shared_contract(derived_generator, version),')!
	for before_pin, after_pin in {
		'9f52eb8f69aaaa6d57f8ca3ce11dd20c870de8032bc821aff5e7527473334c93': '71e311764ece295185656854294a514a9c641419c567d5f96ac66f52f4b89750'
		'74e1d74b9ecf51e302f2802a2d291ff15f1d1793495d67c7c108d1d5350a884b': '3b345e1661ca9f5b616f5abe25c9f4abc1df383204d25333477dae69221a8d21'
	} { text = once(text, before_pin, after_pin)! }
	getter_test := generated.all_after('\nfn getter371_self_test() ! {').all_before('\nfn self_test(output string) ! {')
	assert getter_test.len > 0 && getter_test.contains('assert rejected == 7')
	text = once(text, '\nfn self_test() ! {', '\nfn getter371_self_test() ! {' + getter_test + '\nfn self_test() ! {\n\tgetter371_self_test()!')!
	text = once(text, "'framework369_build_files_checked': json2.Any(framework_files)",
		"'qualified_framework_revision': json2.Any(371)\n\t\t'exact_null_getter_source_and_dex': json2.Any(true)\n\t\t'framework369_build_files_checked': json2.Any(framework_files)")!
	for version in ['359', '361', '365', '367', '369'] {
		assert block(text, version) == block(generated, version)
	}
	assert text.contains("review.number == '372'") && text.contains("startup_seconds']!.int() == 600")
	assert text.contains('before.len == 109 && after.len == 109')
	assert text.contains("'unchanged_runtime_files': json2.Any(106)")
	return text
}
fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}
fn command(label string, argv []string) ! {
	started := time.utc().str()
	pin := hash(argv[0])!
	r := os.exec(argv)
	os.write_file(root + '/' + label + '.log', r.output)!
	write_json(root + '/' + label + '.json', {
		'argv': json2.Any(argv), 'cwd': json2.Any(os.getwd()),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
		'exit_code': json2.Any(r.exit_code), 'program_sha256_before': json2.Any(pin),
		'program_sha256_after': json2.Any(hash(argv[0])!),
		'output_sha256': json2.Any(hash(root + '/' + label + '.log')!),
	})!
	assert r.exit_code == 0 && hash(argv[0])! == pin, r.output
	print(r.output)
}
fn inventory(path string, prefix string, mut entries map[string]string) ! {
	for name in os.ls(path + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		full := path + '/' + key
		assert !os.is_link(full)
		match os.lstat(full)!.get_filetype() {
			.regular { entries[key] = hash(full)! }
			.directory { inventory(path, key, mut entries)! }
			else { return error('ordinary evidence required: ' + full) }
		}
	}
}
fn main() {
	$if prod { panic('assertions required') }
	assert os.getwd() == repo && os.args.len == 2 && os.args[1] in ['--self-test', 'compose']
	assert hash(original)! == original_pin && hash(generator)! == generator_pin
	assert hash(compiler)! == compiler_pin
	text := derive(os.read_file(original)!, os.read_file(generator)!)!
	assert text == derive(os.read_file(original)!, os.read_file(generator)!)!
	if os.args[1] == '--self-test' { println('MAPS372-PRELAUNCH-COMPOSITION-SELF-TEST-PASS'); return }
	for path in [root, build_root] { assert !os.exists(path) && !os.is_link(path), path }
	os.mkdir(root)!
	os.cp(@FILE, root + '/composer.v')!
	os.cp(os.executable(), root + '/composer')!
	os.cp(original, root + '/maps370-review-reference.v')!
	os.cp(generator, root + '/maps372-generator-reference.v')!
	os.write_file(source, text)!
	os.mkdir(root + '/generated-c')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VTMP', root + '/generated-c', true)
	command('compile-bootstrap', [compiler, '-nocache', '-cc', '/usr/bin/cc', '-o', root + '/bootstrap', source])!
	command('review-self-test', [root + '/bootstrap', '--self-test'])!
	command('recorded-review-build', [root + '/bootstrap', 'build', build_root])!
	write_json(root + '/derivation.json', {
		'reference_source_sha256': original_pin, 'generator_source_sha256': generator_pin,
		'composer_source_sha256': hash(@FILE)!, 'derived_source_sha256': hash(source)!,
		'scope': 'Qualified370 comparator preserved; exact372 labels and371 framework pins, complete shared369 block copied verbatim from composed generator, exact getter negatives and immutable370 contract provenance added. No guest.',
	})!
	mut entries := map[string]string{}
	inventory(root, '', mut entries)!
	write_json(root + '/sha256.json', entries)!
	println('MAPS372-PRELAUNCH-COMPOSITION-PASS source=' + hash(source)! + ' binary=' + hash(build_root + '/program')! + ' manifest=' + hash(root + '/sha256.json')!)
}
