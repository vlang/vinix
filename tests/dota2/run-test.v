// SPDX-License-Identifier: GPL-2.0-or-later
import ext2host
import fixturehost
import guesthost
import hosttest
import json2
import nativehost
import net
import os
import policyhost
import qemuhost
import time

#include <fcntl.h>
#include <signal.h>

fn C.fcntl(int, int, ...int) int
fn C.kill(int, int) int

fn fd_count() int {
	mut count := 0
	for fd in 0 .. 1024 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn received(mut connection net.TcpConn, count int) ![]u8 {
	mut bytes := []u8{len: count}
	mut at := 0
	for at < count {
		n := connection.read(mut bytes[at..])!
		if n == 0 { return error('Unexpected EOF') }
		at += n
	}
	return bytes
}

fn sent(mut connection net.TcpConn, bytes []u8) ! {
	mut at := 0
	for at < bytes.len {
		n := connection.write(bytes[at..])!
		if n <= 0 { return error('Short write') }
		at += n
	}
}

fn export_fixture(work string) !string {
	state := work + '/export'
	os.mkdir_all(state)!
	source := state + '/source'
	os.write_file(source, 'actual bytes')!
	os.write_file_array(state + '/metadata.ext2', []u8{len: 8192})!
	manifest := ext2host.Manifest{1, 8192, [ext2host.SourceFile{source, ext2host.inspect(source)!.identity}], [[
		i64(4096),
		4096,
		0,
		0,
	]]}
	os.write_file(state + '/manifest.json', json2.encode(manifest))!
	return state
}

fn observer(work string) ! {
	state := export_fixture(work)!
	before := fd_count()
	mut export := ext2host.open_export(state)!
	export.observe_reads()
	assert export.read(4096, 12)!.bytestr() == 'actual bytes'
	assert export.read(0, 12)! == []u8{len: 12}
	old := export.read_report()
	assert old.requests == 2 && old.bytes == 24 && old.error_count == 0
	os.write_file(state + '/source', 'changed bytes')!
	for _ in 0 .. 40 {
		mut failed := false
		export.read(4096, 12) or {
			assert err.code() == C.EIO
			failed = true
			[]u8{}
		}
		assert failed
	}
	report := export.read_report()
	assert report.requests == 42 && report.bytes == 24 && report.error_count == 40 && report.failures.len == 32
	assert report.failures[0].offset == 4096 && report.failures[0].error_number == C.EIO
	assert old.failures.len == 0 && old.requests == 2
	export.close()
	export.close()
	assert fd_count() == before
	// Real wire errors keep the original EIO response and request handle.
	mut server := ext2host.serve(state, 0, '', 3, 30000)!
	server.observe_reads()
	mut connection := net.dial_tcp('127.0.0.1:' + server.port.str())!
	connection.set_read_timeout(3 * time.second)
	assert received(mut connection, 18)!.len == 18
	mut flags := []u8{len: 4}
	ext2host.put_be(mut flags, 0, 3, 4)
	sent(mut connection, flags)!
	mut option := []u8{len: 16}
	ext2host.put_be(mut option, 0, ext2host.option_magic, 8)
	ext2host.put_be(mut option, 8, 1, 4)
	sent(mut connection, option)!
	assert received(mut connection, 10)!.len == 10
	mut request := []u8{len: 28}
	ext2host.put_be(mut request, 0, ext2host.request_magic, 4)
	for index, byte in 'observer'.bytes() { request[8 + index] = byte }
	ext2host.put_be(mut request, 16, 4096, 8)
	ext2host.put_be(mut request, 24, 12, 4)
	sent(mut connection, request)!
	reply := received(mut connection, 16)!
	assert ext2host.get_be(reply, 4, 4) == u64(C.EIO) && reply[8..].bytestr() == 'observer'
	// Closing joins an idle negotiated worker before retiring the export FDs.
	server.close()
	connection.close()!
	server.close()
	assert server.read_report().error_count == 1 && fd_count() == before
}

fn install_checks(work string) ! {
	source := work + '/pin'
	target := work + '/target'
	os.write_file(source, 'new desktop')!
	os.chmod(source, 0o555)!
	os.write_file(target, 'old desktop')!
	os.chmod(target, 0o555)!
	for _ in 0 .. 4 { nativehost.game_install(source, target)! }
	assert os.read_file(target)! == 'new desktop' && os.stat(target)!.mode & 0o777 == 0o555
	assert os.read_file(source)! == 'new desktop' && os.stat(source)!.mode & 0o777 == 0o555
	nativehost.game_install(source, source)!
	os.rm(target)!
	os.symlink(source, target)!
	os.write_file(work + '/replacement', 'replacement')!
	nativehost.game_install(work + '/replacement', target)!
	assert !os.is_link(target) && os.read_file(source)! == 'new desktop'
	base := work + '/base'
	rootfs := work + '/root'
	runtime := '/usr/libexec/vinix-dota2/root'
	dri := runtime + '/usr/lib/x86_64-linux-gnu/dri'
	os.mkdir_all(base + dri)!
	os.write_file(base + runtime + '/.vinix-dota2-vulkan-generation', 'generation-1\n')!
	os.write_file(base + dri + '/swrast_dri.so', 'software')!
	os.write_file(base + dri + '/unused.so', 'hardware')!
	os.symlink('swrast_dri.so', base + dri + '/kms_swrast_dri.so')!
	os.mkdir_all(base + runtime + '/usr/share/doc')!
	nativehost.refresh_game_runtime(base, rootfs)!
	assert !os.exists(rootfs + dri + '/unused.so') && !os.exists(rootfs + runtime + '/usr/share/doc')
	assert os.is_link(rootfs + dri + '/kms_swrast_dri.so')
	os.write_file(rootfs + runtime + '/cached', 'preserved')!
	nativehost.refresh_game_runtime(base, rootfs)!
	assert os.read_file(rootfs + runtime + '/cached')! == 'preserved'
	os.rm(rootfs + dri + '/swrast_dri.so')!
	nativehost.refresh_game_runtime(base, rootfs)!
	assert os.read_file(rootfs + dri + '/swrast_dri.so')! == 'software' && !os.exists(rootfs + runtime + '/cached')
	query := work + '/query/gldriverquery'
	os.mkdir_all(os.dir(query))!
	os.mkdir_all(rootfs + '/home/dota2/.steam/ubuntu12_64')!
	os.write_file(rootfs + '/home/dota2/.steam/ubuntu12_64/vulkandriverquery', 'stale')!
	nativehost.stage_game_vulkan_query(query, rootfs)!
	assert !os.exists(rootfs + '/home/dota2/.steam/ubuntu12_64/vulkandriverquery')
}

fn recorded_screenshot(_socket string, target string) bool {
	os.write_file(target, 'controlled capture') or { return false }
	return true
}

fn capture_checks(work string) ! {
	for failure in [false, true] {
		state := work + '/capture-' + failure.str()
		os.mkdir_all(state)!
		mut env := policyhost.environment()
		env['VINIX_GAME_MODEL'] = if failure { 'failure' } else { 'idle' }
		env['VINIX_GAME_PID'] = state + '/pid'
		result := guesthost.capture_game([os.executable()], env, state, '', 4, 1, recorded_screenshot, false)!
		assert nativehost.game_start_observed(result.text)
		assert result.failure == if failure { 'VINIX-DOTA2-GAME-EXIT:' } else { '' }
		assert result.captures == [state + '/guest-final.png']
		assert os.read_file(state + '/serial.log')! == os.read_file(state + '/vinix.log')!
		assert C.kill(os.read_file(state + '/pid')!.int(), 0) < 0
	}
}

fn checked() ! {
	guard := policyhost.own_commands()
	defer { guard.close() }
	work := hosttest.work_dir(if os.args.len == 2 { os.args[1] } else { '' }, 'vinix-game-test-')!
	defer { hosttest.remove_work_dir(work) or {} }
	install_checks(work)!
	observer(work)!
	venus_checks()!
	assert nativehost.game_start_observed('VINIX-DOTexec\nA2-GAME-STARTED\nVINIX-DOTA2-GAME-ALIVE\n')
	assert !nativehost.game_start_observed('VINIX-DOTA2-PROBE-START\nVINIX-DOTA2-DESKTOP-STARTED\n')
	assert (nativehost.game_exit_status('VINIX-DOTA2-GAME-EXIT: x\nVINIX-DOTA2-GAME-EXIT: \r\n000139') or { '' }) == '000139'
	assert (nativehost.game_exit_status('VINIX-DOTA2-GAME-EXIT: 1234567890123456789012345678901234567890') or { '' }) == '1234567890123456789012345678901234567890'
	assert nativehost.game_settings(['A=spaces,commas', "Q=a'b", 'A=last'])!['A'] == 'last'
	{
		for value in ['0', '-1', 'bad'] {
			result := fixturehost.capture_owned_bounded([
				os.getenv_opt('VINIX_GAME_RUNNER') or { hosttest.root() + '/tests/dota2/run' },
				'--prepare-only',
				'--work',
				work + '/absent',
				'--memory-mib',
				value,
			], policyhost.environment(), policyhost.caller_arch(), '', 5, policyhost.command_interrupted, false)!
			assert result.status == 2 && !os.exists(work + '/absent')
		}
		result := fixturehost.capture_owned_bounded([
			os.getenv_opt('VINIX_GAME_RUNNER') or { hosttest.root() + '/tests/dota2/run' },
			'--work',
			work + '/absent',
			'--extra-preload',
			work + '/missing.so',
		], policyhost.environment(), policyhost.caller_arch(), '', 10, policyhost.command_interrupted, false)!
		assert result.status == 1 && !os.exists(work + '/absent')
	}
	capture_checks(work)!
	if qemu := os.find_abs_path_of_executable('qemu-system-aarch64') {
		before := fd_count()
		for index in 0 .. 8 {
			mut owner := guesthost.game_network(qemu, policyhost.environment(), work + '/network-' + index.str() + '.log')!
			assert os.exists(owner.socket)
			owner.close()
			owner.close()
			assert !os.exists(owner.socket)
		}
		assert fd_count() == before
	}
	println('PASS native game preparation, bounded export diagnostics, wire errors, capture verdicts and child retirement')
}

fn venus_checks() ! {
	mut data := []u8{len: 1024}
	for index, byte in [u8(0xcf), 0xfa, 0xed, 0xfe] { data[index] = byte }
	ext2host.put_le(mut data, 16, 1, 4)
	ext2host.put_le(mut data, 32, 0x19, 4)
	ext2host.put_le(mut data, 36, 72, 4)
	ext2host.put_le(mut data, 56, 0x1000, 8)
	ext2host.put_le(mut data, 72, 128, 8)
	ext2host.put_le(mut data, 80, 512, 8)
	for index, byte in qemuhost.old_sequence { data[488 + index] = byte }
	changed := qemuhost.patched(data, '0000000000001000 t _hvf_wfi\n')!
	assert data[488..504] == qemuhost.old_sequence && changed[488..504] == qemuhost.new_sequence
	assert data[..488] == changed[..488] && data[504..] == changed[504..]
	assert qemuhost.patched(changed, '0000000000001000 T _hvf_wfi\n')! == changed
	for symbols in ['', '0000000000001000 T _hvf_wfi\n0000000000001000 t _hvf_wfi\n',
		'ffffffffffffffff T _hvf_wfi\n'] {
		mut rejected := false
		qemuhost.patched(data, symbols) or {
			rejected = true
			[]u8{}
		}
		assert rejected
	}
	for position in [0, 36, 81, 488] {
		mut invalid := data.clone()
		invalid[position] = 0
		mut rejected := false
		qemuhost.patched(invalid, '0000000000001000 t _hvf_wfi\n') or {
			rejected = true
			[]u8{}
		}
		assert rejected
	}
}

fn main() {
	if os.getenv('VINIX_GAME_MODEL') != '' {
		// spawn_guest changes to the repository, so the fixture PID path is explicit.
		os.write_file(os.getenv('VINIX_GAME_PID'), os.getpid().str()) or { panic(err) }
		println('VINIX-DOTA2-GAME-ALIVE')
		if os.getenv('VINIX_GAME_MODEL') == 'failure' { println('VINIX-DOTA2-GAME-EXIT: 139') }
		flush_stdout()
		for { time.sleep(20 * time.millisecond) }
	}
	checked() or {
		eprintln(err)
		exit(1)
	}
}
