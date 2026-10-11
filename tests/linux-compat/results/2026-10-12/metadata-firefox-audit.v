import crypto.sha256
import json2
import os
import strconv

fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }

fn main() {
	root := '/Users/alex/code/vinix'
	out := root + '/tests/linux-compat/results/2026-10-12/'
	for size in ['2g'] {
		state := '/Volumes/VinixLinuxCompatPressure1012/metadata-firefox-2g-x86'
		raw := os.read_file(state + '/guest-report.json')!
		report := json2.decode[json2.Any](raw)!.as_map()
		receipt := json2.decode[json2.Any](os.read_file(state + '/application-inputs.json')!)!.as_map()
		inputs := receipt['inputs']!.as_map_of_strings()
		assert receipt['architecture']!.str() == 'x86_64' && receipt['execution_path']!.str() == 'native-x86_64'
		assert receipt['uid']!.int() == 1000 && receipt['exit_code']!.int() == 1
		assert receipt['memory_mib']!.int() == if size == '2g' { 2048 } else { 4096 }
		assert receipt['workload_timeout']!.int() == 120
		assert report['context']!.str() == 'vinix-guest' && report['uid']!.int() == 1000 && report['gid']!.int() == 1000
		assert !report['complete_lifecycle_qualified']!.bool()
		assert inputs['kernel'] == json2.decode[json2.Any](os.read_file('/Volumes/VinixLinuxCompatPressure1012/metadata-after2-x86/receipt.json')!)!.as_map()['kernel_sha256']!.str()
		assert inputs['kernel'] == inputs['snapshot_kernel'] && inputs['kernel'] == digest(state + '/kernel/bin/vinix')
		assert inputs['guest_report'] == sha256.sum(raw.trim_space().bytes()).hex()
		assert inputs['workloads'] == report['suite_sha256']!.str() && inputs['workloads'] == digest(state + '/rootfs/usr/bin/linux-compat-workloads')
		assert inputs['workloads'] == digest('/Volumes/VinixLinuxCompatNext1011/diagnostic-driver3-x86/linux-compat-workloads')
		assert inputs['runtime-probe'] == report['runtime_probe_sha256']!.str() && inputs['runtime-probe'] == digest(state + '/rootfs/usr/share/linux-compat/runtime')
		assert inputs['init_source'] == digest(root + '/tests/linux-compat/appinitfixture/core.v')
		assert inputs['guest_options'] == digest(state + '/rootfs/etc/linux-compat-options')
		assert inputs['guest_credentials'] == digest(state + '/rootfs/etc/linux-compat-uid')
		assert inputs['rootfs_manifest'] == digest(state + '/rootfs-inputs.json')
		manifest := json2.decode[json2.Any](os.read_file(state + '/rootfs-inputs.json')!)!.as_map_of_strings()
		for path, value in manifest {
			file := state + '/rootfs' + path
			if path == '/sbin/init' { assert digest(file) == digest(state + '/init'); continue }
			if value.starts_with('link:') { assert os.is_link(file) && os.readlink(file)! == value.all_after('link:'); continue }
			fields := value.split(':')
			assert (os.stat(file)!.mode & 0o7777).str() == fields[1]
			if fields[0] == 'file' { assert digest(file) == fields[2] }
			else { assert fields[0] == 'directory' && os.is_dir(file) }
		}
		rows := report['results']!.as_array()
		assert rows.len == 1 && rows[0].as_map()['name']!.str() == 'firefox' && rows[0].as_map()['status']!.str() == 'failed'
		commands := report['commands']!.as_array()
		assert commands.len == 2 && commands[0].as_map()['exit_code']!.int() == 0
		last := commands[1].as_map()
		assert last['exit_code']!.int() != 0
		for command in commands {
			row := command.as_map()
			assert row['executable_sha256']!.str() == digest(state + '/rootfs' + row['argv']!.as_array()[0].str())
			assert row['environment_overrides']!.as_map().len == 0 && row['environment_unset']!.as_array().len == 0
			for snapshot in row['diagnostics']!.as_array() {
				mut total := 0
				for data in snapshot.as_map()['files']!.as_array() {
					item := data.as_map()
					assert item['path']!.str().starts_with('/proc/')
					total += item['content']!.str().len
					if item['path']!.str() == '/proc/kernel-resources' {
						mut values := map[string]u64{}
						mut has_evidence := false
						for line in item['content']!.str().split_into_lines() {
								if line.starts_with('LastDenied: ') { has_evidence = true }
							fields := line.fields()
							if fields.len == 2 && fields[0].starts_with('Denied') {
								values[fields[0].trim_right(':')] = strconv.parse_uint(fields[1], 10, 64)!
							}
						}
						assert values.len == 7
						mut sum := u64(0)
						for reason in ['invalid', 'accounts', 'objects', 'global', 'owner', 'cgroup'] {
							assert 'Denied.' + reason in values
							sum += values['Denied.' + reason]
						}
						assert sum == values['Denied'] && has_evidence == (sum != 0)
					}
				}
				assert total <= 65536
			}
		}
		assert last['diagnostics']!.as_array().len == 2
		assert report['browsers']!.as_array().len == 0
		log := os.read_file(state + '/serial.log')!
		assert log.contains('LINUX APPLICATIONS FAIL') && !log.contains('LINUX APPLICATIONS: PASS')
		for source, name in {'guest-report.json': 'metadata-firefox-' + size + '-x86_64.json',
			'application-inputs.json': 'inputs-metadata-firefox-' + size + '-x86_64.json',
			'rootfs-inputs.json': 'metadata-firefox-' + size + '-rootfs-x86_64.json',
			'serial.log': 'metadata-firefox-' + size + '-x86_64.log'} {
			assert !os.exists(out + name)
			os.cp(state + '/' + source, out + name)!
		}
		println(size + ': actual guest failure, bounded diagnostics and every prepared-root file verified')
	}
}
