// SPDX-License-Identifier: GPL-2.0-or-later
// Reuse the frozen Maps298 runner's typed inventory and checker to seal its aborted preparation.
module main

import crypto.sha256
import json2
import os
import time

const work = '/Users/alex/.local/state/vinix/android/maps298-failure-sealer-build-2026-10-25'
const source = 'tests/native-android-ws/maps298-failure-seal.v'

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 1
	assert !os.exists(work) && !os.is_link(work)
	original := os.read_file('tests/native-android-ws/maps298-run.v')!
	assert sha256.sum(original.bytes()).hex() == '5d220b06590bc0823f12c6d5071dc60af51a9dc284a383afb77cb907c1f17ed1'
	compiler := 'build/android-maps/queue284-tools/v_old276'
	assert sha256.sum(os.read_bytes(compiler)!).hex() == '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
	os.mkdir_all(work)!
	own := os.read_file(source)!
	main_source := own.all_after('/* FAILURE_MAIN\n').all_before('\nEND_FAILURE_MAIN */')
	assert main_source.starts_with('fn main()')
	os.write_file(work + '/seal.v', original.all_before('fn main()') + main_source + '\n')!
	os.write_file(work + '/generator.v', own)!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('COPYFILE_DISABLE', '1', true)
	argv := [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', work + '/seal', work + '/seal.v']
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(work + '/build.log', r.output)!
	os.write_file(work + '/build-receipt.json', json2.encode({
		'argv': json2.Any(argv)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(r.exit_code)
		'compiler_sha256': json2.Any(sha256.sum(os.read_bytes(compiler)!).hex())
		'source_sha256': json2.Any(sha256.sum(os.read_bytes(work + '/seal.v')!).hex())
	}, prettify: true) + '\n')!
	assert r.exit_code == 0, r.output
	sealed := os.exec([work + '/seal'])
	print(sealed.output)
	exit(sealed.exit_code)
}

/* FAILURE_MAIN
fn main() {
	$if prod { panic('assertions required') }
	if os.exists(retained + '/sha256.json') { panic('fresh failure seal required') }
	if os.exists(config) || os.exists(output) { panic('failure expected before config and launch') }
	os.setenv('COPYFILE_DISABLE', '1', true)
	clone(target, retained + '/failed-preparation/maps298')!
	clone(outer_build, retained + '/runner-build')!
	clone('/Users/alex/.local/state/vinix/android/maps298-failure-sealer-build-2026-10-25', retained + '/failure-sealer')!
	module_arg := quote(target + '/module')
	boot_arg := quote(target + '/vm/boot.img')
	hasher := quote('build/android-maps/maps298-run-recorded') + ' --hash-stdin'
	producer := quote(os.find_abs_path_of_executable('tar')!) + ' --format=ustar -b 1 -C ' + module_arg + ' -cf - .'
	producer_command := 'set -o pipefail; ' + producer + ' | ' + hasher
	fat_command := 'set -o pipefail; ' + quote(os.find_abs_path_of_executable('mtype')!) + ' -i ' + boot_arg + ' ::/boot/qemu-runtime.tar | ' + hasher
	produced := checked(['/bin/zsh', '-c', producer_command])!.trim_space()
	readback := checked(['/bin/zsh', '-c', fat_command])!.trim_space()
	if produced.len != 64 || produced != readback { panic('failed target archive differs') }
	write_json(retained + '/failure-archive-readback.json', {
		'producer_command': producer_command
		'fat_readback_command': fat_command
		'producer_sha256': produced
		'fat_readback_sha256': readback
	})!
	write_json(retained + '/failure.json', {
		'phase': json2.Any('prepare; creating archive-stream.json after archive-stage exit0 and matched producer/FAT hashes')
		'exit_code': json2.Any(1)
		'launch_created': json2.Any(false)
		'error': json2.Any('V panic: failed to open file /Users/alex/.local/state/vinix/android/maps298-2026-10-25/archive-stream.json')
		'error_origin': json2.Any('Process output copied from terminal tool result; no output redirection existed before the failure.')
		'disk_observation': json2.Any('df reported108MiB immediately afterward; no errno was present in the panic.')
		'sealed_utc': json2.Any(time.utc().str())
		'sealer_binary_sha256': json2.Any(hash(os.executable())!)
		'runner_source_sha256': json2.Any(hash(source)!)
		'native296_manifest_sha256': json2.Any('a27c6341933371e7c0e70dfa6de1b8ce3ab67d5acb69d2e6ea0ed27bb0a36f87')
		'native296_sha256': json2.Any('ddea604e0759bf57587231ed0634f5586771c6266ed88d6bfcecb74ee73e0d0a')
		'framework296b_manifest_sha256': json2.Any('b8d69c2b136873eb75d8891099295cf6b99d56e6144fdae394771d87078442e5')
		'framework296b_sha256': json2.Any('1a8e5c929c23f842561fbe2ea30f403327a317d3b27984c0280b9dd509b74200')
	})!
	write_json(retained + '/sha256.json', tree(retained, true)!)!
	verify(hash(retained + '/sha256.json')!)!
	println('MAPS298-FAILED-PREPARATION-SEALED manifest=' + hash(retained + '/sha256.json')!)
}
END_FAILURE_MAIN */
