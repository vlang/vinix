import crypto.sha256
import json2
import os

struct DesktopRow {
	variant string
	scenario string
	round int
	seconds string
	processes string
	total_cpu string
	total_mb string
	physical_mb string
}

struct WindowPosition { x int y int }

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

// The isolated System window is the only 300px-wide neutral light run in
// this part of the desktop. Locate its top border independently of timing.
fn window_position(path string) !WindowPosition {
	data := os.read_bytes(path)!
	header := 'P6\n2048 1536\n255\n'
	if !data[..header.len].bytestr().starts_with(header) { return error('unexpected screenshot format') }
	for y in 25 .. 900 {
		mut run := 0
		for x in 260 .. 2000 {
			at := header.len + (y * 2048 + x) * 3
			r, g, b := int(data[at]), int(data[at+1]), int(data[at+2])
			if r > 220 && g > 220 && b > 220 && r - g > -15 && r - g < 15 && r - b > -15 && r - b < 15 {
				run++
				if run == 300 { return WindowPosition{x - 299, y} }
			} else { run = 0 }
		}
	}
	return error('System window not found')
}

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	work := area + '/du'
	receipt := json2.decode[map[string]string](os.read_file(work + '/receipt.json')!)!
	mut lines := ['x86 desktop final independent audit', 'Production kernel: cf6426cf16657a6db8d5be8062ef82f170c6b48b', 'Idle/apps: ds; isolated drag with xHCI: du.', 'ds/dt drag attempts are preserved harness qualification failures: unsupported default UHCI delivered no pointer movement despite status0 and DONE.']
	for key, path in {
		'kernel_sha256': work + '/kernel/bin/vinix'
		'desktop_sha256': work + '/overlay/opt/vinix-perf/vinix-desktop-new'
		'init_sha256': work + '/overlay/sbin/init'
		'measure_sha256': work + '/overlay/opt/vinix-perf/measure'
		'archive_sha256': work + '/initramfs.tar'
		'iso_sha256': work + '/vm/test.iso'
	} {
		if digest(path)! != receipt[key] { panic('pin mismatch: ' + path) }
		lines << '${key}: ${receipt[key]}'
	}
	if !receipt['command'].contains('-device qemu-xhci,id=xhci -device usb-tablet,bus=xhci.0') { panic('missing xHCI controller') }
	if os.read_file(work + '/status')!.trim_space() != '0' { panic('drag status failure') }
	for name, scenarios in {'ds': ['idle', 'apps'], 'du': ['drag']} {
		log := os.read_file(area + '/' + name + '/serial.log')!
		hostlog := os.read_file(area + '/' + name + '.log')!
		if !log.contains('VINIX DESKTOP PERF: DONE') || log.contains('PERF-ERROR') || hostlog.contains('pointer driver:') { panic('incomplete desktop log: ' + name) }
		rows := json2.decode[[]DesktopRow](os.read_file(area + '/' + name + '/results.json')!)!
		for scenario in scenarios {
			if !log.contains('PERF-RESULT variant=new scenario=' + scenario + ' round=1 ') || !log.contains('PERF-READY variant=new scenario=' + scenario + ' round=1 ') { panic('missing actual metric: ' + scenario) }
			mut count := 0
			for row in rows {
				if row.variant == 'new' && row.scenario == scenario && row.round == 1 {
					if row.seconds.f64() <= 0 || row.processes.int() < 1 || row.total_cpu.f64() <= 0 || row.total_mb.f64() <= 0 || row.physical_mb.f64() <= 0 { panic('invalid row: ' + scenario) }
					lines << '${scenario}: seconds=${row.seconds} processes=${row.processes} total_cpu=${row.total_cpu} total_mb=${row.total_mb} physical_mb=${row.physical_mb}'
					count++
				}
			}
			if count != 1 { panic('result count: ' + scenario) }
		}
	}
	before := window_position(area + '/dt/shots/new-drag-1.ppm')!
	after := window_position(work + '/shots/new-drag-1.ppm')!
	if before == after { panic('drag did not move System window') }
	lines << 'System window top border: before=(${before.x},${before.y}) after=(${after.x},${after.y}); actual pointer-driven window movement verified.'
	mut publication := json2.decode[map[string]string](os.read_file(area + '/desktop-publication-map.json')!)!
	for extension in ['ppm', 'png'] {
		publication['x86-desktop-initial-unmoved-drag.' + extension] = publication['x86-desktop-drag.' + extension]
		publication['x86-desktop-drag.' + extension] = work + '/shots/new-drag-1.' + extension
		publication['x86-desktop-isolated-unmoved-drag.' + extension] = area + '/dt/shots/new-drag-1.' + extension
	}
	for suffix, path in {
		'x86-desktop-drag-serial.log': work + '/serial.log'
		'x86-desktop-drag-harness.log': area + '/du.log'
		'x86-desktop-drag-results.json': work + '/results.json'
		'x86-desktop-drag-status.txt': work + '/status'
		'x86-desktop-drag-receipt.json': work + '/receipt.json'
		'x86-desktop-drag-wrapper.v': area + '/regression-runner/desktop-x86-xhci.v'
		'x86-desktop-isolated-unmoved-serial.log': area + '/dt/serial.log'
		'x86-desktop-isolated-unmoved-harness.log': area + '/dt.log'
		'x86-desktop-isolated-unmoved-results.json': area + '/dt/results.json'
		'x86-desktop-isolated-unmoved-status.txt': area + '/dt/status'
		'x86-desktop-isolated-unmoved-receipt.json': area + '/dt/receipt.json'
		'x86-desktop-isolated-unmoved-wrapper.v': area + '/regression-runner/desktop-x86-drag.v'
		'x86-desktop-final-audit.txt': area + '/desktop-final-audit.txt'
		'x86-desktop-final-audit.v': area + '/desktop-final-audit.v'
	} { publication[suffix] = path }
	for suffix, path in publication {
		if path.ends_with('/desktop-final-audit.txt') { continue }
		if !os.exists(path) { panic('missing publication artifact: ' + path) }
		lines << '${suffix}: ${digest(path)!}'
	}
	os.write_file(area + '/desktop-final-audit.txt', lines.join('\n') + '\n')!
	os.write_file(area + '/desktop-publication-inputs.json', json2.encode(publication, prettify: true) + '\n')!
	println(lines.join('\n'))
}
