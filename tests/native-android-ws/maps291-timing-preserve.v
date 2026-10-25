// Retain and verify the derivative Maps291 timing evidence; no source-run writes.
module main

import crypto.sha256
import json2
import os
import time

const root = '/Users/alex/.local/state/vinix/android/maps291-timing-2026-10-25'
const repository = '/Users/alex/code/vinix'
const serial = repository + '/build/android-maps/attempt291/google-maps/serial.log'
const serial_pin = '60a9e74bdecc618c6410800532602782e1262ae40d5980de4fc4853775f885f9'

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn record(label string, argv []string) ! {
	assert !os.exists(root + '/' + label + '-receipt.json')
	started := time.utc().str()
	result := os.exec(argv)
	os.write_file(root + '/' + label + '.log', result.output)!
	os.write_file(root + '/' + label + '-receipt.json', json2.encode({
		'argv': json2.Any(argv)
		'command_sha256': json2.Any(hash(os.real_path(argv[0]))!)
		'exit_code': json2.Any(result.exit_code)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
	}, prettify: true) + '\n')!
	assert result.exit_code == 0, label
}

fn retain(label string, from string, to string) ! {
	assert !os.exists(to)
	os.mkdir_all(os.dir(to))!
	record(label, ['/bin/cp', '-c', from, to])!
	assert hash(from)! == hash(to)!, label
}

fn main() {
	$if prod { panic('assertions required') }
	assert !os.exists(root + '/sha256.json')
	assert hash(serial)! == serial_pin
	before := {'scan.json': hash(root + '/scan.json')!, 'scan.txt': hash(root + '/scan.txt')!}
	tracked := repository + '/tests/native-android-ws/maps-timing.v'
	revision := os.exec(['/usr/bin/git', '-C', repository, 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	commit := revision.output.trim_space()
	committed := os.exec(['/usr/bin/git', '-C', repository, 'show', commit + ':tests/native-android-ws/maps-timing.v'])
	assert committed.exit_code == 0 && committed.output == os.read_file(tracked)!
	retain('retain-scanner-source', tracked, root + '/source/maps-timing.v')!
	retain('retain-scanner', repository + '/build/android-maps/maps-timing289-scan', root + '/tools/maps-timing289-scan')!
	retain('retain-serial', serial, root + '/input/serial.log')!
	retain('retain-sealer-source', repository + '/tests/native-android-ws/inflater-trace-seal.v', root + '/source/inflater-trace-seal.v')!
	retain('retain-sealer', repository + '/build/android-maps/inflater-trace292-seal', root + '/tools/inflater-trace-seal')!
	os.mkdir_all(root + '/readback')!
	record('readback-scan', [root + '/tools/maps-timing289-scan', 'scan', serial, root + '/readback/scan'])!
	for suffix in ['json', 'txt'] {
		name := 'scan.' + suffix
		assert hash(root + '/' + name)! == before[name]!
		assert os.read_bytes(root + '/' + name)! == os.read_bytes(root + '/readback/' + name)!
	}
	assert hash(serial)! == serial_pin && hash(root + '/input/serial.log')! == serial_pin
	analysis := json2.decode[map[string]json2.Any](os.read_file(root + '/scan.json')!)!
	runs := analysis['analysis']!.as_map()['runs']!.as_array()
	assert runs.len == 1
	assert runs[0].as_map()['source_path']!.str() == serial
	assert runs[0].as_map()['source_sha256']!.str() == serial_pin
	metadata := {
		'argv': json2.Any(os.args)
		'completed_utc': json2.Any(time.utc().str())
		'serial_source_path': json2.Any(serial)
		'serial_resolved_path': json2.Any(os.real_path(serial))
		'serial_sha256': json2.Any(serial_pin)
		'retained_serial': json2.Any('input/serial.log')
		'scanner_source_revision': json2.Any(commit)
		'scanner_source_sha256': json2.Any(hash(root + '/source/maps-timing.v')!)
		'scanner_binary_sha256': json2.Any(hash(root + '/tools/maps-timing289-scan')!)
		'helper_source_sha256': json2.Any(hash(root + '/source/preserve-timing.v')!)
		'helper_binary_sha256': json2.Any(hash(os.executable())!)
		'existing_outputs_preserved': json2.Any(true)
		'readback_outputs_byte_identical': json2.Any(true)
		'sealed_source_run_modified': json2.Any(false)
	}
	os.write_file(root + '/provenance.json', json2.encode(metadata, prettify: true) + '\n')!
	println('MAPS291-TIMING-PRESERVED: exact serial pin, committed source, retained tools and byte-identical scan readback')
}
