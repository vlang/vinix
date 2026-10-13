// Compose the successful x86 cases after host image-setup/log-write failure.
// This is an artifact composition, not another five-case controller run.
import crypto.sha256
import json2
import os
#include <unistd.h>
fn C.link(&char, &char) i32
struct CaseResult { name string source_sha256 string init_sha256 string iso_sha256 string exit_code int detail string }
struct Receipt {
	architecture string = 'x86_64'
	context string = 'QEMU native musl ELF64; three completed original cases plus two recovery cases on identical kernel bytes; original failed image setup and absent outer aggregate excluded'
	kernel_sha256 string
	results []CaseResult
	provenance map[string]string
	artifacts map[string]string
}
fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn object(path string) !map[string]json2.Any { return json2.decode[json2.Any](os.read_file(path)!)!.as_map() }
fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/lockrange-20261014'; root := '/Users/alex/code/vinix'; original := area + '/verified-after-x86'; recovery := area + '/recovery-after-x86'; target := area + '/qualified-after-x86'
	assert !os.exists(target) && !os.exists(original + '.log')
	kernel := digest(area + '/kernel-x86/kernel/bin/vinix'); old := object(original + '/receipt.json')!; fresh := object(recovery + '/receipt.json')!
	assert old['results']!.as_array().map(it.as_map()['name']!.str()) == ['lockrange', 'ofdlocks', 'fcntlpath', 'open']
	assert old['results']!.as_array()[3].as_map()['exit_code']!.int() == 1 && old['results']!.as_array()[3].as_map()['iso_sha256']!.str() == ''
	assert fresh['results']!.as_array().map(it.as_map()['name']!.str()) == ['open', 'runtime'] && os.read_file(recovery + '.log')!.contains('Linux compatibility guest suite: PASS')
	os.mkdir_all(target + '/kernel/bin')!; os.cp(area + '/kernel-x86/kernel/bin/vinix', target + '/kernel/bin/vinix')!
	mut results := []CaseResult{}; mut provenance := map[string]string{}; mut aggregate := ''
	for name in ['lockrange', 'ofdlocks', 'fcntlpath', 'open', 'runtime'] {
		origin := if name in ['open', 'runtime'] { recovery } else { original }; value := object(origin + '/receipt.json')!
		assert value['architecture']!.str() == 'x86_64' && value['kernel_sha256']!.str() == kernel && digest(origin + '/kernel/bin/vinix') == kernel
		rows := value['results']!.as_array().filter(it.as_map()['name']!.str() == name); assert rows.len == 1; row := rows[0].as_map(); assert row['exit_code']!.int() == 0 && row['detail']!.str() == ''
		source := origin + '/sources/' + name + 'fixture/core.v'; assert digest(source) == row['source_sha256']!.str() && digest(source) == digest(root + '/tests/linux-compat/' + name + 'fixture/core.v')
		assert digest(origin + '/' + name + '/init') == row['init_sha256']!.str() && digest(origin + '/' + name + '/test.iso') == row['iso_sha256']!.str()
		serial := os.read_file(origin + '/' + name + '/serial.log')!; assert serial.contains('LINUX ' + name.to_upper() + ': PASS') && !serial.contains('LINUX ' + name.to_upper() + ' FAIL')
		os.mkdir_all(target + '/sources/' + name + 'fixture')!; os.cp(source, target + '/sources/' + name + 'fixture/core.v')!; os.mkdir_all(target + '/' + name)!
		for file in ['init', 'fixture.c', 'test.iso', 'serial.log', 'serial.c'] {
			input := origin + '/' + name + '/' + file; output := target + '/' + name + '/' + file
			if file == 'test.iso' { assert C.link(input.str, output.str) == 0, 'immutable ISO hardlink' } else { os.cp(input, output)! }; assert digest(input) == digest(output)
		}
		provenance[name] = origin; results << CaseResult{name, row['source_sha256']!.str(), row['init_sha256']!.str(), row['iso_sha256']!.str(), 0, ''}
		aggregate += 'Qualified guest case: ' + name + '; original state: ' + origin + '\n' + serial + '\n'
	}
	artifacts := {'composer_source': digest(@FILE), 'original_receipt': digest(original + '/receipt.json'), 'recovery_receipt': digest(recovery + '/receipt.json'), 'recovery_aggregate': digest(recovery + '.log')}
	os.write_file(target + '/receipt.json', json2.encode(Receipt{kernel_sha256: kernel, results: results, provenance: provenance, artifacts: artifacts}, prettify: true) + '\n')!
	os.write_file(target + '.log', aggregate + 'Qualified guest case composition: PASS\n')!; println('x86_64 five successful cases composed with exact original/recovery provenance: PASS')
}
