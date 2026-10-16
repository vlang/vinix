// SPDX-License-Identifier: GPL-2.0-or-later
// Build/install the desktop's small services without staging ui2 or artwork.
module main

import os
import crypto.sha256

const service_names = ['vinix-session', 'vinix-timesync', 'vinix-service-runner']
const service_sources = ['session', 'timesync', 'runner']

fn run(program string, args []string) ! {
	mut process := os.new_process(program)
	defer { process.close() }
	process.set_args(args)
	process.run()
	process.wait()
	if process.code != 0 { return error('${program} failed (${process.code})') }
}

fn install_services(output string, staging string) ! {
	os.mkdir_all(staging + '/usr/bin')!
	for name in service_names {
		source := output + '/' + name
		if !os.is_executable(source) { return error('missing service executable: ${source}') }
		destination := staging + '/usr/bin/' + name
		if os.is_link(destination) { os.rm(destination)! }
		os.cp(source, destination)!
		os.chmod(destination, 0o755)!
	}
}

fn stage_client_modules(root string, staging string) ! {
	// The editable in-guest desktop also needs its shared client imports.
	for name in ['sessioncore', 'sessionipc'] {
		destination := staging + '/usr/share/vinix/desktop-dev/vmodules/desktop/' + name
		if os.is_dir(destination) { os.rmdir_all(destination)! }
		os.mkdir_all(os.dir(destination))!
		os.mkdir_all(destination)!
		for path in os.walk_ext(root + '/desktop/' + name, '.v') {
			if path.ends_with('_test.v') { continue }
			filename := os.file_name(path)
			os.cp(path, destination + '/' + filename)!
		}
	}
}

fn main() {
	root := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	mut arch := 'arm64'
	mut sysroot := ''
	mut output := root + '/build/services'
	mut staging := ''
	mut install_only := false
	mut modules_only := false
	for arg in os.args[1..] {
		if arg.starts_with('--arch=') {
			arch = arg['--arch='.len..]
		} else if arg.starts_with('--sysroot=') {
			sysroot = os.real_path(arg['--sysroot='.len..])
		} else if arg.starts_with('--output=') {
			output = os.abs_path(arg['--output='.len..])
		} else if arg.starts_with('--staging=') {
			staging = os.abs_path(arg['--staging='.len..])
		} else if arg == '--install-only' {
			install_only = true
		} else if arg == '--client-modules-only' {
			modules_only = true
		} else {
			eprintln('Usage: build-services.v --arch=arm64|amd64|native --sysroot=DIR --output=DIR [--staging=DIR] [--install-only]')
			exit(2)
		}
	}
	if modules_only {
		if staging == '' {
			eprintln('--client-modules-only requires --staging')
			exit(2)
		}
		stage_client_modules(root, staging)!
		return
	}
	if install_only {
		if staging == '' {
			eprintln('--install-only requires --staging')
			exit(2)
		}
		install_services(output, staging)!
		return
	}
	if arch !in ['arm64', 'amd64', 'native'] {
		eprintln('unsupported service architecture')
		exit(2)
	}
	mut compiler := os.getenv('V')
	if compiler == '' { compiler = os.getenv('VINIX_V_COMPILER') }
	if compiler == '' {
		compiler = os.find_abs_path_of_executable('v') or { os.home_dir() + '/code/v/v' }
	}
	if os.is_dir(compiler) { compiler += '/v' }
	if !compiler.contains('/') { compiler = os.find_abs_path_of_executable(compiler)! }
	os.mkdir_all(output)!
	if arch != 'native' && sysroot == '' {
		eprintln('cross builds require --sysroot')
		exit(2)
	}
	mut llvm := os.getenv('LLVM_BIN')
	if llvm == '' { llvm = '/opt/homebrew/opt/llvm/bin' }
	clang := if arch == 'amd64' && os.getenv('VINIX_AMD64_CLANG') != '' {
		os.getenv('VINIX_AMD64_CLANG')
	} else if os.is_executable(llvm + '/clang') {
		llvm + '/clang'
	} else {
		os.find_abs_path_of_executable('clang')!
	}
	mut gcc := ''
	if arch != 'native' {
		triple := if arch == 'arm64' { 'aarch64' } else { 'x86_64' }
		base := sysroot + '/usr/lib/gcc/' + triple + '-alpine-linux-musl'
		mut versions := os.ls(base)!
		versions.sort()
		for version in versions {
			if os.is_file(base + '/' + version + '/crtbeginT.o') { gcc = base + '/' + version }
		}
		if gcc == '' {
			eprintln('missing static GCC runtime in ${base}')
			exit(1)
		}
	}
	// Cache only service source/modules and the selected compiler/runtime inputs.
	mut inputs := [compiler, arch, sysroot, clang]
	for directory in ['services', 'sessiondaemon', 'sessionipc', 'serviceprocess', 'servicerunner',
		'timesync', 'sessioncore'] {
		mut files := os.walk_ext(root + '/desktop/' + directory, '.v')
		files.sort()
		for path in files {
			if path.ends_with('_test.v') { continue }
			inputs << path
			inputs << sha256.sum(os.read_bytes(path)!).hex()
		}
	}
	inputs << sha256.sum(os.read_bytes(@FILE)!).hex()
	for path in [compiler, if arch == 'native' { clang } else { sysroot + '/usr/lib/libc.a' }] {
		info := os.stat(path)!
		inputs << '${info.size}:${info.mtime}'
	}
	key := sha256.sum(inputs.join('\n').bytes()).hex()
	for index, name in service_names {
		binary := output + '/' + name
		if os.is_executable(binary) && (os.read_file(binary + '.key') or { '' }) == key { continue }
		println('Building ${name} (${arch})')
		mut flags := ['-new-compiler', '-gc', 'none', '-manualfree', '-enable-globals', '-prod',
			'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-path', '@vlib|@vmodules|' + root]
		source := root + '/desktop/services/' + service_sources[index]
		if arch == 'native' {
			run(compiler, [...flags, '-cc', 'clang', '-o', binary + '.tmp', source])!
		} else {
			generated := binary + '.c'
			run(compiler, [...flags, '-os', 'linux', '-arch', arch, '-o', generated, source])!
			triple := if arch == 'arm64' { 'aarch64' } else { 'x86_64' }
			run(clang, ['--target=' + triple + '-linux-musl', '-static', '-nostdinc', '-nostdlib',
				'-isystem', gcc + '/include', '-isystem', sysroot + '/usr/include', '-isystem',
				root + '/build-support/aarch64-cc-shim', '-D_GNU_SOURCE', '-O2', '-fno-stack-protector',
				'-w', sysroot + '/usr/lib/crt1.o', sysroot + '/usr/lib/crti.o', gcc + '/crtbeginT.o',
				generated, '-L' + sysroot + '/usr/lib', '-L' + gcc, '-lgcc_eh', '-lc', '-lgcc',
				'-lm', '-lpthread', gcc + '/crtend.o', sysroot + '/usr/lib/crtn.o', '-fuse-ld=lld',
				'-o', binary + '.tmp'])!
		}
		os.rename(binary + '.tmp', binary)!
		os.write_file(binary + '.key', key)!
	}
	if staging != '' { install_services(output, staging)! }
}
