// SPDX-License-Identifier: GPL-2.0-or-later
// Derive one fixed consumer owner; do not compile or execute an owner.
module main

import crypto.sha256
import json2
import os

const state = '/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02'
const suite = state + '/source/tests/software-hosted-x11'
const consumer = state + '/native-consumer-tools-01'
const old_owner = suite + '/build-supervision-03.v'
const new_owner = suite + '/build-supervision-consumer-01.v'
const old_runner = state + '/native-supervision-host-01/supervision-check-01'
const new_runner = consumer + '/supervision-check-01'
const records = consumer + '/source-preparation-01'
const owner_sha256 = '0cc0e57c3b0a7a4912aa9104c14293f0d82b6153cce792e63b8fa35c1cf332f1'
const runner_sha256 = '50f096c4a5bc6ab5be9a9cb8ebcec074c66ea1621db71f047ea7f34d7a3db36e'

fn need(ok bool, message string) ! { if !ok { return error(message) } }

fn hash(path string, limit u64) !string {
	before := os.lstat(path)!
	need(before.mode & 0o170000 == 0o100000 && before.size <= limit,
		'requires a bounded ordinary source or runner: ' + path)!
	data := os.read_bytes(path)!
	after := os.lstat(path)!
	need(before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.nlink == after.nlink
		&& before.size == after.size && before.size == u64(data.len)
		&& before.mtime == after.mtime && before.ctime == after.ctime,
		'input changed during read: ' + path)!
	return sha256.sum(data).hex()
}

fn prepare() ! {
	$if prod {} $else { return error('requires production embedded source binding') }
	need(os.args == [os.executable(), '--prepare-consumer-owner'],
		'requires exact --prepare-consumer-owner')!
	need(hash(@FILE, 65536)! == sha256.hexhash($embed_file('prepare-options-consumer.v').to_string()),
		'consumer preparer source changed')!
	need(os.is_dir(consumer) && !os.is_link(consumer) && os.real_path(consumer) == consumer
		&& os.real_path(suite) == suite, 'requires canonical existing bootstrap/source roots')!
	for path in [records, new_owner, new_runner] {
		need(!os.exists(path) && !os.is_link(path), 'requires a new consumer destination: ' + path)!
	}
	need(hash(old_owner, 65536)! == owner_sha256 && hash(old_runner, 1024 * 1024)! == runner_sha256,
		'qualified owner source or original supervision runner differs')!
	before := os.read_file(old_owner)!
	from := "const output_root = state + '/native-supervision-host-01'"
	to := "const output_root = state + '/native-consumer-tools-01'"
	need(before.count(from) == 1, 'fixed output-root binding count differs')!
	after := before.replace(from, to)
	need(after.replace(to, from) == before, 'consumer owner delta is not exactly reversible')!
	os.mkdir(records, mode: 0o700)!
	os.write_file(records + '/before-build-supervision-03.v', before)!
	os.write_file(records + '/after-build-supervision-consumer-01.v', after)!
	os.write_file(new_owner, after)!
	os.cp(old_runner, new_runner)!
	os.chmod(new_runner, int(os.lstat(old_runner)!.mode & 0o777))!
	need(os.lstat(new_owner)!.nlink == 1 && os.lstat(new_runner)!.nlink == 1
		&& hash(new_owner, 65536)! == sha256.hexhash(after)
		&& hash(new_runner, 1024 * 1024)! == runner_sha256,
		'independent consumer source or copied runner differs')!
	need(hash(old_owner, 65536)! == owner_sha256 && hash(old_runner, 1024 * 1024)! == runner_sha256,
		'original owner source or runner changed during preparation')!
	os.write_file(records + '/result.json', json2.encode({
		'outcome': 'PREPARED', 'preparer_sha256': hash(@FILE, 65536)!,
		'owner_before': old_owner, 'owner_before_sha256': owner_sha256,
		'owner_after': new_owner, 'owner_after_sha256': sha256.hexhash(after),
		'delta_before': from, 'delta_after': to, 'replacement_count': '1',
		'runner_before': old_runner, 'runner_after': new_runner,
		'runner_before_sha256': runner_sha256, 'runner_after_sha256': hash(new_runner, 1024 * 1024)!,
		'scope': 'Source-only fixed path derivation and independent byte-verified qualified runner copy. No owner compile, control execution, import or guest.'
	}) + '\n')!
	println('PREPARED consumer owner one-path delta and verified supervision runner copy; no owner execution')
}

fn main() { prepare() or { eprintln(err); exit(1) } }
