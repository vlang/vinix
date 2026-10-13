// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import encoding.binary
import gamehost
import json2
import net.unix
import os
import sourcecommand
import tarstream
import time
import xtcontroller

fn cross_cc() !int {
	root := os.real_path(os.dir(@FILE) + '/../..')
	sdk := root + '/build-amd64-desktop/initramfs-root'
	gccroot := sdk + '/usr/lib/gcc/x86_64-alpine-linux-musl'
	versions := os.ls(gccroot)!.sorted()
	gcc := gccroot + '/' + versions.last()
	compiler := '/opt/homebrew/opt/llvm/bin/clang'
	resource := sourcecommand.capture_full([compiler, '--print-resource-dir'], os.environ(), -1, 1024 * 1024, cachecli.cancelled)!
	if resource.status != 0 { return error(resource.stderr) }
	args := os.args[1..]
	mut flags := [compiler, '--target=x86_64-linux-musl', '-nostdinc', '-isystem',
		resource.stdout.trim_space() + '/include', '-isystem', sdk + '/usr/include']
	if '-c' in args {
		flags << args
	} else {
		flags << ['-nostdlib', sdk + '/usr/lib/crt1.o', sdk + '/usr/lib/crti.o', gcc + '/crtbeginT.o',
			...args, '-L' + sdk + '/usr/lib', '-L' + gcc, '-lgcc_eh', '-lc', '-lgcc', '-lm',
			gcc + '/crtend.o', sdk + '/usr/lib/crtn.o', '-fuse-ld=lld']
	}
	result := sourcecommand.capture_full(flags, os.environ(), -1, 16 * 1024 * 1024, cachecli.cancelled)!
	print(result.stdout)
	eprint(result.stderr)
	return result.status
}

fn read_qmp(mut connection unix.StreamConn) !map[string]json2.Any {
	mut data := []u8{}
	mut byte := []u8{len: 1}
	for {
		if connection.read(mut byte)! == 0 { return error('QMP closed') }
		if byte[0] == 10 { break }
		data << byte[0]
	}
	return json2.decode[map[string]json2.Any](data.bytestr())!
}

fn mocked() !bool {
	if os.file_name(os.args[0]) == 'build-amd64-iso.sh' {
		assert os.is_file(os.getenv('VINIX_AMD64_KERNEL')) && os.is_file(os.getenv('VINIX_AMD64_INITRAMFS'))
		os.write_file(os.getenv('VINIX_AMD64_ISO'), 'controlled ISO SDK output')!
		return true
	}
	if os.args.len < 2 || os.args[1] !in ['--no-build', '-machine'] { return false }
	state := os.dir(os.getenv('VINIX_QEMU_PERSIST_DISK'))
	mode := os.getenv('VINIX_EXT2_TEST_MODE')
	arch := os.getenv('VINIX_EXT2_TEST_ARCH')
	os.write_file(state + '/child.pid', os.getpid().str())!
	init := os.read_bytes(state + '/init')!
	assert init[..4] == [u8(127), `E`, `L`, `F`] && binary.little_endian_u16_at(init, 18) == if arch == 'aarch64' {
		u16(183)
	} else {
		u16(62)
	}
	mut archive := tarstream.open_plain(os.getenv('VINIX_INITRAMFS'))!
	mut saw_init := false
	for {
		member := archive.next() or {
			if err is tarstream.End { break }
			return err
		}
		if member.name == './sbin/init' {
			mut bytes := []u8{len: int(member.size)}
			assert archive.read(mut bytes)! == bytes.len && bytes == init
			saw_init = true
		}
	}
	archive.close()
	assert saw_init
	if mode == 'early' { exit(7) }
	if mode in ['timeout', 'interrupt'] {
		for { time.sleep(10 * time.millisecond) }
	}
	debugfs := '/opt/homebrew/opt/e2fsprogs/sbin/debugfs'
	disk := state + '/root.ext2'
	if !os.exists(disk) {
		mut file := os.create(disk)!
		assert C.ftruncate(file.fd, 64 * 1024 * 1024) == 0
		file.close()
		xtcontroller.command([os.dir(debugfs) + '/mke2fs', '-q', '-F', '-t', 'ext2', '-b', '4096',
			'-I', '128', '-O',
			'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum',
			disk], os.environ())!
	}
	marker := if arch == 'aarch64' { '/xattr-marker' } else { '/root/xattr-marker' }
	os.write_file(state + '/marker', 'native marker')!
	xtcontroller.command([debugfs, '-w', '-R', 'write ' + state + '/marker ' + marker, disk], os.environ())!
	if os.getenv('VINIX_EXT2_TEST_ACL') == '1' {
		prefix := if arch == 'aarch64' { '' } else { '/root' }
		for name in ['/acl-corrupt', '/acl-corrupt-dir'] {
			// Verify and restore the seeded version in the controlled guest.
			// This fixture establishes no real kernel ACL-repair result.
			block := xtcontroller.acl_block(xtcontroller.output([debugfs, '-R',
				'stat ' + prefix + name, disk], os.environ())!)!
			mut image := os.open_file(disk, 'r+')!
			image.seek(i64(block * 4096), .start)!
			mut bytes := []u8{len: 4096}
			assert image.read(mut bytes)! == bytes.len
			offset := xtcontroller.acl_offset(bytes)!
			assert binary.little_endian_u32_at(bytes, offset) in [u32(0), 1]
			image.seek(i64(block * 4096) + offset, .start)!
			image.write([u8(1), 0, 0, 0])!
			image.close()
			xtcontroller.command([debugfs, '-w', '-R',
				'ea_rm ' + prefix + name + ' system.posix_acl_access', disk], os.environ())!
		}
		xtcontroller.command([debugfs, '-w', '-R',
			'set_inode_field ' + prefix + '/acl-inconsistent mode 0100640', disk], os.environ())!
	}
	for name in ['user.binary', 'trusted.secret', 'security.test'] {
		if mode == 'attributes' && name == 'security.test' { continue }
		xtcontroller.command([debugfs, '-w', '-R', 'ea_set ' + marker + ' ' + name + ' native',
			disk], os.environ())!
	}
	path := state + '/qmp.sock'
	mut listener := unix.listen_stream(path)!
	defer { listener.close() or {} }
	println(if mode == 'reboot' {
		'XATTR: START\nXATTR: PASS'
	} else if mode == 'fail' {
		'XATTR: START\nFAIL: fixture'
	} else {
		'XATTR: START\nXATTR: REBOOT\nXATTR: START\nXATTR: PASS'
	})
	flush_stdout()
	mut connection := listener.accept()!
	defer { connection.close() or {} }
	connection.write_string('{"QMP":{}}\n')!
	assert read_qmp(mut connection)!['execute']!.str() == 'qmp_capabilities'
	connection.write_string('{"return":{}}\n')!
	assert read_qmp(mut connection)!['execute']!.str() == 'quit'
	connection.write_string('{"return":{}}\n')!
	os.write_file(state + '/monitor-quit', 'PASS\n')!
	return true
}

fn signal_after_start(state string, mode string) {
	if mode != 'interrupt' { return }
	deadline := time.sys_mono_now() + 60 * time.second
	for !os.exists(state + '/child.pid') && time.sys_mono_now() < deadline {
		time.sleep(10 * time.millisecond)
	}
	C.kill(os.getpid(), C.SIGINT)
}

fn cases(work string) ! {
	root := os.real_path(os.dir(@FILE) + '/../..')
	project := work + '/project'
	for name in ['kernel/bin', 'kernel/obj', 'tests/kernel-gaps', 'tests/ext2-xattr', 'scripts',
		'build-support', 'build-amd64-iso/limine', 'tools'] {
		gamehost.mkdir(project + '/' + name)!
	}
	gamehost.copy_tree(root + '/tests/kernel-gaps/serialcore', project + '/tests/kernel-gaps/serialcore', false)!
	gamehost.copy_tree(root + '/tests/ext2-xattr/xattrfixture', project + '/tests/ext2-xattr/xattrfixture', false)!
	gamehost.copy_file(root + '/tests/ext2-xattr/test.c', project + '/tests/ext2-xattr/test.c')!
	os.write_file(project + '/kernel/obj/blob.c', 'unchanged generated kernel snapshot')!
	os.symlink(root + '/build-aarch64-userland', project + '/build-aarch64-userland')!
	for name in ['scripts/run-aarch64.sh', 'build-support/build-amd64-iso.sh',
		'tools/qemu-system-x86_64', 'tools/musl-cc'] {
		os.symlink(os.executable(), project + '/' + name)!
	}
	for command in [['git', '-C', project, 'init', '-q'], ['git', '-C', project, 'add', 'kernel']] {
		xtcontroller.command(command, os.environ())!
	}
	os.setenv('CC', '/opt/homebrew/opt/llvm/bin/clang', true)
	os.setenv('CC_AMD64', project + '/tools/musl-cc', true)
	os.setenv('VINIX_QEMU_X86_64', project + '/tools/qemu-system-x86_64', true)
	os.setenv('E2FSCK', '/opt/homebrew/opt/e2fsprogs/sbin/e2fsck', true)
	os.setenv('DEBUGFS', '/opt/homebrew/opt/e2fsprogs/sbin/debugfs', true)
	os.setenv('V', os.args[2], true)
	baseline := os.ls('/dev/fd')!.len
	for row in [['aarch64', 'c', 'plain'], ['x86_64', 'c', 'plain'], ['aarch64', 'c-acl', 'acl'],
		['x86_64', 'c-acl', 'acl'], ['aarch64', 'v', 'acl'], ['x86_64', 'v', 'acl'],
		['aarch64', 'prebuilt', 'plain'], ['aarch64', 'early', 'plain'], ['aarch64', 'fail', 'plain'],
		['aarch64', 'reboot', 'plain'], ['aarch64', 'attributes', 'plain'],
		['aarch64', 'timeout', 'plain'], ['aarch64', 'interrupt', 'plain']] {
		arch, mode, acl := row[0], row[1], row[2] == 'acl'
		os.setenv('TMPDIR', '/tmp', true)
		state := os.real_path(sourcecommand.temporary('vxt')!)
		os.write_file(work + '/' + arch + '-' + mode + '.state', state + '\n')!
		mut header := []u8{len: 20}
		header[0] = 127
		header[1] = `E`
		header[2] = `L`
		header[3] = `F`
		binary.little_endian_put_u16(mut header[18..], if arch == 'aarch64' {
			u16(183)
		} else {
			u16(62)
		})
		os.write_file_array(project + '/kernel/bin/vinix', header)!
		os.setenv('VINIX_EXT2_TEST_MODE', mode, true)
		os.setenv('VINIX_EXT2_TEST_ARCH', arch, true)
		os.setenv('VINIX_EXT2_TEST_ACL', if acl { '1' } else { '0' }, true)
		guard := cachecli.own_commands()
		sender := spawn signal_after_start(state, mode)
		mut failed := false
		mut cause := ''
		xtcontroller.run(project, xtcontroller.Options{
			arch:     arch
			kernel:   project + '/kernel'
			source:   if mode == 'v' {
				''
			} else {
				project + '/tests/ext2-xattr/test.c'
			}
			state:    state
			prebuilt: if mode == 'prebuilt' {
				os.read_file(work + '/aarch64-c.state')!.trim_space() + '/init'
			} else {
				''
			}
			acl:      acl
			timeout:  if mode == 'timeout' { 1 } else { 30 }
		}) or {
			failed = true
			cause = err.msg()
			eprintln(mode + ': ' + cause)
		}
		sender.wait()
		assert failed == (mode !in ['c', 'c-acl', 'prebuilt']), arch + '/' + mode
		if mode == 'v' {
			assert cause.contains('memdup'), cause
		}
		guard.close()
		assert os.ls('/dev/fd')!.len == baseline, arch + '/' + mode
		if os.exists(state + '/child.pid') {
			pid := os.read_file(state + '/child.pid')!.int()
			assert C.kill(i32(pid), 0) != 0 && C.errno == C.ESRCH
		}
		if !failed {
			evidence := json2.decode[map[string]json2.Any](os.read_file(state + '/evidence.json')!)!
			assert evidence['arch']!.str() == arch && evidence['kernel_sha256']!.str() == gamehost.digest(state + '/kernel/bin/vinix')! && evidence['fixture_elf_sha256']!.str() == gamehost.digest(state + '/init')!
			assert os.read_file(state + '/generated.c')! == 'unchanged generated kernel snapshot'
			assert os.read_file(state + '/monitor-quit')! == 'PASS\n'
		}
	}
	os.write_file(work + '/passed', 'PASS\n')!
	println('PASS 13 native ext2 controls: both architectures, real static C ELF builds and filesystem tools, integrated ACL seeding, known V-fixture memdup build failures, controlled PTY/QMP, immutable/prebuilt receipts, failure/timeout/signal cleanup')
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.file_name(os.args[0]) == 'musl-cc' {
		exit(cross_cc() or {
			eprintln(err)
			1
		})
	}
	if mocked() or {
		eprintln(err)
		exit(1)
	} {
		return
	}
	if os.args.len != 3 || os.exists(os.args[1]) {
		eprintln('expected NEW_EVIDENCE COMPILER')
		exit(2)
	}
	gamehost.mkdir(os.args[1]) or { panic(err) }
	cases(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
