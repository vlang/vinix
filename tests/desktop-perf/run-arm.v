// SPDX-License-Identifier: GPL-2.0-or-later
// Retained ARM staging; workloads and foreground ownership are shared.
@[has_globals]
module main

import crypto.sha256
import hwhost
import json2
import os
import perfconsole
import perfrunner

struct Prepared {
	arch string = 'aarch64'
	root string
	base string
	arguments []string
	command []string
	socket string
	inputs map[string]string
	base_manifest string
	staged_manifest string
	storage string = 'archive-overlay'
	firmware string
	sysroot string
	sysroot_manifest string
}

fn require(ok bool, text string) ! { if !ok { return error(text) } }
fn inside(path string, root string) bool { return path == root || path.starts_with(root + '/') }

fn digest(path string) !string {
	mut file := os.open(path)!; defer { file.close() }
	mut sum := sha256.new(); defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 65536}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }; sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn digest_text(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn pin(mut pins map[string]string, path string) ! {
	value := digest(path)!; pins[path] = value; pins[os.real_path(path)] = value
}

fn inventory(root string, relative string) !string {
	mut names := os.ls(root + '/' + relative)!; names.sort()
	mut rows := []string{}
	for name in names {
		require(!name.contains_any('\t\r\n'), 'unsupported inventory path')!
		item := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + item
		if os.is_link(path) {
			target := os.readlink(path)!
			require(!target.contains_any('\t\r\n'), 'unsupported inventory link')!
			rows << 'link\t' + item + '\t' + target
		} else if os.is_dir(path) {
			rows << 'directory\t' + os.stat(path)!.mode.str() + '\t' + item
			rows << inventory(root, item)!
		} else if os.is_file(path) {
			rows << 'file\t' + digest(path)! + '\t' + os.stat(path)!.mode.str() + '\t' + item
		} else { return error('unsupported inventory entry: ' + path) }
	}
	return rows.filter(it != '').join('\n')
}

fn archive_record(base string) !string {
	require(os.lstat(base)!.get_filetype() == .regular && !base.contains_any('\t\r\n'), 'regular base archive required')!
	return 'file\t' + digest(base)! + '\t' + os.lstat(base)!.mode.str() + '\t' + base + '\n'
}

fn elf(path string) ! {
	mut file := os.open(path)!; defer { file.close() }
	mut header := []u8{len: 20}
	require(file.read(mut header)! == 20 && header[..7] == [u8(127), `E`, `L`, `F`, 2, 1, 1]
		&& header[18] == 183 && header[19] == 0, 'expected AArch64 ELF: ' + path)!
}

fn selected(name string, directory bool) !string {
	path := os.getenv(name)
	require(path != '' && path == os.real_path(path), 'canonical selected input required: ' + name)!
	require(if directory { os.is_dir(path) } else { os.is_file(path) }, 'selected input missing: ' + name)!
	return path
}

fn selected_linker() !string {
	path := os.getenv('VINIX_PERF_ARM_LINKER')
	// lld dispatches by argv[0]; preserve the explicit ELF-driver alias.
	require(path.starts_with('/') && os.base(path) == 'ld.lld' && os.is_executable(path)
		&& os.is_file(os.real_path(path)), 'absolute selected ld.lld driver required')!
	return path
}

fn source_inputs(root string, mut pins map[string]string) ! {
	for dir in ['tests/desktop-perf', 'tests/hardware-platform/hwhost', 'tests/hardware-platform/plainiso',
		'tests/linuxkpi/hosttest', 'tools/hosttest', 'tools/sourcecommand', 'tools/qmpclient'] {
		for extension in ['.v', '.h', '.c', '.sh'] {
			for path in os.walk_ext(root + '/' + dir, extension) { pins[path] = digest(path)! }
		}
	}
}

fn options(arguments []string) !(string, []string) {
	mut expected := ''; mut remaining := []string{}
	for argument in arguments {
		if argument.starts_with('--base-manifest-sha256=') {
			require(expected == '', 'duplicate base archive pin')!
			expected = argument.all_after('=')
			require(digest_text(expected), 'invalid base archive pin')!
		} else { remaining << argument }
	}
	require(expected != '', 'base archive pin required')!
	return expected, remaining
}

fn admitted(root string, base string, state string, expected string) !string {
	require(root == os.real_path(root) && os.is_dir(root), 'canonical source required')!
	require(base == os.real_path(base) && os.is_file(base), 'canonical base archive required')!
	require(state.starts_with('/') && os.real_path(os.dir(state)) == os.dir(state)
		&& !os.exists(state) && !os.is_link(state), 'fresh canonical state required')!
	require(!inside(state, root) && !inside(root, state) && !inside(base, state), 'state overlaps input')!
	require(digest(base)! == expected, 'base archive pin differs before staging')!
	return archive_record(base)!
}

fn compile_command(cc string, linker string, sysroot string, gcc string, source string, output string, init bool) []string {
	lib := sysroot + '/usr/lib'
	mut argv := [cc, '--no-default-config', '--target=aarch64-linux-musl', '-static', '-nostdinc', '-nostdlib',
		'-isystem', gcc + '/include', '-isystem', sysroot + '/usr/include', '-O2', '-Wall',
		'-D_GNU_SOURCE', '-fno-stack-protector', lib + '/crt1.o', lib + '/crti.o', gcc + '/crtbeginT.o', source,
		'-L' + lib, '-L' + gcc]
	if init { argv << ['-lm', '-lpthread'] }
	argv << ['-lc', '-lgcc', gcc + '/crtend.o', lib + '/crtn.o', '-fuse-ld=' + linker, '-o', output]
	return argv
}

fn tool(argv []string, state string, name string) ! {
	os.write_file(state + '/' + name + '-argv.json', json2.encode(argv) + '\n')!
	hwhost.run_tool(argv, {}, state + '/' + name + '.log', 300)!
}

fn configuration() string {
	return 'timeout: 0\nverbose: yes\n\n/Vinix\n    protocol: limine\n'
		+ '    kernel_path: boot():/boot/vinix\n    module_path: boot():/boot/base.tar\n'
		+ '    module_path: boot():/boot/overlay.tar\n    resolution: 2048x1536x32\n'
		+ '    kaslr: no\n    cmdline: vinix.qemu_platform=1 quiet\n'
}

fn fat_size(files []u64) !u64 {
	mut payload := u64(0)
	for size in files {
		require(size < (u64(4) << 30) && payload <= (u64(16) << 30) - size, 'FAT payload exceeds bounds')!
		payload += size
	}
	mut size := u64(64) << 20
	for size < payload + payload / 8 + (u64(8) << 20) { size *= 2 }
	return size
}

fn qemu_command(qemu string, firmware string, state string, socket string, memory int) []string {
	return [qemu, '-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-m', memory.str(), '-smp', '2',
		'-object', 'rng-random,filename=/dev/urandom,id=vinix-rng', '-device', 'virtio-rng-device,rng=vinix-rng',
		'-drive', 'if=pflash,format=raw,readonly=on,file=' + firmware,
		'-drive', 'if=pflash,format=raw,file=' + state + '/vars.fd',
		'-drive', 'if=none,id=vinix-boot,format=raw,readonly=on,file=' + state + '/boot.img',
		'-device', 'virtio-blk-pci,drive=vinix-boot',
		'-drive', 'if=none,format=raw,file=' + state + '/root.ext2,id=vinix-persist',
		'-device', 'virtio-blk-device,drive=vinix-persist', '-device', 'virtio-keyboard-device',
		'-device', 'virtio-tablet-device', '-device', 'ramfb', '-display', 'none', '-serial', 'mon:stdio',
		'-qmp', 'unix:' + socket + ',server=on,wait=off', '-no-reboot', '-nic', 'none']
}

fn verify(p Prepared, state string) ! {
	require(p.arch == 'aarch64' && p.storage == 'archive-overlay', 'ARM prepared architecture/storage differs')!
	for path, expected in p.inputs { require(digest(path)! == expected, 'input changed: ' + path)! }
	require(digest(p.base)! == p.base_manifest
		&& os.read_file(state + '/base-before.tsv')! == archive_record(p.base)!, 'base archive changed')!
	require(digest(state + '/staged-before.tsv')! == p.staged_manifest
		&& os.read_file(state + '/staged-before.tsv')! == inventory(state + '/rootfs', '')! + '\n', 'staged overlay changed')!
	require(digest(state + '/sysroot-before.tsv')! == p.sysroot_manifest
		&& os.read_file(state + '/sysroot-before.tsv')! == inventory(p.sysroot, '')! + '\n', 'ARM sysroot changed')!
}

fn prepare(args []string, stage bool) ! {
	require(args.len >= 5, 'expected REPO BASE_ARCHIVE KERNEL FRESH_STATE NAME=DESKTOP [perf options]')!
	root, base, kernel, state := args[0], args[1], args[2], args[3]
	expected, arguments := options(args[4..])!
	base_before := admitted(root, base, state, expected)!
	plan := perfrunner.parse(arguments, root, root + '/tests/desktop-perf', '')!
	require(plan.builds.len == 1 && plan.builds[0].name == 'new' && plan.assets.len == 0
		&& plan.desktop_args == '' && plan.mem == 3072 && plan.rounds == 1 && plan.settle == 3
		&& plan.seconds == 5 && plan.timeout == 2400
		&& plan.scenarios == ['ops', 'churn', 'cache', 'idle', 'apps', 'drag'], 'fixed ARM six-scenario plan required')!
	compiler := selected('V', false)!; qemu := selected('VINIX_QEMU_AARCH64', false)!
	firmware := selected('VINIX_OVMF_CODE_AARCH64', false)!; variables := selected('VINIX_OVMF_VARS_AARCH64', false)!
	cc := selected('CC_AARCH64', false)!; linker := selected_linker()!
	sysroot := selected('VINIX_AARCH64_SYSROOT', true)!; gcc := selected('VINIX_PERF_ARM_GCC', true)!
	readelf := selected('VINIX_PERF_READELF', false)!; mkfs := selected('VINIX_PERF_MKFS', false)!
	mformat := selected('VINIX_PERF_ARM_MFORMAT', false)!; mmd := selected('VINIX_PERF_ARM_MMD', false)!
	mcopy := selected('VINIX_PERF_ARM_MCOPY', false)!; loader := selected('VINIX_LIMINE_BOOTAA64', false)!
	require(inside(gcc, sysroot), 'selected GCC must be inside ARM sysroot')!
	require(!inside(state, sysroot) && !inside(sysroot, state), 'state overlaps ARM sysroot')!
	mut pins := map[string]string{}; source_inputs(root, mut pins)!
	for path in [base, kernel, plan.builds[0].binary, compiler, qemu, firmware, variables, cc, linker,
		readelf, mkfs, mformat, mmd, mcopy, loader, os.executable(), '/usr/bin/tar', '/bin/cp'] { pin(mut pins, path)! }
	elf(kernel)!; elf(plan.builds[0].binary)!
	if !stage { println('PERF ARM INPUT CHECK PASS; archive pinned; no staging or VM execution'); return }
	os.mkdir(state)!
	os.write_file(state + '/prepare-arguments.json', json2.encode(os.args) + '\n')!
	os.write_file(state + '/base-before.tsv', base_before)!
	os.write_file(state + '/sysroot-before.tsv', inventory(sysroot, '')! + '\n')!
	// Check churn names without claiming a DT_NEEDED closure or resolving
	// guest absolute links through host file APIs.
	tool(['/usr/bin/tar', '-tf', base, './bin/true', './bin/sleep', './bin/busybox', './bin/zsh',
		'./usr/bin/curl', './lib/ld-musl-aarch64.so.1'], state, 'base-runtime')!
	for directory in ['sbin', 'bin', 'dev', 'proc', 'sys', 'tmp', 'run', 'root', 'opt/vinix-perf'] { os.mkdir_all(state + '/rootfs/' + directory)! }
	os.chmod(state + '/rootfs/tmp', 0o1777)!
	for name in ['sh', 'true', 'sleep', 'mkdir', 'chmod', 'od', 'tr', 'rm', 'touch', 'kill', 'sync',
		'cat', 'sed', 'dd', 'awk', 'grep', 'tail', 'install', 'ln'] { os.symlink('/bin/busybox', state + '/rootfs/bin/' + name)! }
	os.mkdir(state + '/guest')!
	c_file := state + '/guest/init.c'; init := state + '/rootfs/sbin/init'
	tool([compiler, '-nocache', '-os', 'linux', '-arch', 'arm64', '-gc', 'none', '-d', 'no_backtrace',
		'-d', 'no_segfault_handler', '-o', c_file, root + '/tests/desktop-perf/arm-init'], state, 'init-v')!
	tool(compile_command(cc, linker, sysroot, gcc, c_file, init, true), state, 'init-link')!
	perf := state + '/rootfs/opt/vinix-perf'
	tool(compile_command(cc, linker, sysroot, gcc, root + '/tests/desktop-perf/measure.c', perf + '/measure', false), state, 'measure-link')!
	for path in [init, perf + '/measure'] {
		elf(path)!
		tool([readelf, '-h', '-l', '-d', path], state, if path == init { 'init-elf' } else { 'measure-elf' })!
	}
	os.cp(plan.builds[0].binary, perf + '/vinix-desktop-new')!
	os.cp(root + '/tests/desktop-perf/perf-init.sh', perf + '/perf-init.sh')!
	os.write_file(perf + '/config', "VARIANTS='new'\nSCENARIOS='ops churn cache idle apps drag'\nROUNDS=1\nSETTLE=3\nMEASURE=5\nDESKTOP_ARGS=''\n")!
	finish_prepare(root, base, kernel, state, arguments, plan.mem, expected, sysroot, qemu, firmware,
		variables, loader, mformat, mmd, mcopy, mkfs, c_file, init, perf, mut pins)!
}

fn finish_prepare(root string, base string, kernel string, state string, arguments []string, memory int,
	expected string, sysroot string, qemu string, firmware string, variables string, loader string,
	mformat string, mmd string, mcopy string, mkfs string, c_file string, init string, perf string,
	mut pins map[string]string) ! {
	archive := state + '/overlay.tar'
	os.setenv('COPYFILE_DISABLE', '1', true)
	tool(['/usr/bin/tar', '--format=ustar', '-cf', archive, '-C', state + '/rootfs', '.'], state, 'overlay')!
	os.write_file(state + '/limine.conf', configuration())!
	image := state + '/boot.img'; os.write_file(image, '')!
	os.truncate(image, fat_size([os.file_size(loader), os.file_size(state + '/limine.conf'), os.file_size(kernel), os.file_size(base), os.file_size(archive)])!)!
	tool([mformat, '-F', '-i', image, '::'], state, 'fat-format')!
	tool([mmd, '-i', image, '::/EFI', '::/EFI/BOOT', '::/boot'], state, 'fat-directories')!
	for index, pair in [[loader, '::/EFI/BOOT/BOOTAA64.EFI'], [state + '/limine.conf', '::/boot/limine.conf'],
		[kernel, '::/boot/vinix'], [base, '::/boot/base.tar'], [archive, '::/boot/overlay.tar']] {
		tool([mcopy, '-i', image, pair[0], pair[1]], state, 'fat-copy-' + index.str())!
	}
	os.cp(variables, state + '/vars.fd')!
	os.write_file(state + '/root.ext2', '')!; os.truncate(state + '/root.ext2', u64(256) << 20)!
	tool([mkfs, '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128', '-O',
		'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum', state + '/root.ext2'], state, 'ext2')!
	for path in [c_file, init, perf + '/measure', archive, image, state + '/vars.fd', state + '/root.ext2', state + '/limine.conf',
		state + '/base-before.tsv', state + '/sysroot-before.tsv'] { pin(mut pins, path)! }
	sources := pins.keys().filter(it.starts_with(root + '/') && (it.ends_with('.v') || it.ends_with('.c') || it.ends_with('.h') || it.ends_with('.sh')))
	for path in sources {
		destination := state + '/source/' + path[root.len + 1..]
		os.mkdir_all(os.dir(destination))!; os.cp(path, destination)!; pins[destination] = digest(destination)!
	}
	os.write_file(state + '/staged-before.tsv', inventory(state + '/rootfs', '')! + '\n')!
	socket := '/tmp/vinix-perf-arm-' + sha256.sum(state.bytes()).hex()[..16] + '.qmp'
	p := Prepared{root: root, base: base, arguments: arguments, command: qemu_command(qemu, firmware, state, socket, memory),
		socket: socket, inputs: pins, base_manifest: expected, staged_manifest: digest(state + '/staged-before.tsv')!,
		firmware: firmware, sysroot: sysroot, sysroot_manifest: digest(state + '/sysroot-before.tsv')!}
	verify(p, state)!
	os.write_file(state + '/prepared.json', json2.encode(p) + '\n')!
	println('PERF ARM PREPARED sha256=' + digest(state + '/prepared.json')!)
}

fn run(state string, expected string) !int {
	require(digest(state + '/prepared.json')! == expected, 'prepared receipt digest mismatch')!
	p := json2.decode[Prepared](os.read_file(state + '/prepared.json')!)!
	verify(p, state)!
	plan := perfrunner.parse(p.arguments, p.root, p.root + '/tests/desktop-perf', '')!
	require(!os.exists(p.socket), 'QMP socket already exists')!
	os.mkdir(state + '/results')!
	defer { os.rm(p.socket) or {} }
	guard := perfconsole.own_commands(); defer { guard.close() }
	status := perfrunner.drive(plan, perfrunner.Launch{p.command, os.environ(), p.socket}, state + '/results', 10, true)!
	mut after := p.inputs.clone()
	for name in ['root.ext2', 'vars.fd'] { require(state + '/' + name in after, 'prepared mutable input missing')!; after.delete(state + '/' + name) }
	verify(Prepared{...p, inputs: after}, state)!
	for name in ['root.ext2', 'vars.fd'] { after[state + '/' + name] = digest(state + '/' + name)! }
	os.write_file(state + '/after-inputs.json', json2.encode(after) + '\n')!
	os.write_file(state + '/results/status', status.str() + '\n')!
	return status
}

fn selfcheck(state string) ! {
	require(!os.exists(state) && !os.is_link(state), 'selfcheck state must be fresh')!
	os.mkdir_all(state + '/rootfs/bin')!; os.mkdir(state + '/sysroot')!
	base := state + '/base.tar'; os.write_file(base, 'archive fixture')!
	os.write_file(state + '/base-before.tsv', archive_record(base)!)!
	os.write_file(state + '/sysroot-before.tsv', '\n')!
	os.write_file(state + '/staged-before.tsv', inventory(state + '/rootfs', '')! + '\n')!
	os.write_file(state + '/root.ext2', 'disk')!; os.write_file(state + '/vars.fd', 'variables')!
	p := Prepared{base: base, base_manifest: digest(base)!, staged_manifest: digest(state + '/staged-before.tsv')!,
		sysroot: state + '/sysroot', sysroot_manifest: digest(state + '/sysroot-before.tsv')!,
		inputs: {base: digest(base)!, state + '/vars.fd': digest(state + '/vars.fd')!, state + '/root.ext2': digest(state + '/root.ext2')!}}
	verify(p, state)!
	mut checks := ['valid archive/overlay receipt']
	for name in ['base.tar', 'base-before.tsv', 'staged-before.tsv', 'sysroot-before.tsv', 'vars.fd', 'root.ext2'] {
		path := state + '/' + name; original := os.read_file(path)!; os.write_file(path, original + 'changed')!
		verify(p, state) or { checks << 'refused changed ' + name; os.write_file(path, original)!; continue }
		return error('changed retained input accepted: ' + name)
	}
	for directory in ['rootfs', 'sysroot'] {
		path := state + '/' + directory + '/extra'; os.write_file(path, 'new')!
		verify(p, state) or { checks << 'refused extra ' + directory + ' entry'; os.rm(path)!; continue }
		return error('extra input accepted')
	}
	for value in ['', 'invalid', '0'.repeat(63)] {
		options(['--base-manifest-sha256=' + value]) or { checks << 'refused invalid archive pin'; continue }
		return error('invalid archive pin accepted')
	}
	options(['--base-manifest-sha256=' + '0'.repeat(64), '--base-manifest-sha256=' + '0'.repeat(64)]) or { checks << 'refused duplicate archive pin' }
	require(checks.len == 13, 'archive control count differs')!
	for machine in [183, 62] {
		header := [u8(127), `E`, `L`, `F`, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, u8(machine), 0]
		path := state + '/elf'; os.write_file_array(path, header)!
		if machine == 183 { elf(path)!; checks << 'accepted ARM ELF' } else {
			elf(path) or { checks << 'refused x86 ELF'; continue }; return error('wrong architecture accepted')
		}
	}
	argv := qemu_command('/qemu', '/firmware', '/state', '/socket', 3072)
	require(argv.contains('mon:stdio') && argv.contains('virtio-blk-pci,drive=vinix-boot')
		&& argv.contains('virtio-blk-device,drive=vinix-persist')
		&& argv.contains('if=none,id=vinix-boot,format=raw,readonly=on,file=/state/boot.img'), 'ARM boot ownership/disk topology differs')!
	checks << 'fixed foreground monitor and separate PCI/MMIO disks'
	config := configuration()
	base_module := config.index('base.tar') or { return error('base module missing') }
	overlay_module := config.index('overlay.tar') or { return error('overlay module missing') }
	require(base_module < overlay_module && config.contains('2048x1536x32'), 'ordered modules/geometry differs')!
	checks << 'ordered base/overlay and fixed pointer geometry'
	require(fat_size([u64(635720192), 40621216, 24 << 20])! == (u64(1) << 30), 'ARM FAT projection differs')!
	checks << 'bounded 1 GiB FAT sizing for selected archive'
	require(checks.len == 18, 'ARM control count differs')!
	verify(p, state)!
	os.write_file(state + '/result.json', json2.encode(checks) + '\n')!
	println('PERF ARM HOST PASS eighteen checks; no guest executed')
}

fn main() {
	if os.args.len >= 7 && os.args[1] in ['check', 'prepare'] {
		prepare(os.args[2..], os.args[1] == 'prepare') or { eprintln(err); exit(1) }; return
	}
	if os.args.len == 4 && os.args[1] == 'run' { status := run(os.args[2], os.args[3]) or { eprintln(err); exit(1) }; exit(status) }
	if os.args.len == 3 && os.args[1] == 'selfcheck' { selfcheck(os.args[2]) or { eprintln(err); exit(1) }; return }
	eprintln('usage: run-arm check|prepare REPO BASE_ARCHIVE KERNEL FRESH_STATE new=DESKTOP [fixed perf options]\n       run-arm run STATE PREPARED_JSON_SHA256\n       run-arm selfcheck FRESH_STATE')
	exit(2)
}
