// SPDX-License-Identifier: GPL-2.0-or-later
module vkcore

import androidhost as ah

fn command(items []ah.Value) !string {
	result := list()!
	for item in items { append(result, item)! }
	return result
}
fn main_policy(options string) ! {
	for name in ['staging', 'kernel_dir'] {
		resolved := method(option(options, name)!, 'resolve', [], {})!
		call('builtins.setattr', o(options), s(name), o(resolved))!
	}
	work := method(option(options, 'work')!, 'resolve', [], {})!
	mkdir(work)!
	root := call('prepare', o(options), o(work))!
	driver := if truth(option(options, 'venus')!)! { 'venus' } else { 'lavapipe' }
	method(join(root, 'etc/vinix-dota2-vulkan-driver')!, 'write_text', [s(driver + '\n')], {})!
	archive := join(work, 'initramfs.tar.gz')!
	manager := invoke('tarfile.open', [o(archive), s('w:gz')], {'compresslevel': n(1), 'format': o(call('tarfile.USTAR_FORMAT')!)})!
	output := enter(manager)!
	mut retired := false
	method(output, 'add', [o(root)], {'arcname': s('.')}) or {
		failure := err
		retired = true
		if !retire(manager, failure)! { return failure }
	}
	if !retired { retire(manager, none)! }
	pinned := join(work, 'kernel/bin')!
	mkdir(pinned)!
	call('shutil.copy2', o(join(option(options, 'kernel_dir')!, 'bin/vinix')!), o(join(pinned, 'vinix')!))!
	socket := join(work, 'qmp.sock')!
	if truth(method(socket, 'exists', [], {})!)! { method(socket, 'unlink', [], {})! }
	environment := call('builtins.dict', o(call('os.environ')!))!
	for row in [['VINIX_KERNEL_DIR', text(attr(pinned, 'parent')!)!], ['VINIX_INITRAMFS', text(archive)!],
		['VINIX_INITRAMFS_COMPRESSED', '1'], ['VINIX_QEMU_ROOT_DISK', '0'], ['VINIX_BOOT_DISK', text(join(work, 'boot.img')!)!],
		['VINIX_EFIVARS', text(join(work, 'efivars.fd')!)!], ['VINIX_BOOT_DISK_SIZE_MB', '2048'],
		['VINIX_QEMU_PACKAGE_STORE', text(join(work, 'packages.tar')!)!], ['VINIX_QEMU_PACKAGE_PERSIST', '0'],
		['VINIX_QEMU_HOST_SOURCE', '0'], ['VINIX_QEMU_AUDIO', 'off'], ['VINIX_QEMU_SMP', '4'],
		['VINIX_KEEP_TEMP_BOOT_DISK', '1'], ['VINIX_QEMU_EXTRA', '-qmp unix:' + format(socket)! + ',server=on,wait=off']] {
		set(environment, row[0], s(row[1]))!
	}
	firmware := join('repo', 'boot-image/edk2-aarch64-code-2048x1536.fd')!
	if truth(option(options, 'venus')!)! && truth(method(firmware, 'exists', [], {})!)! {
		method(environment, 'update', [o(literal(ah.Value({'VINIX_QEMU_RESOLUTION': ah.Value('2048x1536x32'),
			'VINIX_OVMF_CODE': ah.Value(text(firmware)!)}))!)], {})!
	}
	launch := command([o(text_id(join('repo', 'scripts/run-aarch64.sh')!)!), s('--no-build'), s('--no-persist'), s('--mem=8192')])!
	append(launch, s(if truth(option(options, 'venus')!)! { '--venus' } else { '--serial' }))!
	transcript := raw_boot(launch, environment, work, option(options, 'timeout')!)!
	report(transcript, work, root, pinned, driver)!
}
fn hash(path string) !string { return method(call('hashlib.sha256', o(method(path, 'read_bytes', [], {})!))!, 'hexdigest', [], {})! }
fn report(transcript string, work string, root string, pinned string, driver string) ! {
	normalized := method(call('builtins.bytes', o(transcript))!, 'replace', [b('0d'), b('')], {})!
	mut passed := truth(call('operator.contains', o(normalized), b('VINIX-DOTA2-VULKAN-PASS'.bytes().hex()))!)!
	mut colors := literal(ah.Value(0))!
	if truth(call('operator.contains', o(normalized), b('VINIX-DOTA2-VULKAN-SHOT-END'.bytes().hex()))!)! {
		xwd := join(work, 'vkcube.xwd')!
		contents := call('decode_capture', o(normalized))!
		method(xwd, 'write_bytes', [o(contents)], {})!
		header := call('struct.unpack', s('>25I'), o(get(contents, o(call('builtins.slice', n(0), n(100))!))!))!
		if !eq(get(header, n(1))!, n(7))! || !eq(get(header, n(11))!, n(32))! { system_exit(s('unexpected Xvfb XWD format'))! }
		begin := call('operator.add', o(get(header, n(0))!), o(call('operator.mul', o(get(header, n(19))!), n(12))!))!
		end := call('operator.add', o(begin), o(call('operator.mul', o(get(header, n(12))!), o(get(header, n(5))!))!))!
		pixels := get(contents, o(call('builtins.slice', o(begin), o(end))!))!
		unique := call('builtins.set')!
		indexes := iter(call('builtins.range', n(0), o(call('builtins.len', o(pixels))!), n(4))!)!
		for {
			row := next(indexes)!
			if row.done { break }
			slice := call('builtins.slice', o(row.id), o(call('operator.add', o(row.id), n(4))!))!
			method(unique, 'add', [o(get(pixels, o(slice))!)], {})!
		}
		colors = call('builtins.len', o(unique))!
		if truth(call('shutil.which', s('ffmpeg'))!)! {
			args := command([s('ffmpeg'), s('-hide_banner'), s('-loglevel'), s('error'), s('-y'), s('-i'), o(text_id(xwd)!),
				s('-frames:v'), s('1'), o(text_id(join(work, 'vkcube.png')!)!)])!
			invoke('subprocess.run', [o(args)], {'check': v(ah.Value(true))})!
		}
	}
	passed = passed && compare('gt', colors, n(8))!
	result := dict()!
	set(result, 'passed', v(ah.Value(passed)))!
	set(result, 'requested_frames', n(3000))!
	set(result, 'cpu', s('Haswell'))!
	set(result, 'kernel_sha256', o(hash(join(pinned, 'vinix')!)!))!
	set(result, 'translator_sha256', o(hash(join(root, 'usr/bin/qemu-x86_64')!)!))!
	set(result, 'driver', s(driver))!
	icd := if driver == 'venus' { 'libvulkan_virtio.so' } else { 'libvulkan_lvp.so' }
	set(result, 'icd_sha256', o(hash(join(join(root, 'usr/libexec/vinix-dota2/root/usr/lib/x86_64-linux-gnu')!, icd)!)!))!
	set(result, 'enumerated', o(call('operator.contains', o(normalized), b('VINIX-DOTA2-VULKAN-ENUMERATE-PASS'.bytes().hex()))!))!
	set(result, 'captured_colors', o(colors))!
	set(result, 'log', o(text_id(join(work, 'vinix.log')!)!))!
	write_json(join(work, 'results.json')!, result)!
	print_json(result, true)!
	if !passed { system_exit(n(1))! }
}
