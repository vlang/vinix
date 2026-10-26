// SPDX-License-Identifier: GPL-2.0-or-later
// Compose pinned370 host auditors and the unchanged canonical-readback wrapper.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/maps372-host-review-composition-2026-10-26'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const references = {
	'maps370-host-peer-check.v': 'f391274158126331609a49399f1830985509656ba27fa46a38d6a4641d5228fe'
	'maps370-prelaunch-command.v': '57ef766a8d3c195f33fb2dc6ff4da9c25008a789a280938299c45bee4222a549'
	'maps370-completed-readback.v': '1326b27355b51af206036d7af38f45fe65364de4a6ffd28010377d7bd43310ca'
}
const generator = state + '/maps372-generator-composition-b-2026-10-26/maps372-generate.v'
const review = state + '/maps372-prelaunch-composition-2026-10-26/maps372-prelaunch-review.v'
const review_source_pin = '449771f0fd36d1a507547f3a9d559f9037f6ddb4d6a6ba47ab0027e787c7e827'
const review_binary_pin = 'c094db46d1bb362e765e4964a6dc9222ccf218d5ae3134ef600aa4d5e9ee14ce'
const generation_pin = 'ea8a788c9d5fe1e074b15e9e3b301e346fa6a7509a2eb2878a61299d09786ffb'
const runner_source_pin = '07fc948c5affd1142f2b86c50024278e719d3f68339f4697864a16103fa36d67'
const runner_binary_pin = '741952dfd7bed0f1408e16a7b966771cbe556f69ed3954fe4672f270f2a3787d'

fn hash(path string) !string {
	assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular
	return sha256.sum(os.read_bytes(path)!).hex()
}
fn once(text string, before string, after string) !string {
	assert text.count(before) == 1, 'unique replacement required: ' + before
	return text.replace(before, after)
}
fn derive(before string, name string) !string {
	mut text := before
	for token in ['maps370', 'Maps370', 'MAPS370', "'370'"] { text = text.replace(token, token.replace('370', '372')) }
	text = text.replace('370 PRELAUNCH_SHA', '372 PRELAUNCH_SHA')
	text = text.replace('74e1d74b9ecf51e302f2802a2d291ff15f1d1793495d67c7c108d1d5350a884b',
		'3b345e1661ca9f5b616f5abe25c9f4abc1df383204d25333477dae69221a8d21')
	if name == 'maps370-host-peer-check.v' {
		for old_pin, new_pin in {
			'515cf9c83cf9c13c6957904a5bfc5458f452791de8854880fe682c214ecd396a': 'e7753d6eb876980fb6fecaad1b5e68a3616f23f329d7773808e9f775110c09c0'
			'16665b939253625039bca65822d964af49809a3d4b12e290562e5f4979e89a93': review_source_pin
			'd871020faca0c5b3f88c46de25895924e7958c212457c503064bc61150ca043d': review_binary_pin
			'c269ff3cc6582fd27a86d5d3821e07a573220c07cd46632a83e862fbf35b8802': '04799744135aff1d13fda345eacfdbf9a59b118873387a1ce519be8ec23edefa'
			'9f52eb8f69aaaa6d57f8ca3ce11dd20c870de8032bc821aff5e7527473334c93': '71e311764ece295185656854294a514a9c641419c567d5f96ac66f52f4b89750'
		} { text = once(text, old_pin, new_pin)! }
		assert text.count('b3b7cc8a7f669c0b302c1b7d842c88915c655df7173b805339ab8301a8599633') == 2
		text = text.replace('b3b7cc8a7f669c0b302c1b7d842c88915c655df7173b805339ab8301a8599633',
			'47741733ef500bc4a62b3fa9f303978ef4987bb1e7b71853e9e0a2a9d24fe121')
		text = once(text, "repo + '/tests/native-android-ws/maps372-prelaunch-review.v'", "'" + review + "'")!
		text = once(text, "repo + '/tests/native-android-ws/maps372-generate.v'", "'" + generator + "'")!
	} else if name == 'maps370-prelaunch-command.v' {
		text = once(text, 'd871020faca0c5b3f88c46de25895924e7958c212457c503064bc61150ca043d', review_binary_pin)!
	} else {
		text = once(text, 'd8fb503f68deb073e351d3a292b08e03b80aa181395647dc18bb20d231526330', runner_binary_pin)!
		text = once(text, '11ab2cd3ac79ec8c24810f127c4a163d267d998fc1ea03f60258ef9e33e84ac1', runner_source_pin)!
		for marker in ['fn qualify(manifest string) ! {', "argv := [runner, 'verify', manifest]", 'assert status,'] { assert text.contains(marker) }
	}
	return text
}
fn write_json[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }
fn command(label string, argv []string) ! {
	started := time.utc().str()
	pin := hash(argv[0])!
	r := os.exec(argv)
	os.write_file(root + '/' + label + '.log', r.output)!
	write_json(root + '/' + label + '.json', {
		'argv': json2.Any(argv), 'cwd': json2.Any(os.getwd()),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
		'exit_code': json2.Any(r.exit_code), 'program_sha256_before': json2.Any(pin),
		'program_sha256_after': json2.Any(hash(argv[0])!), 'output_sha256': json2.Any(hash(root + '/' + label + '.log')!),
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
	assert hash(compiler)! == compiler_pin && hash(review)! == review_source_pin
	mut derived := map[string]string{}
	for name, pin in references {
		path := repo + '/tests/native-android-ws/' + name
		assert hash(path)! == pin
		derived[name.replace('370', '372')] = derive(os.read_file(path)!, name)!
	}
	if os.args[1] == '--self-test' { println('MAPS372-HOST-REVIEW-COMPOSITION-SELF-TEST-PASS'); return }
	assert !os.exists(root) && !os.is_link(root)
	os.mkdir(root)!
	os.cp(@FILE, root + '/composer.v')!
	os.cp(os.executable(), root + '/composer')!
	os.mkdir(root + '/generated-c')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VTMP', root + '/generated-c', true)
	mut source_pins := map[string]string{}
	for name, text in derived {
		os.cp(repo + '/tests/native-android-ws/' + name.replace('372', '370'), root + '/' + name.replace('372', '370'))!
		os.write_file(root + '/' + name, text)!
		source_pins[name] = hash(root + '/' + name)!
		command('compile-' + name, [compiler, '-nocache', '-cc', '/usr/bin/cc', '-o', root + '/' + name.trim_string_right('.v'), root + '/' + name])!
	}
	command('comparator-readback', [root + '/maps372-host-peer-check', '--comparator'])!
	command('runner-readback', [root + '/maps372-host-peer-check', '--runner', generation_pin, runner_source_pin, runner_binary_pin])!
	write_json(root + '/derivation.json', {
		'reference_source_sha256': json2.decode[json2.Any](json2.encode(references))!,
		'derived_source_sha256': json2.decode[json2.Any](json2.encode(source_pins))!,
		'composer_source_sha256': json2.Any(hash(@FILE)!),
		'scope': json2.Any('Exact372 paths and qualified371/recorded372 pins only; original complete290, exact272 live/retained closures, typed prelaunch command, canonical runner verification and status/pin retention unchanged. No guest. Canonical reader is compiled, not executed here.'),
	})!
	mut entries := map[string]string{}
	inventory(root, '', mut entries)!
	write_json(root + '/sha256.json', entries)!
	println('MAPS372-HOST-REVIEW-COMPOSITION-PASS manifest=' + hash(root + '/sha256.json')!)
}
