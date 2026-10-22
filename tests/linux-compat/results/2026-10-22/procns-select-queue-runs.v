import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	mut selected := map[string]string{}
	for arch in ['arm', 'x86'] {
		state := area + '/states/queue-after-' + arch
		receipt := (json2.decode[json2.Any](os.read_file(state + '/receipt.json')!)!).as_map()
		assert receipt['exit_code']!.int() == 0 && receipt['detail']!.str() == ''
		assert receipt['kernel_commit']!.str() == os.read_file(area + '/queue-fix/commit.txt')!.trim_space()
		assert receipt['init_sha256']!.str() == digest(area + '/states/build-init2-' + arch + '/init')!
		assert receipt['manifest_sha256']!.str() == digest(area + '/source-manifest3.json')!
		log := os.read_file(state + '/serial.log')!
		assert receipt['serial_sha256']!.str() == digest(state + '/serial.log')!
		assert log.contains('LINUX PROCNS: PASS') && !log.contains('LINUX PROCNS FAIL') && !log.contains('timed out')
		mut rows := [0, 0, 0, 0]
		mut storage := 0
		mut readers := 0
		for raw in log.split_into_lines() {
			line := raw.trim_space()
			if line.starts_with('LINUX PROCNS SLAB:') {
				fields := line.fields()
				kind := fields[3].all_after('=').int()
				counts := fields[5].all_after('=').split('/')
				assert kind >= 0 && kind < 4 && counts.len == 2 && counts[0] == counts[1]
				rows[kind]++
			} else if line.starts_with('LINUX PROCNS STORAGE:') {
				assert line.contains('errors=0 ') && line.contains('written_after_free=0/0 ')
				for field in line.fields() {
					if field.starts_with('big_pages=') {
						values := field.all_after('=').split('/')
						assert values.len == 2 && values[0] == values[1]
					}
				}
				storage++
			} else if line.starts_with('LINUX PROCNS READER:') {
				assert line.all_after('calls=').int() > 0
				readers++
			}
		}
		assert storage == 4 && readers == 4
		for count in rows { assert count == if arch == 'arm' { 18 } else { 14 } }
		selected[arch + '-after'] = state
		selected[arch + '-before'] = area + '/states/' + if arch == 'arm' { 'final2-before-arm' } else { 'final3-before-x86' }
		selected[arch + '-reference'] = area + '/states/final2-reference-' + arch
	}
	os.write_file(area + '/selected-runs.json', json2.encode(selected, prettify: true) + '\n')!
	println('Selected both strict-flat Q candidates plus valid unchanged-ELF baseline/Linux references')
}
