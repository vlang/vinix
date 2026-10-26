// SPDX-License-Identifier: GPL-2.0-or-later
// x86 staging only; the workloads, pointer driver and result policy are shared.
@[has_globals]
module main

import crypto.sha256
import hwhost
import json2
import os
import perfconsole
import perfrunner
import plainiso

$if macos {
	#include <sys/clonefile.h>
}

fn C.clonefile(&char, &char, int) int

struct Prepared {
	root            string
	base            string
	arguments       []string
	command         []string
	socket          string
	inputs          map[string]string
	base_manifest   string
	staged_manifest string
	storage         string
}

fn serial_console_arguments() []string {
	// perfconsole retires the foreground QEMU owner with Ctrl-A X. The monitor
	// must share stdio with serial for that escape to exit QEMU cleanly.
	return ['-serial', 'mon:stdio']
}

fn clone_mode() !bool {
	value := os.getenv('VINIX_PERF_X86_APFS_CLONE')
	if value !in ['', '0', '1'] { return error('invalid VINIX_PERF_X86_APFS_CLONE') }
	if value != '1' { return false }
	$if macos {
		return true
	} $else {
		return error('APFS clone staging requires macOS')
	}
}

fn clone_file(source string, destination string) ! {
	$if macos {
		before := os.lstat(source)!
		if before.get_filetype() != .regular { return error('clone source must be regular') }
		if os.exists(destination) || os.is_link(destination) { return error('clone destination exists') }
		// clonefile is exclusive and has no copy fallback. Independent inodes
		// retain private writes in either direction; never hardlink frozen inputs.
		if C.clonefile(source.str, destination.str, C.CLONE_NOFOLLOW) != 0 {
			return error('clonefile failed: ' + source + ' -> ' + destination)
		}
		os.chmod(destination, int(before.mode & 0o7777))!
		after := os.lstat(destination)!
		if after.get_filetype() != .regular || (before.dev == after.dev && before.inode == after.inode)
			|| before.mode != after.mode || before.size != after.size {
			return error('clone identity or metadata differs')
		}
	} $else {
		return error('APFS clone staging requires macOS')
	}
}

fn destination_path(path string) !string {
	// Resolve the existing ancestor before creating anything: an absent output
	// below a host symlink must not be mistaken for a separate source tree.
	mut current := os.abs_path(path)
	mut missing := []string{}
	for !os.exists(current) && !os.is_link(current) {
		missing << os.file_name(current)
		parent := os.dir(current)
		if parent == current { return error('missing destination ancestor') }
		current = parent
	}
	if !os.is_dir(current) { return error('destination ancestor is not a directory') }
	mut resolved := os.real_path(current)
	if resolved == '' { return error('cannot resolve destination ancestor') }
	for name in missing.reverse() { resolved = os.join_path(resolved, name) }
	return resolved
}

fn inside(path string, root string) bool {
	return path == root || path.starts_with(root.trim_right('/') + '/')
}

fn admit_destination(base string, state string) ! {
	if inside(destination_path(state)!, os.real_path(base)) {
		return error('staging destination is inside source')
	}
}

fn clone_tree(source string, destination string) ! {
	if os.exists(destination) || os.is_link(destination) { return error('clone destination exists') }
	info := os.lstat(source)!
	if info.get_filetype() == .directory { admit_destination(source, destination)! }
	match info.get_filetype() {
		.regular { clone_file(source, destination)! }
		.symbolic_link { os.symlink(os.readlink(source)!, destination)! }
		.directory {
			os.mkdir(destination)!
			mut names := os.ls(source)!
			names.sort()
			for name in names { clone_tree(source + '/' + name, destination + '/' + name)! }
			os.chmod(destination, int(info.mode & 0o7777))!
		}
		else { return error('unsupported clone entry: ' + source) }
	}
}

fn stage_file(source string, destination string, clone bool) ! {
	if clone { clone_file(source, destination)! } else { os.cp(source, destination)! }
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut buf := []u8{len: 65536}
	for {
		n := file.read(mut buf) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		sum.write(buf[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn pin(mut pins map[string]string, path string) ! {
	value := digest(path)!
	pins[path] = value
	pins[os.real_path(path)] = value
}

fn inventory(root string, relative string) !string {
	mut entries := os.ls(root + '/' + relative)!
	entries.sort()
	mut rows := []string{}
	for name in entries {
		if name.contains_any('\t\r\n') { return error('unsupported inventory path') }
		item := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + item
		if os.is_link(path) {
			target := os.readlink(path)!
			if target.contains_any('\t\r\n') { return error('unsupported link target') }
			rows << 'link\t' + item + '\t' + target
		} else if os.is_dir(path) {
			rows << 'directory\t' + os.stat(path)!.mode.str() + '\t' + item
			rows << inventory(root, item)!
		} else if os.is_file(path) {
			rows << 'file\t' + digest(path)! + '\t' + os.stat(path)!.mode.str() + '\t' + item
		} else {
			return error('unsupported root entry: ' + path)
		}
	}
	return rows.filter(it != '').join('\n')
}

fn guest_path(root string, relative string) !string {
	// Resolve every component before using host file APIs: an intermediate
	// guest-absolute link must never become a host-absolute pathname.
	mut pending := relative.split('/')
	mut resolved := []string{}
	mut links := 0
	for pending.len > 0 {
		component := pending[0]
		pending.delete(0)
		if component in ['', '.'] { continue }
		if component == '..' {
			if resolved.len == 0 { return error('guest link escapes root: ' + relative) }
			resolved.pop()
			continue
		}
		path := root + '/' + if resolved.len == 0 {
			component
		} else {
			resolved.join('/') + '/' + component
		}
		if os.is_link(path) {
			links++
			if links > 40 { return error('guest symlink cycle: ' + relative) }
			target := os.readlink(path)!
			if target.starts_with('/') { resolved.clear() }
			mut next := target.split('/')
			next << pending
			pending = next.clone()
			continue
		}
		if pending.len > 0 && !os.is_dir(path) {
			return error('missing guest directory: ' + relative)
		}
		resolved << component
	}
	path := root + '/' + resolved.join('/')
	if !os.is_file(path) { return error('missing guest file: ' + relative) }
	return path
}

fn elf(path string) ! {
	mut f := os.open(path)!
	defer { f.close() }
	mut header := []u8{len: 20}
	if f.read(mut header)! != 20 || header[..7] != [u8(127), `E`, `L`, `F`, 2, 1, 1] || header[18] != 62 || header[19] != 0 {
		return error('expected x86-64 ELF: ' + path)
	}
}

fn capture(args []string) !string {
	r := os.exec(args)
	if r.exit_code != 0 { return error(args.join(' ') + ': ' + r.output) }
	return r.output
}

fn closure(base string, programs []string, readelf string) ! {
	mut pending := programs.clone()
	mut seen := map[string]bool{}
	for pending.len > 0 {
		path := pending.pop()
		if path in seen { continue }
		seen[path] = true
		elf(path)!
		for line in capture([readelf, '-d', path])!.split_into_lines() {
			if !line.contains('(NEEDED)') { continue }
			name := line.all_after('[').all_before(']')
			if name == '' || name.contains('/') { return error('invalid DT_NEEDED') }
			mut found := false
			for dir in ['/lib/', '/usr/lib/'] {
				candidate := guest_path(base, dir + name) or { continue }
				pending << candidate
				found = true
				break
			}
			if !found { return error('missing guest dependency ' + name) }
		}
	}
}

fn source_inputs(root string, mut pins map[string]string) ! {
	for dir in ['tests/desktop-perf', 'tests/hardware-platform/hwhost',
		'tests/hardware-platform/plainiso', 'tests/linuxkpi/hosttest', 'tools/hosttest',
		'tools/sourcecommand', 'tools/qmpclient'] {
		for extension in ['.v', '.h', '.c', '.sh'] {
			for path in os.walk_ext(root + '/' + dir, extension) { pins[path] = digest(path)! }
		}
	}
}

fn verify(p Prepared, state string) ! {
	for path, expected in p.inputs {
		if digest(path)! != expected { return error('input changed: ' + path) }
	}
	if digest(state + '/base-before.tsv')! != p.base_manifest
		|| os.read_file(state + '/base-before.tsv')! != inventory(p.base, '')! + '\n' {
		return error('base runtime changed')
	}
	if digest(state + '/staged-before.tsv')! != p.staged_manifest
		|| os.read_file(state + '/staged-before.tsv')! != inventory(state + '/rootfs', '')! + '\n' {
		return error('staged guest changed')
	}
}

fn iso_configuration() string {
	// Production kernels initialize ATA/AHCI only when a disk is requested.
	// Without an installer image id, the fixture's root stays in memory.
	return plainiso.configuration().replace('1024x768x32', '2048x1536x32') +
		'    cmdline: vinix.disk=auto quiet\n'
}

fn image_builder() ! {
	build := os.getenv('VINIX_AMD64_ISO_BUILD_DIR')
	output := os.getenv('VINIX_AMD64_ISO')
	loader := os.getenv('VINIX_PERF_X86_LOADER')
	if build == '' || output == '' || loader == '' { return error('missing x86 media inputs') }
	clone := clone_mode()!
	stage := build + '/iso-root'
	os.mkdir_all(stage + '/EFI/BOOT')!
	os.mkdir_all(stage + '/boot')!
	for pair in [[os.getenv('VINIX_AMD64_KERNEL'), '/boot/vinix'],
		[os.getenv('VINIX_AMD64_INITRAMFS'), '/boot/initramfs.tar'],
		[loader + '/BOOTX64.EFI', '/EFI/BOOT/BOOTX64.EFI'],
		[loader + '/limine-uefi-cd.bin', '/boot/limine-uefi-cd.bin']] {
		stage_file(pair[0], stage + pair[1], clone)!
	}
	os.write_file(stage + '/boot/limine.conf', iso_configuration())!
	args := [os.getenv('VINIX_PERF_X86_XORRISO'), '-as', 'mkisofs', '-iso-level', '3', '-R', '-r',
		'-J', '--efi-boot', 'boot/limine-uefi-cd.bin', '-efi-boot-part', '--efi-boot-image',
		'--protective-msdos-label', stage, '-o', output]
	os.write_file(os.dir(output) + '/image-command.json', json2.encode(args,
		escape_unicode: true
		time_as_unix:   true
	) + '\n')!
	hwhost.run_tool(args, {}, os.dir(output) + '/image-build.log', 300)!
}

fn prepare(args []string, stage bool) ! {
	if args.len < 5 {
		return error('expected REPO BASE_ROOT KERNEL FRESH_STATE NAME=DESKTOP [perf options]')
	}
	root, base, kernel, state := os.real_path(args[0]), os.real_path(args[1]), os.real_path(args[2]), os.abs_path(args[3])
	if os.exists(state) || os.is_link(state) { return error('state must be fresh') }
	admit_destination(base, state)!
	clone := clone_mode()!
	plan := perfrunner.parse(args[4..], root, root + '/tests/desktop-perf', '')!
	if plan.mem < 512 || plan.mem > 65536 || plan.desktop_args.contains_any("'\r\n") || plan.assets.len != 0 {
		return error('unsupported memory, quoted desktop arguments or dictionary assets')
	}
	if plan.scenarios.any(it !in ['ops', 'churn', 'cache', 'idle', 'apps', 'drag']) {
		return error('x86 adapter supports ops,churn,cache,idle,apps,drag')
	}
	if 'ops' in plan.scenarios && plan.timeout < 1800 {
		return error('ops requires timeout >=1800')
	}
	found := hwhost.find_host(root, 'x86_64', '')!
	// Deferred execution uses the admitted files if host symlinks change.
	host := hwhost.Host{
		...found
		v:        os.real_path(found.v)
		qemu:     os.real_path(found.qemu)
		firmware: os.real_path(found.firmware)
	}
	tools := plainiso.inputs(root)!
	cc := os.find_abs_path_of_executable(os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' })!
	readelf := os.find_abs_path_of_executable(os.getenv_opt('VINIX_PERF_READELF') or { 'llvm-readelf' })!
	mkfs := os.find_abs_path_of_executable(os.getenv_opt('VINIX_PERF_MKFS') or { 'mkfs.ext2' })!
	mut pins := map[string]string{}
	source_inputs(root, mut pins)!
	for path in [kernel, host.v, host.qemu, host.firmware, cc, readelf, mkfs, os.executable(),
		os.find_abs_path_of_executable('cp')!, os.find_abs_path_of_executable('tar')!] {
		pin(mut pins, path)!
	}
	for _, path in tools { pin(mut pins, path)! }
	elf(kernel)!
	mut programs := []string{}
	for path in ['/bin/busybox', '/bin/sh', '/bin/zsh', '/usr/bin/curl', '/lib/ld-musl-x86_64.so.1'] {
		programs << guest_path(base, path)!
	}
	for build in plan.builds {
		pin(mut pins, build.binary)!
		programs << build.binary
	}
	closure(base, programs, readelf)!
	if !stage {
		println('PERF X86 INPUTS ' + json2.encode(pins,
			escape_unicode: true
			time_as_unix:   true
		))
		println('PERF X86 INPUT CHECK PASS; no staging or VM execution')
		return
	}
	os.mkdir_all(state)!
	os.write_file(state + '/prepare-arguments.json', json2.encode(os.args,
		escape_unicode: true
		time_as_unix:   true
	) + '\n')!
	os.write_file(state + '/base-before.tsv', inventory(base, '')! + '\n')!
	if clone {
		clone_tree(base, state + '/rootfs')!
	} else {
		os.mkdir(state + '/rootfs')!
		hwhost.run_tool(['cp', '-Rp', base + '/.', state + '/rootfs'], {}, state + '/prepare.log', 300)!
	}
	if os.read_file(state + '/base-before.tsv')! != inventory(state + '/rootfs', '')! + '\n' {
		return error('root copy differs from frozen base')
	}
	// Cached release roots place some applets only in /usr/bin. Install the
	// same fixed busybox names used by the ARM perf staging adapter.
	for name in ['sh', 'true', 'sleep', 'mkdir', 'chmod', 'od', 'tr', 'rm', 'touch', 'kill', 'sync',
		'cat', 'sed', 'dd', 'awk', 'grep', 'tail', 'install', 'ln'] {
		path := state + '/rootfs/bin/' + name
		if os.exists(path) || os.is_link(path) { os.rm(path)! }
		os.symlink('/bin/busybox', path)!
	}
	init := hwhost.build_program(host, root + '/tests/desktop-perf/x86-init', state + '/guest', 'init', [])!
	os.rm(state + '/rootfs/sbin/init') or {}
	os.cp(init, state + '/rootfs/sbin/init')!
	os.chmod(state + '/rootfs/sbin/init', 0o755)!
	perf := state + '/rootfs/opt/vinix-perf'
	os.mkdir_all(perf)!
	hwhost.run_tool([cc, '-static', '-O2', '-Wall', root + '/tests/desktop-perf/measure.c', '-o',
		perf + '/measure'], {}, state + '/measure-build.log', 300)!
	for path in [init, state + '/guest/init.c', perf + '/measure'] { pins[path] = digest(path)! }
	for build in plan.builds { stage_file(build.binary, perf + '/vinix-desktop-' + build.name, clone)! }
	os.cp(root + '/tests/desktop-perf/perf-init.sh', perf + '/perf-init.sh')!
	os.write_file(perf + '/config', "VARIANTS='" + plan.builds.map(it.name).join(' ') + "'\nSCENARIOS='" + plan.scenarios.join(' ') + "'\nROUNDS=${plan.rounds}\nSETTLE=${plan.settle}\nMEASURE=${plan.seconds}\nDESKTOP_ARGS='" + plan.desktop_args + "'\n")!
	for directory in ['dev', 'proc', 'sys', 'tmp', 'run', 'root'] {
		os.mkdir_all(state + '/rootfs/' + directory)!
	}
	os.chmod(state + '/rootfs/tmp', 0o1777)!
	archive := state + '/initramfs.tar'
	hwhost.run_tool(['tar', '--format=ustar', '-cf', archive, '-C', state + '/rootfs', '.'], {
		'COPYFILE_DISABLE': '1'
	}, state + '/prepare.log', 300)!
	os.mkdir_all(state + '/image-builder/build-support')!
	os.symlink(os.executable(), state + '/image-builder/build-support/build-amd64-iso.sh')!
	os.setenv('VINIX_PERF_X86_IMAGE', '1', true)
	os.setenv('VINIX_PERF_X86_LOADER', os.dir(tools['iso-BOOTX64.EFI']), true)
	os.setenv('VINIX_PERF_X86_XORRISO', tools['iso-xorriso'], true)
	media := hwhost.boot_media(hwhost.Host{ ...host, root: state + '/image-builder' }, kernel, archive, 'quiet', state)!
	os.write_file(state + '/root.ext2', '')!
	os.truncate(state + '/root.ext2', u64(256) << 20)!
	hwhost.run_tool([mkfs, '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-O',
		'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum',
		state + '/root.ext2'], {}, state + '/prepare.log', 300)!
	socket := '/tmp/vinix-perf-x86-' + sha256.sum(state.bytes()).hex()[..16] + '.qmp'
	console := serial_console_arguments()
	command := [host.qemu, '-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-vga', 'std',
		'-device', 'qemu-xhci,id=gui-input', '-device', 'usb-kbd,bus=gui-input.0', '-device',
		'usb-tablet,bus=gui-input.0', '-m', plan.mem.str(), '-smp', '2', ...media, '-display',
		'none', ...console, '-qmp', 'unix:' + socket + ',server=on,wait=off', '-no-reboot',
		'-nic', 'none', '-drive', 'if=ide,format=raw,file=' + state + '/root.ext2']
	for path in [archive, state + '/test.iso', state + '/root.ext2'] { pins[path] = digest(path)! }
	// Preserve the actual maintained adapter and unchanged supervisor/workloads.
	sources := pins.keys().filter(it.starts_with(root + '/')
		&& (it.ends_with('.v') || it.ends_with('.c') || it.ends_with('.h') || it.ends_with('.sh')))
	for path in sources {
		destination := state + '/source/' + path[root.len + 1..]
		os.mkdir_all(os.dir(destination))!
		os.cp(path, destination)!
		pins[destination] = digest(destination)!
	}
	os.write_file(state + '/staged-before.tsv', inventory(state + '/rootfs', '')! + '\n')!
	p := Prepared{root, base, args[4..], command, socket, pins, digest(state + '/base-before.tsv')!, digest(state + '/staged-before.tsv')!, if clone { 'apfs-clone' } else { 'copy' }}
	verify(p, state)!
	os.write_file(state + '/prepared.json', json2.encode(p,
		escape_unicode: true
		time_as_unix:   true
	) + '\n')!
	println('PERF X86 PREPARED sha256=' + digest(state + '/prepared.json')!)
}

fn run(state string, expected string) !int {
	if digest(state + '/prepared.json')! != expected {
		return error('prepared receipt digest mismatch')
	}
	p := json2.decode[Prepared](os.read_file(state + '/prepared.json')!)!
	verify(p, state)!
	plan := perfrunner.parse(p.arguments, p.root, p.root + '/tests/desktop-perf', '')!
	os.mkdir(state + '/results')!
	if os.exists(p.socket) { return error('QMP socket already exists') }
	defer { os.rm(p.socket) or {} }
	guard := perfconsole.own_commands()
	defer { guard.close() }
	status := perfrunner.drive(plan, perfrunner.Launch{p.command, os.environ(), p.socket}, state + '/results', 10, true)!
	// Only the ext2 workload disk may change during execution.
	mut after := p.inputs.clone()
	after.delete(state + '/root.ext2')
	verify(Prepared{ ...p, inputs: after }, state)!
	after[state + '/root.ext2'] = digest(state + '/root.ext2')!
	os.write_file(state + '/after-inputs.json', json2.encode(after,
		escape_unicode: true
		time_as_unix:   true
	) + '\n')!
	os.write_file(state + '/results/status', status.str() + '\n')!
	return status
}

fn selfcheck(state string) ! {
	if os.exists(state) || os.is_link(state) { return error('selfcheck state must be fresh') }
	os.mkdir_all(state + '/base/bin')!
	os.mkdir_all(state + '/rootfs')!
	os.write_file(state + '/base/bin/busybox', 'runtime')!
	os.symlink('/bin/busybox', state + '/base/bin/sh')!
	if guest_path(state + '/base', '/bin/sh')! != state + '/base/bin/busybox' {
		return error('absolute guest link was resolved on host')
	}
	os.symlink('../bin/busybox', state + '/base/relative')!
	if _ := guest_path(state + '/base', '/relative') {
		return error('escaping guest link accepted')
	}
	os.symlink('/cycle', state + '/base/cycle')!
	if _ := guest_path(state + '/base', '/cycle') { return error('link cycle accepted') }
	if _ := guest_path(state + '/base', '/missing') { return error('missing file accepted') }
	os.mkdir_all(state + '/base/usr/lib')!
	os.write_file(state + '/base/usr/lib/libc.so', 'library')!
	os.symlink('/usr/lib', state + '/base/lib')!
	if guest_path(state + '/base', '/lib/libc.so')! != state + '/base/usr/lib/libc.so' {
		return error('absolute intermediate guest link resolved on host')
	}
	os.symlink('usr', state + '/base/relative-dir')!
	if guest_path(state + '/base', '/relative-dir/lib/libc.so')! != state + '/base/usr/lib/libc.so' {
		return error('relative intermediate guest link resolved incorrectly')
	}
	os.symlink('../outside', state + '/base/escape-dir')!
	if _ := guest_path(state + '/base', '/escape-dir/libc.so') {
		return error('escaping intermediate guest link accepted')
	}
	os.symlink('/cycle-dir', state + '/base/cycle-dir')!
	if _ := guest_path(state + '/base', '/cycle-dir/libc.so') {
		return error('intermediate guest link cycle accepted')
	}
	os.write_file(state + '/empty', '')!
	if digest(state + '/empty')! != sha256.sum([]u8{}).hex() {
		return error('empty streaming digest')
	}
	base := inventory(state + '/base', '')! + '\n'
	os.write_file(state + '/base-before.tsv', base)!
	os.write_file(state + '/staged-before.tsv', '\n')!
	p := Prepared{
		base:            state + '/base'
		inputs:          {
			state + '/empty': digest(state + '/empty')!
		}
		base_manifest:   digest(state + '/base-before.tsv')!
		staged_manifest: digest(state + '/staged-before.tsv')!
	}
	verify(p, state)!
	os.rm(state + '/base/lib')!
	os.symlink('/bin', state + '/base/lib')!
	if _ := verify(p, state) { return error('retargeted intermediate guest link accepted') }
	os.rm(state + '/base/lib')!
	os.symlink('/usr/lib', state + '/base/lib')!
	os.write_file(state + '/empty', 'changed')!
	if _ := verify(p, state) { return error('changed pinned input accepted') }
	os.write_file(state + '/empty', '')!
	os.write_file(state + '/base/bin/busybox', 'changed')!
	if _ := verify(p, state) { return error('changed link referent accepted') }
	os.write_file(state + '/base/bin/busybox', 'runtime')!
	os.rm(state + '/base/bin/sh')!
	os.symlink('/elsewhere', state + '/base/bin/sh')!
	if _ := verify(p, state) { return error('changed symlink target accepted') }
	os.rm(state + '/base/bin/sh')!
	os.symlink('/bin/busybox', state + '/base/bin/sh')!
	os.write_file(state + '/rootfs/extra', 'new')!
	if _ := verify(p, state) { return error('extra staged file accepted') }
	os.rm(state + '/rootfs/extra')!
	verify(p, state)!
	if iso_configuration().contains('1024x768') || !iso_configuration().contains('2048x1536x32') {
		return error('pointer geometry changed')
	}
	if !iso_configuration().ends_with('    cmdline: vinix.disk=auto quiet\n')
		|| iso_configuration().count('    cmdline:') != 1 {
		return error('production disk boot arguments changed')
	}
	if serial_console_arguments() != ['-serial', 'mon:stdio'] {
		return error('foreground serial monitor escape changed')
	}
	for options in [['--scenarios=ops', '--timeout=1799'], ['--scenarios=idle', '--mem=-1'],
		['--scenarios=pointer'], ['--scenarios=idle', "--desktop-args='bad'"]] {
		mut args := [state, state + '/base', state + '/empty', state + '/never',
			'test=' + state + '/empty']
		args << options
		if _ := prepare(args, false) { return error('invalid prepare options accepted') }
		if os.exists(state + '/never') { return error('refused prepare wrote staging') }
	}
	os.write_file(state + '/tool-a', 'first')!
	os.write_file(state + '/tool-b', 'second')!
	os.symlink('tool-a', state + '/host-tool')!
	mut tool_pins := map[string]string{}
	pin(mut tool_pins, state + '/host-tool')!
	tool := Prepared{ ...p, inputs: tool_pins }
	verify(tool, state)!
	os.rm(state + '/host-tool')!
	os.symlink('tool-b', state + '/host-tool')!
	if _ := verify(tool, state) { return error('retargeted host tool accepted') }
	os.rm(state + '/host-tool')!
	os.symlink('tool-a', state + '/host-tool')!
	verify(tool, state)!
	os.write_file(state + '/result', 'PASS 26 checks including 15 refusals: final/intermediate absolute and relative guest links, escape/cycle/referral/link/staged mutations, streaming digest, restore, geometry, production disk boot arguments, foreground serial monitor escape, timeout/memory/scenario/quote controls, host-tool symlink retarget\n')!
	println('PERF X86 SELFCHECK PASS 26 checks including 15 refusals')
}

fn clonecheck(state string) ! {
	$if !macos { return error('APFS clone controls require macOS') }
	if os.exists(state) || os.is_link(state) { return error('clonecheck state must be fresh') }
	previous := os.getenv_opt('VINIX_PERF_X86_APFS_CLONE')
	defer {
		if value := previous { os.setenv('VINIX_PERF_X86_APFS_CLONE', value, true) }
		else { os.unsetenv('VINIX_PERF_X86_APFS_CLONE') }
	}
	mut checks := []string{}
	os.setenv('VINIX_PERF_X86_APFS_CLONE', '1', true)
	if !clone_mode()! { return error('clone opt-in ignored') }
	checks << 'explicit clone mode admitted'
	os.setenv('VINIX_PERF_X86_APFS_CLONE', 'invalid', true)
	if _ := clone_mode() { return error('invalid clone mode accepted') }
	checks << 'invalid clone mode refused'
	os.setenv('VINIX_PERF_X86_APFS_CLONE', '0', true)
	if clone_mode()! { return error('copy mode ignored') }
	checks << 'explicit copy mode retained'
	source, destination := state + '/source', state + '/destination'
	os.mkdir_all(source + '/bin')!
	os.mkdir_all(source + '/usr/lib')!
	os.write_file(source + '/bin/tool', 'source bytes')!
	os.chmod(source + '/bin/tool', 0o750)!
	os.write_file(source + '/usr/lib/library', 'library bytes')!
	os.chmod(source + '/usr/lib/library', 0o640)!
	os.symlink('/bin/tool', source + '/absolute')!
	os.symlink('bin/tool', source + '/relative')!
	os.symlink('/usr/lib', source + '/lib')!
	os.symlink('/missing', source + '/dangling')!
	before := inventory(source, '')!
	clone_tree(source, destination)!
	if inventory(destination, '')! != before { return error('clone inventory mismatch') }
	checks << 'tree bytes, permission modes and four literal guest links preserved'
	s := os.lstat(source + '/bin/tool')!
	d := os.lstat(destination + '/bin/tool')!
	if s.dev == d.dev && s.inode == d.inode { return error('clone shares source inode') }
	checks << 'regular clone has independent inode'
	os.write_file(destination + '/bin/tool', 'destination change')!
	if os.read_file(source + '/bin/tool')! != 'source bytes' { return error('destination write changed source') }
	checks << 'destination write leaves source bytes unchanged'
	os.write_file(source + '/bin/tool', 'source change')!
	if os.read_file(destination + '/bin/tool')! != 'destination change' { return error('source write changed destination') }
	checks << 'source write leaves destination bytes unchanged'
	if _ := clone_file(source + '/bin/tool', destination + '/bin/tool') {
		return error('existing clone target accepted')
	}
	if os.read_file(destination + '/bin/tool')! != 'destination change' { return error('refusal changed existing target') }
	checks << 'existing regular target refused without replacement'
	if _ := clone_file(source + '/bin/tool', destination + '/dangling') {
		return error('existing dangling link target accepted')
	}
	if os.readlink(destination + '/dangling')! != '/missing' { return error('refusal changed dangling link') }
	checks << 'existing dangling target refused without replacement'
	if _ := clone_file(source + '/missing', state + '/missing-output') {
		return error('missing clone source accepted')
	}
	if os.exists(state + '/missing-output') { return error('missing source wrote output') }
	checks << 'missing source propagates failure without output'
	if _ := clone_file(source + '/bin/tool', state + '/missing-parent/file') {
		return error('clonefile system call failure ignored')
	}
	if os.exists(state + '/missing-parent') { return error('failed clone created parent') }
	checks << 'clonefile system call failure propagates without copy fallback'
	if _ := clone_file(source + '/absolute', state + '/link-output') {
		return error('literal symlink admitted as regular clone source')
	}
	checks << 'regular clone refuses symlink source'
	if _ := clone_file(source + '/bin', state + '/directory-output') {
		return error('directory admitted as regular clone source')
	}
	checks << 'regular clone refuses directory source'
	if _ := clone_tree(source, destination) { return error('existing tree accepted') }
	checks << 'existing tree destination refused'
	if _ := clone_tree(source, source + '/nested') { return error('nested tree accepted') }
	if os.exists(source + '/nested') { return error('nested refusal created output') }
	checks << 'destination inside source refused without output'
	os.symlink(source, state + '/source-alias')!
	alias_output := state + '/source-alias/nested'
	alias_before := inventory(source, '')!
	if _ := clone_tree(source, alias_output) { return error('aliased nested tree accepted') }
	else { if err.msg() != 'staging destination is inside source' { return err } }
	if os.exists(source + '/nested') || inventory(source, '')! != alias_before {
		return error('aliased tree refusal changed source or created output')
	}
	checks << 'parent alias nesting refused before source or output mutation'
	if _ := prepare([state, source, source + '/bin/tool',
		state + '/source-alias/absent-parent/nested', 'test=' + source + '/bin/tool'], true) {
		return error('aliased prepare state accepted')
	} else { if err.msg() != 'staging destination is inside source' { return err } }
	if os.exists(source + '/absent-parent') || inventory(source, '')! != alias_before {
		return error('aliased prepare refusal changed source or created output')
	}
	checks << 'prepare admission refuses aliased state before directory creation'
	os.write_file(source + '/bin/tool', 'source bytes')!
	os.write_file(destination + '/bin/tool', 'source bytes')!
	if inventory(source, '')! != before || inventory(destination, '')! != before {
		return error('clone restore differs')
	}
	checks << 'full source and destination inventories agree after restore'
	os.write_file(state + '/result.json', json2.encode(checks, escape_unicode: true) + '\n')!
	println('PERF X86 CLONECHECK PASS ' + checks.len.str() + ' controls')
}

fn main() {
	if os.getenv('VINIX_PERF_X86_IMAGE') == '1' && os.getenv('VINIX_AMD64_INITRAMFS') != '' {
		image_builder() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len > 1 && os.args[1] in ['check', 'prepare'] {
		prepare(os.args[2..], os.args[1] == 'prepare') or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len == 3 && os.args[1] == 'selfcheck' {
		selfcheck(os.abs_path(os.args[2])) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len == 3 && os.args[1] == 'clonecheck' {
		clonecheck(os.abs_path(os.args[2])) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len == 4 && os.args[1] == 'run' {
		status := run(os.abs_path(os.args[2]), os.args[3]) or {
			eprintln(err)
			exit(1)
		}
		exit(status)
	}
	eprintln('usage: run-x86 check|prepare REPO FULL_BASE_ROOT KERNEL FRESH_STATE NAME=DESKTOP [perf options]\n       run-x86 run STATE PREPARED_JSON_SHA256\n       run-x86 selfcheck|clonecheck FRESH_STATE')
	exit(2)
}
