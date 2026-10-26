// SPDX-License-Identifier: GPL-2.0-or-later
// Guest-only launcher for a separate, real GTK4/WebKit diagnostic session.
module main

import crypto.rand
import crypto.sha256
import json2
import net
import net.unix
import os
import time

#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>

const webkit_helpers = ['WebKitWebProcess', 'WebKitNetworkProcess', 'WebKitGPUProcess']

struct BuildPins {
	runtime_references map[string]string
	probe_sha256       string
	session_sha256     string
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
	return '${base}/lib:${base}/usr/lib:${addon}/lib:${addon}/usr/lib'
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

fn validate(base string, addon string, executable string) !(string, string) {
	root := os.dir(addon)
	build_path := root + '/build.json'
	addon_path := root + '/addon-files.json'
	build := json2.decode[BuildPins](os.read_file(build_path)!)!
	files := json2.decode[map[string]string](os.read_file(addon_path)!)!
	for name, expected in build.runtime_references {
		if !safe_relative(name) { return error('unsafe runtime receipt path') }
		equal_hash(base + '/' + name, expected)!
	}
	for name in ['lib/ld-musl-aarch64.so.1', 'usr/libexec/webkitgtk-6.0/WebKitWebProcess',
		'usr/libexec/webkitgtk-6.0/WebKitNetworkProcess', 'usr/libexec/webkitgtk-6.0/WebKitGPUProcess',
		'usr/bin/mkfontscale'] {
		if name !in build.runtime_references {
			return error('runtime receipt does not pin ' + name)
		}
	}
	for name in ['usr/bin/Xvfb', 'usr/bin/xkbcomp'] {
		if name !in files { return error('addon receipt does not pin ' + name) }
		equal_hash(addon + '/' + name, files[name])!
	}
	equal_hash(executable, build.session_sha256)!
	equal_hash(os.dir(executable) + '/browser-probe', build.probe_sha256)!
	return hash(build_path)!, hash(addon_path)!
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
	equal_hash('/proc/self/exe', build.session_sha256)!
	equal_hash(base + '/lib/ld-musl-aarch64.so.1', build.runtime_references['lib/ld-musl-aarch64.so.1'])!
	mut target := ''
	if name == 'xkbcomp' {
		files := json2.decode[map[string]string](os.read_file(addon_path)!)!
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
		'authenticated_x11':     'false'
		'wrong_cookie_rejected': 'false'
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
	defer {
		mut removed := true
		remove_aliases(owned_aliases, owned_directories, executable, mut events) or {
			removed = false
			eprintln(err.msg())
		}
		receipt['helper_removed'] = removed.str()
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
		// Atomic creation refuses any existing file, including dangling links.
		if C.symlink(executable.str, path.str) != 0 {
			return error('refusing to replace existing guest helper ' + path)
		}
		owned_aliases << path
		events.write_string('helper-created ' + path + ' -> ' + executable + ' argv=explicit-musl-loader,pinned-original,inherited-arguments\n')!
	}
	receipt['helper_created'] = 'true'
	receipt['helper_aliases'] = owned_aliases.join(',')
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
	mut environment := os.environ()
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
	environment['WEBKIT_DISABLE_DMABUF_RENDERER'] = '1'
	// This fixture loads only its credential-free local document; Vinix lacks
	// bubblewrap's Linux namespace sandbox. Never use this mode for accounts.
	environment['WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS'] = '1'
	receipt['webkit_sandbox'] = 'disabled-for-credential-free-local-diagnostic'
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
	mut xlog := os.open_file(output + '/xvfb.log', 'w', 0o600)!
	defer { xlog.close() }
	mut server := child(loader, ['--library-path', libraries, addon + '/usr/bin/Xvfb', ':' + display,
		'-screen', '0', '800x600x24', '-auth', output + '/Xauthority', '-nolisten', 'tcp', '-noreset',
		'-xkbdir', base + '/usr/share/X11/xkb', '-fp', output + '/fonts'], environment)
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
	receipt['helper_removed'] = 'true'
	receipt['probe_result'] = 'pass'
	println('BROWSER-SESSION PASS output=' + output)
}

fn self_test() ! {
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
	println('BROWSER-SESSION SELF-TEST PASS authority-record x11-setup receipt-paths')
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
