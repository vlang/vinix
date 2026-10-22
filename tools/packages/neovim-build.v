// SPDX-License-Identifier: GPL-2.0-or-later
// Build the pinned Neovim distribution without executing target generators.
import crypto.sha256
import json2
import nvimcompat
import os

struct Source {
	name string
	url string
	sha256 string
}

fn sources() []Source {
	return [
		Source{'neovim', 'https://codeload.github.com/neovim/neovim/tar.gz/5885a30e1e1225349079e7a1c4a3848aa8e43e42', '314bb8d8695cc2c1c9b69e6c93df8c75108ca66588dfffb81c42369d2f85c90a'},
		Source{'libuv', 'https://github.com/libuv/libuv/archive/v1.52.1.tar.gz', '478baf2599bfbc882c355288c9cb6f92e0e7dda435fa04031fa5b607cf3f414c'},
		Source{'lua', 'https://www.lua.org/ftp/lua-5.1.5.tar.gz', '2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333'},
		Source{'luv', 'https://github.com/luvit/luv/archive/1.52.1-0.tar.gz', 'e8b8774b31d24be4fcf2b021b90599ecccc8e476c61efcc59c3c10cab813a885'},
		Source{'lpeg', 'https://github.com/neovim/deps/raw/d495ee6f79e7962a53ad79670cb92488abe0b9b4/opt/lpeg-1.1.0.tar.gz', '4b155d67d2246c1ffa7ad7bc466c1ea899bbc40fef0257cc9c03cecbaed4352a'},
		Source{'lua-compat', 'https://github.com/lunarmodules/lua-compat-5.3/archive/v0.13.tar.gz', 'f5dc30e7b1fda856ee4d392be457642c1f0c259264a9b9bfbcb680302ce88fc2'},
		Source{'utf8proc', 'https://github.com/juliastrings/utf8proc/archive/v2.11.3.tar.gz', 'abfed50b6d4da51345713661370290f4f4747263ee73dc90356299dfc7990c78'},
		Source{'tree-sitter', 'https://github.com/tree-sitter/tree-sitter/archive/v0.26.13.tar.gz', 'ece24c3c5e2a76384075e830c7139b59fce8fb01e4ef8436fab08bbe10444c89'},
	]
}

fn runtime_notices() []Source {
	return [
		Source{'gcc-14.2.0-COPYING.RUNTIME', 'https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-14.2.0/COPYING.RUNTIME', '9d6b43ce4d8de0c878bf16b54d8e7a10d9bd42b75178153e3af6a815bdc90f74'},
		Source{'gcc-14.2.0-COPYING3', 'https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-14.2.0/COPYING3', '8ceb4b9ee5adedde47b31e975c1d90c73ad27b6b165a1dcd80c7c545eb65b903'},
	]
}

fn digest(path string) !string {
	contents := os.read_file(path)!
	defer { unsafe { contents.free() } }
	return sha256.hexhash(contents)
}

fn invoke(argv []string, directory string, log string) ! {
	os.mkdir_all(os.dir(log))!
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	mut process := os.new_process(argv[0])
	defer { process.close() }
	process.set_args(argv[1..])
	process.set_work_folder(directory)
	process.set_redirect_stdio_merged()
	process.run()
	C.close(process.stdio_fd[0]); process.stdio_fd[0] = -1
	output := process.stdout_slurp()
	process.wait()
	os.write_file(log, output)!
	if process.code != 0 {
		start := if output.len > 3000 { output.len - 3000 } else { 0 }
		return error('command failed (' + process.code.str() + '): ' + log + '\n' + output[start..])
	}
}

fn acquire(cache string) !map[string]string {
	os.mkdir_all(cache)!
	mut result := map[string]string{}
	for source in sources() {
		archive := cache + '/' + source.name + '.tar.gz'
		if !os.is_file(archive) {
			println('Fetch ' + source.name)
			invoke(['/usr/bin/curl', '--fail', '--location', '--proto', '=https', '--tlsv1.2', '--retry', '2', '--max-time', '180', '--max-filesize', '50000000', '--output', archive + '.part', source.url], cache, cache + '/' + source.name + '.fetch.log')!
			if digest(archive + '.part')! != source.sha256 { return error('source hash refused: ' + source.name) }
			os.mv(archive + '.part', archive)!
		}
		if digest(archive)! != source.sha256 { return error('cached source hash refused: ' + source.name) }
		result[source.name] = archive
	}
	for notice in runtime_notices() {
		path := cache + '/' + notice.name
		if !os.is_file(path) {
			invoke(['/usr/bin/curl', '--fail', '--location', '--proto', '=https', '--tlsv1.2', '--retry', '2', '--max-time', '60', '--max-filesize', '1000000', '--output', path + '.part', notice.url], cache, cache + '/' + notice.name + '.fetch.log')!
			if digest(path + '.part')! != notice.sha256 { return error('runtime notice hash refused: ' + notice.name) }
			os.mv(path + '.part', path)!
		}
		if digest(path)! != notice.sha256 { return error('cached runtime notice hash refused: ' + notice.name) }
		result[notice.name] = path
	}
	os.write_file(cache + '/sources.json', json2.encode(sources()) + '\n')!
	os.write_file(cache + '/runtime-notices.json', json2.encode(runtime_notices()) + '\n')!
	return result
}

const llvm = '/opt/homebrew/opt/llvm/bin'
const cmake = '/opt/homebrew/bin/cmake'
const ninja = '/opt/homebrew/bin/ninja'

struct Build {
	repository string
	arch string
	output string
	prefix string
	sysroot string
	gcc string
	toolchain string
	sources map[string]string
	archives map[string]string
	v string
	v_license string
}

fn (b Build) cc() []string {
	return [llvm + '/clang', '--target=' + b.arch + '-linux-musl', '--sysroot=' + b.sysroot,
		'--gcc-install-dir=' + b.gcc, '-O2', '-fPIC', '-fno-stack-protector']
}

fn (b Build) configure(name string, source string, arguments []string) ! {
	directory := b.output + '/build/' + name
	mut argv := [cmake, '-S', source, '-B', directory, '-G', 'Ninja',
		'-DCMAKE_MAKE_PROGRAM=' + ninja, '-DCMAKE_TOOLCHAIN_FILE=' + b.toolchain,
		'-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_INSTALL_PREFIX=' + b.prefix,
		'-DCMAKE_INSTALL_LIBDIR=lib', '-DBUILD_SHARED_LIBS=OFF', '-DBUILD_TESTING=OFF',
		'-DCMAKE_POSITION_INDEPENDENT_CODE=ON', '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON']
	argv << arguments
	println('Configure ' + name + ' ' + b.arch)
	invoke(argv, b.output, b.output + '/logs/' + name + '.configure.log')!
	invoke([ninja, '-C', directory, '-t', 'commands'], b.output, b.output + '/logs/' + name + '.commands.log')!
	commands := os.read_file(b.output + '/logs/' + name + '.commands.log')!
	if commands.to_lower().contains('python') { return error('Python build command refused: ' + name) }
	println('Build ' + name + ' ' + b.arch)
	invoke([cmake, '--build', directory, '--parallel', '2'], b.output, b.output + '/logs/' + name + '.build.log')!
	invoke([cmake, '--install', directory], b.output, b.output + '/logs/' + name + '.install.log')!
}

fn (b Build) static_library(name string, files []string, flags []string) ! {
	directory := b.output + '/build/' + name
	os.mkdir_all(directory)!
	mut objects := []string{}
	for file in files {
		object := directory + '/' + os.base(file).all_before_last('.') + '.o'
		mut argv := b.cc()
		argv << flags
		argv << ['-c', file, '-o', object]
		invoke(argv, b.output, b.output + '/logs/' + name + '.' + os.base(file) + '.log')!
		objects << object
	}
	mut argv := [llvm + '/llvm-ar', 'rcs', b.prefix + '/lib/lib' + name + '.a']
	argv << objects
	invoke(argv, b.output, b.output + '/logs/' + name + '.archive.log')!
}

fn c_files(directory string) ![]string {
	mut result := []string{}
	for name in os.ls(directory)! { if name.ends_with('.c') { result << directory + '/' + name } }
	result.sort()
	return result
}

fn (b Build) lua() ! {
	source := b.sources['lua'] + '/src'
	mut files := []string{}
	for name in ['lapi', 'lcode', 'ldebug', 'ldo', 'ldump', 'lfunc', 'lgc', 'llex', 'lmem',
		'lobject', 'lopcodes', 'lparser', 'lstate', 'lstring', 'ltable', 'ltm', 'lundump', 'lvm', 'lzio',
		'lauxlib', 'lbaselib', 'ldblib', 'liolib', 'lmathlib', 'loslib', 'ltablib', 'lstrlib', 'loadlib', 'linit'] {
		files << source + '/' + name + '.c'
	}
	b.static_library('lua', files, ['-DLUA_USE_POSIX', '-DLUA_USE_DLOPEN'])!
	for name in ['lua.h', 'luaconf.h', 'lauxlib.h', 'lualib.h'] { os.cp(source + '/' + name, b.prefix + '/include/' + name)! }
	b.static_library('lpeg', c_files(b.sources['lpeg'])!, ['-I' + b.prefix + '/include'])!
}

fn (b Build) host_generator() !string {
	directory := b.output + '/host'
	os.mkdir(directory)!
	module_path := directory + '/nlua0.so'
	mut argv := [llvm + '/clang', '-O2', '-fPIC', '-DNVIM_NLUA0', '-bundle', '-undefined', 'dynamic_lookup',
		'-I/opt/homebrew/opt/luajit/include/luajit-2.1', '-I' + b.sources['neovim'] + '/src',
		b.sources['neovim'] + '/src/nlua0.c']
	argv << c_files(b.sources['neovim'] + '/src/mpack')!
	argv << c_files(b.sources['lpeg'])!
	argv << ['-o', module_path]
	invoke(argv, b.output, b.output + '/logs/host-generator.log')!
	return module_path
}

fn inventory(directory string) !map[string]string {
	mut result := map[string]string{}
	mut paths := os.walk_ext(directory, '')
	paths.sort()
	for path in paths { if os.is_file(path) { result[path[directory.len + 1..]] = digest(path)! } }
	return result
}

fn tool_inputs(v string, v_license string) !map[string]string {
	mut result := map[string]string{}
	for path in [llvm + '/clang', llvm + '/clang++', '/opt/homebrew/bin/ld.lld', llvm + '/llvm-ar', llvm + '/llvm-ranlib', llvm + '/llvm-readelf',
		cmake, ninja, '/opt/homebrew/bin/luajit', '/opt/homebrew/bin/nvim', '/usr/bin/tar', '/usr/bin/curl', v, v_license,
		os.dir(v) + '/vlib/os/execute_capture_nix.h', os.dir(v) + '/vlib/sync/thread_helper.h'] {
		result[path] = digest(path)!
	}
	return result
}

fn (b Build) adapter(name string, source string, destination string) ! {
	directory := b.output + '/adapters/' + name
	os.mkdir_all(directory)!
	os.cp(source, directory + '/' + name + '.v')!
	generated := directory + '/' + name + '.c'
	invoke([b.v, '-backend', 'c', '-prod', '-os', 'linux', '-arch', if b.arch == 'aarch64' { 'arm64' } else { 'amd64' },
		'-gc', 'none', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
		'-o', generated, directory + '/' + name + '.v'], b.output, b.output + '/logs/' + name + '.generate.log')!
	runtime := directory + '/runtime.c'
	os.write_file(runtime, '#include <unistd.h>\n#include <fcntl.h>\n#include <sys/wait.h>\n#define V_OS_EXECUTE_SCOPE\n#include "' +
		os.dir(b.v) + '/vlib/os/execute_capture_nix.h"\n#include "' + os.dir(b.v) + '/vlib/sync/thread_helper.h"\n')!
	mut command := b.cc()
	command << ['-fuse-ld=lld', '-static', '-static-libgcc', '-D_GNU_SOURCE', '-Wno-error=incompatible-pointer-types',
		generated, runtime, '-lm', '-lpthread', '-o', destination]
	invoke(command, b.output, b.output + '/logs/' + name + '.link.log')!
}

fn copy_payload(source string, destination string, executable bool) ! {
	os.mkdir_all(os.dir(destination))!
	os.cp(source, destination)!
	os.chmod(destination, if executable { 0o755 } else { 0o644 })!
	if digest(source)! != digest(destination)! { return error('payload copy changed: ' + source) }
}

fn (b Build) prepared(roots string) ! {
	if os.is_link(roots) { return error('prepared roots must be an ordinary directory') }
	os.mkdir_all(roots, mode: 0o700)!
	root := roots + '/' + b.arch
	if os.exists(root) { return error('prepared architecture root already exists') }
	os.mkdir(root, mode: 0o700)!
	copy_payload(b.prefix + '/bin/nvim', root + '/bin/nvim', true)!
	for name in ['neovim-runner'] {
		b.adapter(name, b.repository + '/tools/packages/' + name + '.v', root + '/bin/vinix-' + name)!
		copy_payload(b.output + '/adapters/' + name + '/' + name + '.v', root + '/sources/' + name + '.v', false)!
	}
	// Materialize only ordinary data. The signed import never depends on
	// symlinks, upstream install modes or a mutable host runtime directory.
	data := b.prefix + '/share/nvim/runtime'
	for path in os.walk_ext(data, '') {
		if os.lstat(path)!.get_filetype() != .regular { return error('unexpected runtime data node: ' + path) }
		copy_payload(path, root + '/share/nvim/runtime/' + path[data.len + 1..], false)!
	}
	for name, license_path in {'neovim': 'LICENSE.txt', 'libuv': 'LICENSE', 'lua': 'COPYRIGHT', 'luv': 'LICENSE.txt',
		'lpeg': 'lpeg.html', 'lua-compat': 'LICENSE', 'utf8proc': 'LICENSE.md', 'tree-sitter': 'LICENSE'} {
		label := if name == 'lpeg' { 'LICENSE' } else { license_path }
		copy_payload(b.sources[name] + '/' + license_path, root + '/licenses/' + name + '-' + label, false)!
	}
	for name, path in {'musl': b.repository + '/build-support/musl/COPYRIGHT',
		'vinix': b.repository + '/LICENSE', 'v': b.v_license} {
		copy_payload(path, root + '/licenses/' + name + '-' + if name == 'vinix' { 'COPYING' } else { 'COPYRIGHT' }, false)!
	}
	for source in sources() { copy_payload(b.archives[source.name], root + '/sources/' + source.name + '.tar.gz', false)! }
	for notice in runtime_notices() { copy_payload(b.archives[notice.name], root + '/licenses/' + notice.name, false)! }
	copy_payload(b.output + '/neovim-build.v', root + '/sources/neovim-build.v', false)!
	copy_payload(b.output + '/nvimcompat-libuv.v', root + '/sources/nvimcompat-libuv.v', false)!
	copy_payload(b.output + '/source-patches.json', root + '/sources/libuv-patches.json', false)!
	mut commands := map[string][]string{}
	for path in os.walk_ext(b.output + '/logs', '.argv.json') {
		commands[os.base(path)] = json2.decode[[]string](os.read_file(path)!)!
	}
	os.write_file(root + '/sources/build.json', json2.encode(commands) + '\n')!
	os.write_file(b.output + '/prepared.json', json2.encode(inventory(root)!) + '\n')!
}

fn build(root string, output string, architecture string, archives map[string]string, prepared string) ! {
	if architecture !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	if os.exists(output) { return error('--out must be a new directory') }
	sysroot := root + if architecture == 'aarch64' { '/build-aarch64-x11/sysroot' } else { '/build-amd64-x11/sysroot' }
	userland := root + if architecture == 'aarch64' { '/build-aarch64-userland/staging' } else { '/build/session-amd64-sysroot' }
	gcc := userland + '/usr/lib/gcc/' + architecture + '-alpine-linux-musl/14.2.0'
	if !os.is_file(sysroot + '/usr/lib/libc.so') || !os.is_dir(gcc) { return error('musl development sysroot is missing') }
	os.mkdir(output, mode: 0o700)!
	for notice in runtime_notices() { if digest(archives[notice.name])! != notice.sha256 { return error('runtime notice changed before build: ' + notice.name) } }
	mut inputs := map[string]string{}
	for source in sources() {
		archive := archives[source.name]
		if digest(archive)! != source.sha256 { return error('source changed before extraction: ' + source.name) }
		directory := output + '/source/' + source.name
		os.mkdir_all(directory, mode: 0o700)!
		invoke(['/usr/bin/tar', '-xzf', archive, '--strip-components=1', '-C', directory], output,
			output + '/logs/' + source.name + '.extract.log')!
		inputs[source.name] = directory
	}
	os.mkdir_all(output + '/prefix/include')!
	os.mkdir_all(output + '/prefix/lib')!
	toolchain := output + '/toolchain.cmake'
	os.write_file(toolchain, 'set(CMAKE_SYSTEM_NAME Linux)\nset(CMAKE_SYSTEM_PROCESSOR ' + architecture + ')\n' +
		'set(CMAKE_C_COMPILER "' + llvm + '/clang")\nset(CMAKE_CXX_COMPILER "' + llvm + '/clang++")\n' +
		'set(CMAKE_C_COMPILER_TARGET ' + architecture + '-linux-musl)\nset(CMAKE_CXX_COMPILER_TARGET ' + architecture + '-linux-musl)\n' +
		'set(CMAKE_SYSROOT "' + sysroot + '")\nset(CMAKE_AR "' + llvm + '/llvm-ar")\nset(CMAKE_RANLIB "' + llvm + '/llvm-ranlib")\n' +
		'set(CMAKE_C_FLAGS_INIT "--gcc-install-dir=' + gcc + ' -fno-stack-protector")\n' +
		'set(CMAKE_CXX_FLAGS_INIT "--gcc-install-dir=' + gcc + ' -fno-stack-protector")\n' +
		'set(CMAKE_EXE_LINKER_FLAGS_INIT "-fuse-ld=lld -static-libgcc")\nset(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld -static-libgcc")\n' +
		'set(CMAKE_MODULE_LINKER_FLAGS_INIT "-fuse-ld=lld -static-libgcc")\n' +
		'set(CMAKE_FIND_ROOT_PATH "' + output + '/prefix;' + sysroot + '")\n' +
		'set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)\nset(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)\n' +
		'set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)\nset(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)\n')!
	v := os.real_path(os.getenv_opt('VINIX_NEOVIM_V') or { return error('VINIX_NEOVIM_V must name the pinned V compiler') })
	v_license := os.real_path(os.getenv_opt('VINIX_NEOVIM_V_LICENSE') or { os.dir(v) + '/LICENSE' })
	repository := os.dir(os.dir(os.dir(@FILE)))
	b := Build{repository: repository, arch: architecture, output: output, prefix: output + '/prefix', sysroot: sysroot,
		gcc: gcc, toolchain: toolchain, sources: inputs, archives: archives, v: v, v_license: v_license}
	tools := tool_inputs(v, v_license)!
	os.write_file(output + '/tools.json', json2.encode(tools) + '\n')!
	// Preserve the archive-derived tree before the one explicit compatibility
	// selection, then bind the exact patched tree used by every build command.
	mut upstream := map[string]map[string]string{}
	for name, directory in inputs { upstream[name] = inventory(directory)! }
	os.write_file(output + '/upstream-source-inventory.json', json2.encode(upstream) + '\n')!
	libuv_path := inputs['libuv'] + '/src/unix/linux.c'
	libuv_original := os.read_file(libuv_path)!
	libuv_patched := nvimcompat.libuv_linux(libuv_original)!
	os.write_file(libuv_path, libuv_patched)!
	os.write_file(output + '/source-patches.json', json2.encode({
		'libuv/src/unix/linux.c': {
			'original-sha256': sha256.hexhash(libuv_original)
			'patched-sha256': sha256.hexhash(libuv_patched)
			'original-branch': nvimcompat.libuv_original
			'replacement-branch': nvimcompat.libuv_replacement
			'compiler-define': nvimcompat.libuv_define + '=1'
		}
	}) + '\n')!
	mut before := map[string]map[string]string{}
	for name, directory in inputs { before[name] = inventory(directory)! }
	os.write_file(output + '/source-inventory.json', json2.encode(before) + '\n')!
	os.cp(@FILE, output + '/neovim-build.v')!
	os.cp(repository + '/tools/packages/nvimcompat/libuv.v', output + '/nvimcompat-libuv.v')!
	os.setenv('PKG_CONFIG_LIBDIR', b.prefix + '/lib/pkgconfig', true)
	os.unsetenv('PKG_CONFIG_PATH')
	b.lua()!
	b.configure('libuv', inputs['libuv'], ['-DLIBUV_BUILD_TESTS=OFF', '-DLIBUV_BUILD_BENCH=OFF', '-DLIBUV_BUILD_SHARED=OFF',
		'-DCMAKE_C_FLAGS=--gcc-install-dir=' + gcc + ' -fno-stack-protector -D' + nvimcompat.libuv_define + '=1'])!
	b.configure('utf8proc', inputs['utf8proc'], ['-DUTF8PROC_ENABLE_TESTING=OFF'])!
	b.configure('tree-sitter', inputs['tree-sitter'], ['-DTREE_SITTER_FEATURE_WASM=OFF'])!
	b.configure('luv', inputs['luv'], ['-DLUA_BUILD_TYPE=System', '-DWITH_LUA_ENGINE=Lua',
		'-DWITH_SHARED_LIBUV=ON', '-DBUILD_STATIC_LIBS=ON', '-DBUILD_MODULE=OFF',
		'-DLUA_COMPAT53_DIR=' + inputs['lua-compat'], '-DLUA_INCLUDE_DIR=' + b.prefix + '/include',
		'-DLUA_LIBRARY=' + b.prefix + '/lib/liblua.a', '-DLIBUV_INCLUDE_DIR=' + b.prefix + '/include',
		'-DLIBUV_LIBRARY=' + b.prefix + '/lib/libuv.a'])!
	host := b.host_generator()!
	b.configure('neovim', inputs['neovim'], ['-DPREFER_LUA=ON', '-DCOMPILE_LUA=OFF',
		'-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld -static -static-libgcc',
		'-DENABLE_LIBINTL=OFF', '-DENABLE_TRANSLATIONS=OFF', '-DENABLE_UNIBILIUM=OFF', '-DENABLE_WASMTIME=OFF', '-DENABLE_LTO=OFF',
		'-DLUA_PRG=/opt/homebrew/bin/luajit', '-DLUA_GEN_PRG=/opt/homebrew/bin/luajit',
		'-DNVIM_HOST_PRG=/opt/homebrew/bin/nvim', '-DNLUA0_HOST_PRG=' + host,
		'-DLUA_INCLUDE_DIR=' + b.prefix + '/include', '-DLUA_LIBRARY=' + b.prefix + '/lib/liblua.a',
		'-DLPEG_LIBRARY=' + b.prefix + '/lib/liblpeg.a', '-DLUV_LIBRARY=' + b.prefix + '/lib/libluv.a',
		'-DLUV_INCLUDE_DIR=' + b.prefix + '/include', '-DLIBUV_LIBRARY=' + b.prefix + '/lib/libuv.a',
		'-DLIBUV_INCLUDE_DIR=' + b.prefix + '/include', '-DTREESITTER_LIBRARY=' + b.prefix + '/lib/libtree-sitter.a',
		'-DTREESITTER_INCLUDE_DIR=' + b.prefix + '/include', '-DUTF8PROC_LIBRARY=' + b.prefix + '/lib/libutf8proc.a',
		'-DUTF8PROC_INCLUDE_DIR=' + b.prefix + '/include'])!
	for name, directory in inputs { if inventory(directory)! != before[name] { return error('source changed during build: ' + name) } }
	if prepared != '' { b.prepared(prepared)! }
	if tool_inputs(v, v_license)! != tools { return error('build tool changed during target build') }
	for source in sources() { if digest(archives[source.name])! != source.sha256 { return error('source archive changed during build: ' + source.name) } }
	for notice in runtime_notices() { if digest(archives[notice.name])! != notice.sha256 { return error('runtime notice changed during build: ' + notice.name) } }
	invoke([llvm + '/llvm-readelf', '-h', '-l', '-d', b.prefix + '/bin/nvim'], output, output + '/logs/neovim.elf.log')!
	os.write_file(output + '/artifacts.json', json2.encode(inventory(b.prefix)!) + '\n')!
	os.write_file(output + '/evidence.json', json2.encode(inventory(output + '/logs')!) + '\n')!
	println('NEOVIM TARGET BUILD PASS ' + architecture + ' ' + output)
}

fn main() {
	run() or { eprintln(err); exit(1) }
}

fn run() ! {
	$if prod {} $else { return error('compile neovim-build with -prod to bind the retained builder source') }
	if os.read_file(@FILE)! != $embed_file('neovim-build.v').to_string() { return error('builder source differs from the compiled driver') }
	compat_path := os.dir(@FILE) + '/nvimcompat/libuv.v'
	if os.read_file(compat_path)! != $embed_file('nvimcompat/libuv.v').to_string() { return error('libuv compatibility helper differs from the compiled driver') }
	mut options := map[string]string{}
	for argument in os.args[1..] {
		if !argument.starts_with('--') || !argument.contains('=') { return error('use --cache=ABSOLUTE_DIRECTORY [--arch=aarch64|x86_64 --out=NEW_DIRECTORY --root=REPOSITORY]') }
		options[argument.all_before('=')] = argument.all_after('=')
	}
	cache := os.abs_path(options['--cache'] or { return error('--cache is required') })
	inputs := acquire(cache)!
	println('NEOVIM PINNED SOURCES PASS ' + cache)
	if architecture := options['--arch'] {
		root := os.real_path(options['--root'] or { return error('--root is required for target builds') })
		output := os.abs_path(options['--out'] or { return error('--out is required for target builds') })
		prepared := if path := options['--prepared'] { os.abs_path(path) } else { '' }
		build(root, output, architecture, inputs, prepared)!
	}
	if os.read_file(@FILE)! != $embed_file('neovim-build.v').to_string() { return error('builder source changed during execution') }
	if os.read_file(compat_path)! != $embed_file('nvimcompat/libuv.v').to_string() { return error('libuv compatibility helper changed during execution') }
}
