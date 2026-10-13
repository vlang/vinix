// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import encoding.binary
import gamehost
import ioshost
import json2
import os
import sourcecommand
import tarstream
import time

#include <termios.h>
struct C.termios {}

fn C.tcgetattr(i32, &C.termios) i32
fn C.tcsetattr(i32, i32, &C.termios) i32
fn C.cfmakeraw(&C.termios)
fn C.fork() i32

const flags = ['--no-build', '--with-2048', '--with-cxx', '--with-gles', '--with-ppsspp',
	'--ppsspp-muted', '--ppsspp-cube', '--ppsspp-nzp', '--ppsspp-gow']

fn options(mask int) !ioshost.Options {
	mut argv := []string{}
	for index, flag in flags { if mask & (1 << index) != 0 { argv << flag } }
	return ioshost.parse(argv)!
}

fn pure() ! {
	for marker in ['VINIX iOS GUEST: PASS', 'iOS FAIL:', 'FATAL EXCEPTION', 'KERNEL PANIC'] {
		bytes := ('x'.repeat(1000) + marker).bytes()
		for split in 0 .. marker.len + 1 {
			assert ioshost.finished_chunk(bytes, 1000 + split)
			assert !ioshost.finished_chunk(bytes[..1000 + split], 1000) || split == marker.len
		}
	}
	assert !ioshost.finished_chunk([]u8{}, 0)
	assert !ioshost.finished_chunk(('x'.repeat(1000) + '\x00nothing').bytes(), 1000)
	for mask in 0 .. 512 {
		no_build, game, cxx, gles, psp, muted, cube, nzp, gow := mask & 1 != 0, mask & 2 != 0, mask & 4 != 0, mask & 8 != 0, mask & 16 != 0, mask & 32 != 0, mask & 64 != 0, mask & 128 != 0, mask & 256 != 0
		valid := (!psp || cxx) && (!muted || (psp && gles)) && (!cube || muted) && (!nzp || (muted && !cube)) && (!gow || (muted && !cube && !nzp))
		value := options(mask) or {
			assert !valid
			assert err.code() == 2
			continue
		}
		assert valid && value.no_build == no_build && value.timeout == 180
		markers := value.expected()
		assert markers.len == 61 + (if game { 2 } else { 0 }) + (if cxx { 4 } else { 0 }) + (if gles {
			4
		} else {
			0
		}) + (if psp { 1 } else { 0 }) + (if cube || nzp || gow { 1 } else { 0 })
		assert markers[..60] == ioshost.features && markers.last() == 'VINIX iOS GUEST: PASS'
		assert markers.join('\n').contains('unsupported API reached at runtime') == (psp && !muted)
		assert markers.join('\n').contains('process lifecycle (muted)') == muted
		assert ioshost.verdict(markers.join('\n').bytes(), markers, false, 0) == 0
		for index in 0 .. markers.len {
			mut missing := markers.clone()
			missing.delete(index)
			assert ioshost.verdict(missing.join('\n').bytes(), markers, false, 0) == 1
			assert ioshost.verdict((markers.join('\n') + '\n' + markers[index]).bytes(), markers, false, 0) == 1
		}
	}
	markers := ioshost.Options{}.expected()
	for text in ['iOS FAIL:', 'FATAL EXCEPTION', 'KERNEL PANIC'] {
		assert ioshost.verdict((markers.join('\n') + '\n' + text).bytes(), markers, false, 0) == 1
	}
	assert ioshost.verdict(markers.join('\n').bytes(), markers, true, 0) == 1
	assert ioshost.verdict(markers.join('\n').bytes(), markers, false, 7) == 1
	for argv in [['--timeout', '0'], ['--timeout', '-1'], ['--timeout', 'nan'],
		['--timeout', '2147483648'], ['--unknown'], ['extra'], ['--ppsspp']] {
		ioshost.parse(argv) or {
			assert err.code() == 2
			continue
		}
		return error('invalid option accepted: ' + argv.str())
	}
	assert ioshost.parse(['--with-20', '--timeout=19'])!.with_2048
	for size in [12, 31, 32, 4095, 4096, 4097, 65537] {
		mut input := []u8{len: size}
		for index in 0 .. size { input[index] = u8(index % 251) }
		result := ioshost.images(input)!
		second := ((4096 + size + 4095) / 4096) * 4096
		mut golden := []u8{}
		for value in [u32(0xcafebabe), 2, 0x100000c, 2, 4096, u32(size), 12, 0x100000c, 0, u32(second),
			u32(size), 12] {
			golden << [u8(value >> 24), u8(value >> 16), u8(value >> 8), u8(value)]
		}
		golden << []u8{len: 4096 - golden.len}
		mut altered := input.clone()
		altered[8] = 2
		altered[9] = 0
		altered[10] = 0
		altered[11] = 0
		golden << altered
		golden << []u8{len: second - golden.len}
		golden << input
		assert result['calculator-fat']! == golden && result['calculator-arm64e']! == altered && result['truncated']! == input[..if size < 31 {
			size
		} else {
			31
		}]
	}
	ioshost.images([]u8{len: 11}) or { return }
	return error('short Mach-O accepted')
}

fn create(path string, bytes []u8) ! {
	gamehost.mkdir(os.dir(path))!
	os.write_file_array(path, bytes)!
	os.chmod(path, 0o751)!
}

fn fixtures(root string, build string) ! {
	calculator := os.read_bytes(root + '/build/ios/fixtures/calculator')!
	for name in ioshost.fixtures { create(build + '/fixtures/' + name, calculator)! }
	for name in ['cxx', 'cxx-extended', 'cxx-native', 'startup', 'gles', 'gles-app', 'compression'] {
		create(build + '/fixtures/' + name, calculator)!
	}
	for name in ['SceneFixture.app/SceneFixture', 'Modules.app/Modules',
		'Modules.app/Frameworks/Leaf.framework/Leaf', 'TextFixture.app/TextFixture'] {
		create(build + '/fixtures/' + name, calculator)!
	}
	os.symlink('TextFixture', build + '/fixtures/TextFixture.app/followed')!
	for name in ['run-ios', 'run-ios-gles'] {
		create(build + '/staging/usr/bin/' + name, name.bytes())!
	}
	create(build + '/staging/usr/lib/vinix/ios-gles/library.so', 'library'.bytes())!
	os.symlink('library.so', build + '/staging/usr/lib/vinix/ios-gles/linked.so')!
	create(build + '/objc/Calculator.app/Calculator', os.read_bytes(root + '/build/ios/objc/Calculator.app/Calculator')!)!
	create(build + '/2048/NumberTileGame.app/NumberTileGame', os.read_bytes(root + '/build/ios/2048/NumberTileGame.app/NumberTileGame')!)!
	create(build + '/2048/model-tests', 'model'.bytes())!
	for name in ['PPSSPP', 'assets/Roboto_Condensed-Regular.ttf', 'assets/nested/asset.bin'] {
		create(build + '/ppsspp/unpacked/Payload/PPSSPP.app/' + name, name.bytes())!
	}
	create(build + '/ppsspp/cube.pbp', 'cube'.bytes())!
	create(build + '/nzportable/unpacked/nzportable/nzp/pak', 'nzp'.bytes())!
	create(build + '/god-of-war/unpacked/PSP/GAME/UCUS98713/EBOOT.PBP', 'gow'.bytes())!
}

fn inspect_archive(path string, value ioshost.Options) ! {
	mut image := tarstream.open_concatenated(path)!
	defer { image.close() }
	mut names := map[string]bool{}
	for {
		member := image.next() or {
			if err is tarstream.End { break }
			return err
		}
		names[member.name] = true
		if member.name == './opt/ios/permissions-loop' {
			assert member.linkname == 'permissions-loop'
		}
		if member.name == './usr/lib/vinix/ios-gles/linked.so' {
			assert member.linkname == 'library.so'
		}
		if member.name == './opt/ios/PPSSPP' {
			assert member.linkname == if value.ppsspp_muted {
				'/usr/share/vinix/ios/PPSSPP.app/PPSSPP'
			} else {
				'PPSSPP.app/PPSSPP'
			}
		}
		if member.size == 0 { continue }
		mut bytes := []u8{len: int(member.size)}
		mut at := 0
		for at < bytes.len {
			count := image.read(mut bytes[at..])!
			assert count > 0
			at += count
		}
		if member.name == './opt/ios/run-ios' {
			assert bytes.bytestr() == if value.with_gles { 'run-ios-gles' } else { 'run-ios' }
			assert member.mode == 0o751
		}
		if member.name == './opt/ios/launch name#é%?.bin' {
			assert bytes.bytestr() == 'native file launch fixture\n'
		}
		if member.name == './etc/passwd' {
			assert bytes.bytestr() == 'root:*:0:0:Vinix iOS root:/root:/bin/sh\nios-fixture:*:1001:37:' + 'G'.repeat(8192) + ':/var/empty:/bin/false\n'
		}
		if member.name.ends_with('/ModulesArm64e.app/Frameworks/Leaf.framework/Leaf') {
			assert binary.little_endian_u32_at(bytes, 8) == 2
		}
		if member.name == './opt/ios/TextFixture.app/followed' {
			assert member.linkname == '' && member.mode == 0o751
		}
		if member.name.ends_with('/PSP/GAME/nzportable/setup.ini') {
			assert bytes.bytestr() == '-condebug +developer 1 +exec vinix-input.cfg\n'
		}
		if member.name.ends_with('/nzp/vinix-input.cfg') {
			assert bytes.bytestr() == 'bind "SELECT" "edict 1; echo VINIX-NZP-STATE-DONE"\nbinddt "SELECT" ""\n'
		}
		if member.name.ends_with('/PSP/SYSTEM/ppsspp.ini') {
			assert bytes.bytestr() == '[Sound]\nEnable=False\n[Graphics]\nInternalResolution=1\n'
		}
	}
	for name in ioshost.fixtures {
		assert names['./opt/ios/' + name]
	}
	for name in ['calculator-arm64e', 'calculator-fat', 'truncated', 'UIKitCalculator',
		'ModulesMissing.app', 'ModulesArm64e.app'] {
		assert names['./opt/ios/' + name]
	}
	assert !names['./opt/ios/ModulesMissing.app/Frameworks/Leaf.framework/Leaf']
	assert names['./opt/ios/NumberTileGame.app'] == value.with_2048 && names['./opt/ios/cxx-native'] == value.with_cxx
	assert names['./opt/ios/TextFixture.app/font.ttf'] == value.with_gles && names['./opt/ios/PPSSPP'] == value.with_ppsspp
	assert names['./opt/ios/ppsspp-cube'] == value.ppsspp_cube && names['./opt/ios/ppsspp-nzp'] == value.ppsspp_nzp && names['./opt/ios/ppsspp-gow'] == value.ppsspp_gow
}

fn emulator() ! {
	work := os.getenv('VINIX_IOS_RUN_CASE')
	mode := os.getenv('VINIX_IOS_RUN_MODE')
	value := options(os.getenv('VINIX_IOS_RUN_MASK').int())!
	os.write_file(work + '/child.pid', os.getpid().str())!
	assert os.args[1..4] == ['--no-build', '--serial', '--mem=2048']
	assert os.getenv('VINIX_QEMU_PERSIST_SIZE_MB') == '64' && os.getenv('VINIX_QEMU_NETWORK') == '0' && os.getenv('VINIX_QEMU_HOST_SOURCE') == '0' && os.getenv('VINIX_QEMU_AUDIO') == 'off' && os.getenv('VINIX_QEMU_CLIPBOARD') == '0'
	assert os.getenv('VINIX_QEMU_PERSIST') == '' && os.getenv('VINIX_QEMU_PACKAGE_STORE_PORT').int() > 0
	assert os.getwd() == work + '/project'
	init := os.read_bytes(os.args[4].all_after('='))!
	assert init[..4] == [u8(127), `E`, `L`, `F`] && binary.little_endian_u16_at(init, 18) == 183
	for index in 0 .. int(binary.little_endian_u16_at(init, 56)) {
		at := int(binary.little_endian_u64_at(init, 32)) + index * int(binary.little_endian_u16_at(init, 54))
		assert binary.little_endian_u32_at(init, at) != 3
	}
	inspect_archive(os.getenv('VINIX_INITRAMFS'), value)!
	os.write_file(work + '/archive-passed', 'PASS\n')!
	mut attributes := C.termios{}
	assert C.tcgetattr(0, &attributes) == 0
	C.cfmakeraw(&attributes)
	assert C.tcsetattr(0, C.TCSANOW, &attributes) == 0
	if mode == 'descendant' {
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			os.write_file(work + '/descendant.pid', os.getpid().str())!
			for { time.sleep(10 * time.millisecond) }
		}
		for !os.exists(work + '/descendant.pid') { time.sleep(time.millisecond) }
	}
	if mode == 'early' { exit(7) }
	if mode in ['timeout', 'interrupt', 'terminate'] {
		for { time.sleep(10 * time.millisecond) }
	}
	if mode == 'large' {
		print('z'.repeat(2 * 1024 * 1024))
		flush_stdout()
	}
	mut markers := value.expected()
	if mode == 'missing' { markers.delete(0) }
	println(markers.join('\n'))
	if mode == 'duplicate' { println(markers[0]) }
	if mode == 'panic' { println('KERNEL PANIC fixture') }
	if mode == 'fail' { println('iOS FAIL: fixture') }
	flush_stdout()
	mut bytes := []u8{len: 2}
	mut at := 0
	for at < 2 {
		count := os.stdin().read(mut bytes[at..])!
		assert count > 0
		at += count
	}
	assert bytes == [u8(1), `x`]
	os.write_file(work + '/quit-passed', 'PASS\n')!
	if mode == 'exit7' { exit(7) }
}

fn recorded(argv []string, environment map[string]string, context voidptr) !sourcecommand.Output {
	work := unsafe { &string(context) }
	mut log := os.open_append(*work + '/commands.log')!
	log.write_string(json2.encode(json2.Any(argv.map(json2.Any(it)))) + '\n')!
	log.close()
	assert argv.len > 0 && !argv.join(' ').contains('.py')
	if argv[0] == '/controlled/native-cc' {
		assert argv[1..4] == ['--target=aarch64-linux-musl',
			'--sysroot=' + environment['VINIX_IOS_TEST_SYSROOT'], '-static']
		ioshost.copy_file(*work + '/../init', argv.last())!
	} else if argv[1].ends_with('/examples/ios-calculator/build.sh') {
		assert environment['VINIX_IOS_CALCULATOR_BUILD_DIR'] == *work + '/../build/objc'
	}
	return sourcecommand.Output{}
}

fn signal_after_start(work string, mode string) {
	if mode !in ['interrupt', 'terminate'] { return }
	deadline := time.sys_mono_now() + 10 * time.second
	for !os.exists(work + '/child.pid') && time.sys_mono_now() < deadline {
		time.sleep(10 * time.millisecond)
	}
	C.kill(os.getpid(), if mode == 'interrupt' { C.SIGINT } else { C.SIGTERM })
}

fn controlled(work string, mode string, mask int) !int {
	mut environment := os.environ()
	for name, value in {
		'VINIX_IOS_BUILD_DIR':    work + '/../build'
		'VINIX_IOS_RUN_CASE':     work
		'VINIX_IOS_RUN_MODE':     mode
		'VINIX_IOS_RUN_MASK':     mask.str()
		'VINIX_QEMU_PERSIST':     '1'
		'CC':                     '/controlled/native-cc'
		'VINIX_IOS_TEST_SYSROOT': '/controlled/sdk'
	} {
		environment[name] = value
	}
	tools := ioshost.Tools{ root: work + '/project', environment: environment, hook: recorded, context: unsafe { &work } }
	worker := spawn signal_after_start(work, mode)
	defer { worker.wait() }
	parsed := options(mask)!
	return tools.run(ioshost.Options{ ...parsed, timeout: if mode == 'timeout' { 1 } else { 10 } })!
}

fn gone(work string, name string) ! {
	pid := os.read_file(work + '/' + name)!.int()
	deadline := time.sys_mono_now() + 3 * time.second
	for time.sys_mono_now() < deadline {
		if C.kill(i32(pid), 0) != 0 && C.errno == C.ESRCH { return }
		time.sleep(10 * time.millisecond)
	}
	return error('process remains ' + name)
}

fn cases(work string) ! {
	assert !os.exists(work)
	gamehost.mkdir(work)!
	pure()!
	root := os.real_path(os.dir(@FILE) + '/../..')
	fixtures(root, work + '/build')!
	mut environment := os.environ()
	environment['CC'] = '/opt/homebrew/opt/llvm/bin/clang'
	ioshost.Tools{ root: root, environment: environment }.compile(work)!
	for index, mask in [0, 3, 5, 9, 21, 125, 189, 317] {
		name := work + '/success-' + index.str()
		gamehost.mkdir(name + '/project/scripts')!
		os.symlink(os.executable(), name + '/project/scripts/run-aarch64.sh')!
		result := sourcecommand.capture_full([os.executable(), '--controlled', name, 'success',
			mask.str()], os.environ(), 30, 8 * 1024 * 1024, cachecli.cancelled)!
		os.write_file(name + '/console.log', result.stdout + result.stderr)!
		assert result.status == 0 && !result.stderr.contains(': fn '), 'success ${index}: status ${result.status}, stderr ${result.stderr}'
		assert os.read_file(name + '/archive-passed')! == 'PASS\n' && os.read_file(name + '/quit-passed')! == 'PASS\n'
		commands := os.read_lines(name + '/commands.log')!
		assert commands.len >= 3 && commands.last().contains('guest.c')
		assert commands.any(it.contains('build-ios-aarch64.sh')) == (mask & 1 == 0)
		assert commands.any(it.contains('ios-ppsspp/download"')) == (mask & (8 | 16) != 0)
		gone(name, 'child.pid')!
	}
	for mode in ['missing', 'duplicate', 'panic', 'fail', 'early', 'exit7', 'large', 'timeout',
		'interrupt', 'terminate', 'descendant'] {
		name := work + '/' + mode
		gamehost.mkdir(name + '/project/scripts')!
		os.symlink(os.executable(), name + '/project/scripts/run-aarch64.sh')!
		result := sourcecommand.capture_full([os.executable(), '--controlled', name, mode, '1'], os.environ(), 30, 8 * 1024 * 1024, cachecli.cancelled)!
		os.write_file(name + '/console.log', result.stdout + result.stderr)!
		expected := if mode == 'interrupt' {
			130
		} else if mode == 'terminate' {
			143
		} else if mode in ['large', 'descendant'] {
			0
		} else {
			1
		}
		assert result.status == expected && !result.stderr.contains(': fn '), '${mode}: status ${result.status}, stderr ${result.stderr}'
		gone(name, 'child.pid')!
		if mode == 'descendant' { gone(name, 'descendant.pid')! }
	}
	// A failed exec is still observed and reaped; repeated boots keep FD count flat.
	name := work + '/exec'
	gamehost.mkdir(name + '/scripts')!
	before := os.ls('/dev/fd')!.len
	for _ in 0 .. 100 {
		assert ioshost.guest(name, work + '/init', work + '/missing.tar', name + '/state', 1, ['never'], os.environ())! == 1
	}
	assert os.ls('/dev/fd')!.len == before
	println('PASS 512 option combinations, exact images, 19 controlled workflows, real static init, archives and 100 failed-exec cleanup cycles')
	os.write_file(work + '/passed', 'PASS\n')!
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len > 1 && os.args[1] == '--no-build' {
		emulator() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len == 5 && os.args[1] == '--controlled' {
		exit(controlled(os.args[2], os.args[3], os.args[4].int()) or {
			eprintln(err)
			if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }
		})
	}
	if os.args.len != 2 {
		eprintln('expected NEW_EVIDENCE')
		exit(2)
	}
	cases(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
