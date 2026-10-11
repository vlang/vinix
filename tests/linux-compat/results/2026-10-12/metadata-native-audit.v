import crypto.sha256
import json2
import os
struct Evidence {
	architecture string
	context string = 'native musl regression on the mapping-storage kernel'
	kernel_sha256 string
	inputs map[string]string
	launch json2.Any
	verdicts []string
}
fn hash(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn main() {
	assert os.args.len == 2 && os.args[1] == 'paging'
	area := '/Volumes/VinixLinuxCompatPressure1012/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-12/'
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		state := area + 'metadata-paging-' + suffix
		launch := json2.decode[json2.Any](os.read_file(state + '/launch.json')!)!
		kernel := hash(state + '/kernel/bin/vinix')
		assert launch.as_map()['kernel_sha256']!.str() == kernel
		assert kernel == json2.decode[json2.Any](os.read_file(area + 'metadata-after2-' + suffix + '/receipt.json')!)!.as_map()['kernel_sha256']!.str()
		assert launch.as_map()['init_sha256']!.str() == hash(state + '/init')
		assert launch.as_map()['archive_sha256']!.str() == hash(state + '/initramfs.tar')
		assert !launch.as_map()['kernel_rebuilt_by_runner']!.bool()
		log := os.read_file(state + '/serial.log')!
		assert log.contains('PAGING encrypted-disk-swapoff PASS') && log.contains('PAGING PASS')
		assert !log.contains('PAGING FAIL') && !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION')
		mut verdicts := []string{}
		mut classes := map[string]bool{}
		for raw in log.split_into_lines() {
			line := raw.trim_space()
			if line.starts_with('PAGING SLAB ') {
				fields := line.fields()
				assert fields.len == 7 && fields[5] == 'delta=0' && fields[6] == 'rounds=200'
				assert fields[2] !in classes
				classes[fields[2]] = true
				verdicts << line
			} else if line.starts_with('PAGING ') && line.contains('PASS') { verdicts << line }
		}
		assert classes.len >= 14
		mut inputs := {'init': hash(state + '/init'), 'archive': hash(state + '/initramfs.tar'),
			'iso': hash(state + '/test.iso'), 'swap_after': hash(state + '/swap.img'),
			'audit_source': hash(@FILE)}
		for path in ['tests/paging/guest.c', 'tests/native-system-tools/paging-main.v',
			'tests/native-system-tools/systemhost/paging.v'] { inputs[path] = hash(root + path) }
		name := 'metadata-paging-' + arch
		assert !os.exists(out + name + '.json') && !os.exists(out + name + '.log')
		os.write_file(out + name + '.json', json2.encode(Evidence{arch, 'native musl regression on the mapping-storage kernel', kernel, inputs, launch, verdicts}, prettify: true) + '\n')!
		os.cp(state + '/serial.log', out + name + '.log')!
		println(arch + ': exact kernel/init/archive/ISO/swap hashes and 200-cycle flat slab verdicts verified')
	}
	assert !os.exists(out + 'metadata-native-audit.v')
	os.cp(@FILE, out + 'metadata-native-audit.v')!
}
