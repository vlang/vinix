// SPDX-License-Identifier: GPL-2.0-or-later
// Compute the source pin in V and preserve the actual outer builder action.
module main

import crypto.sha256
import json2
import os
import time

fn hash(path string) !string {
	assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn main() {
	assert os.args.len == 3
	revision := os.args[1]
	assert revision.len == 40 && revision.bytes().all(it in '0123456789abcdef'.bytes())
	recorder := os.args[2]
	assert os.real_path(recorder) == recorder
	source := '/Users/alex/code/vinix/tests/native-android-ws/intent-uri371-run.v'
	prefix := '/Users/alex/.local/state/vinix/android/intent-uri371-run-bootstrap-launch-2026-10-26'
	for suffix in ['-before.json', '-command.json', '.log'] { assert !os.exists(prefix + suffix) }
	argv := [recorder, revision, hash(source)!]
	mut receipt := {'argv': json2.Any(argv), 'cwd': json2.Any(os.getwd()),
		'started_utc': json2.Any(time.utc().str()), 'executable_sha256_before': json2.Any(hash(recorder)!),
		'launcher_source_sha256': json2.Any(hash(@FILE)!),
		'launcher_binary_sha256': json2.Any(hash(os.executable())!)}
	os.write_file(prefix + '-before.json', json2.encode(receipt, prettify: true) + '\n')!
	println('INTENT371-BOOTSTRAP-LAUNCH source=' + argv[2])
	result := os.exec(argv)
	os.write_file(prefix + '.log', result.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	receipt['executable_sha256_after'] = hash(recorder)!
	receipt['output_sha256'] = hash(prefix + '.log')!
	os.write_file(prefix + '-command.json', json2.encode(receipt, prettify: true) + '\n')!
	print(result.output)
	assert result.exit_code == 0, result.output
	assert receipt['executable_sha256_before']! == receipt['executable_sha256_after']!
}
