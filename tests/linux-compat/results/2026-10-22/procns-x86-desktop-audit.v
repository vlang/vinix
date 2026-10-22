import crypto.sha256
import json2
import os

struct DesktopRow {
	report string
	variant string
	scenario string
	round int
	seconds string
	processes string
	total_cpu string
	physical_mb string
	total_mb string
}

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	root := '/Users/alex/code/vinix'
	work := area + '/ds'
	receipt := json2.decode[map[string]string](os.read_file(work + '/receipt.json')!)!
	os.mkdir_all(work + '/sources')!
	for source, key in {'perf-init.sh': 'init_source_sha256', 'measure.c': 'measure_source_sha256'} {
		input := root + '/tests/desktop-perf/' + source
		if digest(input)! != receipt[key] { panic('source changed: ' + input) }
		os.cp(input, work + '/sources/' + source)!
	}
	for module_name in ['perfrunner', 'perfconsole', 'perfreport', 'sourcecommand', 'qmpclient'] {
		input := root + '/tests/desktop-perf/' + module_name
		if os.exists(input) && !os.exists(work + '/sources/' + module_name) {
			os.cp_all(input, work + '/sources/' + module_name, false)!
		}
	}
	for module_name in ['guesthost', 'fixturehost', 'hosttest', 'nativepolicy', 'policyhost'] {
		if !os.exists(work + '/sources/' + module_name) {
			input := match module_name {
				'nativepolicy' { root + '/tests/native-policy-tools/nativepolicy' }
				'policyhost' { root + '/tests/host-policy/policyhost' }
				else { os.real_path(area + '/regression-runner/' + module_name) }
			}
			os.cp_all(input, work + '/sources/' + module_name, false)!
		}
	}
	for source, destination in {
		area + '/regression-runner/desktop-x86-serial.v': 'desktop-x86-serial.v'
		area + '/desktop-iso.v': 'desktop-iso.v'
		area + '/desktop-x86-launch/build-support/limine.conf': 'limine.conf'
		work + '/overlay/sbin/init': 'init'
		work + '/overlay/opt/vinix-perf/config': 'config'
	} { os.cp(source, work + '/sources/' + destination)! }
	if os.args.len > 1 && os.args[1] == 'freeze' { return }
	mut lines := ['x86_64 desktop qualification, 2026-10-22', 'Fix commit: cf6426cf16657a6db8d5be8062ef82f170c6b48b']
	for key, path in {
		'kernel_sha256': work + '/kernel/bin/vinix'
		'desktop_sha256': work + '/overlay/opt/vinix-perf/vinix-desktop-new'
		'init_sha256': work + '/overlay/sbin/init'
		'measure_sha256': work + '/overlay/opt/vinix-perf/measure'
		'archive_sha256': work + '/initramfs.tar'
		'iso_sha256': work + '/vm/test.iso'
	} {
		if digest(path)! != receipt[key] { panic('hash mismatch: ' + path) }
		lines << '${key}: ${receipt[key]}'
	}
	status := os.read_file(work + '/status')!.trim_space()
	if status != '0' { panic('desktop status ' + status) }
	log := os.read_file(work + '/serial.log')!
	if !log.contains('VINIX DESKTOP PERF: DONE') { panic('missing DONE marker') }
	if log.contains('ERROR:') || log.contains('PERF-FAIL') { panic('desktop error marker') }
	if log.contains('pointer driver:') { panic('pointer driver error') }
	if !log.contains('PERF-DRIVE drag 10') { panic('missing actual drag drive marker') }
	rows := json2.decode[[]DesktopRow](os.read_file(work + '/results.json')!)!
	for scenario in ['idle', 'apps', 'drag'] {
		marker := 'PERF-RESULT variant=new scenario=' + scenario + ' round=1 '
		if !log.contains(marker) { panic('missing actual result: ' + scenario) }
		if !log.contains('PERF-READY variant=new scenario=' + scenario + ' round=1 ') { panic('missing READY: ' + scenario) }
		mut found := 0
		for row in rows {
			if row.report == '' && row.variant == 'new' && row.scenario == scenario && row.round == 1 {
				if row.seconds.f64() <= 0 || row.processes.int() < 1 || row.total_cpu.f64() <= 0 || row.total_mb.f64() <= 0 || row.physical_mb.f64() <= 0 { panic('invalid JSON metrics: ' + scenario) }
				lines << '${scenario}: seconds=${row.seconds} processes=${row.processes} total_cpu=${row.total_cpu} total_mb=${row.total_mb} physical_mb=${row.physical_mb}'
				found++
			}
		}
		if found != 1 { panic('expected exactly one JSON result: ' + scenario) }
		shot := work + '/shots/new-' + scenario + '-1.ppm'
		if os.file_size(shot) < 1000000 { panic('missing screenshot: ' + scenario) }
		lines << '${scenario}: actual result, READY and screenshot verified; screenshot=${digest(shot)!}'
	}
	os.setenv('COPYFILE_DISABLE', '1', true)
	mut bundle := os.new_process('/usr/bin/tar')
	bundle.set_args(['-czf', area + '/desktop-tooling.tar.gz', '-C', work + '/sources', '.'])
	bundle.run()
	bundle.wait()
	if bundle.code != 0 { panic('tooling archive failed') }
	for path in [work + '/results.json', work + '/receipt.json', work + '/serial.log', area + '/ds.log', area + '/regression-runner/desktop-x86-serial.v', area + '/regression-runner/desktop-x86-serial', area + '/desktop-iso.v', area + '/desktop-iso', area + '/desktop-tooling.tar.gz', area + '/desktop-audit.v', area + '/desktop-audit'] {
		lines << '${digest(path)!} ${path}'
	}
	lines << 'Invalid initial framebuffer-only attempt preserved: ${area}/desktop-x86.log and desktop-x86/status=1; diagnostic screenshot confirms guest but no host serial evidence.'
	text := lines.join('\n') + '\n'
	os.write_file(area + '/desktop-audit.txt', text)!
	print(text)
	mut publication := {
		'x86-desktop-serial.log': work + '/serial.log'
		'x86-desktop-harness.log': area + '/ds.log'
		'x86-desktop-results.json': work + '/results.json'
		'x86-desktop-status.txt': work + '/status'
		'x86-desktop-receipt.json': work + '/receipt.json'
		'x86-desktop-audit.txt': area + '/desktop-audit.txt'
		'x86-desktop-audit.v': area + '/desktop-audit.v'
		'x86-desktop-wrapper.v': area + '/regression-runner/desktop-x86-serial.v'
		'x86-desktop-iso.v': area + '/desktop-iso.v'
		'x86-desktop-tooling.tar.gz': area + '/desktop-tooling.tar.gz'
		'x86-desktop-initial-serial.log': area + '/desktop-x86/serial.log'
		'x86-desktop-initial-harness.log': area + '/desktop-x86.log'
		'x86-desktop-initial-receipt.json': area + '/desktop-x86/receipt.json'
		'x86-desktop-initial-status.txt': area + '/desktop-x86/status'
		'x86-desktop-initial-diagnostic.png': area + '/desktop-x86/diagnostic.png'
	}
	for scenario in ['idle', 'apps', 'drag'] {
		for extension in ['ppm', 'png'] {
			publication['x86-desktop-' + scenario + '.' + extension] = work + '/shots/new-' + scenario + '-1.' + extension
		}
	}
	for _, path in publication { if !os.exists(path) { panic('missing publication file: ' + path) } }
	os.write_file(area + '/desktop-publication-map.json', json2.encode(publication, prettify: true) + '\n')!
}
