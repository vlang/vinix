// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import androidhost as ah
import androidrun
import cachecli
import gamehost
import hosttest
import os
import sourcecommand
import strconv
import time
import transcriptcore

pub struct VulkanGuestOptions {
pub:
	staging string
	kernel  string
	work    string
	timeout int = 600
	venus   bool
}

pub fn install_translator(staging string, root string) ! {
	source := staging + '/usr/bin/qemu-x86_64'
	mut input := os.open(source)!
	defer { input.close() }
	mut bytes := []u8{len: 20}
	mut total := 0
	for total < bytes.len {
		count := input.read(mut bytes[total..]) or { if err is os.Eof { 0 } else { return err } }
		if count == 0 { break }
		total += count
	}
	if total < 20 || bytes[..7] != [u8(127), `E`, `L`, `F`, 2, 1, 1] || bytes[16] !in [
		u8(2),
		3,
	] || bytes[17] != 0 || bytes[18] != 183 || bytes[19] != 0 || !os.is_executable(source) {
		return error('Expected an executable native AArch64 translator: ' + source)
	}
	for directory in ['usr/lib', 'lib'] {
		if os.is_dir(staging + '/' + directory) {
			doom_copy_layer(staging + '/' + directory, root + '/' + directory)!
		}
	}
	gamehost.mkdir(root + '/usr/bin')!
	destination := root + '/usr/bin/qemu-x86_64'
	if os.is_link(destination) { os.rm(destination)! }
	hosttest.module_copy_file_preserving_stat(source, destination)!
}

fn native_library(root string, name string) string {
	for directory in ['usr/lib', 'lib'] {
		candidate := root + '/' + directory + '/' + name
		if os.exists(candidate) { return candidate }
	}
	return ''
}

pub fn complete_native_closure(tools gamehost.Tools, root string) ! {
	mut queue := [root + '/usr/bin/Xvfb', root + '/usr/bin/xkbcomp', root + '/usr/bin/qemu-x86_64']
	mut seen := map[string]bool{}
	for queue.len > 0 {
		file := queue.pop()
		if file in seen || !os.exists(file) { continue }
		seen[file] = true
		dynamic := tools.output(['aarch64-linux-musl-readelf', '-d', file])!
		for line in dynamic.split_into_lines() {
			if !line.contains('(NEEDED)') || !line.contains('[') || !line.contains(']') { continue }
			name := line.all_after('[').all_before(']')
			mut found := native_library(root, name)
			if found == '' {
				original := native_library(tools.root + '/build-aarch64-userland/staging', name)
				if original == '' { return error('native probe dependency is missing: ' + name) }
				found = root + '/usr/lib/' + name
				if os.is_link(found) { os.rm(found)! }
				hosttest.module_copy_file_preserving_stat(original, found)!
			}
			queue << found
		}
	}
}

pub fn retain_software_gl(source string, guest string) ! {
	relative := '/usr/lib/x86_64-linux-gnu/dri'
	destination := guest + relative
	gamehost.mkdir(destination)!
	for name in ['swrast_dri.so', 'kms_swrast_dri.so'] {
		original := source + relative + '/' + name
		if os.is_file(original) {
			target := destination + '/' + name
			if os.is_link(target) { os.rm(target)! }
			hosttest.module_copy_file_preserving_stat(original, target)!
		}
	}
	for name in os.ls(destination)! {
		if name !in ['swrast_dri.so', 'kms_swrast_dri.so'] {
			gamehost.remove(destination + '/' + name)!
		}
	}
}

pub fn prepare_vulkan_guest(tools gamehost.Tools, options VulkanGuestOptions) !string {
	root := options.work + '/root'
	staged_translator := os.exists(options.staging + '/usr/bin/qemu-x86_64')
	if !os.exists(root + '/.prepared') {
		doom_copy_layer(tools.root + '/build-aarch64-x11/staging', root)!
		if !staged_translator {
			install_translator(tools.root + '/build-aarch64-x86-translation/staging', root)!
		}
		gamehost.mkdir(root + '/bin')!
		userland := tools.root + '/build-aarch64-userland/staging'
		hosttest.module_copy_file_preserving_stat(userland + '/bin/busybox', root + '/bin/busybox')!
		loader := root + '/lib/ld-musl-aarch64.so.1'
		if os.is_link(loader) { os.rm(loader)! }
		hosttest.module_copy_file_preserving_stat(userland + '/lib/ld-musl-aarch64.so.1', loader)!
		for name in ['sh', 'cat', 'mkdir', 'chmod', 'sleep', 'kill', 'base64', 'uname', 'grep'] {
			target := root + '/bin/' + name
			if os.exists(target) || os.is_link(target) { os.rm(target)! }
			os.symlink('busybox', target)!
		}
		for name in ['sbin', 'proc', 'dev', 'sys', 'tmp', 'root', 'run', 'etc'] {
			gamehost.mkdir(root + '/' + name)!
		}
		os.write_file(root + '/etc/passwd', 'root:x:0:0:root:/root:/bin/sh\n')!
		os.write_file(root + '/etc/group', 'root:x:0:root\n')!
		os.write_file(root + '/.prepared', '')!
	}
	if staged_translator { install_translator(options.staging, root)! }
	source := options.staging + '/usr/libexec/vinix-dota2/root'
	generation := os.read_file(source + '/.vinix-dota2-vulkan-generation')!
	marker := root + '/.vulkan-runtime-generation'
	guest := root + '/usr/libexec/vinix-dota2/root'
	if !os.exists(marker) || os.read_file(marker)! != generation || !os.exists(guest) {
		gamehost.remove(guest)!
		gamehost.mkdir(gamehost.parent(guest))!
		if os.user_os() == 'macos' {
			tools.run(['/bin/cp', '-cRp', source, guest])!
		} else {
			gamehost.copy_tree(source, guest, false)!
		}
		os.write_file(marker, generation)!
	}
	hosttest.module_copy_file_preserving_stat(tools.root + '/tests/dota2/vulkan-init.sh', root + '/sbin/init')!
	os.chmod(root + '/sbin/init', 0o755)!
	complete_native_closure(tools, root)!
	retain_software_gl(source, guest)!
	for name in ['usr/lib/i386-linux-gnu', 'lib/i386-linux-gnu', 'usr/share/doc', 'usr/share/man',
		'usr/share/locale'] {
		gamehost.remove(guest + '/' + name)!
	}
	return root
}

pub fn vulkan_capture_colors(bytes []u8) !int {
	if bytes.len < 100 { return error('unexpected Xvfb XWD format') }
	mut header := []u32{}
	for i in 0 .. 25 {
		offset := i * 4
		header << (u32(bytes[offset]) << 24) | (u32(bytes[offset + 1]) << 16) | (u32(bytes[offset + 2]) << 8) | u32(bytes[offset + 3])
	}
	if header[1] != 7 || header[11] != 32 { return error('unexpected Xvfb XWD format') }
	begin := u64(header[0]) + u64(header[19]) * 12
	end := begin + u64(header[12]) * header[5]
	start := int(if begin < bytes.len { begin } else { u64(bytes.len) })
	limit := int(if end < bytes.len { end } else { u64(bytes.len) })
	mut unique := map[string]bool{}
	for offset := start; offset < limit; offset += 4 {
		unique[bytes[offset..int_min(offset + 4, limit)].hex()] = true
	}
	return unique.len
}

pub fn vulkan_report(tools gamehost.Tools, options VulkanGuestOptions, root string, transcript string) !bool {
	normalized := transcript.replace('\r', '')
	mut colors := 0
	if normalized.contains('VINIX-DOTA2-VULKAN-SHOT-END') {
		capture := transcriptcore.decode_capture(normalized)!
		os.write_file_array(options.work + '/vkcube.xwd', capture)!
		colors = vulkan_capture_colors(capture)!
		if ffmpeg := os.find_abs_path_of_executable('ffmpeg') {
			tools.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-i',
				options.work + '/vkcube.xwd', '-frames:v', '1', options.work + '/vkcube.png'])!
		}
	}
	passed := normalized.contains('VINIX-DOTA2-VULKAN-PASS') && colors > 8
	driver := if options.venus { 'venus' } else { 'lavapipe' }
	library := if options.venus { 'libvulkan_virtio.so' } else { 'libvulkan_lvp.so' }
	record := ah.Value({
		'passed':            ah.Value(passed)
		'requested_frames':  ah.Value(3000)
		'cpu':               ah.Value('Haswell')
		'kernel_sha256':     ah.Value(gamehost.digest(options.work + '/kernel/bin/vinix')!)
		'translator_sha256': ah.Value(gamehost.digest(root + '/usr/bin/qemu-x86_64')!)
		'driver':            ah.Value(driver)
		'icd_sha256':        ah.Value(gamehost.digest(root + '/usr/libexec/vinix-dota2/root/usr/lib/x86_64-linux-gnu/' + library)!)
		'enumerated':        ah.Value(normalized.contains('VINIX-DOTA2-VULKAN-ENUMERATE-PASS'))
		'captured_colors':   ah.Value(colors)
		'log':               ah.Value(options.work + '/vinix.log')
	})
	os.write_file(options.work + '/results.json', androidrun.dump_json(record, 2) + '\n')!
	println(androidrun.dump_json(record, 2))
	return passed
}

pub fn run_vulkan_guest(tools gamehost.Tools, options VulkanGuestOptions) !bool {
	gamehost.mkdir(options.work)!
	root := prepare_vulkan_guest(tools, options)!
	os.write_file(root + '/etc/vinix-dota2-vulkan-driver', if options.venus {
		'venus\n'
	} else {
		'lavapipe\n'
	})!
	archive := options.work + '/initramfs.tar.gz'
	gamehost.archive_gzip(root, archive)!
	gamehost.mkdir(options.work + '/kernel/bin')!
	hosttest.module_copy_file_preserving_stat(options.kernel + '/bin/vinix', options.work + '/kernel/bin/vinix')!
	socket := options.work + '/qmp.sock'
	gamehost.remove(socket)!
	mut environment := os.environ()
	for key, value in {
		'VINIX_KERNEL_DIR':           options.work + '/kernel'
		'VINIX_INITRAMFS':            archive
		'VINIX_INITRAMFS_COMPRESSED': '1'
		'VINIX_QEMU_ROOT_DISK':       '0'
		'VINIX_BOOT_DISK':            options.work + '/boot.img'
		'VINIX_EFIVARS':              options.work + '/efivars.fd'
		'VINIX_BOOT_DISK_SIZE_MB':    '2048'
		'VINIX_QEMU_PACKAGE_STORE':   options.work + '/packages.tar'
		'VINIX_QEMU_PACKAGE_PERSIST': '0'
		'VINIX_QEMU_HOST_SOURCE':     '0'
		'VINIX_QEMU_AUDIO':           'off'
		'VINIX_QEMU_SMP':             '4'
		'VINIX_KEEP_TEMP_BOOT_DISK':  '1'
		'VINIX_QEMU_EXTRA':           '-qmp unix:${socket},server=on,wait=off'
	} {
		environment[key] = value
	}
	firmware := tools.root + '/boot-image/edk2-aarch64-code-2048x1536.fd'
	if options.venus && os.exists(firmware) {
		environment['VINIX_QEMU_RESOLUTION'] = '2048x1536x32'
		environment['VINIX_OVMF_CODE'] = firmware
	}
	command := [tools.root + '/scripts/run-aarch64.sh', '--no-build', '--no-persist', '--mem=8192',
		if options.venus { '--venus' } else { '--serial' }]
	mut child := sourcecommand.spawn_pty(command, environment, tools.root)!
	defer { child.close() or {} }
	mut log := os.create(options.work + '/vinix.log')!
	defer { log.close() }
	mut transcript := []u8{}
	mut buffer := []u8{len: 65536}
	deadline := time.sys_mono_now() + u64(if options.timeout > 0 { options.timeout } else { 0 }) * time.second
	for time.sys_mono_now() < deadline {
		cachecli.checkpoint()!
		count := child.read(mut buffer, 100)!
		if count == 0 { break }
		if count < 0 { continue }
		transcript << buffer[..count]
		unsafe { log.write_full_buffer(buffer.data, usize(count))! }
		log.flush()
		content := transcript.bytestr()
		if content.contains('VINIX-DOTA2-VULKAN-PASS') || content.contains('VINIX-DOTA2-VULKAN-FAIL') || content.contains('KERNEL PANIC') {
			break
		}
	}
	child.write([u8(1), `x`]) or {}
	child.signal(C.SIGTERM) or {}
	child.settle(5) or {}
	child.close()!
	return vulkan_report(tools, options, root, transcript.bytestr())
}

pub fn vulkan_guest_cli(root string, argv []string) !int {
	args := cachecli.arguments(argv, ['--staging', '--work', '--kernel-dir', '--timeout'], [], ['--venus'], 0, 0, 'Boot Vinix and exercise translated Vulkan/X11.\nUsage: vulkan-run [--staging DIR --work DIR --kernel-dir DIR --timeout 600 --venus]') or { return error_with_code(err.msg(), 2) }
	options := VulkanGuestOptions{ staging: hosttest.module_resolve(args.value('--staging', root + '/build/dota2-vulkan/staging'))!, work: hosttest.module_resolve(args.value('--work', root + '/build/dota2-vulkan/test'))!, kernel: hosttest.module_resolve(args.value('--kernel-dir', root + '/kernel'))!, timeout: strconv.atoi(args.value('--timeout', '600')) or { return error_with_code(err.msg(), 2) }, venus: '--venus' in args.options }
	return if run_vulkan_guest(gamehost.Tools{ root: root }, options)! { 0 } else { 1 }
}
