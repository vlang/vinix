// SPDX-License-Identifier: GPL-2.0-or-later
// Prepare the existing pinned Wine Win64 distribution and a native SDK bridge.
// This does not infer redistribution rights or enroll a publisher key.
module main

import crypto.sha256
import json2
import os
import wineadapter

struct Entry { source string; path string }
struct Recipe { format int = 1; manifest Manifest; entries []Entry }
struct Dependency { id string; minimum string; before string }
struct Manifest {
	id string
	version string
	architecture string
	name string
	description string
	homepage string
	license string
	kind string
	runtime string
	entrypoint string
	arguments []string
	permissions []string
	dependencies []Dependency
	sdk int = 1
}

fn digest(path string) !string {
	text := os.read_file(path)!
	defer { unsafe { text.free() } }
	return sha256.hexhash(text)
}

fn verify_sources() ! {
	$if prod {} $else { return error('compile Wine producer with -prod for embedded source admission') }
	for path, contents in {
		@FILE: $embed_file('wine-build.v').to_string()
		os.dir(@FILE) + '/wine-runner.v': $embed_file('wine-runner.v').to_string()
	} {
		if digest(path)! != sha256.hexhash(contents) { return error('compiled Wine producer source differs: ' + path) }
	}
}

fn invoke(argv []string, log string) !string {
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..]); child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	child.wait()
	os.write_file(log, output)!
	if child.code != 0 { unsafe { output.free() }; return error('Wine producer command failed; see ' + log) }
	return output
}

fn copy_input(source string, destination string, mut inputs map[string]string) ! {
	if !os.is_file(source) { return error('missing Wine distribution input: ' + source) }
	inputs[source] = digest(source)!
	os.mkdir_all(os.dir(destination))!
	os.cp(source, destination)!
	os.chmod(destination, if os.stat(source)!.mode & 0o111 != 0 { 0o755 } else { 0o644 })!
	if digest(destination)! != inputs[source] { return error('Wine copied input differs: ' + source) }
}

fn dependencies(seeds []string, root string, destination string, work string, mut inputs map[string]string) ! {
	mut pending := seeds.clone()
	mut seen := map[string]bool{}
	for pending.len > 0 {
		file := pending.pop()
		if file in seen { continue }
		seen[file] = true
		output := invoke(['/opt/homebrew/opt/llvm/bin/llvm-readelf', '-d', file], work + '/elf-' + seen.len.str() + '.log')!
		for line in output.split_into_lines() {
			if !line.contains('(NEEDED)') { continue }
			name := line.all_after('[').all_before(']')
			if name == '' || name.contains('/') { return error('invalid Wine ELF dependency') }
			mut source := ''
			mut relative := ''
			for directory in ['/lib/', '/usr/lib/', '/usr/lib/wine/x86_64-unix/', '/usr/lib/pulseaudio/']! {
				if os.is_file(root + directory + name) { source = root + directory + name; relative = directory + name; break }
			}
			if source == '' { return error('missing Wine ELF dependency: ' + name) }
			if !os.exists(destination + relative) { copy_input(source, destination + relative, mut inputs)! }
			pending << source
		}
	}
}

fn build() ! {
	verify_sources()!
	if os.args.len != 10 || os.args[9] != '--local-qualification-only' {
		return error('usage: wine-build ARCH TRANSLATION_STAGE OUTPUT V MUSL_SYSROOT GCC_RUNTIME NOTICES PE_PRODUCER --local-qualification-only')
	}
	arch := os.args[1]
	if arch !in ['aarch64', 'x86_64'] { return error('Wine producer architecture must be aarch64 or x86_64') }
	stage := os.real_path(os.args[2])
	output := os.abs_path(os.args[3])
	v := os.real_path(os.args[4])
	sysroot := os.real_path(os.args[5])
	gcc := os.real_path(os.args[6])
	notices := os.real_path(os.args[7])
	pe_directory := os.real_path(os.args[8])
	base := os.dir(os.dir(os.dir(os.real_path(@FILE)))))
	mut pe := wineadapter.admit_local_pe_proof(pe_directory, base + '/tests/packages/wine-native/program.v', base + '/tests/packages/wine-pe-check.v')!
	defer { pe.close() }
	application := pe.executable
	if os.exists(output) { return error('Wine producer needs a new output directory') }
	// This producer deliberately supports local experiments only. Incomplete
	// corresponding source cannot authorize redistribution of this closure.
	mut offer := wineadapter.admit_local_source_offer(notices, 'org.vinix.wine-runtime', '9.17-r1', arch)!
	defer { offer.close() }
	root := stage + '/usr/libexec/vinix-x86_64/root'
	os.mkdir_all(output + '/build')!
	os.mkdir_all(output + '/logs')!
	prepared := output + '/prepared/' + arch
	runtime := prepared + '/runtime'
	app := prepared + '/application'
	mut inputs := map[string]string{}
	for path in [os.executable(), '/opt/homebrew/opt/llvm/bin/llvm-readelf', '/usr/bin/tar']! { inputs[path] = digest(path)! }
	os.write_file(output + '/build-producer.json', json2.encode({'executable': os.executable(), 'compiler': v, 'source': @FILE}) + '\n')!
	for path, hash in pe.artifacts { inputs[path] = hash }
	os.write_file(output + '/pe-producer.json', json2.encode({
		'directory': pe_directory, 'executable': application,
		'program_source': base + '/tests/packages/wine-native/program.v',
		'producer_source': base + '/tests/packages/wine-pe-check.v'
	}) + '\n')!
	mut seeds := []string{}
	for relative in ['/usr/bin/wine', '/usr/bin/wineserver', '/lib/ld-musl-x86_64.so.1']! {
		copy_input(root + relative, runtime + '/root' + relative, mut inputs)!
		seeds << root + relative
	}
	for directory in ['/usr/lib/wine/x86_64-windows', '/usr/lib/wine/x86_64-unix', '/usr/share/wine', '/etc/fonts']! {
		for path in os.walk_ext(root + directory, '') {
			if os.is_dir(path) { continue }
			if !os.is_file(path) { return error('Wine data node is not an ordinary file: ' + path) }
			copy_input(path, runtime + '/root' + path[root.len..], mut inputs)!
			if directory.ends_with('-unix') { seeds << path }
		}
	}
	dependencies(seeds, root, runtime + '/root', output + '/logs', mut inputs)!
	// Wine derives ../share/wine from its usr/bin entrypoint. These files
	// must retain the distribution layout even when entered through musl.
	for name in ['locale.nls', 'l_intl.nls']! {
		if digest(runtime + '/root/usr/share/wine/nls/' + name)! != inputs[root + '/usr/share/wine/nls/' + name] {
			return error('Wine NLS resource differs from its distribution input: ' + name)
		}
	}
	if digest(runtime + '/root/usr/share/wine/wine.inf')! != inputs[root + '/usr/share/wine/wine.inf'] {
		return error('Wine INF resource differs from its distribution input')
	}
	for part in ['/usr/bin/wineserver', '/usr/lib/wine/x86_64-unix/ntdll.so']! {
		text := os.read_file(root + part)!
		patched := wineadapter.private_server_patch(text, part.ends_with('ntdll.so'))!
		os.write_file(runtime + '/root' + part, patched)!
		unsafe { text.free(); patched.free() }
	}
	if arch == 'aarch64' {
		copy_input(stage + '/usr/bin/qemu-x86_64', runtime + '/bin/qemu-x86_64', mut inputs)!
		text := os.read_file(runtime + '/bin/qemu-x86_64')!
		patched := wineadapter.splitwx_patch(text)!
		os.write_file(runtime + '/bin/qemu-x86_64', patched)!
		os.chmod(runtime + '/bin/qemu-x86_64', 0o755)!
		unsafe { text.free(); patched.free() }
		os.write_file(output + '/translator-patch.json', json2.encode({
			'input': stage + '/usr/bin/qemu-x86_64', 'input_sha256': wineadapter.qemu_splitwx_input,
			'output': runtime + '/bin/qemu-x86_64', 'output_sha256': digest(runtime + '/bin/qemu-x86_64')!,
			'scope': 'local-qualification-only: exact AArch64 tcg_init_machine argument instruction forces splitwx=1; no RWX fallback',
			'offset': '0x85c64', 'before': '612e40b9', 'after': '21008052'
		}) + '\n')!
	}
	for path in os.walk_ext(notices, '') {
		if os.lstat(path)!.get_filetype() != .regular { return error('Wine notices/source offer must contain ordinary files') }
		copy_input(path, output + '/publisher-notices/' + path[notices.len + 1..], mut inputs)!
	}
	copy_input(notices + '/runtime-LICENSE.txt', runtime + '/licenses/runtime-LICENSE.txt', mut inputs)!
	copy_input(notices + '/application-LICENSE.txt', app + '/licenses/application-LICENSE.txt', mut inputs)!
	// Keep the complete supplied local record in the signed payload without
	// exhausting the format's selector bound with individual recipe fragments.
	mut copied_offer := wineadapter.admit_local_source_offer(output + '/publisher-notices', 'org.vinix.wine-runtime', '9.17-r1', arch)!
	copied_offer.close()
	invoke(['/usr/bin/tar', '--format=ustar', '-cf', runtime + '/licenses/local-source-evidence.tar', '-C', output + '/publisher-notices', '.'], output + '/logs/source-evidence.log')!
	mut checked_offer := wineadapter.admit_local_source_offer(output + '/publisher-notices', 'org.vinix.wine-runtime', '9.17-r1', arch)!
	checked_offer.close()
	copy_input(application, app + '/bin/program.exe', mut inputs)!
	for path in [base + '/tools/packages/wine-runner.v', @FILE] {
		inputs[path] = digest(path)!
	}
	for directory in [base + '/tools/packages/wineadapter', base + '/tools/packages/appsdk', base + '/tools/packages/pkgprotocol', os.dir(v) + '/vlib', os.dir(v) + '/thirdparty', sysroot + '/usr/include', sysroot + '/usr/lib', sysroot + '/lib', gcc] {
		for path in os.walk_ext(directory, '') { if os.is_file(path) { inputs[path] = digest(path)! } }
	}
	for path in [v, '/opt/homebrew/opt/llvm/bin/clang', '/opt/homebrew/bin/ld.lld', '/usr/bin/tar'] { inputs[path] = digest(path)! }
	os.write_file(output + '/inputs-before-build.json', json2.encode(inputs) + '\n')!
	generated := output + '/build/wine-runner.c'
	invoke([v, '-backend', 'c', '-prod', '-os', 'linux', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' },
		'-gc', 'none', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-o', generated,
		base + '/tools/packages/wine-runner.v'], output + '/logs/v.log')!
	runtime_c := output + '/build/runtime.c'
	os.write_file(runtime_c, '#include <unistd.h>\n#include <fcntl.h>\n#include <sys/wait.h>\n#define V_OS_EXECUTE_SCOPE\n#include "' +
		os.dir(v) + '/vlib/os/execute_capture_nix.h"\n#define V_SYNC_THREAD_SCOPE\n#include "' + os.dir(v) + '/vlib/sync/thread_helper.h"\n')!
	os.mkdir_all(runtime + '/bin')!
	invoke(['/opt/homebrew/opt/llvm/bin/clang', '--target=' + arch + '-linux-musl', '--sysroot=' + sysroot,
		'--gcc-install-dir=' + gcc, '-fuse-ld=lld', '-O2', '-w', '-fno-stack-protector', '-static', '-D_GNU_SOURCE',
		'-Wno-error=incompatible-pointer-types', generated, runtime_c, '-lm', '-lpthread', '-o', runtime + '/bin/wine-runner'], output + '/logs/cc.log')!
	for name in ['wine64', 'wineserver']! { os.cp(runtime + '/bin/wine-runner', runtime + '/bin/' + name)! }
	for role in ['application', 'runtime']! {
		payload := prepared + '/' + role
		mut entries := []Entry{}
		for path in os.walk_ext(payload, '') {
			if os.lstat(path)!.get_filetype() != .regular { return error('Wine prepared payload must use ordinary files') }
			relative := path[payload.len + 1..]
			entries << Entry{source: role + '/' + relative, path: relative}
		}
		manifest := if role == 'runtime' {
			Manifest{id: 'org.vinix.wine-runtime', version: '9.17.1', architecture: arch, name: 'Wine Win64 runtime',
				description: 'Private-prefix Wine 9.17 with explicit signed Win64 application closure', homepage: 'https://www.winehq.org/',
				license: 'LicenseRef-Vinix-Wine-Local-Qualification', kind: 'runtime'}
		} else {
			Manifest{id: 'org.vinix.wine-win64-probe', version: '1.0.0', architecture: arch, name: 'Wine Win64 qualification probe',
				description: 'Local Windows API qualification with an isolated explicit Wine runtime', homepage: 'https://github.com/vlang/vinix',
				license: 'GPL-2.0-or-later', kind: 'windows', runtime: 'org.vinix.wine-runtime', entrypoint: 'bin/wine-runner',
				arguments: ['@APP@/bin/program.exe'], permissions: ['process'],
				dependencies: [Dependency{'org.vinix.wine-runtime', '9.17.1', '10.0.0'}]}
		}
		os.write_file(output + '/' + role + '.json', json2.encode(Recipe{manifest: manifest, entries: entries}) + '\n')!
	}
	mut checked_pe := wineadapter.admit_local_pe_proof(pe_directory, base + '/tests/packages/wine-native/program.v', base + '/tests/packages/wine-pe-check.v')!
	defer { checked_pe.close() }
	if checked_pe.executable != application || checked_pe.artifacts != pe.artifacts { return error('Wine PE producer proof changed') }
	for path, hash in inputs { if digest(path)! != hash { return error('Wine producer input changed: ' + path) } }
	verify_sources()!
	os.write_file(output + '/inputs-verified.json', json2.encode(inputs) + '\n')!
	mut outputs := map[string]string{}
	for path in os.walk_ext(output, '') { if os.is_file(path) { outputs[path[output.len + 1..]] = digest(path)! } }
	os.write_file(output + '/outputs.json', json2.encode(outputs) + '\n')!
	println('Wine prepared ' + arch + ': ' + prepared)
}

fn main() { build() or { eprintln(err); exit(1) } }
