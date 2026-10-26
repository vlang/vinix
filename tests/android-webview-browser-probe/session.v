// SPDX-License-Identifier: GPL-2.0-or-later
// Guest-only launcher for a separate, real GTK4/WebKit diagnostic session.
module main

import crypto.rand
import crypto.sha256
import json2
import net
import net.unix
import os
import strconv
import time

#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>

const webkit_helpers = ['WebKitWebProcess', 'WebKitNetworkProcess', 'WebKitGPUProcess']
const injected_bundle = 'usr/lib/webkitgtk-6.0/injected-bundle/libwebkitgtkinjectedbundle.so'
const libproxy_backend = 'usr/lib/libproxy/libpxbackend-1.0.so'

struct BuildPins {
	runtime_references map[string]string
	guest_helper_references map[string]string
	probe_sha256       string
	session_sha256     string
	fault_probe_build_sha256 string
	fault_probe_shim_sha256 string
	fault_probe_fixture_sha256 string
	fault_probe_files_sha256 map[string]string
}

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn equal_hash(path string, expected string) ! {
	if expected.len != 64 || hash(path)! != expected {
		return error('pinned file hash mismatch: ' + path)
	}
}

fn library_path(base string, addon string) string {
	// libproxy's packaged RUNPATH is /usr/lib/libproxy. Resolve the relocated
	// backend in the pinned roots before any ambient guest library directory.
	return '${base}/lib:${base}/usr/lib:${base}/usr/lib/libproxy:${addon}/lib:${addon}/usr/lib:${addon}/usr/lib/libproxy'
}

fn safe_root(path string) !string {
	if !path.starts_with('/') || path.contains_any('\x00\n\r:') || !os.is_dir(path) {
		return error('expected absolute existing root without colons: ' + path)
	}
	return os.real_path(path)
}

fn safe_relative(path string) bool {
	return path != '' && !path.starts_with('/') && !path.contains_any('\x00\n\r\\')
		&& !path.split('/').any(it in ['', '.', '..'])
}

fn protected_library_stat(info os.Stat, directory bool) bool {
	return info.uid == 0 && info.mode & 0o022 == 0
		&& if directory { info.get_filetype() == .directory }
			else { info.get_filetype() == .regular && info.nlink == 1 }
}

// Newly searched backend directories must be root protected, including their
// parents. Every backend entry must be a pinned regular file, never an alias.
fn validate_libproxy_directory(root string, references map[string]string) ! {
	for relative in ['', 'usr', 'usr/lib', 'usr/lib/libproxy'] {
		path := if relative == '' { root } else { root + '/' + relative }
		if relative == 'usr/lib/libproxy' && !os.exists(path) && !os.is_link(path) { return }
		if !protected_library_stat(os.lstat(path)!, true) {
			return error('libproxy search directory is not root protected: ' + path)
		}
	}
	for name in os.ls(root + '/usr/lib/libproxy')! {
		relative := 'usr/lib/libproxy/' + name
		path := root + '/' + relative
		if !safe_relative(name) || relative !in references
			|| !protected_library_stat(os.lstat(path)!, false) {
			return error('libproxy backend is not a pinned root-protected regular file: ' + path)
		}
		equal_hash(path, references[relative])!
	}
}

fn little16(bytes []u8, offset int) u16 {
	return u16(bytes[offset]) | u16(bytes[offset + 1]) << 8
}

fn little32(bytes []u8, offset int) u32 {
	return u32(little16(bytes, offset)) | u32(little16(bytes, offset + 2)) << 16
}

fn little64(bytes []u8, offset int) u64 {
	return u64(little32(bytes, offset)) | u64(little32(bytes, offset + 4)) << 32
}

// Xvfb invokes /usr/bin/xkbcomp without a loader. Verify an actual static
// executable, rather than trusting a filename or a build option.
fn static_aarch64(path string) !bool {
	bytes := os.read_bytes(path)!
	if bytes.len < 64 || bytes[..6] != [u8(127), `E`, `L`, `F`, 2, 1]
		|| little16(bytes, 18) != 183 || little16(bytes, 16) !in [2, 3] {
		return false
	}
	offset := little64(bytes, 32)
	stride := u64(little16(bytes, 54))
	count := u64(little16(bytes, 56))
	if stride < 56 || count == 0 || offset > u64(bytes.len)
		|| count > (u64(bytes.len) - offset) / stride {
		return false
	}
	mut executable := false
	for index in u64(0) .. count {
		position := int(offset + index * stride)
		kind := little32(bytes, position)
		if kind == 3 { return false }
		if kind == 1 && little32(bytes, position + 4) & 1 != 0 { executable = true }
	}
	return executable
}

fn validate_runtime(base string, references map[string]string) ! {
	for name, expected in references {
		if !safe_relative(name) { return error('unsafe runtime receipt path') }
		equal_hash(base + '/' + name, expected)!
	}
	for name in ['lib/ld-musl-aarch64.so.1', 'usr/libexec/webkitgtk-6.0/WebKitWebProcess',
		'usr/libexec/webkitgtk-6.0/WebKitNetworkProcess', 'usr/libexec/webkitgtk-6.0/WebKitGPUProcess',
		'usr/bin/mkfontscale', injected_bundle, libproxy_backend] {
		if name !in references {
			return error('runtime receipt does not pin ' + name)
		}
	}
}

fn validate(base string, addon string, executable string) !(string, string) {
	root := os.dir(addon)
	build_path := root + '/build.json'
	addon_path := root + '/addon-files.json'
	build := json2.decode[BuildPins](os.read_file(build_path)!)!
	files := json2.decode[map[string]string](os.read_file(addon_path)!)!
	validate_runtime(base, build.runtime_references)!
	validate_libproxy_directory(base, build.runtime_references)!
	validate_libproxy_directory(addon, files)!
	for name in ['usr/bin/Xvfb', 'usr/bin/xkbcomp'] {
		if name !in files { return error('addon receipt does not pin ' + name) }
		equal_hash(addon + '/' + name, files[name])!
	}
	equal_hash(executable, build.session_sha256)!
	equal_hash(os.dir(executable) + '/browser-probe', build.probe_sha256)!
	return hash(build_path)!, hash(addon_path)!
}

// GTK's Cairo renderer does not select WebKit's Skia image-buffer backend.
// Set these before WebKit initialization, including its initial preferences.
// The release's bundle override takes a directory, not a shared-library path.
fn cpu_webkit_environment(base string, inherited map[string]string) map[string]string {
	mut environment := inherited.clone()
	environment.delete('WEBKIT_FORCE_COMPOSITING_MODE')
	environment['WEBKIT_SKIA_ENABLE_CPU_RENDERING'] = '1'
	environment['WEBKIT_DISABLE_COMPOSITING_MODE'] = '1'
	environment['WEBKIT_DISABLE_DMABUF_RENDERER'] = '1'
	environment['WEBKIT_INJECTED_BUNDLE_PATH'] = os.dir(base + '/' + injected_bundle)
	return environment
}

// Aliases execute this static binary. The immutable receipt hashes inherited
// from the session bind every dispatch to its loader and original helper.
fn trampoline(name string) ! {
	base := safe_root(os.getenv('VINIX_BROWSER_BASE'))!
	addon := safe_root(os.getenv('VINIX_BROWSER_ADDON'))!
	build_path := os.dir(addon) + '/build.json'
	addon_path := os.dir(addon) + '/addon-files.json'
	equal_hash(build_path, os.getenv('VINIX_BROWSER_BUILD_SHA256'))!
	equal_hash(addon_path, os.getenv('VINIX_BROWSER_ADDON_SHA256'))!
	build := json2.decode[BuildPins](os.read_file(build_path)!)!
	files := json2.decode[map[string]string](os.read_file(addon_path)!)!
	validate_libproxy_directory(base, build.runtime_references)!
	validate_libproxy_directory(addon, files)!
	equal_hash('/proc/self/exe', build.session_sha256)!
	equal_hash(base + '/lib/ld-musl-aarch64.so.1', build.runtime_references['lib/ld-musl-aarch64.so.1'])!
	mut target := ''
	if name == 'xkbcomp' {
		target = addon + '/usr/bin/xkbcomp'
		equal_hash(target, files['usr/bin/xkbcomp'])!
	} else if name in webkit_helpers {
		relative := 'usr/libexec/webkitgtk-6.0/' + name
		target = base + '/' + relative
		equal_hash(target, build.runtime_references[relative])!
	} else {
		return error('unsupported helper name')
	}
	mut environment := []string{}
	for key, value in os.environ() {
		if name != 'xkbcomp' || !key.starts_with('VINIX_BROWSER_') {
			environment << '${key}=${value}'
		}
	}
	mut argv := ['--library-path', library_path(base, addon), target]
	argv << os.args[1..]
	os.execve(base + '/lib/ld-musl-aarch64.so.1', argv, environment)!
}

fn authority_record(display string, cookie []u8) []u8 {
	mut bytes := [u8(255), 255, 0, 0, 0, u8(display.len)]
	bytes << display.bytes()
	bytes << [u8(0), 18]
	bytes << 'MIT-MAGIC-COOKIE-1'.bytes()
	bytes << [u8(0), 16]
	bytes << cookie
	return bytes
}

fn authority(path string, display string, cookie []u8) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('could not exclusively create private Xauthority') }
	defer { C.close(fd) }
	bytes := authority_record(display, cookie)
	mut used := 0
	for used < bytes.len {
		n := unsafe { C.write(fd, &u8(bytes.data) + used, uint(bytes.len - used)) }
		if n <= 0 { return error('could not write Xauthority') }
		used += int(n)
	}
}

fn setup_packet(cookie []u8) []u8 {
	mut bytes := [u8(`l`), 0, 11, 0, 0, 0, 18, 0, u8(cookie.len), 0, 0, 0]
	bytes << 'MIT-MAGIC-COOKIE-1'.bytes()
	bytes << [u8(0), 0]
	bytes << cookie
	return bytes
}

// Check the actual wire setup handshake. Socket existence cannot establish
// readiness or authentication; a deliberately wrong cookie must also fail.
fn authenticated(display string, cookie []u8) !bool {
	mut connection := unix.connect_stream('/tmp/.X11-unix/X' + display)!
	defer { connection.close() or {} }
	net.set_blocking(connection.sock.handle, false)!
	connection.set_read_timeout(250 * time.millisecond)
	connection.set_write_timeout(250 * time.millisecond)
	connection.write(setup_packet(cookie))!
	mut header := []u8{len: 8}
	mut used := 0
	for used < header.len {
		mut remaining := unsafe { header[used..] }
		n := connection.read(mut remaining)!
		if n == 0 { return error('X11 setup response ended early') }
		used += n
	}
	if header[0] == 0 { return false }
	if header[0] != 1 || little16(header, 2) != 11 { return error('invalid X11 setup response') }
	return true
}

fn x11_read_exact(mut connection unix.StreamConn, length int) ![]u8 {
	if length < 0 || length > 256 * 1024 { return error('X11 response exceeds fixed bound') }
	mut bytes := []u8{len: length}
	mut used := 0
	for used < bytes.len {
		mut remaining := unsafe { bytes[used..] }
		n := connection.read(mut remaining)!
		if n == 0 { return error('X11 response ended early') }
		used += n
	}
	return bytes
}

fn glx_query() []u8 {
	// QueryExtension, sequence 1, with the padded three-byte extension name.
	return [u8(98), 0, 3, 0, 3, 0, 0, 0, `G`, `L`, `X`, 0]
}

fn glx_absent_reply(reply []u8) ! {
	if reply.len != 32 || reply[0] != 1 || little16(reply, 2) != 1
		|| little32(reply, 4) != 0 || reply[8] != 0 {
		return error('X11 GLX extension is present or its absence was not established')
	}
}

fn require_glx_absent(display string, cookie []u8) ! {
	mut connection := unix.connect_stream('/tmp/.X11-unix/X' + display)!
	defer { connection.close() or {} }
	net.set_blocking(connection.sock.handle, false)!
	connection.set_read_timeout(250 * time.millisecond)
	connection.set_write_timeout(250 * time.millisecond)
	setup := setup_packet(cookie)
	if connection.write(setup)! != setup.len { return error('partial X11 setup request') }
	header := x11_read_exact(mut connection, 8)!
	if header[0] != 1 || little16(header, 2) != 11 {
		return error('GLX query requires authenticated X11 setup')
	}
	x11_read_exact(mut connection, int(little16(header, 6)) * 4)!
	query := glx_query()
	if connection.write(query)! != query.len { return error('partial X11 GLX query') }
	glx_absent_reply(x11_read_exact(mut connection, 32)!)!
}

fn xvfb_arguments(addon string, display string, output string, base string) []string {
	// This CPU-rendered local fixture must not dlopen the guest's older Mesa
	// DRI stack into its separately pinned Mesa/LLVM runtime.
	return [addon + '/usr/bin/Xvfb', ':' + display,
		'-screen', '0', '800x600x24', '-auth', output + '/Xauthority', '-nolisten', 'tcp', '-noreset',
		'-extension', 'GLX', '-xkbdir', base + '/usr/share/X11/xkb', '-fp', output + '/fonts']
}

fn choose_display() !string {
	for number in 120 .. 240 {
		value := number.str()
		if !os.exists('/tmp/.X11-unix/X' + value) && !os.is_link('/tmp/.X11-unix/X' + value)
			&& !os.exists('/tmp/.X' + value + '-lock') && !os.is_link('/tmp/.X' + value + '-lock') {
			return value
		}
	}
	return error('no unused diagnostic display in :120 through :239')
}

fn child(loader string, arguments []string, environment map[string]string) &os.Process {
	mut process := os.new_process(loader)
	process.use_pgroup = true
	process.set_args(arguments)
	process.set_environment(environment)
	process.set_stdin_path('/dev/null')
	process.set_redirect_stdio_merged()
	process.run()
	return process
}

fn drain(mut process os.Process, mut log os.File) ! {
	// A noisy child must not hide deadlines: read at most one block per turn.
	text := process.stdout_read()
	if text != '' { log.write_string(text)! }
}

fn stop(mut process os.Process, mut log os.File) {
	if process.status == .closed { return }
	if process.is_alive() {
		C.kill(-process.pid, 15)
		deadline := time.sys_mono_now() + u64(time.second)
		for process.is_alive() && time.sys_mono_now() < deadline {
			drain(mut process, mut log) or {}
			time.sleep(10 * time.millisecond)
		}
	}
	// Descendants may still hold our group after the leader has exited.
	if process.pid > 0 { C.kill(-process.pid, 9) }
	process.wait()
	for _ in 0 .. 64 {
		text := process.stdout_read()
		if text == '' { break }
		log.write_string(text) or {}
	}
	process.close()
}

fn fault_environment(root string, build BuildPins, environment map[string]string) !map[string]string {
	mut result := environment.clone()
	if build.fault_probe_build_sha256 == '' {
		if build.fault_probe_shim_sha256 != '' || build.fault_probe_fixture_sha256 != ''
			|| build.fault_probe_files_sha256.len != 0 {
			return error('incomplete fault diagnostic pins')
		}
		return result
	}
	if os.lstat(root)!.get_filetype() != .directory {
		return error('fault diagnostic root must be a real directory')
	}
	for path, expected in build.fault_probe_files_sha256 {
		if !safe_relative(path) { return error('unsafe fault diagnostic receipt path') }
		mut parent := os.dir(path)
		for parent != '.' {
			if os.lstat(root + '/' + parent)!.get_filetype() != .directory {
				return error('fault diagnostic parent must be a real directory')
			}
			parent = os.dir(parent)
		}
		st := os.lstat(root + '/' + path)!
		if st.get_filetype() != .regular { return error('fault diagnostic file must be regular') }
		equal_hash(root + '/' + path, expected)!
	}
	for path, expected in {
		'build.json': build.fault_probe_build_sha256
		'libx11-fault-probe.so': build.fault_probe_shim_sha256
		'known-fault': build.fault_probe_fixture_sha256
	} {
		if build.fault_probe_files_sha256[path] != expected || expected.len != 64 {
			return error('missing fault diagnostic file pin: ' + path)
		}
	}
	return result
}

fn fault_loader_arguments(root string, build BuildPins) []string {
	return if build.fault_probe_build_sha256 == '' { []string{} } else {
		['--preload', root + '/libx11-fault-probe.so']
	}
}

fn fault_number(line string, key string) !u64 {
	if !line.contains(key + '=0x') { return error('missing fault field: ' + key) }
	return strconv.parse_uint(line.all_after(key + '=0x').all_before(' ').trim_space(), 16, 64)
}

fn known_fault_evidence(raw string) ! {
	text := raw.replace('\r\n', '\n')
	lines := text.split_into_lines()
	expected := lines.filter(it.starts_with('X11-KNOWN-FAULT-EXPECTED '))
	fault := lines.filter(it.starts_with('X11-FAULT '))
	registers := lines.filter(it.starts_with('X11-REGS '))
	if expected.len != 1 || fault.len != 1 || registers.len != 1 {
		return error('one complete controlled fault required')
	}
	if fault_number(expected[0], 'address')! == 0
		|| fault_number(fault[0], 'address')! != fault_number(expected[0], 'address')!
		|| fault_number(fault[0], 'signal')! != 11 || fault_number(fault[0], 'code')! != 2
		|| fault_number(fault[0], 'pc')! == 0 || fault_number(fault[0], 'sp')! == 0 {
		return error('controlled fault context mismatch')
	}
	for index in 0 .. 31 { _ := fault_number(registers[0], 'x${index:02}')! }
	if fault_number(registers[0], 'x30')! == 0 { return error('controlled fault link register missing') }
	for marker in ['X11-KNOWN-FAULT-CHAINED', 'X11-MAPS-BEGIN', 'X11-MAPS-END',
		'X11-KNOWN-FAULT-PASS query=preserved restoration=preserved chain=preserved'] {
		if !lines.contains(marker) { return error('missing controlled fault marker: ' + marker) }
	}
}

fn known_fault_log(mut log os.File, path string) ! {
	// The child can exit with its final marker still in the parent's stdio
	// buffer. Validate the complete stream before the deferred close runs.
	log.flush()
	known_fault_evidence(os.read_file(path)!)!
}

fn fault_preflight(loader string, libraries string, root string, output string, environment map[string]string) ! {
	mut log := os.open_file(output + '/x11-known-fault.log', 'w', 0o600)!
	defer { log.close() }
	fixture_arguments := ['--library-path', libraries, '--preload', root + '/libx11-fault-probe.so', root + '/known-fault']
	mut fixture := child(loader, fixture_arguments, environment)
	defer { stop(mut fixture, mut log) }
	deadline := time.sys_mono_now() + u64(10 * time.second)
	for fixture.is_alive() {
		drain(mut fixture, mut log)!
		if time.sys_mono_now() >= deadline { return error('fault diagnostic preflight exceeded watchdog') }
		time.sleep(10 * time.millisecond)
	}
	stop(mut fixture, mut log)
	if fixture.code != 0 { return error('fault diagnostic preflight failed; see x11-known-fault.log') }
	known_fault_log(mut log, output + '/x11-known-fault.log')!
}

fn remove_aliases(paths []string, directories []string, executable string, mut events os.File) ! {
	mut failures := []string{}
	for path in paths.reverse() {
		if (os.readlink(path) or { '' }) == executable {
			os.rm(path) or { failures << 'unlink ' + path }
			if !os.exists(path) && !os.is_link(path) {
				events.write_string('helper-removed ' + path + '\n')!
			} else {
				failures << 'helper remains ' + path
			}
		} else {
			failures << 'helper target changed ' + path
		}
	}
	for directory in directories.reverse() {
		// Never recurse over new data from another process.
		if C.rmdir(directory.str) != 0 { failures << 'rmdir ' + directory }
	}
	if failures.len > 0 { return error('helper cleanup failed: ' + failures.join('; ')) }
}

// Only a specifically pinned original helper may be reused. It stays in place
// throughout the session and never enters the list of aliases we remove.
fn helper(path string, executable string, expected string, mut events os.File) !bool {
	if os.exists(path) || os.is_link(path) {
		stat := os.lstat(path)!
		if stat.mode & 0o170000 != 0o100000 || stat.mode & 0o111 == 0
			|| expected.len != 64 || hash(path)! != expected {
			return error('refusing unqualified existing guest helper ' + path)
		}
		events.write_string('helper-reused ' + path + ' sha256=' + expected + '\n')!
		return false
	}
	if C.symlink(executable.str, path.str) != 0 {
		return error('refusing to replace existing guest helper ' + path)
	}
	events.write_string('helper-created ' + path + ' -> ' + executable + ' argv=explicit-musl-loader,pinned-original,inherited-arguments\n')!
	return true
}

fn preserved_helpers(paths map[string]string, mut events os.File) ! {
	for path, expected in paths {
		stat := os.lstat(path)!
		if stat.mode & 0o170000 != 0o100000 { return error('reused guest helper type changed') }
		equal_hash(path, expected)!
		events.write_string('helper-preserved ' + path + ' sha256=' + expected + '\n')!
	}
}

fn xml_text(value string) string {
	return value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;').replace("'", '&apos;')
}

fn fonts(base string, addon string, output string, environment map[string]string, mut events os.File) !string {
	directory := output + '/fonts'
	if unsafe { C.mkdir(directory.str, 0o700) } != 0 {
		return error('cannot create private font tree')
	}
	manifest := json2.decode[map[string]string](os.read_file(os.dir(addon) + '/addon-files.json')!)!
	mut count := 0
	for name in os.ls(addon + '/usr/share/fonts/misc')! {
		if !name.ends_with('.pcf.gz') && name != 'fonts.alias' { continue }
		relative := 'usr/share/fonts/misc/' + name
		equal_hash(addon + '/' + relative, manifest[relative])!
		os.symlink(addon + '/' + relative, directory + '/' + name)!
		count++
	}
	if count < 2 { return error('pinned bitmap font payload is missing') }
	mut compiler := child(base + '/lib/ld-musl-aarch64.so.1', ['--library-path',
		library_path(base, addon), base + '/usr/bin/mkfontscale', '-b', '-s', '-l', directory], environment)
	defer { stop(mut compiler, mut events) }
	deadline := time.sys_mono_now() + u64(30 * time.second)
	for compiler.is_alive() {
		drain(mut compiler, mut events)!
		if time.sys_mono_now() >= deadline { return error('font index generation timed out') }
		time.sleep(10 * time.millisecond)
	}
	stop(mut compiler, mut events)
	if compiler.code != 0 { return error('font index generator failed') }
	index_hash := hash(directory + '/fonts.dir')!
	events.write_string('fonts-derived source=pinned-addon tool=pinned-mkfontscale argv=-b,-s,-l fonts.dir-sha256=' + index_hash + '\n')!
	return index_hash
}

fn run(base_arg string, addon_arg string, output_arg string) ! {
	$if !linux {
		return error('browser session may only run in the Linux guest')
	}
	base := safe_root(base_arg)!
	addon := safe_root(addon_arg)!
	executable := os.real_path('/proc/self/exe')
	if !static_aarch64(executable)! {
		return error('session trampoline must be static ELF64/AArch64')
	}
	build_hash, addon_hash := validate(base, addon, executable)!
	build := json2.decode[BuildPins](os.read_file(os.dir(addon) + '/build.json')!)!
	if !output_arg.starts_with('/') || output_arg.contains_any('\x00\n\r') {
		return error('output must be an absolute fresh directory')
	}
	parent := safe_root(os.dir(output_arg))!
	leaf := os.file_name(output_arg)
	if leaf in ['', '.', '..'] { return error('invalid output directory name') }
	output := parent + '/' + leaf
	if unsafe { C.mkdir(output.str, 0o700) } != 0 {
		return error('output directory must not already exist')
	}
	mut events := os.open_file(output + '/session.log', 'w', 0o600)!
	defer { events.close() }
	mut receipt := {
		'base_root':             base
		'addon_root':            addon
		'build_sha256':          build_hash
		'addon_files_sha256':    addon_hash
		'started_utc':           time.utc().str()
		'helper_created':        'false'
		'helper_removed':        'false'
		'helper_preserved':      'false'
		'authenticated_x11':     'false'
		'wrong_cookie_rejected': 'false'
		'x11_glx_policy':        'disabled-for-cpu-rendered-local-diagnostic'
		'x11_glx_absent':        'false'
		'probe_result':          'incomplete'
		'scope':                 'Separate real-engine diagnostic; no Android integration or Google authentication proof.'
	}
	defer {
		receipt['finished_utc'] = time.utc().str()
		os.write_file(output + '/session.json', json2.encode(receipt,
			prettify:       true
			legacy_layout:  true
			escape_unicode: true
			time_as_unix:   true
		) + '\n') or {}
	}
	if !os.is_dir('/usr/bin') || !os.exists('/bin/sh') {
		return error('Xvfb requires guest /usr/bin and /bin/sh')
	}
	mut owned_aliases := []string{}
	mut owned_directories := []string{}
	mut reused_helpers := map[string]string{}
	defer {
		mut removed := true
		remove_aliases(owned_aliases, owned_directories, executable, mut events) or {
			removed = false
			eprintln(err.msg())
		}
		receipt['helper_removed'] = removed.str()
		mut preserved := true
		preserved_helpers(reused_helpers, mut events) or {
			preserved = false
			eprintln(err.msg())
		}
		receipt['helper_preserved'] = preserved.str()
	}
	if !os.exists('/usr/libexec') && !os.is_link('/usr/libexec') {
		if unsafe { C.mkdir(c'/usr/libexec', 0o755) } != 0 {
			return error('cannot create guest libexec parent')
		}
		owned_directories << '/usr/libexec'
	}
	if !os.is_dir('/usr/libexec') || os.is_link('/usr/libexec') {
		return error('guest libexec parent must be a real directory')
	}
	if unsafe { C.mkdir(c'/usr/libexec/webkitgtk-6.0', 0o700) } != 0 {
		return error('refusing existing guest WebKit helper directory')
	}
	owned_directories << '/usr/libexec/webkitgtk-6.0'
	mut aliases := ['/usr/bin/xkbcomp']
	for name in webkit_helpers { aliases << '/usr/libexec/webkitgtk-6.0/' + name }
	for path in aliases {
		mut expected := ''
		if path == '/usr/bin/xkbcomp' && (os.exists(path) || os.is_link(path)) {
			// This original helper is dynamically linked through the original
			// guest musl interpreter. Pin that interpreter before executing it.
			preserved_helpers({'/lib/ld-musl-aarch64.so.1': build.guest_helper_references['/lib/ld-musl-aarch64.so.1']}, mut events)!
			expected = build.guest_helper_references[path]
			reused_helpers['/lib/ld-musl-aarch64.so.1'] = build.guest_helper_references['/lib/ld-musl-aarch64.so.1']
		}
		if helper(path, executable, expected, mut events)! {
			owned_aliases << path
		} else {
			reused_helpers[path] = expected
		}
	}
	receipt['helper_created'] = 'true'
	receipt['helper_aliases'] = owned_aliases.join(',')
	receipt['helper_reused'] = reused_helpers.keys().join(',')
	display := choose_display()!
	receipt['display'] = ':' + display
	mut cookie := rand.bytes(16)!
	defer {
		for index in 0 .. cookie.len { cookie[index] = 0 }
	}
	authority(output + '/Xauthority', display, cookie)!
	for name in ['xdg-runtime', 'cache', 'config', 'data', 'results'] {
		if unsafe { C.mkdir((output + '/' + name).str, 0o700) } != 0 {
			return error('cannot create private directory')
		}
	}
	loader := base + '/lib/ld-musl-aarch64.so.1'
	libraries := library_path(base, addon)
	receipt['library_path'] = libraries
	receipt['libproxy_backend_path'] = base + '/' + libproxy_backend
	receipt['libproxy_backend_sha256'] = build.runtime_references[libproxy_backend]
	mut environment := cpu_webkit_environment(base, os.environ())
	for key in ['WAYLAND_DISPLAY', 'DBUS_SESSION_BUS_ADDRESS', 'DBUS_STARTER_ADDRESS', 'GTK_MODULES',
		'GTK_PATH', 'LD_PRELOAD'] {
		environment.delete(key)
	}
	environment['DISPLAY'] = ':' + display
	environment['XAUTHORITY'] = output + '/Xauthority'
	environment['LD_LIBRARY_PATH'] = libraries
	environment['PATH'] = addon + '/usr/bin:' + base + '/usr/bin:/usr/bin:/bin'
	environment['XDG_RUNTIME_DIR'] = output + '/xdg-runtime'
	environment['XDG_CACHE_HOME'] = output + '/cache'
	environment['XDG_CONFIG_HOME'] = output + '/config'
	environment['XDG_DATA_HOME'] = output + '/data'
	environment['XDG_DATA_DIRS'] = base + '/usr/share:' + addon + '/usr/share'
	environment['GIO_MODULE_DIR'] = base + '/usr/lib/gio/modules'
	environment['GDK_BACKEND'] = 'x11'
	environment['GSK_RENDERER'] = 'cairo'
	environment['GSETTINGS_BACKEND'] = 'memory'
	environment['LIBGL_ALWAYS_SOFTWARE'] = '1'
	environment['GALLIUM_DRIVER'] = 'softpipe'
	// This fixture loads only its credential-free local document; Vinix lacks
	// bubblewrap's Linux namespace sandbox. Never use this mode for accounts.
	environment['WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS'] = '1'
	receipt['webkit_sandbox'] = 'disabled-for-credential-free-local-diagnostic'
	receipt['webkit_skia_renderer'] = 'cpu'
	receipt['webkit_compositing_policy'] = 'disabled-for-cpu-rendered-local-diagnostic'
	receipt['webkit_dmabuf_renderer_policy'] = 'disabled-for-cpu-rendered-local-diagnostic'
	receipt['webkit_injected_bundle_path'] = environment['WEBKIT_INJECTED_BUNDLE_PATH']
	receipt['webkit_injected_bundle_sha256'] = build.runtime_references[injected_bundle]
	environment['VINIX_BROWSER_BASE'] = base
	environment['VINIX_BROWSER_ADDON'] = addon
	environment['VINIX_BROWSER_BUILD_SHA256'] = build_hash
	environment['VINIX_BROWSER_ADDON_SHA256'] = addon_hash
	receipt['fonts_dir_sha256'] = fonts(base, addon, output, environment, mut events)!
	os.write_file(output + '/fonts.conf', '<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig><dir>' +
		xml_text(base + '/usr/share/fonts') + '</dir><dir>' + xml_text(output + '/fonts') +
		'</dir><cachedir>' + xml_text(output + '/cache/fontconfig') + '</cachedir></fontconfig>\n')!
	environment['FONTCONFIG_FILE'] = output + '/fonts.conf'
	environment['FONTCONFIG_PATH'] = output
	fault_root := os.dir(addon) + '/fault-probe'
	x_environment := fault_environment(fault_root, build, environment)!
	if build.fault_probe_build_sha256 != '' {
		receipt['x11_fault_build_sha256'] = build.fault_probe_build_sha256
		receipt['x11_fault_shim_sha256'] = build.fault_probe_shim_sha256
		receipt['x11_fault_fixture_sha256'] = build.fault_probe_fixture_sha256
		receipt['x11_fault_preload_scope'] = 'musl-loader-argument-only:known-fault,xvfb'
		receipt['x11_fault_preflight'] = 'incomplete'
		fault_preflight(loader, libraries, fault_root, output, x_environment)!
		receipt['x11_fault_preflight'] = 'pass'
	}
	mut xlog := os.open_file(output + '/xvfb.log', 'w', 0o600)!
	defer { xlog.close() }
	mut x_arguments := ['--library-path', libraries]
	x_arguments << fault_loader_arguments(fault_root, build)
	x_arguments << xvfb_arguments(addon, display, output, base)
	mut server := child(loader, x_arguments, x_environment)
	defer { stop(mut server, mut xlog) }
	deadline := time.sys_mono_now() + u64(30 * time.second)
	mut ready := false
	for time.sys_mono_now() < deadline {
		drain(mut server, mut xlog)!
		if !server.is_alive() { return error('Xvfb exited before readiness; see xvfb.log') }
		ready = authenticated(display, cookie) or { false }
		if ready { break }
		time.sleep(50 * time.millisecond)
	}
	if !ready { return error('Xvfb authentication did not become ready within 30 seconds') }
	receipt['authenticated_x11'] = 'true'
	mut wrong := cookie.clone()
	wrong[0] ^= 255
	if authenticated(display, wrong)! { return error('Xvfb admitted an invalid cookie') }
	receipt['wrong_cookie_rejected'] = 'true'
	require_glx_absent(display, cookie)!
	receipt['x11_glx_absent'] = 'true'
	events.write_string('X11-GLX-ABSENT PASS authenticated QueryExtension GLX\n')!
	mut plog := os.open_file(output + '/probe.log', 'w', 0o600)!
	defer { plog.close() }
	mut probe := child(loader, ['--library-path', libraries, os.dir(executable) + '/browser-probe',
		output + '/results'], environment)
	defer { stop(mut probe, mut plog) }
	probe_deadline := time.sys_mono_now() + u64(120 * time.second)
	for probe.is_alive() {
		drain(mut probe, mut plog)!
		drain(mut server, mut xlog)!
		if !server.is_alive() { return error('Xvfb exited during browser probe') }
		if time.sys_mono_now() >= probe_deadline {
			receipt['probe_result'] = 'timeout'
			return error('browser probe exceeded 120-second process watchdog')
		}
		time.sleep(10 * time.millisecond)
	}
	stop(mut probe, mut plog)
	if probe.code != 0 {
		receipt['probe_result'] = 'exit-' + probe.code.str()
		return error('browser probe failed; see probe.log')
	}
	if !os.read_file(output + '/probe.log')!.contains('BROWSER-PROBE PASS ') {
		return error('browser probe exited without its success marker')
	}
	receipt['png_sha256'] = hash(output + '/results/webkit-javascript-cookies.png')!
	stop(mut server, mut xlog)
	remove_aliases(owned_aliases, owned_directories, executable, mut events)!
	owned_aliases.clear()
	owned_directories.clear()
	preserved_helpers(reused_helpers, mut events)!
	receipt['helper_preserved'] = 'true'
	receipt['helper_removed'] = 'true'
	receipt['probe_result'] = 'pass'
	println('BROWSER-SESSION PASS output=' + output)
}

fn self_test() ! {
	assert library_path('/base', '/addon') == '/base/lib:/base/usr/lib:/base/usr/lib/libproxy:/addon/lib:/addon/usr/lib:/addon/usr/lib/libproxy'
	assert protected_library_stat(os.Stat{ mode: u32(C.S_IFDIR) | 0o755, uid: 0 }, true)
	assert protected_library_stat(os.Stat{ mode: u32(C.S_IFREG) | 0o644, uid: 0, nlink: 1 }, false)
	for mode in [u32(0o775), u32(0o777)] {
		assert !protected_library_stat(os.Stat{ mode: u32(C.S_IFDIR) | mode, uid: 0 }, true)
	}
	assert !protected_library_stat(os.Stat{ mode: u32(C.S_IFDIR) | 0o755, uid: 1000 }, true)
	assert !protected_library_stat(os.Stat{ mode: u32(C.S_IFLNK) | 0o755, uid: 0 }, true)
	assert !protected_library_stat(os.Stat{ mode: u32(C.S_IFREG) | 0o644, uid: 0, nlink: 2 }, false)
	assert !protected_library_stat(os.Stat{ mode: u32(C.S_IFREG) | 0o666, uid: 0, nlink: 1 }, false)
	assert glx_query() == [u8(98), 0, 3, 0, 3, 0, 0, 0, `G`, `L`, `X`, 0]
	mut absent := []u8{len: 32}
	absent[0] = 1
	absent[2] = 1
	glx_absent_reply(absent)!
	for offset in [0, 2, 4, 8] {
		mut bad := absent.clone()
		bad[offset] = if offset in [0, 2] { u8(0) } else { u8(1) }
		if _ := glx_absent_reply(bad) { return error('unqualified GLX absence accepted') }
	}
	if _ := glx_absent_reply(absent[..31]) { return error('short GLX response accepted') }
	xargs := xvfb_arguments('/addon', '120', '/out', '/base')
	assert xargs == ['/addon/usr/bin/Xvfb', ':120', '-screen', '0', '800x600x24',
		'-auth', '/out/Xauthority', '-nolisten', 'tcp', '-noreset', '-extension', 'GLX',
		'-xkbdir', '/base/usr/share/X11/xkb', '-fp', '/out/fonts']
	cookie := []u8{len: 16, init: u8(index)}
	record := authority_record('120', cookie)
	if record.len != 47 || record[..9] != [u8(255), 255, 0, 0, 0, 3, `1`, `2`, `0`]
		|| record[11..29].bytestr() != 'MIT-MAGIC-COOKIE-1' || record[31..] != cookie {
		return error('Xauthority record regression')
	}
	packet := setup_packet(cookie)
	if packet.len != 48 || little16(packet, 2) != 11 || little16(packet, 6) != 18
		|| little16(packet, 8) != 16 || packet[12..30].bytestr() != 'MIT-MAGIC-COOKIE-1'
		|| packet[32..] != cookie {
		return error('X11 setup packet regression')
	}
	for bad in ['', '/bin', '../bin', 'usr/../bin', 'usr//bin', 'usr/./bin', 'usr\\bin'] {
		if safe_relative(bad) { return error('unsafe receipt path admitted') }
	}
	if !safe_relative('usr/bin/xkbcomp') { return error('safe receipt path rejected') }
	root := os.join_path(os.temp_dir(), 'vinix-browser-helper-selftest-' + os.getpid().str())
	if os.exists(root) || os.is_link(root) { return error('selftest directory already exists') }
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	mut runtime_pins := map[string]string{}
	for name in ['lib/ld-musl-aarch64.so.1', 'usr/libexec/webkitgtk-6.0/WebKitWebProcess',
		'usr/libexec/webkitgtk-6.0/WebKitNetworkProcess', 'usr/libexec/webkitgtk-6.0/WebKitGPUProcess',
		'usr/bin/mkfontscale', injected_bundle, libproxy_backend] {
		os.mkdir_all(os.dir(root + '/' + name))!
		os.write_file(root + '/' + name, 'fixture-' + name)!
		runtime_pins[name] = hash(root + '/' + name)!
	}
	validate_runtime(root, runtime_pins)!
	mut missing_backend := runtime_pins.clone()
	missing_backend.delete(libproxy_backend)
	if _ := validate_runtime(root, missing_backend) { return error('unpinned libproxy backend accepted') }
	os.write_file(root + '/' + libproxy_backend, 'changed-backend')!
	if _ := validate_runtime(root, runtime_pins) { return error('changed libproxy backend accepted') }
	os.rm(root + '/' + libproxy_backend)!
	if _ := validate_runtime(root, runtime_pins) { return error('missing libproxy backend accepted') }
	os.write_file(root + '/' + libproxy_backend, 'fixture-' + libproxy_backend)!
	validate_runtime(root, runtime_pins)!
	mut missing_bundle := runtime_pins.clone()
	missing_bundle.delete(injected_bundle)
	if _ := validate_runtime(root, missing_bundle) { return error('unpinned injected bundle accepted') }
	os.write_file(root + '/' + injected_bundle, 'changed-bundle')!
	if _ := validate_runtime(root, runtime_pins) { return error('changed injected bundle accepted') }
	os.rm(root + '/' + injected_bundle)!
	if _ := validate_runtime(root, runtime_pins) { return error('missing injected bundle accepted') }
	inherited := {'WEBKIT_SKIA_ENABLE_CPU_RENDERING': '0',
		'WEBKIT_DISABLE_COMPOSITING_MODE': '0', 'WEBKIT_FORCE_COMPOSITING_MODE': '1',
		'WEBKIT_DISABLE_DMABUF_RENDERER': '0',
		'WEBKIT_INJECTED_BUNDLE_PATH': '/foreign/bundle', 'DISPLAY': ':120'}
	webkit_env := cpu_webkit_environment(root, inherited)
	assert webkit_env['WEBKIT_SKIA_ENABLE_CPU_RENDERING'] == '1'
	assert webkit_env['WEBKIT_DISABLE_COMPOSITING_MODE'] == '1'
	assert webkit_env['WEBKIT_DISABLE_DMABUF_RENDERER'] == '1'
	assert inherited['WEBKIT_DISABLE_DMABUF_RENDERER'] == '0'
	assert 'WEBKIT_FORCE_COMPOSITING_MODE' !in webkit_env
	assert webkit_env['WEBKIT_INJECTED_BUNDLE_PATH'] == os.dir(root + '/' + injected_bundle)
	assert webkit_env['DISPLAY'] == ':120' && inherited['WEBKIT_SKIA_ENABLE_CPU_RENDERING'] == '0'
	mut events := os.open_file(root + '/events', 'w', 0o600)!
	defer { events.close() }
	original := root + '/original'
	os.write_file(original, 'pinned-existing-helper')!
	os.chmod(original, 0o755)!
	pin := hash(original)!
	if helper(original, '/never-replace-original', pin, mut events)! {
		return error('existing helper was marked for removal')
	}
	assert os.read_file(original)! == 'pinned-existing-helper' && !os.is_link(original)
	preserved_helpers({original: pin}, mut events)!
	for expected in ['', '0'.repeat(64)] {
		if _ := helper(original, '/never-replace-original', expected, mut events) {
			return error('unqualified original helper accepted')
		}
	}
	alias := root + '/alias'
	if !helper(alias, original, '', mut events)! { return error('new alias not owned') }
	remove_aliases([alias], [], original, mut events)!
	assert !os.exists(alias) && !os.is_link(alias) && os.read_file(original)! == 'pinned-existing-helper'
	os.symlink(root + '/missing', alias)!
	if _ := helper(alias, original, pin, mut events) { return error('dangling helper link replaced') }
	assert os.readlink(alias)! == root + '/missing'
	os.write_file(original, 'changed')!
	if _ := preserved_helpers({original: pin}, mut events) { return error('changed original helper passed preservation') }
	clean_environment := {'DISPLAY': ':120'}
	assert fault_environment(root, BuildPins{}, clean_environment)! == clean_environment
	mut fault_files := map[string]string{}
	for name in ['build.json', 'libx11-fault-probe.so', 'known-fault'] {
		os.write_file(root + '/' + name, 'fixture-' + name)!
		fault_files[name] = hash(root + '/' + name)!
	}
	fault_pins := BuildPins{
		fault_probe_build_sha256: fault_files['build.json']
		fault_probe_shim_sha256: fault_files['libx11-fault-probe.so']
		fault_probe_fixture_sha256: fault_files['known-fault']
		fault_probe_files_sha256: fault_files
	}
	fault_env := fault_environment(root, fault_pins, clean_environment)!
	assert fault_env == clean_environment
	assert fault_loader_arguments(root, fault_pins) == ['--preload', root + '/libx11-fault-probe.so']
	assert fault_loader_arguments(root, BuildPins{}).len == 0
	assert 'LD_PRELOAD' !in clean_environment
	os.write_file(root + '/known-fault', 'tampered')!
	if _ := fault_environment(root, fault_pins, clean_environment) { return error('changed fault fixture accepted') }
	os.rm(root + '/known-fault')!
	os.symlink(original, root + '/known-fault')!
	if _ := fault_environment(root, fault_pins, clean_environment) { return error('linked fault fixture accepted') }
	if _ := fault_environment(root, BuildPins{fault_probe_shim_sha256: pin}, clean_environment) {
		return error('partial fault diagnostic pins accepted')
	}
	mut context := 'X11-KNOWN-FAULT-EXPECTED address=0x1234\nX11-FAULT signal=0xb code=0x2 address=0x1234 pc=0x5678 sp=0x9abc\nX11-REGS'
	for index in 0 .. 31 { context += ' x${index:02}=0x1' }
	context += '\nX11-MAPS-BEGIN\nX11-MAPS-END\nX11-KNOWN-FAULT-CHAINED\nX11-KNOWN-FAULT-PASS query=preserved restoration=preserved chain=preserved\n'
	known_fault_evidence(context)!
	mut context_log := os.open_file(root + '/controlled-fault.log', 'w', 0o600)!
	defer { context_log.close() }
	context_log.write_string(context)!
	known_fault_log(mut context_log, root + '/controlled-fault.log')!
	for bad in [context.replace('address=0x1234 pc=', 'address=0x1235 pc='),
		context.replace('signal=0xb', 'signal=0x6'), context.replace(' x29=0x1', ''),
		context.replace('x30=0x1', 'x30=0x0'), context + 'X11-FAULT signal=0xb\n',
		context.replace('X11-MAPS-END\n', '')] {
		if _ := known_fault_evidence(bad) { return error('incomplete or inconsistent fault evidence accepted') }
	}
	println('BROWSER-SESSION SELF-TEST PASS library-path libproxy-protection libproxy-pins libproxy-tamper libproxy-missing glx-arguments glx-wire-query glx-absence-negative authority-record x11-setup receipt-paths bundle-pins bundle-tamper bundle-missing cpu-renderer-environment dmabuf-renderer-environment pinned-reuse foreign-helper dangling-link owned-cleanup changed-helper fault-pins preload-isolation tamper link partial-pins complete-context buffered-context negative-context')
}

fn main() {
	name := os.file_name(os.args[0])
	if name == 'xkbcomp' || name in webkit_helpers {
		trampoline(name) or {
			eprintln('BROWSER-SESSION HELPER FAIL ' + err.msg())
			exit(1)
		}
		return
	}
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len != 4 {
		eprintln('usage: browser-session BASE_RUNTIME_ROOT ADDON_RUNTIME_ROOT FRESH_OUTPUT_DIRECTORY')
		exit(2)
	}
	run(os.args[1], os.args[2], os.args[3]) or {
		eprintln('BROWSER-SESSION FAIL ' + err.msg())
		exit(1)
	}
}
