// SPDX-License-Identifier: GPL-2.0-or-later
// Install every app the first-run software picker offers, in QEMU, the way a
// user does: boot an ISO onto a blank disk, create the user, choose all the
// apps and let the setup Terminal install them. Each app's result is the
// `vinix-setup:` line that Terminal writes to the console (the serial port).
module main

import json2
import os
import qmpclient
import time

const usage = 'Usage: tests/first-run-apps/run [--out=DIR] [--timeout=MINUTES] [--disk=GIB] [--apps=A,B] [--min-free=GIB] [--keep] ISO
       tests/first-run-apps/run DIR key QCODE... | type TEXT | click X Y [double] | shot FILE

Boots ISO (vinix-arm64.iso under HVF, vinix-amd64.iso under TCG) with a blank
disk and a network card, creates a user, selects every app on the "Choose your
software" screen and waits for the setup Terminal to install them. Exits 0 when
every app installed. Serial log and screenshots go to DIR (default
build/first-run-apps/ARCH); --keep leaves the VM running at the end, with its
QMP socket in DIR. --apps chooses only those apps, and --apps= none at all.
The second form drives a VM that test runs, through the QMP socket in DIR: keys
by QEMU name, text, a click at X Y of a 1024x768 screen, or a screenshot.'

struct Options {
mut:
	iso      string
	arch     string
	out      string
	timeout  int = 300
	disk_gib int = 16
	// What the host must have free before a run starts.
	min_free int = 10
	keep     bool
	apps     ?[]string
}

struct Vm {
mut:
	process &os.Process = unsafe { nil }
	qmp     string
	serial  string
	out     string
	offset  i64
	text    string
}

fn parse_options() !Options {
	mut options := Options{}
	for argument in os.args[1..] {
		if argument in ['-h', '--help'] {
			println(usage)
			exit(0)
		} else if argument.starts_with('--out=') {
			options.out = argument.all_after('=')
		} else if argument.starts_with('--timeout=') {
			options.timeout = argument.all_after('=').int()
		} else if argument.starts_with('--disk=') {
			options.disk_gib = argument.all_after('=').int()
		} else if argument.starts_with('--apps=') {
			options.apps = argument.all_after('=').split(',').filter(it != '')
		} else if argument.starts_with('--min-free=') {
			options.min_free = argument.all_after('=').int()
		} else if argument == '--keep' {
			options.keep = true
		} else if argument.starts_with('-') {
			return error('unknown option ${argument}\n${usage}')
		} else {
			options.iso = os.real_path(argument)
		}
	}
	if options.iso == '' || !os.is_file(options.iso) {
		return error(usage)
	}
	name := os.file_name(options.iso)
	options.arch = if name.contains('arm64') || name.contains('aarch64') { 'arm64' } else { 'amd64' }
	if options.out == '' {
		options.out = os.join_path(repository(), 'build', 'first-run-apps', options.arch)
	}
	return options
}

fn repository() string {
	return os.real_path(os.join_path(@DIR, '..', '..'))
}

// The apps the picker offers on this architecture, in the order its arrow
// keys visit them (category by category), read from the catalogue itself so
// that a new app is tested without edits.
fn offered_apps(arch string) ![]string {
	source := os.read_file(os.join_path(repository(), 'desktop', 'app_selection_catalogue.v'))!
	categories := source.all_after('const first_run_categories = [').all_before(']').replace('FirstRunCategory', '').split(',').map(it.trim_space().trim_left('.'))
	mut by_category := map[string][]string{}
	for block in source.split('FirstRunApp{')[1..] {
		name := block.all_after("package_name:").all_after("'").all_before("'")
		if name == '' {
			continue
		}
		if arch != 'arm64' && block.all_before('},').contains('arm64_only:      true') {
			continue
		}
		// An app without a category has the enum's zero value, its first
		// member: the browsers name none.
		category := if block.contains('category:') {
			block.all_after('category:').all_before('\n').trim_space().trim_left('.')
		} else {
			source.all_after('enum FirstRunCategory {').trim_space().all_before('\n').trim_space()
		}
		by_category[category] << name
	}
	mut apps := []string{}
	for category in categories {
		apps << by_category[category]
	}
	if apps.len == 0 {
		return error('no apps found in desktop/app_selection_catalogue.v')
	}
	return apps
}

fn firmware(name string) !string {
	for prefix in ['/opt/homebrew/share/qemu', '/usr/local/share/qemu', '/usr/share/qemu'] {
		path := os.join_path(prefix, name)
		if os.is_file(path) {
			return path
		}
	}
	return error('QEMU firmware ${name} not found')
}

fn start(options Options) !Vm {
	os.mkdir_all(options.out)!
	for name in ['serial.log', 'qmp.sock', 'disk.img', 'vars.fd'] {
		os.rm(os.join_path(options.out, name)) or {}
	}
	// The disk image is sparse and grows by every app installed, to about
	// 8 GiB. When the host's own disk filled, QEMU's write stalled, the guest's
	// disk request timed out and the run hung halfway, which looks like a
	// Vinix failure.
	usage := os.disk_usage(options.out)!
	if usage.available < u64(options.min_free) << 30 {
		return error('${options.out} has ${usage.available >> 20} MiB free; the run wants ${options.min_free} GiB (--min-free)')
	}
	disk := os.join_path(options.out, 'disk.img')
	mut file := os.create(disk)!
	file.close()
	os.truncate(disk, u64(options.disk_gib) << 30)!
	vm := Vm{
		qmp:    os.join_path(options.out, 'qmp.sock')
		serial: os.join_path(options.out, 'serial.log')
		out:    options.out
	}
	mut program := ''
	mut qemu_args := []string{}
	if options.arch == 'arm64' {
		program = 'qemu-system-aarch64'
		vars := os.join_path(options.out, 'vars.fd')
		os.cp(firmware('edk2-arm-vars.fd')!, vars)!
		qemu_args = ['-machine', 'virt', '-accel', 'hvf', '-cpu', 'host', '-m', '4096', '-smp',
			'4', '-drive', 'if=pflash,format=raw,readonly=on,file=${firmware('edk2-aarch64-code.fd')!}',
			'-drive', 'if=pflash,format=raw,file=${vars}', '-device', 'virtio-scsi-pci,id=scsi0',
			'-drive', 'if=none,id=cd0,media=cdrom,readonly=on,file=${options.iso}', '-device',
			'scsi-cd,drive=cd0,bus=scsi0.0', '-drive', 'if=none,id=hd0,format=raw,file=${disk}',
			'-device', 'virtio-blk-device,drive=hd0', '-device', 'ramfb', '-device',
			'virtio-keyboard-device', '-device', 'virtio-tablet-device', '-netdev',
			'user,id=net0', '-device', 'virtio-net-device,netdev=net0']
	} else {
		program = 'qemu-system-x86_64'
		qemu_args = ['-machine', 'q35', '-accel', 'tcg,thread=multi', '-cpu', 'max', '-m', '4096',
			'-smp', '4', '-vga', 'std', '-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=${firmware('edk2-x86_64-code.fd')!}',
			'-cdrom', options.iso, '-drive', 'file=${disk},format=raw', '-nic', 'user,model=e1000']
	}
	qemu_args << ['-display', 'none', '-no-reboot', '-serial', 'file:${vm.serial}', '-qmp',
		'unix:${vm.qmp},server=on,wait=off']
	mut process := os.new_process(os.find_abs_path_of_executable(program)!)
	process.set_args(qemu_args)
	process.run()
	return Vm{
		...vm
		process: process
	}
}

fn (mut vm Vm) alive() bool {
	return vm.process.is_alive()
}

// New serial output since the last call, appended to vm.text.
fn (mut vm Vm) poll() string {
	mut file := os.open(vm.serial) or { return '' }
	defer { file.close() }
	size := os.file_size(vm.serial)
	if size <= u64(vm.offset) {
		return ''
	}
	mut buffer := []u8{len: int(size - u64(vm.offset))}
	count := file.read_from(u64(vm.offset), mut buffer) or { return '' }
	vm.offset += count
	chunk := buffer[..count].bytestr()
	vm.text += chunk
	return chunk
}

fn (mut vm Vm) monitor(name string, arguments map[string]json2.Any) ! {
	mut monitor := qmpclient.connect(vm.qmp)!
	defer { monitor.close() }
	monitor.command(name, arguments)!
}

fn (mut vm Vm) key(name string) ! {
	vm.monitor('human-monitor-command', {
		'command-line': json2.Any('sendkey ' + name)
	})!
	time.sleep(200 * time.millisecond)
}

fn key_name(character u8) !string {
	if (character >= `a` && character <= `z`) || (character >= `0` && character <= `9`) {
		return character.ascii_str()
	}
	if character >= `A` && character <= `Z` {
		return 'shift-' + (character + 32).ascii_str()
	}
	return match character {
		` ` { 'spc' }
		`\n` { 'ret' }
		`.` { 'dot' }
		`-` { 'minus' }
		`/` { 'slash' }
		`_` { 'shift-minus' }
		`>` { 'shift-dot' }
		`<` { 'shift-comma' }
		`|` { 'shift-backslash' }
		`'` { 'apostrophe' }
		`"` { 'shift-apostrophe' }
		`;` { 'semicolon' }
		`:` { 'shift-semicolon' }
		`=` { 'equal' }
		`&` { 'shift-7' }
		`*` { 'shift-8' }
		`$` { 'shift-4' }
		`(` { 'shift-9' }
		`)` { 'shift-0' }
		`,` { 'comma' }
		`+` { 'shift-equal' }
		`!` { 'shift-1' }
		`#` { 'shift-3' }
		`[` { 'bracket_left' }
		`]` { 'bracket_right' }
		`{` { 'shift-bracket_left' }
		`}` { 'shift-bracket_right' }
		`%` { 'shift-5' }
		`~` { 'shift-grave_accent' }
		`@` { 'shift-2' }
		`?` { 'shift-slash' }
		`\\` { 'backslash' }
		else { error('cannot type ${character.ascii_str()}') }
	}
}

fn (mut vm Vm) type_text(text string) ! {
	for character in text.bytes() {
		vm.key(key_name(character)!)!
	}
}

fn (mut vm Vm) screenshot(name string) !string {
	path := os.join_path(vm.out, name)
	vm.monitor('screendump', {
		'filename': json2.Any(path)
		'format':   json2.Any('png')
	})!
	return path
}

// The screen as raw pixels, from a PPM screendump.
struct Screen {
	width  int
	height int
	rgb    []u8
}

// Whether the pixel x, y from the screen's centre is light.
fn (s Screen) light(x int, y int) bool {
	at := ((s.height / 2 + y) * s.width + s.width / 2 + x) * 3
	return at >= 0 && at + 2 < s.rgb.len && s.rgb[at] > 220 && s.rgb[at + 1] > 220
		&& s.rgb[at + 2] > 220
}

// The screen's pixels, from a PPM screendump: P6, width, height, 255, then RGB.
fn (mut vm Vm) screen() !Screen {
	path := os.join_path(vm.out, '.screen.ppm')
	vm.monitor('screendump', {
		'filename': json2.Any(path)
	})!
	data := os.read_bytes(path)!
	mut fields := []string{}
	mut start := 0
	for i, b in data {
		if b == `\n` || b == ` ` {
			fields << data[start..i].bytestr()
			start = i + 1
			if fields.len == 4 {
				return Screen{
					width:  fields[1].int()
					height: fields[2].int()
					rgb:    data[start..]
				}
			}
		}
	}
	return error('unreadable screendump')
}

// Wait for the "Create your user" card: light at three points of the card
// clear of its text, its fields and the pointer, which starts at the centre.
fn (mut vm Vm) wait_for_registration(deadline time.Time) ! {
	for time.now() < deadline {
		vm.poll()
		if !vm.alive() {
			return error('QEMU exited before the setup screen appeared')
		}
		screen := vm.screen() or {
			time.sleep(5 * time.second)
			continue
		}
		if screen.light(180, -150) && screen.light(-200, 190) && screen.light(180, 190)
			&& !screen.light(-400, -300) {
			return
		}
		time.sleep(5 * time.second)
	}
	return error('the setup screen did not appear')
}

fn (mut vm Vm) wait_for_change(before []u8, deadline time.Time) ! {
	for time.now() < deadline {
		time.sleep(3 * time.second)
		vm.poll()
		now := (vm.screen() or { continue }).rgb
		if now.len != before.len {
			return
		}
		mut changed := 0
		for i := 0; i < now.len; i += 61 {
			if now[i] != before[i] {
				changed++
			}
		}
		if changed > now.len / 61 / 10 {
			return
		}
	}
	return error('the screen did not change')
}

fn result_lines(text string) map[string]string {
	mut results := map[string]string{}
	for raw in text.split_into_lines() {
		// The kernel's own output can run into the start of a line on arm64.
		if !raw.contains('vinix-setup: ') {
			continue
		}
		rest := raw.trim_space().all_after_last('vinix-setup: ')
		name := rest.all_before(' ')
		results[name] = rest.all_after(' ')
	}
	return results
}

fn run(options Options) !bool {
	offered := offered_apps(options.arch)!
	println('Apps offered on ${options.arch}: ${offered.join(' ')}')
	apps := if chosen := options.apps { offered.filter(it in chosen) } else { offered }
	mut vm := start(options)!
	defer {
		if !options.keep && vm.alive() {
			vm.monitor('quit', {}) or { vm.process.signal_kill() }
		}
		vm.process.wait()
		vm.process.close()
	}
	started := time.now()
	// TCG emulates amd64 an order of magnitude slower than HVF runs arm64.
	boot_limit := if options.arch == 'arm64' { 20 } else { 90 }
	println('Booting and installing Vinix onto the blank disk...')
	vm.wait_for_registration(started.add(boot_limit * time.minute))!
	time.sleep(5 * time.second)
	registration := vm.screen()!.rgb
	vm.screenshot('1-registration.png')!
	println('Creating the user (${time.since(started).seconds():.0f} s)')
	vm.type_text('tester\n')!
	vm.type_text('vinix-test\n')!
	vm.type_text('vinix-test\n')!
	vm.wait_for_change(registration, time.now().add(5 * time.minute))!
	time.sleep(5 * time.second)
	vm.screenshot('2-software.png')!
	println('Choosing ${if apps.len == offered.len { 'every app' } else { apps.join(' ') }}')
	// Slower than typing: each toggle redraws the whole picker, and keys sent
	// faster than that were lost (the last two apps of 19 once went unchosen).
	for app in offered {
		if app in apps {
			vm.key('spc')!
			time.sleep(300 * time.millisecond)
		}
		vm.key('right')!
		time.sleep(300 * time.millisecond)
	}
	vm.screenshot('3-chosen.png')!
	vm.key('ret')!
	if apps.len == 0 {
		println('Nothing chosen; the desktop starts without a setup Terminal')
		if options.keep {
			println('The VM keeps running; QMP at ${vm.qmp}')
			vm.process.wait()
		}
		return true
	}
	deadline := time.now().add(options.timeout * time.minute)
	mut reported := map[string]bool{}
	mut last_shot := time.now()
	mut done := false
	for time.now() < deadline && vm.alive() {
		vm.poll()
		results := result_lines(vm.text)
		if installing := results['installing'] {
			if 'installing' !in reported {
				reported['installing'] = true
				missing := apps.filter(it !in installing.fields())
				println('Setup Terminal is installing: ${installing}')
				if missing.len > 0 {
					println('NOT CHOSEN: ${missing.join(' ')}')
				}
			}
		}
		for app in apps {
			if result := results[app] {
				if app !in reported {
					reported[app] = true
					elapsed := time.since(started).minutes()
					println('  ${app}: ${result} (${elapsed:.0f} min)')
					if result != 'installed' {
						vm.screenshot('failed-${app}.png') or {}
					}
				}
			}
		}
		if 'done' in results || results.keys().any(it.starts_with('done')) {
			done = true
			break
		}
		if time.since(last_shot) > 5 * time.minute {
			vm.screenshot('progress.png') or {}
			last_shot = time.now()
		}
		time.sleep(10 * time.second)
	}
	vm.screenshot('4-finished.png') or {}
	results := result_lines(vm.text)
	mut ok := done
	println('')
	for app in apps {
		result := results[app] or { 'no result' }
		if result != 'installed' {
			ok = false
		}
		println('${if result == 'installed' { 'PASS' } else { 'FAIL' }}  ${app}: ${result}')
	}
	if !done {
		println('The setup Terminal did not finish within ${options.timeout} minutes')
	}
	println('Serial log and screenshots: ${options.out}')
	if options.keep {
		println('The VM keeps running; QMP at ${vm.qmp}')
		vm.process.wait()
	}
	return ok
}

// Click at x, y of a 1024x768 screen, through the tablet's absolute axes.
fn (mut vm Vm) click(x int, y int, times int) ! {
	mut events := []json2.Any{}
	events << json2.Any({
		'type': json2.Any('abs')
		'data': json2.Any({
			'axis':  json2.Any('x')
			'value': json2.Any(x * 32767 / 1024)
		})
	})
	events << json2.Any({
		'type': json2.Any('abs')
		'data': json2.Any({
			'axis':  json2.Any('y')
			'value': json2.Any(y * 32767 / 768)
		})
	})
	vm.monitor('input-send-event', {
		'events': json2.Any(events)
	})!
	for _ in 0 .. times {
		for down in [true, false] {
			vm.monitor('input-send-event', {
				'events': json2.Any([json2.Any({
					'type': json2.Any('btn')
					'data': json2.Any({
						'down':   json2.Any(down)
						'button': json2.Any('left')
					})
				})])
			})!
			time.sleep(60 * time.millisecond)
		}
	}
}

// `run DIR key|type|click|shot ...`: drive the VM a run left in DIR.
fn drive(args []string) ! {
	mut vm := Vm{
		qmp: os.join_path(args[0], 'qmp.sock')
		out: args[0]
	}
	match args[1] {
		'key' {
			for name in args[2..] {
				vm.key(name)!
			}
		}
		'type' {
			vm.type_text(args[2..].join(' '))!
		}
		'click' {
			vm.click(args[2].int(), args[3].int(), if args.len > 4 && args[4] == 'double' { 2 } else { 1 })!
		}
		'shot' {
			vm.monitor('screendump', {
				'filename': json2.Any(os.abs_path(args[2]))
				'format':   json2.Any('png')
			})!
		}
		else {
			return error(usage)
		}
	}
}

fn main() {
	if os.args.len > 3 && os.args[2] in ['key', 'type', 'click', 'shot'] {
		drive(os.args[1..]) or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	options := parse_options() or {
		eprintln(err.msg())
		exit(2)
	}
	ok := run(options) or {
		eprintln('ERROR: ${err.msg()}')
		exit(1)
	}
	exit(if ok { 0 } else { 1 })
}
