// Compose successful, unchanged-kernel cases without rerunning passed probes.
import crypto.sha256
import json2
import os

#include <unistd.h>
fn C.link(&char, &char) i32

struct CaseResult {
	name string
	source_sha256 string
	init_sha256 string
	iso_sha256 string
	exit_code int
	detail string
}
struct Receipt {
	architecture string
	context string = 'QEMU native musl ELF64; successful cases composed from actual runs on identical kernel bytes; pre-strengthening sync probe and ARM failed ISO setup excluded'
	kernel_sha256 string
	results []CaseResult
	provenance map[string]string
	artifacts map[string]string
}
fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn object(path string) !map[string]json2.Any { return json2.decode[json2.Any](os.read_file(path)!)!.as_map() }
fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/fcntlsync-20261013'; root := '/Users/alex/code/vinix'
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		original := area + '/initial-after-' + suffix; fresh := area + '/new-after-' + suffix; target := area + '/final-after-' + suffix
		assert !os.exists(target)
		old := object(original + '/receipt.json')!; current := object(fresh + '/receipt.json')!
		kernel := digest(area + '/kernel-' + suffix + '/kernel/bin/vinix')
		for value in [old, current] { assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel }
		assert digest(original + '/kernel/bin/vinix') == kernel && digest(fresh + '/kernel/bin/vinix') == kernel
		assert os.read_file(fresh + '.log')!.contains('Linux compatibility guest suite: PASS')
		assert old['results']!.as_array().map(it.as_map()['name']!.str()) == ['fcntlsync', 'fcntlabi', 'fcntlpath', 'open', 'runtime']
		assert current['results']!.as_array().map(it.as_map()['name']!.str()) == ['fcntlsync']
		os.mkdir_all(target + '/kernel/bin')!; os.cp(fresh + '/kernel/bin/vinix', target + '/kernel/bin/vinix')!
		mut results := []CaseResult{}; mut provenance := map[string]string{}; mut aggregate := ''
		for name in ['fcntlsync', 'fcntlabi', 'fcntlpath', 'open', 'runtime'] {
			origin := if name == 'fcntlsync' { fresh } else if arch == 'aarch64' && name == 'fcntlpath' { area + '/initial-mask-new-after-arm' } else { original }
			value := object(origin + '/receipt.json')!; assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel
			rows := value['results']!.as_array().filter(it.as_map()['name']!.str() == name); assert rows.len == 1
			row := rows[0].as_map(); assert row['exit_code']!.int() == 0 && row['detail']!.str() == ''
			source := origin + '/sources/' + name + 'fixture/core.v'; assert digest(source) == row['source_sha256']!.str() && digest(source) == digest(root + '/tests/linux-compat/' + name + 'fixture/core.v')
			assert digest(origin + '/' + name + '/init') == row['init_sha256']!.str() && digest(origin + '/' + name + '/test.iso') == row['iso_sha256']!.str()
			serial := os.read_file(origin + '/' + name + '/serial.log')!; assert serial.contains('LINUX ' + name.to_upper() + ': PASS') && !serial.contains('LINUX ' + name.to_upper() + ' FAIL')
			os.mkdir_all(target + '/sources/' + name + 'fixture')!; os.cp(source, target + '/sources/' + name + 'fixture/core.v')!; os.mkdir_all(target + '/' + name)!
			for file in ['init', 'fixture.c', 'test.iso', 'serial.log', 'serial.c'] {
				input := origin + '/' + name + '/' + file; output := target + '/' + name + '/' + file
				if file == 'test.iso' { assert C.link(input.str, output.str) == 0, 'hardlink immutable ISO' } else { os.cp(input, output)! }
				assert digest(input) == digest(output)
			}
			provenance[name] = origin
			results << CaseResult{name, row['source_sha256']!.str(), row['init_sha256']!.str(), row['iso_sha256']!.str(), 0, ''}
			aggregate += 'Qualified guest case: ' + name + '; original state: ' + origin + '\n' + serial + '\n'
		}
		artifacts := {'original_receipt': digest(original + '/receipt.json'), 'original_aggregate': digest(original + '.log'), 'fresh_receipt': digest(fresh + '/receipt.json'), 'fresh_aggregate': digest(fresh + '.log'), 'composer_source': digest(@FILE)}
		os.write_file(target + '/receipt.json', json2.encode(Receipt{architecture: arch, kernel_sha256: kernel, results: results, provenance: provenance, artifacts: artifacts}, prettify: true) + '\n')!
		os.write_file(target + '.log', aggregate + 'Qualified guest case composition: PASS\n')!
		println(arch + ': five cases composed with exact successful-case provenance; PASS')
	}
}
