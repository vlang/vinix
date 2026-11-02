// SPDX-License-Identifier: GPL-2.0-or-later
module linuxcheck

import os
import json2
import crypto.sha256
import encoding.binary
import tlsbuild

struct FileDigest {
	path   string
	sha256 string
}

struct Qualification {
	mode              string
	host              string
	target            string = 'aarch64-linux-gnu'
	native_foundation bool
	sanitizers        bool
	gcc_low_memory    bool
	optional_backends []string
	graphics_root     string
	graphics_driver   string
	cxx_root          string
	cxx_ubsan_archive string
	compiler          string
	toolchain         string
	sysroot           string
	loader_prefix     string
	emulator          string
	source_commit     string
	inputs            []FileDigest
}

fn executable(variable string, fallback string) !string {
	name := os.getenv_opt(variable) or { fallback }
	if name.len == 0 { return error('${variable} must name an executable') }
	return os.find_abs_path_of_executable(name) or {
		return error('${variable}: cannot find ${name}')
	}
}

fn digest(path string) !FileDigest {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return FileDigest{ path: path, sha256: sha256.sum(bytes).hex() }
}

// A caller's compiler/test filters must not remove assertions or select only
// part of a fixture. Keep required host tool paths, but isolate V's controls.
fn runtime_environment(out string, vroot string) !map[string]string {
	mut env := isolated_build_environment()
	for name in ['cache', 'vmodules'] { os.mkdir(out + '/' + name)! }
	env['TMPDIR'] = out + '/tmp'
	env['XDG_CACHE_HOME'] = out + '/cache'
	env['VMODULES'] = out + '/vmodules'
	env['V_RESOURCE_PATH'] = vroot
	env['V_SKIP_VVMRC'] = '1'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'
	env.delete('SWIFT_DETERMINISTIC_HASHING')
	return env
}

// Include hidden entries and propagate traversal errors. Successful sealing
// must never silently omit a directory or follow an external symlink.
fn directory_names(directory string) ![]string {
	// Frozen os.ls does not report readdir failures. Check both directory
	// operations before accepting a complete list of the captured entries.
	stream := unsafe { C.opendir(directory.str) }
	if isnil(stream) { return os.error_posix() }
	mut names := []string{}
	for {
		C.errno = 0
		item := C.readdir(stream)
		if isnil(item) {
			number := C.errno
			closed := C.closedir(stream)
			if number != 0 {
				return error_with_code('cannot enumerate evidence directory: ${directory}', number)
			}
			if closed != 0 { return os.error_posix() }
			break
		}
		name := unsafe { tos_clone(&u8(&item.d_name[0])) }
		if name !in ['.', '..'] { names << name }
	}
	names.sort()
	return names
}

fn inventory_files(root string, relative string, mut items []FileDigest) ! {
	directory := if relative == '' { root } else { root + '/' + relative }
	names := directory_names(directory)!
	for name in names {
		path := directory + '/' + name
		entry := if relative == '' { name } else { relative + '/' + name }
		// Frozen os.is_file also accepts FIFOs/devices. lstat avoids following
		// links and rejects every non-regular entry before attempting a read.
		match os.lstat(path)!.get_filetype() {
			.directory { inventory_files(root, entry, mut items)! }
			.regular {
				item := digest(path)!
				items << FileDigest{ path: entry, sha256: item.sha256 }
			}
			.symbolic_link { return error('evidence contains a symlink: ${path}') }
			else { return error('evidence contains an unsupported entry: ${path}') }
		}
	}
}

// All child execution, including the complete nested TLS build, is owned by
// the process-group guard. Expected nonzero exits are used only by smoke apps.
fn checked(out string, label string, args []string, cwd string, env map[string]string) !string {
	return checked_exit(out, label, args, cwd, env, 0)
}

fn checked_exit(out string, label string, args []string, cwd string, env map[string]string, expected int) !string {
	code, output := guarded_command(out, label, args, cwd, env, 600)!
	if code != expected {
		return error('${label} exited ${code}, expected ${expected}; see ${out}/${label}.log')
	}
	if output.contains('ERROR: AddressSanitizer') || output.contains('runtime error:')
		|| output.contains('V panic:') || output.contains('> assert ') {
		return error('${label} reported a runtime failure; see ${out}/${label}.log')
	}
	return output
}

pub fn fixture(mode string) !string {
	return match mode {
		'url-request', 'url-request-host' { 'url_request_test.v' }
		'data-http', 'data-http-host' { 'ns_data_http_test.v' }
		'storekit-purchase', 'storekit-purchase-host' { 'storekit_purchase_test.v' }
		'netdb-scope' { 'netdb_numeric_scope_test.v' }
		'reachability' { 'reachability_test.v' }
		'network-path' { 'network_path_test.v' }
		'gles', 'cxx-gles' { 'gles_linux_test.v' }
		'cxx' { 'cxx_linux_test.v' }
		'image-initializers' { 'image_initializers_test.v' }
		'build-run-ios', 'build-run-ios-gles', 'build-run-ios-cxx', 'build-run-ios-cxx-gles', 'probe-no-ads' { '' }
		else { return error('unsupported Linux mode: ${mode}') }
	}
}

fn require_arm64_elf(path string) ! {
	mut file := os.open(path)!
	defer { file.close() }
	bytes := file.read_bytes(64)
	if bytes.len != 64 || bytes[..4] != [u8(0x7f), `E`, `L`, `F`] || bytes[4] != 2
		|| bytes[5] != 1 || bytes[6] != 1 || binary.little_endian_u16(bytes[16..18]) !in [
		u16(2),
		3,
	]
		|| binary.little_endian_u16(bytes[18..20]) != 183 {
		return error('Linux iOS execution requires a 64-bit little-endian ARM64 ELF: ${path}')
	}
}

fn require_markers(fixture_name string, output string) ! {
	markers := match fixture_name {
		'url_request_test.v' { ['IOS-REQUEST:', 'IOS-REQUEST-REJECT:'] }
		'ns_data_http_test.v' {
			['IOS-DATA-HTTP-FRAMING:', 'IOS-DATA-HTTP-REDIRECT:', 'IOS-DATA-HTTP-TLS:',
				'IOS-DATA-HTTP-FACTORY:', 'IOS-HTTP-TRANSPORT:', 'IOS-HTTP-TRANSPORT-VALIDATION:',
				'IOS-HTTP-TRANSPORT-BOUNDS:', 'IOS-HTTP-TRANSPORT-ENTROPY:',
				'IOS-HTTP-TRANSPORT-CANCEL:', 'IOS-HTTP-RESPONSE-DECISION:',
				'IOS-HTTP-TRANSPORT-DECISION:', 'IOS-HTTP-RESPONSE-DECISION-REJECT:',
				'IOS-SESSION-WORKERS-OWNERSHIP:', 'IOS-SESSION-WORKERS-HTTP:',
				'IOS-SESSION-WORKERS-REJECT:', 'IOS-SESSION-ADAPTER-REQUEST:',
				'IOS-SESSION-ADAPTER-POLICY:', 'IOS-SESSION-ADAPTER-RESPONSE:',
				'IOS-SESSION-ADAPTER-REENTRY:', 'IOS-SESSION-ADAPTER-BOUNDS:', 'IOS-SESSION-TRANSFER:',
				'IOS-SESSION-TRANSFER-SHUTDOWN:', 'IOS-BUILTIN-PROTOCOL:',
				'IOS-BUILTIN-PROTOCOL-POLICY:', 'IOS-SESSION-COOKIES-DISABLED:',
				'IOS-HTTP-SYSTEM-TRUST:']
		}
		'storekit_purchase_test.v' {
			['IOS-STOREKIT-PURCHASE:', 'IOS-STOREKIT-PURCHASE-REJECT:', 'IOS-STOREKIT-QUEUE:',
				'IOS-STOREKIT-QUEUE-REJECT:', 'IOS-SELECTOR-GROWTH:', 'IOS-STOREKIT-OBSERVERS:',
				'IOS-STOREKIT-OBSERVERS-REJECT:']
		}
		'netdb_numeric_scope_test.v' { ['IOS-NETDB-NUMERIC-SCOPE:', 'IOS-NETDB-SCOPE-NAMES:'] }
		'reachability_test.v' { ['IOS-REACHABILITY:'] }
		'network_path_test.v' { ['IOS-NETWORK-PATH:'] }
		'gles_linux_test.v' {
			['IOS-LINUX-GLES-CONTEXTS:', 'IOS-LINUX-GLES-DRAW:', 'IOS-LINUX-GLES-SURFACE:',
				'IOS-LINUX-GLES-THREADS:', 'IOS-LINUX-GLES-CLEANUP:']
		}
		'cxx_linux_test.v' {
			['IOS-LINUX-CXX-SYMBOLS:', 'IOS-LINUX-CXX-STRINGS:', 'IOS-LINUX-CXX-LOCALE:',
				'IOS-LINUX-CXX-CONVERSIONS:', 'IOS-LINUX-CXX-THREADS:', 'IOS-LINUX-CXX-CLEANUP:']
		}
		'image_initializers_test.v' { ['IOS-IMAGE-INITIALIZERS:', 'IOS-IMAGE-INITIALIZER-ENTRY:'] }
		else { []string{} }
	}
	if output.contains('FAIL') || output.contains('V panic:') || output.contains('> assert ') {
		return error('runtime coverage includes a failure')
	}
	for marker in markers {
		if output.split_into_lines().filter(it.starts_with(marker)).len != 1 {
			return error('expected exactly one runtime coverage marker: ${marker}')
		}
	}
}

struct TlsTask {
	root      string
	toolchain string
	out       string
	compiler  []string
}

// The parent guards this whole worker, including compiler/ar grandchildren.
// Historical tlsbuild behavior and its saved receipts remain unchanged.
pub fn maybe_tls_child() !bool {
	if os.args.len != 3 || os.args[1] != '--linux-tls' { return false }
	task := json2.decode[TlsTask](os.read_file(os.args[2])!)!
	root := os.real_path(task.root)
	out := os.real_path(task.out)
	if !os.is_dir(out) || out == root || out.starts_with(root + os.path_separator) {
		return error('TLS worker output must be an existing external directory')
	}
	archive := tlsbuild.build(root, task.toolchain, out, task.compiler)
	os.write_file(out + '/tls-archive.txt', archive + '\n')!
	return true
}

// Refuse existing output and resolve its parent before testing containment, so
// a symlink cannot put generated C, binaries or logs inside the repository.
pub fn fresh_output(root string, requested string) !string {
	return fresh_output_outside_app(root, requested, '')
}

// Probe output must be rejected before creating anything in the supplied app,
// including when an output-parent alias resolves into that app.
fn fresh_output_outside_app(root string, requested string, bundle string) !string {
	path := os.abs_path(requested)
	parent := os.real_path(os.dir(path))
	if !os.is_dir(parent) { return error('output parent must exist: ${os.dir(path)}') }
	out := os.join_path(parent, os.file_name(path))
	if out == root || out.starts_with(root + os.path_separator) {
		return error('Linux evidence must be outside the repository')
	}
	if bundle != '' && (out == bundle || out.starts_with(bundle + os.path_separator)) {
		return error('Linux evidence must be outside the supplied application')
	}
	if os.exists(out) || os.is_link(out) { return error('output must be fresh: ${out}') }
	os.mkdir(out)!
	os.mkdir(out + '/payload')!
	os.mkdir(out + '/tmp')!
	return out
}

pub fn run(repository string, mode string, requested string) ! {
	$if !linux {
		return error('this execution path requires a Linux host')
	}
	fixture_name := fixture(mode)!
	mut application := ProbeInput{}
	mut probe_deadline := 600
	if mode == 'probe-no-ads' {
		deadline := os.getenv_opt('VINIX_IOS_LINUX_PROBE_SECONDS') or { '600' }
		if !deadline.is_int() || deadline.int() < 1 || deadline.int() > 1800 {
			return error('VINIX_IOS_LINUX_PROBE_SECONDS must be 1..1800')
		}
		probe_deadline = deadline.int()
		application = probe_input_from_environment()!
	}
	graphics := gles_profile(mode)!
	cxx := cxx_profile(mode)!
	cxx_sanitizer := cxx_sanitizer_profile(cxx)!
	low_memory_value := os.getenv('VINIX_IOS_LINUX_GCC_LOW_MEMORY')
	if low_memory_value !in ['', '0', '1'] {
		return error('VINIX_IOS_LINUX_GCC_LOW_MEMORY must be 0 or 1')
	}
	low_memory := low_memory_value == '1'
	root := os.real_path(repository)
	if !os.is_file(root + '/compat/ios/runner/objc.c.v') {
		return error('run from the Vinix repository root')
	}
	vroot := os.real_path(os.getenv_opt('VINIX_IOS_TOOLCHAIN') or {
		os.dir(os.find_abs_path_of_executable('v')!)
	})
	v := vroot + '/v'
	if !os.is_file(v) || !os.is_file(vroot + '/v.mod') {
		return error('VINIX_IOS_TOOLCHAIN must contain frozen V, v.mod, vlib and thirdparty')
	}
	mut native := false
	$if arm64 {
		native = true
	}
	$if !arm64 && !amd64 {
		return error('Linux iOS checks support ARM64 or x86_64 hosts')
	}
	cc := executable('VINIX_IOS_LINUX_CC', if native { 'cc' } else { 'aarch64-linux-gnu-gcc' })!
	sysroot_value := os.getenv('VINIX_IOS_LINUX_SYSROOT')
	sysroot := if sysroot_value == '' { '' } else { os.real_path(sysroot_value) }
	if sysroot.len > 0 && !os.is_dir(sysroot) {
		return error('Linux compiler sysroot does not exist: ${sysroot}')
	}
	mut emulator := ''
	mut prefix := ''
	if !native {
		emulator = executable('VINIX_IOS_QEMU_USER', 'qemu-aarch64')!
		prefix = os.real_path(os.getenv_opt('VINIX_IOS_LINUX_LD_PREFIX') or { '/usr/aarch64-linux-gnu' })
		if !os.is_file(prefix + '/lib/ld-linux-aarch64.so.1') {
			return error('VINIX_IOS_LINUX_LD_PREFIX must contain lib/ld-linux-aarch64.so.1')
		}
	}
	out := fresh_output_outside_app(root, requested, application.bundle)!
	mut env := runtime_environment(out, vroot)!
	cxx_sanitizer_copy(cxx_sanitizer, out)!
	graphics_inputs := gles_inputs(graphics)!
	cxx_before := cxx_inputs(cxx)!
	if graphics.enabled {
		os.write_file(out + '/gles-inputs.json', json2.encode(graphics_inputs, prettify: true))!
	}
	if cxx.enabled {
		os.write_file(out + '/cxx-inputs.json', json2.encode(cxx_before, prettify: true))!
	}
	// tlsbuild uses child processes too; its objects remain in this output tree.
	os.setenv('TMPDIR', env['TMPDIR'], true)
	version := checked(out, 'v-version', [v, 'version'], vroot, env)!
	if !version.contains('V 0.5.2 c6bb06f') {
		return error('expected frozen V 0.5.2 c6bb06f; got ${version.trim_space()}')
	}
	target := checked(out, 'cc-target', [cc, '-dumpmachine'], root, env)!.trim_space()
	if !target.starts_with('aarch64') || !target.ends_with('linux-gnu') {
		return error('this profile requires a GNU/glibc Linux ARM64 compiler; got ${target}')
	}
	checked(out, 'cc-version', [cc, '--version'], root, env)!
	if emulator.len > 0 { checked(out, 'qemu-version', [emulator, '--version'], root, env)! }
	commit := checked(out, 'source-commit', ['git', 'rev-parse', 'HEAD'], root, env)!.trim_space()
	// Source diffs can legitimately contain diagnostic strings such as "V panic".
	diff_code, _ := guarded_command(out, 'source-diff', ['git', 'diff', '--binary', '--', 'compat/ios',
		'tests/ios', 'build-support/ios'], root, env, 600)!
	if diff_code != 0 { return error('source-diff exited ${diff_code}') }
	// Capture the exact V/ABI sources, including uncommitted fixes under test.
	os.mkdir_all(out + '/source/compat')!
	os.cp_all(root + '/compat/ios', out + '/source/compat/ios', false)!
	os.mkdir_all(out + '/source/tests/ios')!
	for name in ['linuxcheck', 'tlsbuild', 'frozenv', 'hosttools', 'probedesktop'] {
		os.cp_all(root + '/tests/ios/' + name, out + '/source/tests/ios/' + name, false)!
	}
	os.cp(root + '/tests/ios/linux-checks.v', out + '/source/tests/ios/linux-checks.v')!
	os.cp(root + '/tests/ios/notification-checks.v', out + '/source/tests/ios/notification-checks.v')!
	if cxx.enabled {
		os.cp(root + '/tests/ios/cxx-extended.cpp', out + '/source/tests/ios/cxx-extended.cpp')!
		os.mkdir_all(out + '/source/build-support')!
		os.cp_all(root + '/build-support/ios', out + '/source/build-support/ios', false)!
	}
	build_root := out + '/source'
	self := os.find_abs_path_of_executable(os.args[0])!
	os.cp(self, out + '/driver')!
	mut inputs := [digest(v)!, digest(cc)!, digest(self)!,
		digest(build_root + '/compat/ios/runner/abi/dispatch.S')!]
	if emulator.len > 0 { inputs << digest(emulator)! }
	if cxx_sanitizer.archive != '' { inputs << digest(cxx_sanitizer.archive)! }
	sanitized := fixture_name.len > 0
	mut backends := []string{}
	if cxx.enabled { backends << 'cxx' }
	if graphics.enabled { backends << 'gles' }
	os.write_file(out + '/qualification.json', json2.encode(Qualification{
		mode:          mode
		host:          if native { 'linux-arm64' } else { 'linux-amd64' }
		sanitizers:    sanitized
		gcc_low_memory: low_memory
		optional_backends: backends
		graphics_root: graphics.root
		graphics_driver: if graphics.enabled { 'softpipe' } else { '' }
		cxx_root: cxx.root
		cxx_ubsan_archive: cxx_sanitizer.archive
		compiler:      cc
		toolchain:     vroot
		sysroot:       sysroot
		loader_prefix: prefix
		emulator:      emulator
		source_commit: commit
		inputs:        inputs
	}, prettify: true))!
	source := if sanitized {
		build_root + '/compat/ios/runner/' + fixture_name
	} else {
		build_root + '/compat/ios/runner'
	}
	generated := out + '/payload/runtime.c'
	if mode == 'cxx' { cxx_probe_header(out)! }
	mut generate := [v, '-enable-globals', '-nocache', '-gc', 'none', '-cc', 'gcc', '-os',
		'linux', '-arch', 'arm64', '-d', 'glibc', '-d', 'no_backtrace', '-path',
		'@vlib|' + build_root + '/compat/ios|' + build_root + '/tests/ios|@vmodules', '-o', generated]
	if graphics.enabled { generate << ['-d', 'ios_gles'] }
	if cxx.enabled { generate << ['-d', 'ios_cxx'] }
	generate << source
	checked(out, 'generate', generate, vroot, env)!
	// Pipe the large generated assembly directly to the assembler. This changes
	// no optimization or sanitizer settings and avoids a large transient file.
	mut compile := [cc, '-pipe', '-D_GNU_SOURCE', '-DCUSTOM_DEFINE_no_backtrace', '-ffixed-x18', '-w', '-g',
		'-fno-omit-frame-pointer']
	if sysroot.len > 0 { compile << '--sysroot=' + sysroot }
	if sanitized { compile << '-fsanitize=address,undefined' }
	os.write_file(out + '/tls-task.json', json2.encode(TlsTask{
		root:      build_root
		toolchain: vroot
		out:       out + '/payload'
		compiler:  compile
	}))!
	checked(out, 'tls-build', [out + '/driver', '--linux-tls', out + '/tls-task.json'], out, env)!
	tls := os.read_file(out + '/payload/tls-archive.txt')!.trim_space()
	// Keep V assertions enabled while avoiding prohibitively slow instrumented
	// dispatch under user-mode ARM64 emulation. Network deadlines stay unchanged.
	compile << ['-O1', '-c']
	// Reduce GCC's own garbage-collector growth on constrained build hosts.
	// This changes compiler memory use, not generated runtime assertions or
	// sanitizer instrumentation. Keep it explicit and record it in the capture.
	if low_memory { compile << ['--param=ggc-min-expand=10', '--param=ggc-min-heapsize=16384'] }
	compile << tlsbuild.includes(vroot)
	if graphics.enabled { compile << ['-isystem', graphics.include] }
	mut objects := []string{}
	mut c_sources := [generated]
	// Stock c6bb06f includes these helpers as headers. Older prepared
	// toolchain layouts can carry separate translation units instead.
	for helper in ['os/execute_capture_nix.c', 'builtin/segfault_handler_nix.c'] {
		path := vroot + '/vlib/' + helper
		if os.is_file(path) { c_sources << path }
	}
	c_sources << build_root + '/compat/ios/runner/abi/dispatch.S'
	for i, input in c_sources {
		object := out + '/payload/runtime-${i}.o'
		mut command := compile.clone()
		command << [input, '-o', object]
		checked(out, 'object-${i}', command, out, env)!
		objects << object
	}
	if mode == 'cxx' { objects << cxx_probe_object(cxx, out, env)! }
	binary_path := out + '/run-ios'
	mut link := [cc, '-g', '-no-pie']
	if sysroot.len > 0 { link << '--sysroot=' + sysroot }
	if sanitized { link << '-fsanitize=address,undefined' }
	link << cxx_sanitizer_link_flags(cxx_sanitizer, out)
	link << objects
	if graphics.enabled {
		link << ['-L' + graphics.libraries, '-Wl,-rpath-link,' + graphics.libraries, '-lEGL', '-lGLESv2']
	}
	link << cxx_link(cxx)
	link << [tls, '-pthread', '-ldl', '-lresolv', '-lm', '-o', binary_path]
	checked(out, 'link', link, out, env)!
	require_arm64_elf(binary_path)!
	if cxx.enabled { cxx_verify_linkage(out, 'runtime', binary_path, env)! }
	// Keep target graphics libraries out of host V/GCC processes. Only the
	// ARM64 runtime (or QEMU's target loader) receives this environment.
	mut execution_env := env.clone()
	if graphics.enabled {
		gles_environment(graphics, out, prefix, mut execution_env)!
		os.mkdir(out + '/payload/frames')!
		execution_env['VINIX_IOS_GLES_FRAME_DIR'] = out + '/payload/frames'
		os.write_file(out + '/gles-environment.json', json2.encode({
			'LD_LIBRARY_PATH': execution_env['LD_LIBRARY_PATH']
			'LIBGL_DRIVERS_PATH': execution_env['LIBGL_DRIVERS_PATH']
			'__EGL_VENDOR_LIBRARY_FILENAMES': execution_env['__EGL_VENDOR_LIBRARY_FILENAMES']
			'LIBGL_ALWAYS_SOFTWARE': execution_env['LIBGL_ALWAYS_SOFTWARE']
			'GALLIUM_DRIVER': execution_env['GALLIUM_DRIVER']
			'MESA_SHADER_CACHE_DISABLE': execution_env['MESA_SHADER_CACHE_DISABLE']
			'EGL_PLATFORM': execution_env['EGL_PLATFORM']
		}, prettify: true))!
	}
	mut invocation := []string{}
	if !native {
		invocation << [emulator, '-L', prefix]
		if graphics.enabled {
			// QEMU may be dynamically linked for the host architecture. Preserve
			// its host loader path and set the target path via QEMU's explicit -E.
			invocation << ['-E', 'LD_LIBRARY_PATH=' + execution_env['LD_LIBRARY_PATH']]
			if 'LD_LIBRARY_PATH' in env { execution_env['LD_LIBRARY_PATH'] = env['LD_LIBRARY_PATH'] }
			else { execution_env.delete('LD_LIBRARY_PATH') }
		}
	}
	invocation << binary_path
	if mode == 'cxx' {
		cxx_sanitizer_controls(cxx, cxx_sanitizer, out, cc, sysroot, invocation, env, execution_env)!
		cxx_native_fixture(cxx, cxx_sanitizer, out, build_root, cc, sysroot, invocation, env, execution_env)!
	}
	if !sanitized {
		mut help := invocation.clone()
		help << '--help'
		help_output := checked(out, 'help', help, out, execution_env)!
		if !help_output.contains('usage: run-ios ') {
			return error('runner help output is missing')
		}
		smoke := out + '/smoke-ios'
		write_smoke(smoke)!
		mut command := invocation.clone()
		command << ['--inspect', smoke]
		checked(out, 'smoke-inspect', command, out, execution_env)!
		command = invocation.clone()
		command << smoke
		checked_exit(out, 'smoke-entry', command, out, execution_env, smoke_success_exit)!
		command << 'extra'
		checked_exit(out, 'smoke-arguments', command, out, execution_env, smoke_argument_error_exit)!
	} else {
		if fixture_name == 'ns_data_http_test.v' {
			openssl := os.find_abs_path_of_executable('openssl')!
			checked(out, 'certificate', [openssl, 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
				'-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost', '-days', '1',
				'-keyout', out + '/server.key', '-out', out + '/server.pem'], out, env)!
			execution_env['VINIX_IOS_HTTP_CERT'] = out + '/server.pem'
			execution_env['VINIX_IOS_HTTP_KEY'] = out + '/server.key'
			os.mkdir(out + '/payload/system-trust')!
			execution_env['VINIX_IOS_HTTP_TRUST_EVIDENCE'] = out + '/payload/system-trust'
		}
		for deterministic in [false, true] {
			label := if deterministic { 'runtime-deterministic' } else { 'runtime' }
			if deterministic { execution_env['SWIFT_DETERMINISTIC_HASHING'] = '1' }
			output := checked(out, label, invocation, out, execution_env)!
			require_markers(fixture_name, output)!
		}
	}
	mut probe_result := ProbeResult{}
	if mode == 'probe-no-ads' {
		probe_result = probe_capture(out + '/application-probe', application, ProbeRuntime{
			invocation: invocation
			environment: execution_env
			profile: 'GNU ARM64 iOS runtime with adapted C++ and Mesa softpipe plus a diagnostic VAPP peer without compositor or input; video, text and SQLite backends disabled; Metal unavailable'
			built_backends: backends
			required_backends: ['cxx', 'gles']
			deadline_seconds: probe_deadline
			desktop_driver: out + '/driver'
		})!
	}
	if graphics.enabled && gles_inputs(graphics)! != graphics_inputs {
		return error('Linux GLES SDK inputs changed during the capture')
	}
	if cxx.enabled && cxx_inputs(cxx)! != cxx_before {
		return error('GNU C++ backend inputs changed during the capture')
	}
	cxx_sanitizer_unchanged(cxx_sanitizer)!
	cxx_sanitizer_copy_unchanged(cxx_sanitizer, out)!
	result_text := if mode == 'probe-no-ads' {
		'COMPLETE guarded Linux ARM64 application capture; application_exit=${probe_result.application_exit}; diagnostic=${probe_result.application_diagnostic}; capture completion does not establish a game frame, menu, login, gameplay or launch gate\n'
	} else if mode == 'cxx-gles' {
		'PASS Linux ARM64 GLES fixture with the adapted C++ backend linked, ASan/UBSan and Mesa softpipe; packaged Mesa and the ELF unwinder are not instrumented; LLVM RTTI internals omit their recursive vptr check only; no Fortnite execution\n'
	} else if cxx.enabled && sanitized {
		'PASS Linux ARM64 C++ runtime fixture with ASan/UBSan plus the native ELF C++ reference with V-generated constructor-lifetime adaptation and all original comparisons, and rejecting vptr/function sanitizer controls; LLVM RTTI internals omit their recursive vptr check only and the ELF unwinder is not instrumented; native Foundation and Fortnite not executed; Mach-O exception unwinding remains unsupported\n'
	} else if cxx.enabled {
		'PASS Linux ARM64 runner with ' + backends.join(', ') + ' backends and synthetic iOS application entry/arguments; no Fortnite execution; video, text and SQLite backends disabled\n'
	} else if graphics.enabled && sanitized {
		'PASS Linux ARM64 GLES runtime fixture with ASan/UBSan and Mesa softpipe; native Foundation and Fortnite not executed; packaged Mesa libraries are not sanitizer-instrumented\n'
	} else if graphics.enabled {
		'PASS Linux ARM64 GLES runner build and synthetic iOS application entry/arguments; no Fortnite execution; C++, video, text and SQLite backends disabled\n'
	} else if sanitized {
		'PASS Linux ARM64 fixture with ASan/UBSan; native Foundation not executed; optional multimedia backends disabled\n'
	} else {
		'PASS Linux ARM64 runner build and synthetic iOS application entry/arguments; no Fortnite execution; optional multimedia backends disabled\n'
	}
	mut inventory := []FileDigest{}
	inventory_files(out, '', mut inventory)!
	inventory << FileDigest{ path: 'result.txt', sha256: sha256.sum(result_text.bytes()).hex() }
	inventory.sort(a.path < b.path)
	os.write_file(out + '/inventory.json', json2.encode(inventory, prettify: true))!
	os.write_file(out + '/result.txt', result_text)!
	if mode == 'probe-no-ads' {
		println('probe-no-ads: capture COMPLETE; application exit ${probe_result.application_exit}; inspect application-probe/probe-result.json and application-wrapper.log; game success not inferred')
	} else {
		println('${mode}: PASS (Linux ARM64 runtime; native Foundation not executed)')
	}
}
