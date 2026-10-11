// SPDX-License-Identifier: GPL-2.0-or-later
module systemhost

import diskhost
import ext2host
import guesthost
import hosttest
import json2
import os

pub fn pattern_file(path string, size int, seed int) ! {
	mut file := os.open_file(path, 'wx', 0o600)!
	defer { file.close() }
	mut bytes := []u8{len: 4096}
	for page in 0 .. size / 4096 {
		for offset in 0 .. 4096 { bytes[offset] = u8(seed + 17 * page + 13 * offset) }
		if file.write(bytes)! != bytes.len { return error('Short pattern fixture write') }
	}
	os.chmod(path, 0o444)!
}

fn storage_compiler(runner string) []string {
	sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { runner + '/build-aarch64-userland/sysroot' }
	mut argv := [os.getenv_opt('CC') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sdk]
	gcc_root := runner + '/build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl'
	if os.is_dir(gcc_root) {
		mut versions := os.ls(gcc_root) or { []string{} }
		versions.sort()
		if versions.len > 0 { argv << '--gcc-install-dir=' + gcc_root + '/' + versions.last() }
	}
	return argv
}

fn storage_init(family string, state string, runner string, options guesthost.Options) !string {
	init := state + '/init'
	if options.has('--prebuilt-init') {
		hosttest.module_copy_file_preserving_stat(resolve(options.value('--prebuilt-init', ''))!, init)!
		return init
	}
	cc := storage_compiler(runner)
	sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { runner + '/build-aarch64-userland/sysroot' }
	compile := [...cc, '-O2', '-fno-stack-protector', '-Wall', '-Wextra', '-Werror']
	if family == 'fsync-scope' {
		object := state + '/fixture.o'
		guesthost.compile_module(root() + '/tests/fsync-scope/syncfixture', object, 'aarch64', [
			...compile,
			'-D_GNU_SOURCE',
			'-fno-strict-aliasing',
		])!
		run([...cc, '-L' + sdk + '/lib', '-fuse-ld=lld', '-static', object, '-o', init])!
	} else {
		source := root() + if family == 'virtio-ro' {
			'/tests/virtio-ro/test.c'
		} else {
			'/tests/dota2/export-read.c'
		}
		run([...compile, '-L' + sdk + '/lib', '-fuse-ld=lld', '-static', source, '-o', init])!
	}
	return init
}

pub fn export_samples(source string, target string) ! {
	mut packages := []string{}
	for name in os.ls(source + '/game/dota')! {
		path := source + '/game/dota/' + name
		if name.ends_with('.vpk') && os.is_file(path) { packages << path }
	}
	packages.sort_with_compare(fn (a &string, b &string) int {
		sa := os.file_size(*a)
		sb := os.file_size(*b)
		return if sa > sb {
			-1
		} else if sa < sb {
			1
		} else if *a < *b {
			-1
		} else if *a > *b {
			1
		} else {
			0
		}
	})
	if packages.len == 0 { return argument('The source contains no game/dota/*.vpk files') }
	mut selected := [packages[0]]
	directory := source + '/game/dota/pak01_dir.vpk'
	if os.is_file(directory) && directory != selected[0] { selected << directory }
	mut samples := [][]u8{}
	for path in selected {
		size := os.file_size(path)
		mut offsets := [i64(0), if size > 8192 { size - 8192 } else { i64(0) }]
		for boundary in [i64(12 * 4096), (12 + 1024) * 4096, 128 * 1024 * 1024] {
			if size > boundary + 4096 { offsets << boundary - 127 }
		}
		offsets.sort()
		mut previous := i64(-1)
		mut file := os.open(path)!
		defer { file.close() }
		for offset in offsets {
			if offset == previous { continue }
			previous = offset
			length := int(if size - offset < 8192 { size - offset } else { 8192 })
			payload := file.read_bytes_at(length, u64(offset))
			if payload.len != length { return error('Source changed while sampling: ' + path) }
			name := path[source.len + 1..]
			mut record := []u8{len: 2}
			ext2host.put_le(mut record, 0, u64(name.len), 2)
			record << name.bytes()
			at := record.len
			record << []u8{len: 12}
			ext2host.put_le(mut record, at, u64(offset), 8)
			ext2host.put_le(mut record, at + 8, u64(payload.len), 4)
			record << payload
			samples << record
		}
	}
	mut file := os.open_file(target, 'wx', 0o600)!
	defer { file.close() }
	mut header := 'VNXDOTA1'.bytes()
	header << []u8{len: 4}
	ext2host.put_le(mut header, 8, u64(samples.len), 4)
	if file.write(header)! != header.len { return error('Short sample header write') }
	for sample in samples {
		if file.write(sample)! != sample.len { return error('Short sample payload write') }
	}
}

fn storage_guest(family string, args []string) !int {
	options := parse(args, [hosttest.Option{ name: '--work', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--runner-root', value: true },
		hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--prebuilt-init', value: true },
		hosttest.Option{ name: '--prepare-only' }, hosttest.Option{ name: '--build-only' },
		hosttest.Option{ name: '--source', value: true },
		hosttest.Option{ name: '--overlay', value: true },
		hosttest.Option{ name: '--export-state', value: true }], ['--overlay'], 'Usage: storage runner --work DIR [--kernel-dir DIR] [--timeout 240] [--prepare-only]')!
	if family == 'virtio-ro' { required(options, ['--work'])! }
	if family == 'export-read' { required(options, ['--source'])! }
	seconds := positive(options, '--timeout', 240)!
	state_option := if family == 'export-read' { '--state-dir' } else { '--work' }
	state := if options.has(state_option) {
		resolve(options.value(state_option, ''))!
	} else if family == 'fsync-scope' {
		root() + '/build/fsync-scope'
	} else {
		hosttest.work_dir('', 'vinix-dota2-export-')!
	}
	if family == 'virtio-ro' && (os.exists(state) || os.is_link(state)) {
		return error('Use a fresh work directory')
	}
	diskhost.mkdir(state)!
	runner := resolve(options.value('--runner-root', root()))!
	kernel := snapshot(state, options.value('--kernel-dir', root() + '/kernel'), 'aarch64')!
	init := storage_init(family, state, runner, options)!
	mut hashes := map[string]string{}
	source := if family == 'export-read' {
		resolve(options.value('--source', ''))!
	} else {
		state + '/source'
	}
	if family != 'export-read' {
		os.mkdir(source)!
		if family == 'fsync-scope' {
			os.write_file(source + '/disk-probe.bin', []u8{len: 8192, init: 0xa5}.bytestr())!
			os.chmod(source + '/disk-probe.bin', 0o444)!
		} else {
			pattern_file(source + '/a-churn.bin', 16 * 1024 * 1024, 7)!
			pattern_file(source + '/mapped.bin', 65536, 91)!
			for index in 0 .. 64 {
				path := source + '/pad-' + (if index < 10 { '0' } else { '' }) + index.str() + '.bin'
				os.write_file(path, '')!
				os.chmod(path, 0o444)!
			}
			pattern_file(source + '/z-probe.bin', 65536, 203)!
		}
		for name in os.ls(source)! { hashes[name] = hosttest.sha(source + '/' + name)! }
	}
	export_state := if options.has('--export-state') {
		resolve(options.value('--export-state', ''))!
	} else {
		state + '/export'
	}
	if !options.has('--export-state') {
		ext2host.build(source, export_state, options.values['--overlay'] or { []string{} })!
	}
	mut export := ext2host.open_export(export_state)!
	capacity := export.size
	export.close()
	if family == 'virtio-ro' && capacity != 128 * 1024 * 1024 {
		return error('Unexpected fixture disk/cache capacity')
	}
	if family == 'export-read' {
		export_samples(source, state + '/samples.bin')!
		diskhost.mkdir(state + '/rootfs')!
		os.cp(state + '/samples.bin', state + '/rootfs/samples.bin')!
	}
	archive := archive_root(init, state, if family == 'virtio-ro' {
		['root', 'alias', 'other', 'sbin', 'tmp', 'dev', 'proc', 'sys', 'run']
	} else {
		['root', 'sbin', 'tmp', 'dev', 'proc', 'sys', 'run']
	})!
	mut unused := os.open_file(state + '/unused.raw', 'wx', 0o600)!
	if C.ftruncate(unused.fd, u64(16 * 1024 * 1024)) != 0 {
		unused.close()
		return os.error_posix()
	}
	unused.close()
	mut report := map[string]json2.Any{}
	report['kernel_sha256'] = json2.Any(hosttest.sha(kernel + '/bin/vinix')!)
	report['native_init_sha256'] = json2.Any(hosttest.sha(init)!)
	report['advertised_read_only'] = json2.Any(family != 'fsync-scope')
	if family == 'virtio-ro' {
		mut source_hashes := map[string]json2.Any{}
		for name, value in hashes { source_hashes[name] = json2.Any(value) }
		report['source_hashes'] = json2.Any(source_hashes)
		report['manifest_sha256'] = json2.Any(hosttest.sha(export_state + '/manifest.json')!)
		report['disk_size'] = json2.Any(capacity)
		hosttest.write_json(state + '/prepared.json', json2.Any(report))!
	}
	if options.has('--prepare-only') || options.has('--build-only') {
		println(json2.encode(report, prettify: true))
		return 0
	}
	mut server := ext2host.serve(export_state, 0, '', if family == 'fsync-scope' {
		u16(1)
	} else {
		u16(3)
	}, 120000)!
	defer { server.close() }
	configured := guesthost.launch_from(init, archive, state, kernel, 'aarch64', false, runner)!
	arm_config(state, runner, 'vinix.qemu_platform=1 vinix.qemu_persist=1 ' + os.getenv('VINIX_CMDLINE'))!
	mut argv := configured.command.clone()
	// The original ARM launcher boots through PCI. QEMU assigns MMIO slots
	// downwards and Vinix probes upwards, so NBD must be declared first to
	// preserve the original unused /dev/vda and exported /dev/vdb names.
	boot_device := argv.index('virtio-blk-device,drive=guest-iso')
	if boot_device < 0 { return error('Missing private boot device') }
	argv[boot_device] = 'virtio-blk-pci,drive=guest-iso'
	id := if family == 'fsync-scope' {
		'sync-fail'
	} else if family == 'virtio-ro' {
		'readonly'
	} else {
		'dota-data'
	}
	argv.insert(1, ['-drive', 'if=none,id=' + id + ',file=nbd://127.0.0.1:' + server.port.str() + '/,format=raw' + if family == 'fsync-scope' {
		''
	} else {
		',readonly=on'
	}, '-device', 'virtio-blk-device,drive=' + id])
	argv.insert(argv.index('virtio-blk-pci,drive=guest-iso') + 1, ['-drive',
		'if=none,id=unused,format=raw,file=' + state + '/unused.raw', '-device',
		'virtio-blk-device,drive=unused'])
	receipt(state, guesthost.Launch{argv, configured.env}, kernel, init, archive, seconds)!
	marker := if family == 'fsync-scope' {
		'FSYNC-SCOPE'
	} else if family == 'virtio-ro' {
		'VIRTIO-RO'
	} else {
		'DOTA2 EXPORT:'
	}
	failure := marker + if family == 'export-read' { ' FAIL' } else { ' FAIL:' }
	result := guesthost.boot(argv, configured.env, state, [marker + ' PASS'], [
		failure,
		'KERNEL PANIC',
		'FATAL EXCEPTION',
	], seconds, true)!
	mut unchanged := true
	for name, expected in hashes {
		if hosttest.sha(source + '/' + name)! != expected { unchanged = false }
	}
	report['passed'] = json2.Any(result == 0 && unchanged)
	report[if family == 'fsync-scope' {
		'readonly_host_file_unchanged'
	} else {
		'readonly_host_files_unchanged'
	}] = json2.Any(unchanged)
	if family == 'fsync-scope' { report['backend_rejects_writes'] = json2.Any(true) }
	report['log'] = json2.Any(state + '/serial.log')
	hosttest.write_json(state + '/results.json', json2.Any(report))!
	println(json2.encode(report, prettify: true))
	return if result == 0 && unchanged { 0 } else { 1 }
}
