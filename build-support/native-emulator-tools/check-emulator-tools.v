// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import encoding.binary
import emulatorbuild
import fixturehost
import hosttest
import json2
import net
import os
import policyhost
import tarcore
import time

fn C.kill(i32, i32) i32
fn C.getppid() i32
fn C.fcntl(i32, i32, ...int) i32
fn C.fstat(i32, &C.stat) i32
fn C.dup2(i32, i32) i32

fn stdio_state() []u64 {
	mut result := []u64{}
	for fd in 0 .. 3 {
		mut state := C.stat{}
		if C.fstat(fd, &state) < 0 { result << [u64(fd), u64(0)]; continue }
		result << [u64(fd), u64(state.st_mode & C.S_IFMT), u64(state.st_dev), u64(state.st_ino), u64(C.fcntl(fd, C.F_GETFD))]
	}
	return result
}

fn check_log_layouts(work string) ! {
	mut owners := []i32{}
	mut flags := []i32{}
	for fd in 0 .. 3 {
		owners << C.fcntl(fd, C.F_DUPFD_CLOEXEC, 30)
		flags << C.fcntl(fd, C.F_GETFD)
		if owners.last() < 0 { return error('Cannot save standard descriptor') }
	}
	defer {
		for fd in 0 .. 3 { C.dup2(owners[fd], fd); C.fcntl(fd, C.F_SETFD, flags[fd]); C.close(owners[fd]) }
	}
	for layout in 0 .. 27 {
		mut value := layout
		for fd in 0 .. 3 {
			C.dup2(owners[fd], fd)
			C.fcntl(fd, C.F_SETFD, flags[fd])
			match value % 3 {
				1 { C.close(fd) }
				2 { C.fcntl(fd, C.F_SETFD, flags[fd] | C.FD_CLOEXEC) }
				else {}
			}
			value /= 3
		}
		expected := stdio_state()
		if fixturehost.logged_owned([os.executable(), '--child', 'output'], policyhost.environment(),
			policyhost.caller_arch(), work, work + '/layouts.log', unsafe { nil })! != 7 {
			return error('Logged command status changed in descriptor layout ' + layout.str())
		}
		if stdio_state() != expected { return error('Parent standard descriptor changed: ' + layout.str()) }
		if os.read_file(work + '/layouts.log')! != 'stdout\x00\xff' + 'a'.repeat(700000) + 'stderr\x80' + 'b'.repeat(600000) {
			return error('Merged log bytes changed: ' + layout.str())
		}
	}
}

fn descriptors() int {
	mut count := 0
	for fd in 0 .. 4096 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn child() {
	if os.args[2] == 'interrupt' {
		print('partial log\x00\xff')
		flush_stdout()
		C.kill(C.getppid(), C.SIGINT)
		for { time.sleep(20 * time.millisecond) }
	}
	print('stdout\x00\xff' + 'a'.repeat(700000))
	flush_stdout()
	eprint('stderr\x80' + 'b'.repeat(600000))
	exit(7)
}

fn serve(mut listener net.TcpListener, body string, mode string) ! {
	defer { listener.close() or {} }
	mut connection := listener.accept()!
	defer { connection.close() or {} }
	connection.set_read_timeout(3 * time.second)
	mut request := []u8{len: 8192}
	connection.read(mut request)!
	if mode == 'error' { connection.write_string('HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')!; return }
	connection.write_string('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n')!
	for _ in 0 .. if mode == 'oversize' { 100 } else { 1 } {
		connection.write_string(body.len.hex() + '\r\n' + body + '\r\n') or { return }
	}
	connection.write_string('0\r\n\r\n') or {}
}

fn check_download(work string) ! {
	previous_proxy := os.getenv_opt('NO_PROXY')
	os.setenv('NO_PROXY', '127.0.0.1,::1', true)
	defer { if value := previous_proxy { os.setenv('NO_PROXY', value, true) } else { os.unsetenv('NO_PROXY') } }
	guard := policyhost.own_commands()
	defer { guard.close() }
	for mode in ['good', 'checksum', 'oversize', 'error'] {
		body := 'binary\x00\xffbody'
		mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
		listener.set_accept_timeout(3 * time.second)
		url := 'http://' + listener.addr()!.str() + '/pinned'
		server_thread := spawn serve(mut listener, body, mode)
		path := work + '/download-' + mode
		mut rejected := false
		emulatorbuild.fetch(path, url, sha256.hexhash(if mode == 'checksum' { 'wrong' } else { body }), body.len) or { rejected = true }
		server_thread.wait()!
		assert rejected == (mode != 'good')
		assert os.exists(path) == (mode == 'good')
		assert !os.ls(work)!.any(it.starts_with('vinix-fetch-'))
		if mode == 'good' {
			assert os.read_file(path)! == body
			emulatorbuild.fetch(path, 'http://127.0.0.1:1/unused', sha256.hexhash(body), body.len)!
			os.write_file(path, 'corrupt')!
			emulatorbuild.fetch(path, 'http://127.0.0.1:1/unused', sha256.hexhash(body), body.len) or {
				assert os.read_file(path)! == 'corrupt'
				continue
			}
			return error('Corrupt cache was accepted')
		}
	}
	println('PASS streamed/chunked download, size/status/digest failures, cache reuse and temporary retirement')
}

fn check_archives(work string) ! {
	guard := policyhost.own_commands()
	defer { guard.close() }
	for bad in ['/root/file', 'root/../file', 'root/back\\file', 'root/link', 'orphan', 'root/large'] {
		path := work + '/bad.tar'
		mut writer := tarcore.create(path)!
		if bad == 'root/large' {
			writer.write(tarcore.header(tarcore.Member{ name: bad, size: 32 * 1024 * 1024 + 1 })!)!
		} else {
			writer.add(tarcore.Member{ name: bad, kind: if bad == 'root/link' { u8(`2`) } else { u8(`0`) }, size: 0 }, []u8{})!
		}
		writer.finish()!
		writer.close()
		destination := work + '/extract-' + bad.bytes().hex()
		os.mkdir(destination)!
		emulatorbuild.unpack(path, destination) or { continue }
		return error('Unsupported source member was accepted: ' + bad)
	}
	archive := work + '/good.tar'
	mut writer := tarcore.create(archive)!
	writer.add(tarcore.Member{ name: 'root', kind: `5` }, []u8{})!
	for index in 0 .. 256 {
		writer.add(tarcore.Member{ name: 'root/e\u0301/' + index.str(), mode: if index == 1 { 0o711 } else { 0o600 }, size: 3 }, 'abc'.bytes())!
	}
	writer.finish()!
	writer.close()
	baseline := descriptors()
	os.mkdir(work + '/unicode')!
	emulatorbuild.unpack(archive, work + '/unicode')!
	assert descriptors() == baseline
	assert os.ls(work + '/unicode/e\u0301')!.len == 256
	assert (os.stat(work + '/unicode/e\u0301/1')!).mode & 0o777 == 0o755
	assert (os.stat(work + '/unicode/e\u0301/2')!).mode & 0o777 == 0o644
	assert os.read_file(work + '/unicode/e\u0301/200')! == 'abc'
	println('PASS archive path/type/size guards, decomposed Unicode, modes and 256 file owners')
}

fn check_log(work string) ! {
	baseline := descriptors()
	log := work + '/build.log'
	assert fixturehost.logged_owned([os.executable(), '--child', 'output'], policyhost.environment(),
		policyhost.caller_arch(), work, log, unsafe { nil })! == 7
	assert os.read_file(log)! == 'stdout\x00\xff' + 'a'.repeat(700000) + 'stderr\x80' + 'b'.repeat(600000)
	assert descriptors() == baseline
	guard := policyhost.own_commands()
	fixturehost.logged_owned([os.executable(), '--child', 'interrupt'], policyhost.environment(),
		policyhost.caller_arch(), work, log, policyhost.command_interrupted) or {
		assert err.code() == 130 && os.read_file(log)! == 'partial log\x00\xff'
		guard.close()
		assert descriptors() == baseline
		println('PASS merged streaming build log, nonzero exit, partial SIGINT log and descriptor retirement')
		return
	}
	guard.close()
	return error('Logged command ignored interrupt')
}

fn check_segments(work string) ! {
	for big in [true, false] {
		mut data := []u8{len: 160}
		data[0] = 0x7f; data[1] = `E`; data[2] = `L`; data[3] = `F`
		data[4] = 1; data[5] = if big { 2 } else { 1 }
		put16 := fn [big] (mut bytes []u8, value u16) {
			if big { binary.big_endian_put_u16(mut bytes, value) } else { binary.little_endian_put_u16(mut bytes, value) }
		}
		put32 := fn [big] (mut bytes []u8, value u32) {
			if big { binary.big_endian_put_u32(mut bytes, value) } else { binary.little_endian_put_u32(mut bytes, value) }
		}
		put16(mut data[18..20], 8)
		put32(mut data[28..32], 52)
		put16(mut data[42..44], 32)
		put16(mut data[44..46], 2)
		for i in 0 .. 2 {
			at := 52 + i * 32
			put32(mut data[at..at + 4], 1)
			put32(mut data[at + 4..at + 8], u32(128 + i * 4))
			put32(mut data[at + 8..at + 12], u32(0x1000 + i * 16))
			put32(mut data[at + 16..at + 20], u32(4 - i))
			put32(mut data[at + 20..at + 24], 8)
		}
		for i, b in 'ABCDEFG'.bytes() { data[128 + i] = b }
		path := work + '/segments.elf'
		os.write_file_array(path, data)!
		mut expected := 'ABCD'.bytes()
		expected << []u8{len: 12}
		expected << 'EFG'.bytes()
		expected << []u8{len: 5}
		assert emulatorbuild.segments(path, 0x1000, 0x1100, big)! == expected
		for mode in ['address', 'range', 'file-size', 'table', 'truncated', 'machine'] {
			mut bad := data.clone()
			match mode {
				'address' { put32(mut bad[60..64], 0xfff) }
				'range' { put32(mut bad[72..76], 0xffffffff) }
				'file-size' { put32(mut bad[68..72], 9) }
				'table' { put32(mut bad[28..32], 0xffffff00) }
				'truncated' { bad = bad[..130].clone() }
				else { put16(mut bad[18..20], 3) }
			}
			os.write_file_array(path, bad)!
			emulatorbuild.segments(path, 0x1000, 0x1100, big) or { continue }
			return error('Malformed MIPS ELF accepted: ' + mode)
		}
	}
	mut zero := []u8{len: 24}
	emulatorbuild.checksum(mut zero)!
	assert binary.big_endian_u32(zero[16..20]) == 0xf8ca4ddc
	assert binary.big_endian_u32(zero[20..24]) == u32((u64(0xf8ca4ddc) * 262145) & 0xffffffff)
	golden := hosttest.root() + '/build/n64/homebrew/paddle.z64'
	if os.is_file(golden) {
		original := os.read_bytes(golden)!
		mut changed := original.clone()
		emulatorbuild.checksum(mut changed)!
		assert changed == original
	}
	println('PASS both-endian MIPS BSS/holes, truncated/range/ABI guards and original CIC checksum')
}

fn check_interrupts(work string) ! {
	bin := work + '/fake tools'
	os.mkdir(bin)!
	for name in ['clang', 'llvm-ar', 'ld.lld', 'make'] { os.symlink(os.executable(), bin + '/' + name)! }
	mut env := policyhost.environment()
	env['VINIX_EMULATOR_QA_SURROGATE'] = '1'
	env['VINIX_EMULATOR_QA_PID'] = work + '/surrogate.pid'
	env['PATH'] = bin + ':' + env['PATH']
	for index in 1 .. if os.args.len > 4 { 4 } else { os.args.len } {
		output := work + '/interrupt-' + index.str()
		mut args := [os.args[index], '--output', output, '--llvm-bin', bin]
		if index == 3 {
			emulatorbuild.mkdir(output + '/source')!
			emulatorbuild.mkdir(output + '/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/1')!
			os.write_file(output + '/sdk/usr/lib/libc.a', 'test libc')!
			os.cp(hosttest.root() + '/build/ps1/pcsx-source.tar.gz', output + '/pcsx-source.tar.gz')!
			os.write_file(output + '/source/.vinix-source', 'edeb21fdeef8815521cb9d4488d2cd35746607c968ca9b26cce4e42c09f2dc99')!
			args << ['--sysroot', output + '/sdk']
		}
		result := fixturehost.capture_both_preferred(args, env, policyhost.caller_arch())!
		assert result.status == 130, result.stdout + result.stderr
		pid := os.read_file(work + '/surrogate.pid')!.int()
		assert C.kill(pid, 0) < 0 && C.errno == C.ESRCH
		if index == 3 { assert os.read_file(output + '/core-clean.log')!.contains('surrogate partial') }
	}
	// Reach the V producer after real LLVM startup assembly commands. Its
	// caller owns the V scratch and compiler group in the same process.
	scratch := work + '/module scratch\\literal'
	os.mkdir(scratch)!
	env['TMPDIR'] = scratch
	env['V'] = os.executable()
	for index in 1 .. 3 {
		result := fixturehost.capture_both_preferred([os.args[index], '--output', work + '/v-interrupt-' + index.str(),
			'--llvm-bin', '/opt/homebrew/opt/llvm/bin'], env, policyhost.caller_arch())!
		assert result.status == 130, result.stdout + result.stderr
		assert os.ls(scratch)!.len == 0
		pid := os.read_file(work + '/surrogate.pid')!.int()
		assert C.kill(pid, 0) < 0 && C.errno == C.ESRCH
	}
	if os.args.len > 4 {
		output := work + '/download-interrupt'
		os.symlink(os.executable(), bin + '/curl')!
		result := fixturehost.capture_both_preferred([os.args[4], '--output', output], env, policyhost.caller_arch())!
		assert result.status == 130, result.stdout + result.stderr
		assert os.ls(output)!.len == 0
		pid := os.read_file(work + '/surrogate.pid')!.int()
		assert C.kill(pid, 0) < 0 && C.errno == C.ESRCH
	}
	println('PASS actual N64/PS2 compiler and PS1 make SIGINT controllers, partial logs and child retirement')
}

fn checked() ! {
	work := hosttest.work_dir('', 'vinix-emulator-check-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	assert emulatorbuild.shell_word('/space/back\\slash\'dollar$()') == "'/space/back\\slash'\"'\"'dollar$()'"
	assert emulatorbuild.cache_json(json2.Any({'z': json2.Any('e\u0301😀\n'), 'a': json2.Any('x')})) == '{"a": "x", "z": "e\\u0301\\ud83d\\ude00\\n"}'
	stamp := os.read_file(hosttest.root() + '/build/ps1/core-build-stamp')!
	assert emulatorbuild.cache_json(json2.decode[json2.Any](stamp)!) == stamp
	assert emulatorbuild.image_header([u8(0), 1, 255]) == '// Generated from iopcore; SPDX-License-Identifier: MIT\nstatic const unsigned char iop_image[] = {\n0x00,0x01,0xff\n};\n'
	check_log(work)!
	check_log_layouts(work)!
	println('PASS all 27 open/closed/cloexec standard descriptor layouts and exact binary log bytes')
	check_segments(work)!
	check_archives(work)!
	check_download(work)!
	if os.args.len > 1 { check_interrupts(work)! }
}

fn main() {
	if os.getenv('VINIX_EMULATOR_QA_SURROGATE') == '1' {
		if os.args.len == 2 && os.args[1] == 'version' { println('V 0.5.2 ownership fixture'); return }
		if os.args.len > 1 && os.args[1] == '--version' { println('clang fixture'); return }
		os.write_file(os.getenv('VINIX_EMULATOR_QA_PID'), os.getpid().str()) or { panic(err) }
		println('surrogate partial')
		flush_stdout()
		C.kill(C.getppid(), C.SIGINT)
		for { time.sleep(20 * time.millisecond) }
	}
	if os.args.len > 2 && os.args[1] == '--child' { child(); return }
	checked() or { eprintln(err.msg()); exit(1) }
}
