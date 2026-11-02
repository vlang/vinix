// SPDX-License-Identifier: GPL-2.0-or-later
// Capture a supplied application without replacing its resources or claiming game success.
module linuxcheck

import crypto.sha256
import json2
import macho
import os
import plist

#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.openat(int, &char, int, ...int) int
fn C.fstatat(int, &char, &C.stat, int) int
fn C.fdopendir(int) voidptr
fn C.read(int, voidptr, usize) isize

pub struct ProbeEntry {
pub:
	path   string
	kind   string
	mode   u32
	size   u64
	sha256 string
}

pub struct ProbeInput {
pub:
	bundle            string
	executable        string
	bundle_identifier string
	entries           []ProbeEntry
}

// The driver must build and qualify this runtime and its optional dependencies.
// Declared backend names describe that qualification; they cannot prove it.
pub struct ProbeRuntime {
pub:
	invocation        []string
	// Set by the maintained builder; empty for native protocol-control helpers.
	target_executable Arm64Executable
	arguments         []string
	environment       map[string]string
	profile           string
	built_backends    []string
	required_backends []string
	deadline_seconds  int = 600
	// Empty leaves direct execution available for non-UIKit diagnostics.
	// A captured driver with maybe_probe_desktop_child supplies the VAPP peer.
	desktop_driver     string
	desktop_startup_ms int
	desktop_reply_ms   int = 30000
	desktop_session_ms int = 10000
}

pub struct ProbeResult {
pub mut:
	capture_complete       bool
	inspection_exit        int = -1
	audit_exit             int = -1
	application_attempted  bool
	application_exit       int = -1
	wrapper_exit           int = -1
	desktop_enabled        bool
	desktop_handshake      bool
	desktop_forced         bool
	application_diagnostic bool
	failure                string
	qualification          string = 'Capture completion does not establish a game frame, menu, login, gameplay or launch gate.'
}

struct ProbeRuntimeReceipt {
	profile              string
	built_backends       []string
	required_backends    []string
	invocation           []string
	target_executable    Arm64Executable
	arguments            []string
	deadline_seconds     int
	output_limit         u64
	desktop_driver       string
	desktop_startup_ms   int
	desktop_reply_ms     int
	desktop_session_ms   int
	selected_environment map[string]string
	// The caller retains the build/dependency qualification; this is not a
	// complete shared-library or inherited-environment closure inventory.
	runtime_inputs []FileDigest
}

fn probe_stat(fd int) !C.stat {
	mut result := C.stat{}
	if C.fstat(fd, &result) != 0 { return os.error_posix() }
	return result
}

fn probe_same_stat(left C.stat, right C.stat) bool {
	return left.st_dev == right.st_dev && left.st_ino == right.st_ino
		&& left.st_mode == right.st_mode && left.st_size == right.st_size
		&& left.st_mtime == right.st_mtime && left.st_ctime == right.st_ctime
}

// Open every directory component without following symlinks, including the
// selected root's ancestors. Descriptor-relative traversal keeps aliases from
// redirecting a scan to an external tree between lstat and open.
fn probe_open_directory(path string) !int {
	if path == '' || path.contains('\x00') || !os.is_abs_path(path) {
		return error('probe directory must be an explicit absolute path')
	}
	mut fd := unsafe { C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC) }
	if fd < 0 { return os.error_posix() }
	for component in path.split('/') {
		if component == '' { continue }
		if component in ['.', '..'] {
			C.close(fd)
			return error('probe directory contains an unsafe component')
		}
		next := unsafe {
			C.openat(fd, component.str,
				C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
		}
		if next < 0 {
			failure := os.error_posix()
			C.close(fd)
			return error('probe directory is missing, inaccessible or contains a symlink: ${path}: ${failure}')
		}
		C.close(fd)
		fd = next
	}
	return fd
}

fn probe_directory_names(fd int) ![]string {
	duplicate := C.dup(fd)
	if duplicate < 0 { return os.error_posix() }
	stream := C.fdopendir(duplicate)
	if isnil(stream) {
		failure := os.error_posix()
		C.close(duplicate)
		return failure
	}
	mut names := []string{}
	for {
		C.errno = 0
		item := C.readdir(stream)
		if isnil(item) {
			number := C.errno
			closed := C.closedir(stream)
			if number != 0 { return error_with_code('cannot enumerate supplied app', number) }
			if closed != 0 { return os.error_posix() }
			break
		}
		name := unsafe { tos_clone(&u8(&item.d_name[0])) }
		if name !in ['.', '..'] { names << name }
	}
	names.sort()
	return names
}

fn probe_file_hash(fd int, before C.stat) !string {
	if before.st_mode & u32(C.S_IFMT) != u32(C.S_IFREG) || before.st_size < 0 {
		return error('probe input is not a regular file')
	}
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	mut count := u64(0)
	for {
		n := C.read(fd, buffer.data, usize(buffer.len))
		if n < 0 {
			if C.errno == C.EINTR { continue }
			return os.error_posix()
		}
		if n == 0 { break }
		count += u64(n)
		if count > u64(before.st_size) { return error('probe input grew during hashing') }
		hash.write(buffer[..int(n)])!
	}
	if count != u64(before.st_size) || !probe_same_stat(before, probe_stat(fd)!) {
		return error('probe input changed during hashing')
	}
	return hash.sum([]u8{}).hex()
}

fn probe_walk(fd int, relative string, mut entries []ProbeEntry) ! {
	before := probe_stat(fd)!
	entries << ProbeEntry{
		path: if relative == '' { '.' } else { relative }
		kind: 'directory'
		mode: before.st_mode & 0o7777
	}
	for name in probe_directory_names(fd)! {
		mut metadata := C.stat{}
		if unsafe { C.fstatat(fd, name.str, &metadata, C.AT_SYMLINK_NOFOLLOW) } != 0 {
			return os.error_posix()
		}
		kind := metadata.st_mode & u32(C.S_IFMT)
		path := if relative == '' { name } else { relative + '/' + name }
		if kind !in [u32(C.S_IFREG), u32(C.S_IFDIR)] {
			return error('supplied app contains a symlink or special entry: ${path}')
		}
		flags := C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC
		child := unsafe {
			C.openat(fd, name.str, flags | if kind == u32(C.S_IFDIR) {
				C.O_DIRECTORY
			} else {
				0
			})
		}
		if child < 0 { return os.error_posix() }
		probe_walk_child(child, metadata, path, mut entries) or {
			C.close(child)
			return err
		}
		C.close(child)
	}
	if !probe_same_stat(before, probe_stat(fd)!) {
		return error('supplied app directory changed during inventory: ${relative}')
	}
}

fn probe_walk_child(fd int, metadata C.stat, path string, mut entries []ProbeEntry) ! {
	if !probe_same_stat(metadata, probe_stat(fd)!) {
		return error('supplied app entry changed while opening: ${path}')
	}
	if metadata.st_mode & u32(C.S_IFMT) == u32(C.S_IFDIR) {
		probe_walk(fd, path, mut entries)!
	} else {
		entries << ProbeEntry{
			path:   path
			kind:   'file'
			mode:   metadata.st_mode & 0o7777
			size:   u64(metadata.st_size)
			sha256: probe_file_hash(fd, metadata)!
		}
	}
}

fn probe_snapshot(bundle string) ![]ProbeEntry {
	fd := probe_open_directory(bundle)!
	defer { C.close(fd) }
	mut entries := []ProbeEntry{}
	probe_walk(fd, '', mut entries)!
	entries.sort(a.path < b.path)
	return entries
}

fn probe_read_member(bundle string, name string, entries []ProbeEntry, limit u64) ![]u8 {
	mut expected := ProbeEntry{}
	for entry in entries {
		if entry.path == name {
			expected = entry
			break
		}
	}
	if expected.kind != 'file' || expected.size == 0 || expected.size > limit {
		return error('supplied app requires a nonempty regular ${name} within ${limit} bytes')
	}
	root := probe_open_directory(bundle)!
	defer { C.close(root) }
	fd := unsafe { C.openat(root, name.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC) }
	if fd < 0 { return os.error_posix() }
	defer { C.close(fd) }
	metadata := probe_stat(fd)!
	if metadata.st_mode & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| metadata.st_size < 0 || u64(metadata.st_size) != expected.size {
		return error('supplied app member changed before validation: ${name}')
	}
	mut data := []u8{len: int(expected.size)}
	mut offset := 0
	for offset < data.len {
		n := C.read(fd, unsafe { &data[offset] }, usize(data.len - offset))
		if n < 0 && C.errno == C.EINTR { continue }
		if n <= 0 {
			unsafe { data.free() }
			return error('cannot read supplied app member: ${name}')
		}
		offset += int(n)
	}
	after := probe_stat(fd) or {
		unsafe { data.free() }
		return err
	}
	if !probe_same_stat(metadata, after) || sha256.sum(data).hex() != expected.sha256 {
		unsafe { data.free() }
		return error('supplied app member changed during validation: ${name}')
	}
	return data
}

fn probe_free_image(image macho.Image) {
	for segment in image.segments {
		for section in segment.sections {
			unsafe { section.name.free() }
		}
		unsafe {
			segment.sections.free()
			segment.name.free()
		}
	}
	for library in image.libraries {
		unsafe { library.name.free() }
	}
	unsafe {
		image.data.free()
		image.segments.free()
		image.libraries.free()
		image.install_name.free()
		// The typed []string free releases each runpath and then the array.
		image.rpaths.free()
		image.routines.free()
		image.required_unknown.free()
	}
}

fn probe_require_members(bundle string, main string) ! {
	root := probe_open_directory(bundle)!
	defer { C.close(root) }
	// Reject an incorrect app selection before hashing its potentially large
	// cooked resources. The complete scan and validated reads still follow.
	for name in ['Info.plist', main] {
		mut metadata := C.stat{}
		if unsafe { C.fstatat(root, name.str, &metadata, C.AT_SYMLINK_NOFOLLOW) } != 0
			|| metadata.st_mode & u32(C.S_IFMT) != u32(C.S_IFREG) || metadata.st_size <= 0 {
			return error('supplied app requires a nonempty regular ${name}')
		}
	}
}

// No executable inference, resource replacement, IPA extraction or copying.
// A caller must retain the supplied original tree alongside its evidence.
pub fn probe_input(bundle string, executable string) !ProbeInput {
	if bundle == '' || executable == '' || bundle.contains('\x00') || executable.contains('\x00') {
		return error('probe requires an explicit app directory and main executable')
	}
	root := os.abs_path(bundle)
	main := if os.is_abs_path(executable) { executable } else { root + '/' + executable }
	if os.dir(main) != root || os.file_name(main) in ['', '.', '..'] {
		return error('probe main executable must be a direct child of the supplied app')
	}
	name := os.file_name(main)
	probe_require_members(root, name)!
	entries := probe_snapshot(root)!
	info_bytes := probe_read_member(root, 'Info.plist', entries, 16777216)!
	defer { unsafe { info_bytes.free() } }
	info := plist.parse(info_bytes)!
	defer { info.free() }
	if info.kind != .dictionary || info.fields['CFBundleExecutable'].kind != .string
		|| info.fields['CFBundleExecutable'].text != name {
		return error('Info.plist CFBundleExecutable does not match the supplied main executable')
	}
	bytes := probe_read_member(root, name, entries, 2147483647)!
	defer { unsafe { bytes.free() } }
	image := macho.parse(bytes)!
	defer { probe_free_image(image) }
	issues := image.execution_issues()
	if issues.len > 0 {
		return error('supplied app is not executable by this runtime: ' + issues.join('; '))
	}
	// Validate the entry/segment layout without running any application code.
	image.layout(4096)!
	return ProbeInput{
		bundle:            root
		executable:        main
		bundle_identifier: info.fields['CFBundleIdentifier'].text.clone()
		entries:           entries
	}
}

pub fn probe_input_from_environment() !ProbeInput {
	return probe_input(os.getenv('VINIX_IOS_APP_BUNDLE'), os.getenv('VINIX_IOS_APP_EXECUTABLE'))
}

fn probe_require_runtime(runtime ProbeRuntime) ! {
	if runtime.invocation.len == 0 || runtime.invocation.any(it == '' || it.contains('\x00'))
		|| runtime.arguments.any(it.contains('\x00')) || runtime.profile.trim_space() == ''
		|| runtime.deadline_seconds < 1 || runtime.deadline_seconds > 1800 {
		return error('probe requires an explicit runtime invocation/profile and a 1..1800 second deadline')
	}
	if runtime.built_backends.len == 0 || runtime.required_backends.len == 0 {
		return error('probe runtime must declare built and required optional backends')
	}
	for list in [runtime.built_backends, runtime.required_backends] {
		mut seen := map[string]bool{}
		for name in list {
			if name !in ['cxx', 'gles', 'video', 'text', 'sqlite'] || name in seen {
				return error('invalid or duplicate probe backend: ${name}')
			}
			seen[name] = true
		}
	}
	for name in runtime.required_backends {
		if name !in runtime.built_backends {
			return error('required probe backend was not built: ${name}')
		}
	}
	if runtime.target_executable.path != '' {
		if runtime.target_executable.path != runtime.invocation.last() {
			return error('probe target differs from its ARM64 executable baseline')
		}
		arm64_executable_unchanged(runtime.target_executable)!
	}
	if runtime.desktop_driver != '' { probe_desktop_config(runtime)! }
}

fn probe_runtime_inputs(runtime ProbeRuntime) ![]FileDigest {
	if runtime.target_executable.path != '' { arm64_executable_unchanged(runtime.target_executable)! }
	mut inputs := []FileDigest{}
	mut paths := [runtime.invocation[0], runtime.invocation.last()]
	if runtime.desktop_driver != '' { paths << runtime.desktop_driver }
	for argument in paths {
		path := os.real_path(os.find_abs_path_of_executable(argument)!)
		if inputs.any(it.path == path) { continue }
		inputs << probe_runtime_digest(path)!
	}
	return inputs
}

fn probe_runtime_digest(path string) !FileDigest {
	root := probe_open_directory(os.dir(path))!
	defer { C.close(root) }
	name := os.file_name(path)
	fd := unsafe { C.openat(root, name.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC) }
	if fd < 0 { return os.error_posix() }
	defer { C.close(fd) }
	return FileDigest{ path: path, sha256: probe_file_hash(fd, probe_stat(fd)!)! }
}

fn probe_commands(out string, input ProbeInput, runtime ProbeRuntime, env map[string]string,
	mut result ProbeResult) ! {
	mut command := runtime.invocation.clone()
	command << ['--inspect', input.executable]
	inspect_code, _ := probe_guarded_command(runtime, out, 'inspect', command, input.bundle, env)!
	result.inspection_exit = inspect_code
	if inspect_code != 0 { return error('probe inspection failed; application was not launched') }
	command = runtime.invocation.clone()
	command << ['--audit', input.executable]
	audit_code, _ := probe_guarded_command(runtime, out, 'audit', command, input.bundle, env)!
	result.audit_exit = audit_code
	// Audit remains strict, including SKAdNetwork. Missing imports are useful
	// diagnostic evidence and do not suppress the explicit no-ads launch.
	command = runtime.invocation.clone()
	command << ['--probe-no-ads', input.executable]
	command << runtime.arguments
	result.application_attempted = true
	mut output := ''
	if runtime.desktop_driver != '' {
		output = probe_desktop_application(out, input, runtime, command, env, mut result)!
	} else {
		app_code, captured := probe_guarded_command(runtime, out, 'application', command, input.bundle, env)!
		result.application_exit = app_code
		output = captured
	}
	result.application_diagnostic = output.contains('V panic:') || output.contains('ERROR: AddressSanitizer')
		|| output.contains('runtime error:') || output.contains('> assert ')
}

// out must be fresh and outside the supplied app. Every command has the
// existing process-group deadline, 16 MiB output cap and cleanup receipts.
// A nonzero application status is a captured observation, never a game PASS.
pub fn probe_capture(out string, input ProbeInput, runtime ProbeRuntime) !ProbeResult {
	probe_require_runtime(runtime)!
	current := probe_input(input.bundle, input.executable)!
	if current != input { return error('supplied app changed since probe preparation') }
	destination := os.abs_path(out)
	if destination == current.bundle || destination.starts_with(current.bundle + '/')
		|| os.exists(destination) || os.is_link(destination) {
		return error('probe evidence must use a fresh directory outside the supplied app')
	}
	parent := probe_open_directory(os.dir(destination))!
	C.close(parent)
	runtime_inputs := probe_runtime_inputs(runtime)!
	os.mkdir(destination)!
	os.write_file(destination + '/app-before.json', json2.encode(current, prettify: true))!
	mut env := runtime.environment.clone()
	env['VINIX_IOS_TRACE'] = '1'
	mut selected := map[string]string{}
	for name in ['LD_LIBRARY_PATH', 'LIBGL_DRIVERS_PATH', '__EGL_VENDOR_LIBRARY_FILENAMES',
		'LIBGL_ALWAYS_SOFTWARE', 'GALLIUM_DRIVER', 'MESA_SHADER_CACHE_DISABLE', 'EGL_PLATFORM',
		'VINIX_IOS_TRACE', 'SWIFT_DETERMINISTIC_HASHING', 'ASAN_OPTIONS', 'UBSAN_OPTIONS', 'TMPDIR'] {
		if name in env { selected[name] = env[name] }
	}
	os.write_file(destination + '/runtime.json', json2.encode(ProbeRuntimeReceipt{
		profile:              runtime.profile
		built_backends:       runtime.built_backends
		required_backends:    runtime.required_backends
		invocation:           runtime.invocation
		target_executable:    runtime.target_executable
		arguments:            runtime.arguments
		deadline_seconds:     runtime.deadline_seconds
		output_limit:         guard_output_limit
		desktop_driver:       runtime.desktop_driver
		desktop_startup_ms:   runtime.desktop_startup_ms
		desktop_reply_ms:     runtime.desktop_reply_ms
		desktop_session_ms:   runtime.desktop_session_ms
		selected_environment: selected
		runtime_inputs:       runtime_inputs
	}, prettify: true))!
	mut result := ProbeResult{}
	mut code := 1
	probe_commands(destination, current, runtime, env, mut result) or {
		result.failure = err.msg()
		code = if err.code() > 0 { err.code() } else { 1 }
	}
	if result.application_attempted && result.application_exit < 0 {
		status := os.read_file(destination + '/application.status.txt') or { '' }
		if status.trim_space().is_int() { result.application_exit = status.int() }
	}
	if result.desktop_enabled && result.wrapper_exit < 0 {
		status := os.read_file(destination + '/application-wrapper.status.txt') or { '' }
		if status.trim_space().is_int() { result.wrapper_exit = status.int() }
	}
	// Audit the tree after successful and failed commands alike. A changed app
	// or runtime rejects capture qualification while preserving all receipts.
	after := probe_snapshot(current.bundle) or {
		result.failure += '; cannot inventory app after capture: ' + err.msg()
		[]ProbeEntry{}
	}
	os.write_file(destination + '/app-after.json', json2.encode(after, prettify: true))!
	if after != current.entries { result.failure += '; supplied app changed during capture' }
	after_runtime := probe_runtime_inputs(runtime) or {
		result.failure += '; cannot inventory runtime after capture: ' + err.msg()
		[]FileDigest{}
	}
	os.write_file(destination + '/runtime-after.json', json2.encode(after_runtime, prettify: true))!
	if after_runtime != runtime_inputs { result.failure += '; runtime changed during capture' }
	result.capture_complete = result.failure == ''
	os.write_file(destination + '/probe-result.json', json2.encode(result, prettify: true))!
	if !result.capture_complete {
		return error_with_code('probe capture rejected: ' + result.failure, code)
	}
	return result
}
