// SPDX-License-Identifier: GPL-2.0-or-later
module verifiedhost

import bootpolicy
import bundlehost as bh
import os
import strconv
import tarcore
import verityimage

#include <unistd.h>

fn C.ftruncate(i32, u64) i32
fn C.fsync(i32) i32

const root_blocks = u64(8192)

fn device_block(debugfs string, image string, path string) !u64 {
	output := bh.capture([debugfs, '-R', 'blocks ' + path, image])!
	words := output.split_any(' \t\r\n').filter(it != '')
	if words.len == 0 { return error('no filesystem data blocks for ' + path) }
	mut blocks := []u64{}
	for word in words { blocks << strconv.parse_uint(word, 10, 64)! }
	return blocks[0]
}

fn truncate(path string, size u64) ! {
	mut stream := os.open_file(path, 'r+b')!
	defer { stream.close() }
	if C.ftruncate(stream.fd, size) != 0 { return os.error_posix() }
}

fn root_runtime(args []string) ! {
	original, options := runtime_options(args, true)!
	defer { os.rm(original.work + '/test.key') or {} }
	runtime := secure_runtime(original, options, true)!
	work := runtime.work
	staging := work + '/root'
	for directory in ['dev', 'proc', 'sys', 'tmp', 'run', 'var', 'root', 'sbin'] {
		bh.mkdirs(staging + '/' + directory)!
	}
	bh.run([options.value('--cc', runtime.arch + '-linux-musl-gcc'), '-static', '-O2', '-Wall',
		'-Wextra', '-Werror', bh.root() + '/tests/verified-root/guest.c', '-o', staging + '/sbin/init'])!
	os.write_file_array(staging + '/payload', []u8{len: 4096, init: `v`})!
	os.write_file(staging + '/data-blocks', root_blocks.str() + '\n')!
	device := if runtime.arch == 'aarch64' { '/dev/vda' } else { '/dev/ata0' }
	os.write_file(staging + '/raw-device', device)!
	source := work + '/root.ext2'
	mut file := os.create(source)!
	if C.ftruncate(file.fd, root_blocks * 4096) != 0 {
		file.close()
		return os.error_posix()
	}
	file.close()
	bh.run([options.value('--mke2fs', 'mke2fs'), '-q', '-F', '-t', 'ext2', '-b', '4096', '-I',
		'128', '-O',
		'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum',
		'-d', staging, source])!
	debugfs := options.value('--debugfs', 'debugfs')
	probe := device_block(debugfs, source, '/payload')!
	init_block := device_block(debugfs, source, '/sbin/init')!
	os.write_file(work + '/probe-block', probe.str() + '\n')!
	bh.quiet([debugfs, '-w', '-R', 'write ' + work + '/probe-block /probe-block', source])!
	bh.quiet([bh.root() + '/build-support/ext2-set-root-owner', source])!
	image := work + '/root.verity'
	metadata := verityimage.build(source, image, false)!
	archive := work + '/bootstrap.tar'
	mut tar := tarcore.create_stream(archive)!
	defer { tar.close() }
	content := 'This authenticated module must not be extracted into a verified root.\n'.bytes()
	tar.add(tarcore.Member{ name: 'bootstrap-only', size: content.len }, content)!
	tar.finish()!
	tar.close_checked()!
	bundle := work + '/boot-bundle'
	bh.build(bh.Build{
		arch:          runtime.arch
		loader:        runtime.loader
		kernel:        runtime.kernel
		initramfs:     [archive]
		output:        bundle
		cmdline:       if runtime.arch == 'aarch64' {
			'vinix.qemu_platform=1'
		} else {
			''
		}
		developer:     !runtime.secure
		key:           runtime.key
		certificate:   runtime.certificate
		backend:       runtime.backend
		verity_root:   image
		verity_device: device
		verity_count:  root_blocks
		verity_hash:   metadata.root_hash
	})!
	config := os.read_file(bundle + '/boot/limine.conf')!
	attached := work + '/attached.img'
	os.cp(image, attached)!
	if runtime.secure {
		path := bundle + '/EFI/BOOT/' + bootpolicy.architecture(runtime.arch)!.loader
		signed := os.read_bytes(path)!
		loader_checks(runtime, bundle, attached, path, signed) or {
			failure := err
			os.write_file_array(path, signed)!
			return failure
		}
		os.write_file_array(path, signed)!
	}
	runtime_guest(runtime, bundle, 'valid', 'VERIFIED ROOT: PASS', attached, probe)!
	if !options.has('--only-valid') {
		negatives(runtime, debugfs, bundle, attached, image, source, metadata.root_hash, config, device, init_block)!
	}
	println('PASS: real kernel verified-root enforcement' + if runtime.secure {
		' with enabled UEFI Secure Boot.'
	} else {
		'; firmware Secure Boot was disabled, so firmware trust enrollment is a separate test.'
	})
}

fn loader_checks(runtime Runtime, bundle string, attached string, path string, signed []u8) ! {
	os.write_file_array(path, os.read_bytes(runtime.loader)!)!
	runtime_guest(runtime, bundle, 'unsigned-loader', 'Access Denied', attached, none)!
	mut modified := signed.clone()
	field := int(bootpolicy.pe_info(modified, runtime.arch)!.field)
	modified[field] = if modified[field] != `a` { `a` } else { `b` }
	os.write_file_array(path, modified)!
	runtime_guest(runtime, bundle, 'modified-loader', 'Access Denied', attached, none)!
}

fn negatives(runtime Runtime, debugfs string, bundle string, attached string, image string, source string, digest string, config string, device string, init_block u64) ! {
	offsets := [u64(1024), init_block * 4096 + 17, root_blocks * 4096 + 17,
		verityimage.layout(root_blocks)![0].offset * 4096 + 17]
	for index, scenario in ['metadata', 'init-data', 'top-tree', 'leaf-tree'] {
		os.cp(image, attached)!
		tamper(attached, offsets[index])!
		expected := if scenario == 'init-data' {
			if runtime.arch == 'x86_64' {
				'Kernel has called exit()'
			} else {
				'Could not start init process'
			}
		} else {
			'verity: root integrity or filesystem check failed'
		}
		runtime_guest(runtime, bundle, scenario, expected, attached, none)!
	}
	os.cp(image, attached)!
	truncate(attached, os.file_size(image) - 4096)!
	runtime_guest(runtime, bundle, 'truncated', 'verity: incompatible or truncated backing device', attached, none)!
	os.cp(image, attached)!
	wrong := if digest[0] != `0` { '0' } else { '1' } + digest[1..]
	enroll(runtime, bundle, config.replace(digest, wrong))!
	runtime_guest(runtime, bundle, 'wrong-root', 'verity: root integrity or filesystem check failed', attached, none)!
	token := verityimage.command_line(device, root_blocks, digest)!
	replacements := [token + ' ' + token, 'vinix.disk=auto ' + token,
		token.replace('vinix.verity=1,', 'vinix.verity=2,')]
	for index, scenario in ['duplicate-policy', 'conflicting-policy', 'malformed-policy'] {
		enroll(runtime, bundle, config.replace(token, replacements[index]))!
		runtime_guest(runtime, bundle, scenario, 'verity: invalid, duplicate or conflicting root policy', attached, none)!
	}
	bh.quiet([debugfs, '-w', '-R', 'rmdir /sys', source])!
	missing := runtime.work + '/missing-sys.verity'
	broken := verityimage.build(source, missing, false)!
	os.cp(missing, attached)!
	enroll(runtime, bundle, config.replace(digest, broken.root_hash))!
	runtime_guest(runtime, bundle, 'missing-mountpoint', 'verity: verified root is not a bootable system', attached, none)!
	enroll(runtime, bundle, config)!
}
