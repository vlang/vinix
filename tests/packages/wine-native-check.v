// SPDX-License-Identifier: GPL-2.0-or-later
// Local signed Wine qualification. Publisher notices remain explicit inputs.
module main

import crypto.sha256
import hwhost
import json2
import os
import plainiso
import time
import tests.packages.winesource
import tools.packages.pkgcore
import tools.packages.wineadapter

#include <fcntl.h>
#include <sys/stat.h>
#define wine_receipt_open open
#define wine_receipt_openat openat
#define wine_receipt_fstat fstat
#define wine_receipt_read read
fn C.wine_receipt_open(&char, i32) i32
fn C.wine_receipt_openat(i32, &char, i32) i32
fn C.wine_receipt_fstat(i32, &C.stat) i32
fn C.wine_receipt_read(i32, voidptr, u64) i64

// Fixed relative paths beneath one captured prepared directory. Neither a
// symlink nor a FIFO/device may stand in for a receipt or the compiled runner.
fn owned_bytes(rootfd i32, relative string, limit int) !string {
	parts := relative.split('/')
	defer { unsafe { for part in parts { part.free() }; (&array(&parts)).free() } }
	mut parent := rootfd
	mut own_parent := false
	defer { if own_parent { C.close(parent) } }
	for index in 0 .. parts.len - 1 {
		part := parts[index]
		next := C.wine_receipt_openat(parent, part.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if next < 0 { return error('owned Wine receipt requires captured ordinary files: ' + relative) }
		if own_parent { C.close(parent) }
		parent = next
		own_parent = true
	}
	fd := C.wine_receipt_openat(parent, parts.last().str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('owned Wine receipt requires captured ordinary files: ' + relative) }
	defer { C.close(fd) }
	mut st := C.stat{}
	if C.wine_receipt_fstat(fd, &st) != 0 || st.st_mode & C.S_IFMT != C.S_IFREG || st.st_size < 1 || st.st_size > limit {
		return error('owned Wine receipt file is not bounded and regular: ' + relative)
	}
	mut bytes := []u8{len: int(st.st_size) + 1}
	defer { unsafe { bytes.free() } }
	mut got := 0
	for got < bytes.len {
		count := C.wine_receipt_read(fd, unsafe { &bytes[got] }, u64(bytes.len - got))
		if count < 0 {
			if C.errno == C.EINTR { continue }
			return error('cannot read owned Wine receipt file: ' + relative)
		}
		if count == 0 { break }
		got += int(count)
	}
	mut after := C.stat{}
	if got != st.st_size || C.wine_receipt_fstat(fd, &after) != 0 || after.st_size != st.st_size || after.st_mode != st.st_mode {
		return error('owned Wine receipt file changed while reading: ' + relative)
	}
	return unsafe { tos(bytes.data, got) }.clone()
}

fn owned_receipt(prepared string, arch string, root string) ! {
	if arch != 'x86_64' { return error('owned native Wine qualification requires x86_64') }
	fd := C.wine_receipt_open(prepared.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 { return error('owned Wine prepared directory is unavailable') }
	defer { C.close(fd) }
	mode_text := owned_bytes(fd, 'owned-manager.json', 8192)!
	output_text := owned_bytes(fd, 'outputs.json', 1024 * 1024)!
	argv_text := owned_bytes(fd, 'logs/v.log.argv.json', 65536)!
	runner := owned_bytes(fd, 'prepared/' + arch + '/runtime/bin/wine-runner', 32 * 1024 * 1024)!
	defer { unsafe { mode_text.free(); output_text.free(); argv_text.free(); runner.free() } }
	mode := json2.decode[map[string]string](mode_text) or { return error('owned Wine mode JSON invalid') }
	outputs := json2.decode[map[string]string](output_text) or { return error('owned Wine outputs JSON invalid') }
	argv := json2.decode[[]string](argv_text) or { return error('owned Wine compiler arguments JSON invalid') }
	if argv.len < 2 || argv.len > 512 { return error('owned Wine compiler arguments outside bound') }
	mut flag := false
	for index in 0 .. argv.len - 1 { if argv[index] == '-d' && argv[index + 1] == 'wine_owned_manager' { flag = true } }
	if mode.len != 3 || mode['architecture'] != arch || mode['mode'] != 'wine_owned_manager' || !flag
		|| mode['runner_source_sha256'] != digest(root + '/tools/packages/wine-runner.v')!
		|| outputs['owned-manager.json'] != sha256.hexhash(mode_text)
		|| outputs['prepared/' + arch + '/runtime/bin/wine-runner'] != sha256.hexhash(runner) {
		return error('owned Wine runtime build receipt differs')
	}
}

fn digest(path string) !string {
	return winesource.file_digest(path)
}

fn invoke(arguments []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(arguments))!
	mut child := os.new_process(arguments[0])
	defer { child.close() }
	child.set_args(arguments[1..])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	child.wait()
	defer { unsafe { output.free() } }
	os.write_file(log, output)!
	if child.code != 0 { return error('Wine qualification producer failed: ' + log) }
}

fn v_program(v string, source string, arch string, cfile string, owned bool, collection bool, caller_death bool) ![]string {
	root := hwhost.find_root(@FILE)!
	mut command := [v, '-backend', 'c', '-prod', '-os', 'linux', '-arch',
		if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-gc', 'none', '-manualfree',
		'-enable-globals', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-path',
		'@vlib|' + root + '|' + root + '/tools/accounts|@vmodules', '-o', cfile, source]
	if owned { command.insert(1, ['-d', 'wine_owned_manager']) }
	if collection { command.insert(1, ['-d', 'wine_collection_probe']) }
	if caller_death { command.insert(1, ['-d', 'wine_caller_death_probe']) }
	return command
}

fn discover_program(v string, source string, arch string, work string, name string, owned bool, collection bool, caller_death bool, mut inputs map[string]string) ! {
	directory := work + '/build-' + name
	os.mkdir_all(directory)!
	mut command := v_program(v, source, arch, directory + '/' + name + '.c', owned, collection, caller_death)!
	command.insert(1, ['-print-watched-files', '-dump-files', directory + '/sources-before.txt'])
	invoke(command, directory + '/discover.log')!
	winesource.capture(directory + '/sources-before.txt', mut inputs)!
}

fn build_program(v string, sysroot string, gcc string, source string, arch string, work string, name string, owned bool, collection bool, caller_death bool, inputs map[string]string) !string {
	directory := work + '/build-' + name
	cfile := directory + '/' + name + '.c'
	mut command := v_program(v, source, arch, cfile, owned, collection, caller_death)!
	command.insert(1, ['-dump-files', directory + '/sources-built.txt'])
	invoke(command, directory + '/v.log')!
	winesource.admit(directory + '/sources-before.txt', directory + '/sources-built.txt', inputs)!
	vlib := os.dir(v) + '/vlib'
	os.write_file(directory + '/runtime.c', '#include <unistd.h>\n#include <fcntl.h>\n#include <sys/wait.h>\n#define V_OS_EXECUTE_SCOPE\n#include "' +
		vlib + '/os/execute_capture_nix.h"\n#define V_SYNC_THREAD_SCOPE\n#include "' + vlib + '/sync/thread_helper.h"\n')!
	invoke(['/opt/homebrew/opt/llvm/bin/clang', '--target=' + arch + '-linux-musl',
		'--sysroot=' + sysroot, '--gcc-install-dir=' + gcc, '-fuse-ld=lld', '-O1', '-w',
		'-fno-stack-protector', '-static', '-D_GNU_SOURCE', '-Wno-error=incompatible-pointer-types',
		cfile, directory + '/runtime.c', '-lm', '-lpthread', '-o', directory + '/' + name], directory + '/cc.log')!
	return directory + '/' + name
}

fn verify(inputs map[string]string) ! {
	for path, expected in inputs {
		if digest(path)! != expected { return error('Wine qualification input changed: ' + path) }
	}
}

fn check() ! {
	$if prod {
	} $else {
		return error('compile Wine native controller with -prod for embedded source admission')
	}
	if digest(@FILE)! != sha256.hexhash($embed_file('wine-native-check.v').to_string()) {
		return error('compiled Wine native controller source differs')
	}
	if digest(os.dir(@FILE) + '/winesource/closure.v')! != sha256.hexhash($embed_file('winesource/closure.v').to_string()) {
		return error('compiled Wine source closure admission differs')
	}
	if os.args.len == 4 && os.args[1] == '--check-owned-build' {
		owned_receipt(os.real_path(os.args[3]), os.args[2], hwhost.find_root(@FILE)!)!
		println('WINE OWNED BUILD PREFLIGHT PASS receipt/source/compiler-mode/runner bindings')
		return
	}
	if os.args.len !in [9, 10, 11] || (os.args.len >= 10 && os.args[9] != '--owned-manager')
		|| (os.args.len == 11 && os.args[10] !in ['--collection-probe', '--caller-death-probe']) {
		return error('usage: wine-native-check ARCH OUTPUT PREPARED_BUILD KERNEL ASSEMBLED_STAGE SYSROOT GCC_RUNTIME SANDBOX [--owned-manager [--collection-probe|--caller-death-probe]]')
	}
	owned := os.args.len >= 10
	collection := os.args.len == 11
	caller_death := collection && os.args[10] == '--caller-death-probe'
	arch := os.args[1]
	if arch !in ['aarch64', 'x86_64'] { return error('invalid Wine guest architecture') }
	if owned && arch != 'x86_64' { return error('owned native Wine qualification requires x86_64') }
	work := os.abs_path(os.args[2])
	prepared := os.real_path(os.args[3])
	kernel := os.real_path(os.args[4])
	stage := os.real_path(os.args[5])
	sysroot := os.real_path(os.args[6])
	gcc := os.real_path(os.args[7])
	sandbox := os.real_path(os.args[8])
	if os.exists(work) { return error('Wine native output already exists') }
	os.mkdir_all(work)!
	root := hwhost.find_root(@FILE)!
	mode_file := prepared + '/owned-manager.json'
	marked := os.exists(mode_file) || os.is_link(mode_file)
	if owned != marked { return error('Wine prepared runtime and native controller ownership modes differ') }
	if owned {
		owned_receipt(prepared, arch, root)!
	}
	host := hwhost.find_host(root, arch, '')!
	mut inputs := map[string]string{}
	image_inputs := if arch == 'x86_64' { plainiso.inputs(root)! } else { map[string]string{} }
	for _, path in image_inputs { inputs[path] = digest(path)! }
	mut arm_loader := ''
	if arch == 'aarch64' {
		selected := os.getenv('VINIX_LIMINE_BOOTAA64')
		defer { unsafe { selected.free() } }
		arm_loader = os.real_path(if selected != '' {
			selected
		} else {
			hwhost.shared_path(root, 'boot-image/limine-bin/BOOTAA64.EFI')
		})
		inputs[arm_loader] = digest(arm_loader)!
		// Make the boot helper consume exactly the loader admitted above.
		os.setenv('VINIX_LIMINE_BOOTAA64', arm_loader, true)
		if host.firmware_vars == '' { return error('ARM firmware variable store is required') }
	} else if host.firmware_vars != '' {
		return error('x86 firmware variable store must be empty')
	}
	mut translator_original := ''
	mut translator_busybox := ''
	if arch == 'aarch64' {
		patch := json2.decode[map[string]string](os.read_file(prepared + '/translator-patch.json')!)!
		translator_original = os.real_path(patch['input'])
		translator_busybox = os.dir(os.dir(os.dir(translator_original))) + '/usr/libexec/vinix-x86_64/root/bin/busybox'
		inputs[translator_original] = digest(translator_original)!
		inputs[translator_busybox] = digest(translator_busybox)!
		if patch['method'] == 'pinned-forksafe-v1' {
			wineadapter.admit_forksafe_translator(patch['translator'], patch['translator_manifest'], patch['fork_patch'])!
			for name in ['translator', 'translator_manifest', 'fork_patch']! {
				inputs[patch[name]] = digest(patch[name])!
			}
		}
	}
	for path in [os.executable(), host.v, kernel, host.qemu, host.firmware, @FILE,
		root + '/tests/packages/wine-native/main.v', root + '/tests/packages/winesource/closure.v',
		'/opt/homebrew/opt/llvm/bin/clang', '/opt/homebrew/bin/ld.lld', sandbox] {
		inputs[path] = digest(path)!
	}
	if host.firmware_vars != '' { inputs[host.firmware_vars] = digest(host.firmware_vars)! }
	for directory in [root + '/tools/packages', root + '/tools/accounts',
		root + '/tests/hardware-platform/hwhost', root + '/tests/hardware-platform/plainiso',
		os.dir(host.v) + '/vlib', os.dir(host.v) + '/thirdparty', sysroot + '/usr/include',
		sysroot + '/usr/lib', sysroot + '/lib', gcc, prepared] {
		for path in os.walk_ext(directory, '', hidden: true) {
			if os.is_file(path) { inputs[path] = digest(path)! }
		}
	}
	for name in ['usr/sbin/vinix-account', 'usr/sbin/vinix-session'] {
		inputs[stage + '/' + name] = digest(stage + '/' + name)!
	}
	discover_program(host.v, root + '/tests/packages/wine-native/main.v', arch, work, 'guest', owned, collection, caller_death, mut inputs)!
	discover_program(host.v, root + '/tools/packages/main.v', arch, work, 'package', owned, false, false, mut inputs)!
	os.write_file(work + '/inputs-before-build.json', json2.encode(inputs))!
	guest := build_program(host.v, sysroot, gcc, root + '/tests/packages/wine-native/main.v', arch, work, 'guest', owned, collection, caller_death, inputs)!
	// Rebuild the package CLI from the captured tree. The archived account tools
	// are separate inputs; their stage's package CLI may predate runtime policy.
	package_cli := build_program(host.v, sysroot, gcc, root + '/tools/packages/main.v', arch, work, 'package', owned, false, false, inputs)!
	// An owned local test key signs the real runtime. It is never copied into
	// the guest image or printed. This does not enroll a production publisher.
	publisher := work + '/publisher'
	seed := work + '/publisher-seed'
	key := pkgcore.keygen(seed)!
	for role in ['runtime', 'application']! {
		recipe_file := prepared + '/' + role + '.json'
		mut packed := pkgcore.pack_root(recipe_file, prepared + '/prepared/' + arch, publisher)!
		packed.close()
	}
	pkgcore.publish(publisher, 'wine-fixture', seed, 1, time.now().unix() + 86400)!
	extras := work + '/extras'
	for directory in ['/usr/bin', '/usr/sbin', '/etc/vinix', '/etc/vinix-packages',
		'/var/lib/vinix-packages'] {
		os.mkdir_all(extras + directory)!
	}
	for name in ['usr/sbin/vinix-account', 'usr/sbin/vinix-session'] {
		os.cp(stage + '/' + name, extras + '/' + name)!
	}
	os.cp(package_cli, extras + '/usr/bin/vinix-package')!
	os.cp(sandbox, extras + '/usr/bin/vinix-sandbox')!
	if arch == 'aarch64' {
		os.mkdir_all(extras + '/usr/libexec/wine-qualification')!
		os.cp(translator_original, extras + '/usr/libexec/wine-qualification/qemu-original')!
		os.cp(translator_busybox, extras + '/usr/libexec/wine-qualification/busybox')!
	}
	os.write_file(extras + '/etc/vinix/auth.conf', 'scrypt_ln = 10\nscrypt_p = 1\n')!
	config := pkgcore.Config{
		architecture: arch
		launch_user:  'alex'
		policy:       pkgcore.Policy{ offline: true, reserve_bytes: 0 }
		repositories: [pkgcore.Repository{ id: 'wine-fixture', url: 'file://' + publisher, public_key: key }]
	}
	os.write_file(extras + '/etc/vinix-packages/config.json', json2.encode(config))!
	service := pkgcore.Service{ root: extras }
	mut catalog := service.refresh()!
	catalog.close()
	mut state := service.transact('install', ['org.vinix.wine-win64-probe'], pkgcore.TransactionOptions{})!
	state.close()
	verify(inputs)!
	os.write_file(work + '/inputs.json', json2.encode(inputs))!
	mut generated := map[string]string{}
	for program in ['guest', 'package']! {
		for name in [program, program + '.c', 'runtime.c', 'v.log', 'v.log.argv.json', 'cc.log',
			'cc.log.argv.json', 'discover.log', 'discover.log.argv.json', 'sources-before.txt',
			'sources-built.txt'] {
			path := 'build-' + program + '/' + name
			generated[path] = digest(work + '/' + path)!
		}
	}
	for name in ['usr/bin/vinix-package', 'usr/sbin/vinix-account', 'usr/sbin/vinix-session',
		'usr/bin/vinix-sandbox', 'etc/vinix/auth.conf', 'etc/vinix-packages/config.json']! {
		generated['extras/' + name] = digest(extras + '/' + name)!
	}
	if arch == 'aarch64' {
		for name in ['qemu-original', 'busybox']! {
			generated['extras/usr/libexec/wine-qualification/' + name] = digest(extras + '/usr/libexec/wine-qualification/' + name)!
		}
	}
	os.write_file(work + '/generated-before-boot.json', json2.encode(generated))!
	os.write_file(work + '/declaration.json', json2.encode({
		'architecture':        arch
		'source_root':         root
		'run':                 work
		'prepared':            prepared
		'prepared_namespace':  prepared
		'compiler':            host.v
		'kernel':              kernel
		'qemu':                host.qemu
		'firmware':            host.firmware
		'firmware_vars':       host.firmware_vars
		'arm_loader':          arm_loader
		'stage':               stage
		'sysroot':             sysroot
		'gcc_runtime':         gcc
		'sandbox':             sandbox
		'controller':          os.executable()
		'source_scope':        'parsed-v1'
		'iso_xorriso':         image_inputs['iso-xorriso']
		'iso_bootx64':         image_inputs['iso-BOOTX64.EFI']
		'iso_limine_cd':       image_inputs['iso-limine-uefi-cd.bin']
		'translator_original': translator_original
		'translator_busybox':  translator_busybox
	}))!
	scenario := hwhost.Scenario{
		name:        'packaged-Wine'
		arches:      [arch]
		qemu_x86_64: ['-cpu', 'max']
		required:    [
			if caller_death { 'Wine signed caller-SIGKILL holder-survived collection-retained natural-retirement PASS' }
			else if collection { 'Wine signed detached-client collection lease status37 natural-retirement PASS' }
			else { 'Wine signed-real-Win64 ordinary-private-prefix socket lease Windows-API outside-write-refused natural-exit PASS' },
			'HWTEST PASS packaged-Wine',
		]
		forbidden:   ['HWTEST FAIL', 'Kernel panic', 'KERNEL PANIC', 'FATAL EXCEPTION']
		ending:      .running
	}
	runtime_host := if arch == 'x86_64' {
		hwhost.Host{ ...host, root: plainiso.prepare(root, work)! }
	} else {
		host
	}
	// Collection stages an additional complete runtime generation in guest tmpfs.
	outcome := hwhost.run_scenario(runtime_host, scenario, hwhost.Run{ kernel: kernel, guest: guest, extras: extras, state: work + '/boot', timeout: 600, keep: true, memory_mib: if arch == 'aarch64' || collection { 3072 } else { 1024 } })
	os.write_file(work + '/result.json', json2.encode(outcome))!
	verify(inputs)!
	for path, expected in generated {
		if digest(work + '/' + path)! != expected {
			return error('Wine generated output changed: ' + path)
		}
	}
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	if digest(@FILE)! != sha256.hexhash($embed_file('wine-native-check.v').to_string()) {
		return error('compiled Wine native controller source changed')
	}
	if !outcome.passed || outcome.interrupted || outcome.reason != '' {
		return error('native Wine failed: ' + outcome.reason)
	}
	println('WINE NATIVE PASS ' + arch + ': ' + work)
}

fn main() {
	if plainiso.requested() {
		plainiso.build() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	check() or {
		eprintln(err)
		exit(1)
	}
}
