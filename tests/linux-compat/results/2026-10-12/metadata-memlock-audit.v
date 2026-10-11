import crypto.sha256
import json2
import os
fn hash(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn main() {
	area := '/Volumes/VinixLinuxCompatPressure1012/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-12/'
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		state := area + 'metadata-memlock-' + suffix
		raw := os.read_file(state + '/receipt.json')!
		receipt := json2.decode[json2.Any](raw)!.as_map()
		assert receipt['architecture']!.str() == arch && receipt['exit_code']!.int() == 0
		assert receipt['kernel_sha256']!.str() == hash(state + '/kernel/bin/vinix')
		assert receipt['kernel_sha256']!.str() == json2.decode[json2.Any](os.read_file(area + 'metadata-after2-' + suffix + '/receipt.json')!)!.as_map()['kernel_sha256']!.str()
		assert receipt['init_sha256']!.str() == hash(state + '/init')
		assert receipt['iso_sha256']!.str() == hash(state + '/test.iso')
		assert receipt['source_sha256']!.str() == hash(root + 'tests/memlock/test.c')
		assert receipt['controller_sha256']!.str() == hash('/tmp/vinix-metadata-memlock.v')
		log := os.read_file(state + '/serial.log')!
		for marker in ['range population and limits', 'file and guard mappings',
			'fork, remap, replacement and exec', 'current, future and heap locking',
			'capability and unsupported flags', 'concurrent file replacement and remap',
			'repeated lock and unlock stay flat'] { assert log.contains('MEMLOCK PASS: ' + marker) }
		assert log.contains('VINIX MEMLOCK: PASS') && !log.contains('VINIX MEMLOCK: FAIL')
		name := 'metadata-memlock-' + arch
		assert !os.exists(out + name + '.json') && !os.exists(out + name + '.log')
		os.write_file(out + name + '.json', raw)!
		os.cp(state + '/serial.log', out + name + '.log')!
		println(arch + ': exact kernel/source/controller/init/ISO hashes and all seven memory-lock suites verified')
	}
	assert !os.exists(out + 'metadata-memlock-controller.v') && !os.exists(out + 'metadata-memlock-audit.v')
	os.cp('/tmp/vinix-metadata-memlock.v', out + 'metadata-memlock-controller.v')!
	os.cp(@FILE, out + 'metadata-memlock-audit.v')!
}
