import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn object(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	state := area + '/states/diagnostic-kind2b-after-x86'
	before_path := area + '/qmp-queue-diagnostic-kind2b-after-x86-1792687789.json'
	after_path := area + '/qmp-queue-diagnostic-kind2b-after-x86-1792688014.json'
	before := object(before_path)!
	after := object(after_path)!
	assert before['queue_cap']! == '1024' && before['queue_element_size']! == '200'
	assert after['queue_cap']! == '2048' && after['queue_len']! == '0' && after['queue_element_size']! == '200'
	assert after['metadata_geometry_valid']! == 'true' && after['metadata_magic']! == '0x56494e4958424947'
	assert after['metadata_size']! == '409631' && after['metadata_pages']! == '101' && after['metadata_total_pages']! == '102'
	assert after['queue_capacity_bytes']! == '409600'
	before_total := ((u64(1024) * 200 + 31 + 4095) / 4096) + 1
	assert before_total == 52 && after['metadata_total_pages']!.u64() - before_total == 50
	log := os.read_file(state + '/serial.log')!
	mut before_rows := map[string]string{}
	mut compared := 0
	mut idle_snapshots := 0
	for raw in log.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('PROCNS DIAG SLAB:') {
			fields := line.fields()
			phase := fields[3].all_after('=')
			size := fields[4].all_after('=')
			live := fields[5].all_after('=')
			if phase == 'before' { before_rows[size] = live } else {
				assert before_rows[size]! == live
				compared++
			}
		}
		if line.starts_with('PROCNS DIAG SNAPSHOT:') {
			assert line.contains('taint=0 rows=14')
			if line.contains('phase=before ') { assert line.contains('big_pages=201 ') }
			if line.contains('phase=after ') { assert line.contains('big_pages=251 ') }
			if line.contains('phase=idle ') { assert line.contains('big_pages=251 '); idle_snapshots++ }
		}
	}
	assert before_rows.len == 14 && compared == 14 * 5 && idle_snapshots == 4
	assert log.contains('PROCNS DIAG: DONE')
	receipt := (json2.decode[json2.Any](os.read_file(state + '/receipt.json')!)!).as_map()
	assert receipt['kernel_sha256']!.str() == '5f191bb7355f00bc99e1cd04d1d3b6de570815c8517a9077469d35844f7e6b13'
	assert receipt['serial_sha256']!.str() == digest(state + '/serial.log')!
	mut summary := {'audit': 'PASS', 'purpose': 'Diagnostic allocation attribution; never substitutes for strict qualification', 'kernel_commit': 'cf6426cf16657a6db8d5be8062ef82f170c6b48b', 'guest_big_pages_before': '201', 'guest_big_pages_after_and_four_extended_idle_snapshots': '251', 'all_14_slab_classes_unchanged': 'true', 'queue_element_size': '200', 'queue_cap_during_measure': '1024', 'queue_cap_after_and_idle': '2048', 'queue_request_bytes_before_from_exact_allocator_geometry': '204831', 'queue_total_pages_before_from_exact_allocator_geometry': '52', 'queue_request_bytes_after_from_live_metadata': '409631', 'queue_total_pages_after_from_live_metadata': '102', 'queue_pages_delta': '50', 'caveats': 'Initial exact warm-pause QMP samples failed CRLF parsing and are preserved. cap1024 is measured during work; cap2048 is measured after/idle. First helper derived-page fields omitted array overhead; raw headers remain valid. Enhanced helper reads live metadata and accounts for31B header/alignment overhead. QMP snapshots are not atomic; guest snapshots include observer transients.'}
	for path in [before_path, after_path, state + '/serial.log', state + '/receipt.json', state + '/inputs.json', area + '/diagnostic-kind2b/procnsfixture/core.v', area + '/run-kind2.v', area + '/run-kind2', area + '/qmp-queue.v', area + '/qmp-queue', area + '/qmp-queue-next', area + '/watch-kind2.v', area + '/audit-queue-attribution.v', area + '/x86-track/blob.c'] { summary['sha256:' + path] = digest(path)! }
	os.write_file(area + '/queue-attribution.json', json2.encode(summary, prettify: true) + '\n')!
	println('Queue allocation attribution: PASS; +50 retained pages equals measured cap1024→2048 buffer growth, four extended idle snapshots unchanged')
}
