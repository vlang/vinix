// SPDX-License-Identifier: GPL-2.0-or-later
import ext2host
import fixturehost
import hosttest
import json2
import math
import net
import os
import policyhost
import systemhost
import time

#include <fcntl.h>

fn C.fcntl(int, int, ...int) int
fn C.ftruncate(int, u64) int

fn fd_count() int {
	mut count := 0
	for fd in 0 .. 1024 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn run(argv []string) !string {
	result := fixturehost.capture_owned_bounded(argv, policyhost.environment(), policyhost.caller_arch(), '', -1, policyhost.command_interrupted, false)!
	if result.status != 0 {
		return error(hosttest.shell_join(argv) + '\n' + result.stdout + result.stderr)
	}
	return result.stdout
}

fn tool(name string) !string {
	for candidate in [name, '/opt/homebrew/opt/e2fsprogs/sbin/' + name] {
		return os.find_abs_path_of_executable(candidate) or { continue }
	}
	return error(name + ' is required')
}

fn bmap(state string, path string, index int) !i64 {
	output := run([tool('debugfs')!, '-R', 'bmap /' + path + ' ' + index.str(),
		state + '/metadata.ext2'])!
	return output.trim_space().i64()
}

fn read_exact(mut connection net.TcpConn, count int) ![]u8 {
	mut data := []u8{len: count}
	mut at := 0
	for at < count {
		n := connection.read(mut data[at..])!
		if n == 0 { return error('Client EOF') }
		at += n
	}
	return data
}

fn send_all(mut connection net.TcpConn, data []u8) ! {
	mut at := 0
	for at < data.len {
		n := connection.write(data[at..])!
		if n == 0 { return error('Client short write') }
		at += n
	}
}

struct Client {
mut:
	connection &net.TcpConn
	size       i64
	flags      u16
}

fn client(port int, name string, zeroes bool) !Client {
	mut connection := net.dial_tcp('127.0.0.1:' + port.str())!
	connection.set_read_timeout(5 * time.second)
	connection.set_write_timeout(5 * time.second)
	mut owned := true
	defer { if owned { connection.close() or {} } }
	greeting := read_exact(mut connection, 18)!
	assert ext2host.get_be(greeting, 0, 8) == ext2host.nbd_magic
	assert ext2host.get_be(greeting, 8, 8) == ext2host.option_magic
	assert ext2host.get_be(greeting, 16, 2) == 3
	mut flags := []u8{len: 4}
	ext2host.put_be(mut flags, 0, if zeroes { 1 } else { 3 }, 4)
	send_all(mut connection, flags)!
	mut option := []u8{len: 16}
	ext2host.put_be(mut option, 0, ext2host.option_magic, 8)
	ext2host.put_be(mut option, 8, 1, 4)
	ext2host.put_be(mut option, 12, u64(name.len), 4)
	option << name.bytes()
	// Fragment the negotiation to prove reads retain every byte.
	for byte in option { send_all(mut connection, [byte])! }
	response := read_exact(mut connection, 10)!
	if zeroes {
		assert read_exact(mut connection, 124)! == []u8{len: 124}
	}
	owned = false
	return Client{connection, i64(ext2host.get_be(response, 0, 8)), u16(ext2host.get_be(response, 8, 2))}
}

fn (mut c Client) request(command u16, offset u64, length u32, payload []u8, flags u16) !(u32, []u8) {
	mut packet := []u8{len: 28}
	ext2host.put_be(mut packet, 0, ext2host.request_magic, 4)
	ext2host.put_be(mut packet, 4, flags, 2)
	ext2host.put_be(mut packet, 6, command, 2)
	for index, byte in 'testcase'.bytes() { packet[8 + index] = byte }
	ext2host.put_be(mut packet, 16, offset, 8)
	ext2host.put_be(mut packet, 24, length, 4)
	packet << payload
	send_all(mut c.connection, packet)!
	response := read_exact(mut c.connection, 16)!
	assert ext2host.get_be(response, 0, 4) == 0x67446698
	assert response[8..16].bytestr() == 'testcase'
	code := u32(ext2host.get_be(response, 4, 4))
	return code, if command == 0 && code == 0 {
		read_exact(mut c.connection, int(length))!
	} else {
		[]u8{}
	}
}

fn (mut c Client) close() { c.connection.close() or {} }

fn export_checks(work string) ! {
	source := work + '/source'
	state := work + '/export'
	os.mkdir_all(source + '/nested')!
	os.write_file(source + '/empty', '')!
	os.write_file(source + '/a "quoted" café', 'filename test')!
	os.symlink('nested/package.vpk', source + '/short-link')!
	long_link := 'nested/' + 'x'.repeat(90)
	os.symlink(long_link, source + '/long-link')!
	package := source + '/nested/package.vpk'
	mut file := os.open_file(package, 'wx', 0o600)!
	if C.ftruncate(file.fd, u64(130 * 1024 * 1024 + 13)) != 0 {
		return error('Cannot create sparse package')
	}
	offsets := [i64(0), 12 * 4096 - 127, (12 + 1024) * 4096 - 127, 128 * 1024 * 1024 - 127]
	for index, offset in offsets {
		pattern := u8(0xa5 + index * 17)
		file.seek(offset, .start)!
		assert file.write([]u8{len: 8192, init: pattern})! == 8192
	}
	file.seek(130 * 1024 * 1024, .start)!
	assert file.write('partial block'.bytes())! == 13
	file.close()
	overlay := work + '/overlay'
	os.mkdir_all(overlay + '/nested')!
	os.write_file(overlay + '/nested/loader', 'overlay executable')!
	os.chmod(overlay + '/nested/loader', 0o755)!
	os.write_file(overlay + '/empty', 'replaced')!
	manifest := ext2host.build(source, state, [overlay])!
	assert manifest.size == 256 * 1024 * 1024
	assert ext2host.inspect(state + '/metadata.ext2')!.blocks * 512 < 2 * 1024 * 1024
	assert ext2host.inspect(package)!.blocks * 512 < 128 * 1024
	run([tool('e2fsck')!, '-fn', state + '/metadata.ext2'])!
	mut export := ext2host.open_export(state)!
	defer { export.close() }
	first_block := bmap(state, 'nested/package.vpk', 0)!
	first_bytes := export.read(first_block * 4096, 16)!
	assert first_bytes == []u8{len: 16, init: 0xa5}
	partial := bmap(state, 'nested/package.vpk', 130 * 1024 * 1024 / 4096)!
	mut expected := 'partial block'.bytes()
	expected << []u8{len: 4096 - 13}
	assert export.read(partial * 4096, 4096)! == expected
	assert export.read(bmap(state, 'nested/loader', 0)! * 4096, 18)!.bytestr() == 'overlay executable'
	assert export.read(bmap(state, 'empty', 0)! * 4096, 8)!.bytestr() == 'replaced'
	assert export.read(bmap(state, 'long-link', 0)! * 4096, long_link.len)!.bytestr() == long_link
	for link in ['short-link', 'long-link'] {
		assert run([tool('debugfs')!, '-R', 'stat /' + link, state + '/metadata.ext2'])!.contains('Type: symlink')
	}
	mut server := ext2host.serve(state, 0, '', 3, 120000)!
	defer { server.close() }
	mut io := [tool('qemu-io')!, '-r', '-f', 'raw']
	for index, offset in offsets {
		mut at := offset
		mut remaining := 8192
		for remaining > 0 {
			inside := int(at % 4096)
			take := if remaining < 4096 - inside { remaining } else { 4096 - inside }
			disk := bmap(state, 'nested/package.vpk', int(at / 4096))! * 4096 + inside
			io << ['-c', 'read -P ' + (0xa5 + index * 17).str() + ' ' + disk.str() + ' ' + take.str()]
			at += take
			remaining -= take
		}
	}
	io << 'nbd://127.0.0.1:' + server.port.str() + '/'
	run(io)!
	mut c := client(server.port, '', false)!
	defer { c.close() }
	assert c.flags & 2 == 2 && c.size == manifest.size
	position := u64(bmap(state, 'nested/package.vpk', 0)! * 4096)
	code, bytes := c.request(0, position, 16, [], 0)!
	assert code == 0 && bytes == []u8{len: 16, init: 0xa5}
	rejected, _ := c.request(1, position, 16, []u8{len: 16, init: `X`}, 0)!
	assert rejected == 30
	for operation in [u16(4), 6] {
		rejected_op, _ := c.request(operation, position, 0, [], 0)!
		assert rejected_op == 30
	}
	flushed, _ := c.request(3, 0, 0, [], 0)!
	assert flushed == 0
	invalid, _ := c.request(0, u64(c.size - 1), 2, [], 0)!
	assert invalid == 22
	overflow, _ := c.request(0, ~u64(0), 1, [], 0)!
	assert overflow == 22
	flagged, _ := c.request(0, position, 1, [], 1)!
	assert flagged == 22
	// A remount changes only st_dev and must preserve validity.
	mut changed := manifest
	mut files := manifest.files.clone()
	for index, entry in files {
		mut identity := entry.identity.clone()
		identity[0]++
		files[index] = ext2host.SourceFile{entry.path, identity}
	}
	changed = ext2host.Manifest{ version: manifest.version, size: manifest.size, files: files, regions: manifest.regions }
	os.write_file(state + '/manifest.json', json2.encode(changed))!
	mut remounted := ext2host.open_export(state)!
	defer { remounted.close() }
	assert remounted.read(i64(position), 16)! == []u8{len: 16, init: 0xa5}
	mut changed_file := os.open_file(package, 'r+')!
	changed_file.write_string('changed')!
	changed_file.close()
	changed_code, _ := c.request(0, position, 16, [], 0)!
	assert changed_code == 5
	mut changed_seen := false
	remounted.read(i64(position), 16) or {
		assert err.code() == 5
		changed_seen = true
		[]u8{}
	}
	assert changed_seen
	mut nested_seen := false
	nested := ext2host.build(source, source + '/export', []) or {
		assert err.msg().contains('outside every exported root')
		nested_seen = true
		ext2host.Manifest{}
	}
	assert nested.size == 0
	assert nested_seen
	mut oversized := os.open_file(source + '/too-large', 'wx', 0o600)!
	assert C.ftruncate(oversized.fd, u64(1) << 32) == 0
	oversized.close()
	mut oversized_seen := false
	ext2host.build(source, work + '/oversized', []) or {
		assert err.msg().contains('larger than 4 GiB')
		oversized_seen = true
		ext2host.Manifest{}
	}
	assert oversized_seen
	println('PASS ext2 layout, sparse data, QEMU reads, read-only protocol and source guards')
}

fn idle_checks(work string) ! {
	os.mkdir_all(work + '/idle-source')!
	os.write_file(work + '/idle-source/file', 'idle data')!
	ext2host.build(work + '/idle-source', work + '/idle-export', [])!
	baseline := fd_count()
	for index in 0 .. 8 {
		mut server := ext2host.serve(work + '/idle-export', 0, 'named', if index % 2 == 0 {
			u16(3)
		} else {
			u16(1)
		}, 100)!
		mut c := client(server.port, 'named', true)!
		time.sleep(300 * time.millisecond)
		code, _ := c.request(0, 1024, 64, [], 0)!
		assert code == 0
		rejected, _ := c.request(1, 1024, 1, [u8(1)], 0)!
		assert rejected == 30
		mut unfinished := net.dial_tcp('127.0.0.1:' + server.port.str())!
		unfinished.set_read_timeout(time.second)
		assert read_exact(mut unfinished, 18)!.len == 18
		mut byte := []u8{len: 1}
		eof := unfinished.read(mut byte) or { 0 }
		assert eof == 0
		unfinished.close()!
		start := time.sys_mono_now()
		server.close()
		assert time.sys_mono_now() - start < u64(time.second)
		c.close()
	}
	assert fd_count() == baseline
	println('PASS idle transmission, negotiation deadlines, active-worker shutdown and descriptor retirement')
}

fn descriptor_cache_checks(work string) ! {
	source := work + '/many-source'
	state := work + '/many-export'
	os.mkdir_all(source)!
	for index in 0 .. 70 { os.write_file(source + '/file-' + index.str(), u8(index).ascii_str())! }
	manifest := ext2host.build(source, state, [])!
	baseline := fd_count()
	mut export := ext2host.open_export(state)!
	for _ in 0 .. 3 {
		for region in manifest.regions {
			data := export.read(region[0], 4096)!
			file := manifest.files[int(region[2])]
			assert data[0] == u8(os.file_name(file.path).all_after('file-').int())
			assert data[1..] == []u8{len: 4095}
			assert fd_count() <= baseline + 65
		}
	}
	export.close()
	export.close()
	assert fd_count() == baseline
	original := os.read_file(state + '/manifest.json')!
	defer { os.write_file(state + '/manifest.json', original) or {} }
	for kind in ['missing-version', 'unsupported-version', 'overflow-region', 'null-path'] {
		mut bad := json2.decode[json2.Any](original)!.as_map()
		if kind == 'missing-version' {
			bad.delete('version')
		} else if kind == 'unsupported-version' {
			bad['version'] = json2.Any(2)
		} else if kind == 'overflow-region' {
			mut regions := bad['regions']!.as_array()
			mut first := regions[0].as_array()
			first[3] = json2.Any(i64(0x7fffffffffffffff))
			regions[0] = json2.Any(first)
			bad['regions'] = json2.Any(regions)
		} else {
			mut files := bad['files']!.as_array()
			mut first := files[0].as_map()
			first['path'] = json2.Any('file\x00ignored')
			files[0] = json2.Any(first)
			bad['files'] = json2.Any(files)
		}
		os.write_file(state + '/manifest.json', json2.encode(json2.Any(bad)))!
		mut rejected := false
		mut invalid := ext2host.open_export(state) or {
			rejected = true
			unsafe { nil }
		}
		if !rejected { invalid.close() }
		assert rejected
		assert fd_count() == baseline
	}
	println('PASS bounded 64-source descriptor cache and repeated retirement')
}

fn wav_fixture(rate int, frequencies []int, lengths []f64, channels int, unfinished bool) []u8 {
	mut samples := []u8{}
	for index, frequency in frequencies {
		for at in 0 .. int(lengths[index] * rate) {
			sample := i16(12000 * math.sin(2 * math.pi * frequency * f64(at) / rate))
			for channel in 0 .. channels {
				value := if channel == 0 { sample } else { i16(0) }
				samples << [u8(u16(value)), u8(u16(value) >> 8)]
			}
		}
	}
	mut data := []u8{len: 44}
	for index, byte in 'RIFF'.bytes() { data[index] = byte }
	ext2host.put_le(mut data, 4, u64(samples.len + 36), 4)
	for index, byte in 'WAVEfmt '.bytes() { data[8 + index] = byte }
	ext2host.put_le(mut data, 16, 16, 4)
	ext2host.put_le(mut data, 20, 1, 2)
	ext2host.put_le(mut data, 22, u64(channels), 2)
	ext2host.put_le(mut data, 24, u64(rate), 4)
	ext2host.put_le(mut data, 34, 16, 2)
	for index, byte in 'data'.bytes() { data[36 + index] = byte }
	ext2host.put_le(mut data, 40, if unfinished { 0 } else { u64(samples.len) }, 4)
	data << samples
	return data
}

fn marker_and_sound_checks() ! {
	for mask in 0 .. 8 {
		policy := systemhost.PciPolicy{mask & 1 != 0, mask & 2 != 0, mask & 4 != 0}
		mut text := systemhost.pci_init_marker
		if policy.config { text += systemhost.pci_config_marker }
		if policy.mmap { text += systemhost.pci_mmap_marker }
		if policy.topology { text += systemhost.pci_topology_marker }
		assert systemhost.pci_ready(text, policy) && !systemhost.pci_failed(text, policy)
		assert systemhost.pci_failed(text + 'KERNEL PANIC', policy)
		if !policy.config {
			assert systemhost.pci_failed(text + systemhost.pci_config_marker, policy)
		}
	}
	for channels in [1, 2] {
		for unfinished in [false, true] {
			wav := systemhost.read_wav(wav_fixture(48000, [440, 660, 880], [f64(2), 0.45, 0.5], channels, unfinished))!
			assert wav.channels == channels && wav.samples.len == 141600
			assert systemhost.check_recording(wav).len == 0
		}
	}
	wrong := systemhost.read_wav(wav_fixture(48000, [880, 660, 440], [f64(2), 0.45, 0.5], 1, false))!
	assert systemhost.check_recording(wrong).len > 0
	silent := systemhost.read_wav(wav_fixture(48000, [0], [f64(1)], 1, false))!
	assert systemhost.check_recording(silent) == ['the recording is silent']
	assert systemhost.window_frequency([-3, -1, 1, -1, 1], 100) == 50
	println('PASS PCI marker matrix and independent WAV tone controls')
}

fn checked() ! {
	if os.args.len > 2 { return error_with_code('Usage: export-test [-v|-q|WORK-DIR]', 2) }
	if os.args.len == 2 && os.args[1] in ['-h', '--help'] {
		println('Usage: export-test [-v|-q|WORK-DIR]')
		return
	}
	provided := os.args.len == 2 && os.args[1] !in ['-v', '--verbose', '-q', '--quiet']
	if provided && os.args[1].starts_with('-') {
		return error_with_code('Unknown export-test option: ' + os.args[1], 2)
	}
	guard := policyhost.own_commands()
	defer { guard.close() }
	work := if provided { os.args[1] } else { hosttest.work_dir('', 'vinix-device-host-')! }
	os.mkdir_all(work)!
	defer { if !provided { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } } }
	export_checks(work)!
	idle_checks(work)!
	descriptor_cache_checks(work)!
	marker_and_sound_checks()!
}

fn main() {
	checked() or {
		eprintln(err.msg())
		exit(if err.code() == 2 { 2 } else { 1 })
	}
}
