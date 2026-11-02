// SPDX-License-Identifier: GPL-2.0-or-later
module iosbuild

import cachecli
import cachekey
import crypto.sha256
import json2
import os
import sourcecommand
import tarstream

pub const gnu_cxx_artifacts = [
	Artifact{'libcxx-19.1.7.src.tar.xz', 'https://github.com/llvm/llvm-project/releases/download/llvmorg-19.1.7/libcxx-19.1.7.src.tar.xz', 'b736109650ffc750dbdc506483347b3713ded9d0300f48432b820ad66b6a9052'},
	Artifact{'libcxxabi-19.1.7.src.tar.xz', 'https://github.com/llvm/llvm-project/releases/download/llvmorg-19.1.7/libcxxabi-19.1.7.src.tar.xz', '4d25125109e3febe1393e9e30f93153333d82b48ce7bed637bd2daf52bf40172'},
	Artifact{'libunwind-19.1.7.src.tar.xz', 'https://github.com/llvm/llvm-project/releases/download/llvmorg-19.1.7/libunwind-19.1.7.src.tar.xz', '10e650f436bc416674f01b5e01177405886f4d0f0b2568c6808044eacad52ea0'},
]

pub struct GnuCxxOptions {
pub:
	output     string
	sources    string
	sysroot    string
	compiler   string
	archiver   string
	sanitizers bool
}

pub struct GnuCxxResult {
pub:
	include_dir    string
	libcxx_archive string
	abi_archive    string
	unwind_archive string
	manifest       string
	stamp          string
}

struct GnuCxxManifest {
	target                string = 'aarch64-linux-gnu'
	llvm_version          string = '19.1.7'
	sanitizers            bool
	compiler              string
	compiler_sha256       string
	compiler_version      string
	compiler_resource_dir string
	sysroot_headers       map[string]string
	resource_headers      map[string]string
	archiver              string
	archiver_sha256       string
	archiver_version      string
	sysroot               string
	consumer_flags        []string
	artifacts             map[string]string
	source_archives       []Artifact
	source_tree_keys      map[string]string
	input_key             string
	build_flags           map[string][]string
	per_file_flags        map[string][]string
	instrumentation       map[string]string
	scope                 string
	provenance            string
}

fn gnu_safe_path(value string) !string {
	if value == '' || value.contains_any('\x00\r\n\\"') {
		return error('GNU C++ path contains unsupported characters: ' + value)
	}
	return resolved(value)!
}

// Keep native glibc state inside the Apple-sized state instead of redefining
// glibc's internal __mbstate_t. In particular, native fpos_t must stay 16 bytes.
// The API-name mappings avoid ambiguous overloads for a null state argument.
pub fn gnu_cxx_preamble(sysroot string) !string {
	base := gnu_safe_path(sysroot)!
	return '#ifndef VINIX_IOS_GNU_ABI_H\n#define VINIX_IOS_GNU_ABI_H\n' +
		'#define __mbstate_t __vinix_gnu_native_mbstate_t\n' +
		'#define mbstate_t __vinix_gnu_native_public_mbstate_t\n' +
		'#include "' + base + '/include/stdio.h"\n' +
		'#include "' + base + '/include/wchar.h"\n' +
		'#include "' + base + '/include/uchar.h"\n' +
		'
#undef mbstate_t
#undef __mbstate_t
struct alignas(8) __mbstate_t {
  __vinix_gnu_native_mbstate_t __native;
  unsigned char __opaque[120];
};
typedef struct __mbstate_t mbstate_t;
static_assert(sizeof(__vinix_gnu_native_mbstate_t) == 8 && alignof(__vinix_gnu_native_mbstate_t) == 4, "GNU native mbstate ABI");
static_assert(sizeof(fpos_t) == 16, "GNU native fpos ABI");
static_assert(sizeof(mbstate_t) == 128 && alignof(mbstate_t) == 8, "Apple mbstate ABI");
static_assert(__builtin_offsetof(mbstate_t, __native) == 0, "native conversion state prefix");
static inline __vinix_gnu_native_mbstate_t* __vinix_gnu_state(mbstate_t* p) noexcept { return p ? &p->__native : nullptr; }
static inline const __vinix_gnu_native_mbstate_t* __vinix_gnu_state(const mbstate_t* p) noexcept { return p ? &p->__native : nullptr; }
static inline int __vinix_ios_mbsinit(const mbstate_t* p) noexcept { return ::mbsinit(__vinix_gnu_state(p)); }
static inline size_t __vinix_ios_mbrtowc(wchar_t* d, const char* s, size_t n, mbstate_t* p) noexcept { return ::mbrtowc(d, s, n, __vinix_gnu_state(p)); }
static inline size_t __vinix_ios_wcrtomb(char* d, wchar_t s, mbstate_t* p) noexcept { return ::wcrtomb(d, s, __vinix_gnu_state(p)); }
static inline size_t __vinix_ios_mbrlen(const char* s, size_t n, mbstate_t* p) noexcept { return ::mbrlen(s, n, __vinix_gnu_state(p)); }
static inline size_t __vinix_ios_mbsrtowcs(wchar_t* d, const char** s, size_t n, mbstate_t* p) noexcept { return ::mbsrtowcs(d, s, n, __vinix_gnu_state(p)); }
static inline size_t __vinix_ios_wcsrtombs(char* d, const wchar_t** s, size_t n, mbstate_t* p) noexcept { return ::wcsrtombs(d, s, n, __vinix_gnu_state(p)); }
static inline size_t __vinix_ios_mbsnrtowcs(wchar_t* d, const char** s, size_t n, size_t m, mbstate_t* p) noexcept { return ::mbsnrtowcs(d, s, n, m, __vinix_gnu_state(p)); }
static inline size_t __vinix_ios_wcsnrtombs(char* d, const wchar_t** s, size_t n, size_t m, mbstate_t* p) noexcept { return ::wcsnrtombs(d, s, n, m, __vinix_gnu_state(p)); }
static inline size_t __vinix_ios_mbrtoc16(char16_t* d, const char* s, size_t n, mbstate_t* p) noexcept { return ::mbrtoc16(d, s, n, __vinix_gnu_state(p)); }
static inline size_t __vinix_ios_c16rtomb(char* d, char16_t s, mbstate_t* p) noexcept { return ::c16rtomb(d, s, __vinix_gnu_state(p)); }
static inline size_t __vinix_ios_mbrtoc32(char32_t* d, const char* s, size_t n, mbstate_t* p) noexcept { return ::mbrtoc32(d, s, n, __vinix_gnu_state(p)); }
static inline size_t __vinix_ios_c32rtomb(char* d, char32_t s, mbstate_t* p) noexcept { return ::c32rtomb(d, s, __vinix_gnu_state(p)); }
#if __GLIBC_USE(ISOC2X) || defined(__cpp_char8_t)
static inline size_t __vinix_ios_mbrtoc8(char8_t* d, const char* s, size_t n, mbstate_t* p) noexcept { return ::mbrtoc8(d, s, n, __vinix_gnu_state(p)); }
static inline size_t __vinix_ios_c8rtomb(char* d, char8_t s, mbstate_t* p) noexcept { return ::c8rtomb(d, s, __vinix_gnu_state(p)); }
#define mbrtoc8 __vinix_ios_mbrtoc8
#define c8rtomb __vinix_ios_c8rtomb
#endif
#define mbsinit __vinix_ios_mbsinit
#define mbrtowc __vinix_ios_mbrtowc
#define wcrtomb __vinix_ios_wcrtomb
#define mbrlen __vinix_ios_mbrlen
#define mbsrtowcs __vinix_ios_mbsrtowcs
#define wcsrtombs __vinix_ios_wcsrtombs
#define mbsnrtowcs __vinix_ios_mbsnrtowcs
#define wcsnrtombs __vinix_ios_wcsnrtombs
#define mbrtoc16 __vinix_ios_mbrtoc16
#define c16rtomb __vinix_ios_c16rtomb
#define mbrtoc32 __vinix_ios_mbrtoc32
#define c32rtomb __vinix_ios_c32rtomb
#endif
'
}

fn gnu_cxx_config(sanitizers bool) string {
	return '#ifndef _LIBCPP_CONFIG_SITE\n#define _LIBCPP_CONFIG_SITE\n' +
		'
#define _LIBCPP_ABI_VERSION 1
#define _LIBCPP_ABI_NAMESPACE __1
#define _LIBCPP_ABI_FORCE_ITANIUM
#define _LIBCPP_HAS_THREAD_API_PTHREAD
#define _LIBCPP_HAS_NO_VENDOR_AVAILABILITY_ANNOTATIONS
#define _LIBCPP_PSTL_BACKEND_SERIAL
#define _LIBCPP_HARDENING_MODE_DEFAULT _LIBCPP_HARDENING_MODE_NONE
#define _LIBCPP_ABI_ALTERNATE_STRING_LAYOUT
#define _LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE
#define VINIX_IOS_CXX_ABI
' + if sanitizers { '#define _LIBCPP_INSTRUMENTED_WITH_ASAN\n' } else { '' } + '#endif\n'
}

fn gnu_unpack(archive string, destination string) ! {
	mut reader := tarstream.open_concatenated(archive)!
	defer { reader.close() }
	mut seen := map[string]bool{}
	mut buffer := []u8{len: 1024 * 1024}
	for {
		member := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		parts := member.name.split('/').filter(it != '' && it != '.')
		if '..' in parts || member.name.starts_with('/') || member.name.contains('\x00') {
			return error('unsafe GNU C++ archive member: ' + member.name)
		}
		if parts.len < 2 { continue }
		relative := parts[1..].join('/')
		if parts[1] !in ['src', 'include', 'vendor'] && relative != 'LICENSE.TXT' { continue }
		if !member.regular() {
			if member.kind != `5` {
				return error('GNU C++ source requires a regular archive member: ' + relative)
			}
			continue
		}
		if relative in seen { return error('duplicate GNU C++ source: ' + relative) }
		seen[relative] = true
		path := destination + '/' + relative
		mkdir(parent(path))!
		mut file := os.create(path)!
		for {
			count := reader.read(mut buffer) or {
				file.close()
				return err
			}
			if count == 0 { break }
			unsafe {
				file.write_full_buffer(buffer.data, usize(count)) or {
					file.close()
					return err
				}
			}
		}
		file.close()
	}
}

fn gnu_directory_names(path string) ![]string {
	stream := unsafe { C.opendir(path.str) }
	if isnil(stream) { return os.error_posix() }
	mut names := []string{}
	for {
		C.errno = 0
		entry := C.readdir(stream)
		if isnil(entry) {
			number := C.errno
			closed := C.closedir(stream)
			if number != 0 {
				return error_with_code('cannot enumerate GNU C++ input: ' + path, number)
			}
			if closed != 0 { return os.error_posix() }
			break
		}
		name := unsafe { tos_clone(&u8(&entry.d_name[0])) }
		if name !in ['.', '..'] { names << name }
	}
	names.sort()
	return names
}

fn gnu_tree_files(root string, relative string, mut files []string) ! {
	names := gnu_directory_names(root + if relative == '' { '' } else { '/' + relative })!
	for name in names {
		path := if relative == '' { name } else { relative + '/' + name }
		kind := os.lstat(root + '/' + path)!.get_filetype()
		if kind == .directory {
			gnu_tree_files(root, path, mut files)!
		} else if kind == .regular {
			files << path
		} else {
			return error('GNU C++ input is not a regular file or directory: ' + root + '/' + path)
		}
	}
}

fn gnu_header_hashes(root string) !map[string]string {
	mut files := []string{}
	gnu_tree_files(root, '', mut files)!
	if files.len == 0 { return error('empty GNU C++ header directory: ' + root) }
	mut hashes := map[string]string{}
	for name in files { hashes[name] = digest(root + '/' + name)! }
	return hashes
}

fn gnu_copy_headers(source string, destination string) ! {
	mut files := []string{}
	gnu_tree_files(source, '', mut files)!
	for name in files {
		if name.ends_with('.in') || name == 'CMakeLists.txt' { continue }
		mkdir(parent(destination + '/' + name))!
		os.cp(source + '/' + name, destination + '/' + name)!
	}
}

fn gnu_source_key(root string) !string {
	mut paths := []string{}
	for name in ['src', 'include', 'vendor', 'LICENSE.TXT'] {
		path := root + '/' + name
		if info := os.lstat(path) {
			if info.get_filetype() == .directory {
				mut files := []string{}
				gnu_tree_files(path, '', mut files)!
			} else if info.get_filetype() != .regular {
				return error('GNU C++ source contains a non-regular input: ' + path)
			}
		} else {
			if err.code() != C.ENOENT { return err }
		}
		paths << path
	}
	return cachekey.tree_key(paths, false, 'vinix-ios-gnu-cxx-source-v1')!
}

// A reused extraction is accepted only against a tree key derived from the
// pinned tarball. Older partial extractions without that key are compared with
// a fresh private extraction before their key is recorded.
fn gnu_qualified_source(archive string, destination string, artifact Artifact) !string {
	if !os.exists(destination) {
		work := private_directory(parent(destination))!
		defer { os.rmdir_all(work) or {} }
		gnu_unpack(archive, work + '/tree')!
		key := gnu_source_key(work + '/tree')!
		os.write_file(work + '/tree/.source-sha256', artifact.sha256)!
		os.write_file(work + '/tree/.source-tree-key', key)!
		os.rename(work + '/tree', destination)!
		return key
	}
	if os.lstat(destination)!.get_filetype() != .directory
		|| (os.read_file(destination + '/.source-sha256') or { '' }) != artifact.sha256 {
		return error('unqualified existing GNU C++ source tree: ' + destination)
	}
	actual := gnu_source_key(destination)!
	key := os.read_file(destination + '/.source-tree-key') or {
		work := private_directory(parent(destination))!
		defer { os.rmdir_all(work) or {} }
		gnu_unpack(archive, work + '/tree')!
		expected := gnu_source_key(work + '/tree')!
		if actual != expected {
			return error('GNU C++ extracted sources differ from pinned archive: ' + destination)
		}
		publish(destination + '/.source-tree-key', expected)!
		expected
	}
	if actual != key { return error('GNU C++ extracted sources changed: ' + destination) }
	return key
}

fn (tools Tools) gnu_command(argv []string, temporary string) !sourcecommand.Output {
	if tools.command_hook != unsafe { nil } { return tools.command_hook(argv, tools.context)! }
	mut env := os.environ()
	for key in ['CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'OBJC_INCLUDE_PATH', 'LIBRARY_PATH',
		'COMPILER_PATH', 'GCC_EXEC_PREFIX', 'SDKROOT', 'CCC_OVERRIDE_OPTIONS',
		'CLANG_CONFIG_FILE_SYSTEM_DIR', 'CLANG_CONFIG_FILE_USER_DIR'] {
		env.delete(key)
	}
	env['TMPDIR'] = temporary
	return sourcecommand.capture_combined(argv, env, -1, 16 * 1024 * 1024, cachecli.cancelled)!
}

fn (tools Tools) gnu_checked(argv []string, log string) !string {
	if log == '' { return error('GNU C++ commands require an external log path') }
	temporary := private_directory(parent(log))!
	defer { os.rmdir_all(temporary) or {} }
	result := tools.gnu_command(argv, temporary)!
	if log != '' {
		os.write_file(log + '.command.json', json2.encode(argv, prettify: true))!
		os.write_file(log, result.stdout + result.stderr)!
		os.write_file(log + '.status', result.status.str() + '\n')!
	}
	if result.status != 0 {
		return error('GNU C++ command failed: ' + argv.str() + '\n' + result.stdout + result.stderr)
	}
	return result.stdout + result.stderr
}

pub fn gnu_cxx_consumer_flags(options GnuCxxOptions) []string {
	mut flags := ['--no-default-config', '--target=aarch64-linux-gnu', '--sysroot=' + options.sysroot,
		'-D_GNU_SOURCE', '-nostdinc++', '-isystem', options.output + '/include/c++/v1', '-include',
		options.output + '/apple-gnu-abi.h', '-D_LIBCPP_ABI_ALTERNATE_STRING_LAYOUT',
		'-D_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE', '-DVINIX_IOS_CXX_ABI', '-ffixed-x18',
		'-fno-omit-frame-pointer']
	if options.sanitizers { flags << ['-fsanitize=address,undefined'] }
	return flags
}

fn gnu_cxx_sources(root string) !map[string][]string {
	mut cxx := []string{}
	for directory in [root + '/libcxx/src', root + '/libcxx/src/ryu'] {
		for name in os.ls(directory)! {
			if name.ends_with('.cpp') && name !in ['new.cpp', 'typeinfo.cpp'] {
				cxx << directory + '/' + name
			}
		}
	}
	cxx.sort()
	if cxx.len != 47 { return error('LLVM 19.1.7 libc++ source subset changed: ' + cxx.len.str()) }
	return {
		'libcxx-ios': cxx
		'libc++abi':  ['cxa_aux_runtime.cpp', 'cxa_default_handlers.cpp', 'cxa_demangle.cpp',
			'cxa_exception_storage.cpp', 'cxa_guard.cpp', 'cxa_handlers.cpp', 'cxa_vector.cpp',
			'cxa_virtual.cpp', 'stdlib_exception.cpp', 'stdlib_stdexcept.cpp', 'stdlib_typeinfo.cpp',
			'abort_message.cpp', 'fallback_malloc.cpp', 'private_typeinfo.cpp', 'stdlib_new_delete.cpp',
			'cxa_exception.cpp', 'cxa_personality.cpp', 'cxa_thread_atexit.cpp'].map(root + '/libcxxabi/src/' + it)
		'libunwind':  ['libunwind.cpp', 'Unwind-EHABI.cpp', 'Unwind-seh.cpp', 'UnwindLevel1.c',
			'UnwindLevel1-gcc-ext.c', 'Unwind-sjlj.c', 'Unwind-wasm.c', 'UnwindRegistersRestore.S',
			'UnwindRegistersSave.S'].map(root + '/libunwind/src/' + it)
	}
}

fn gnu_object_valid(path string) ! {
	mut file := os.open(path)!
	defer { file.close() }
	header := file.read_bytes(20)
	if header.len != 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || header[16] != 1
		|| header[17] != 0 || header[18] != 183 || header[19] != 0 {
		return error('compiler did not produce an ARM64 ELF object: ' + path)
	}
}

pub fn build_gnu_cxx(tools Tools, requested GnuCxxOptions) !GnuCxxResult {
	options := GnuCxxOptions{
		output:     gnu_safe_path(requested.output)!
		sources:    gnu_safe_path(if requested.sources == '' {
			requested.output + '/sources'
		} else {
			requested.sources
		})!
		sysroot:    gnu_safe_path(requested.sysroot)!
		compiler:   os.find_abs_path_of_executable(requested.compiler)!
		archiver:   os.find_abs_path_of_executable(requested.archiver)!
		sanitizers: requested.sanitizers
	}
	for name in ['stdio.h', 'wchar.h', 'uchar.h', 'features.h', 'bits/types/__mbstate_t.h'] {
		if !os.is_file(options.sysroot + '/include/' + name) {
			return error('missing GNU ARM64 sysroot header: ' + name)
		}
	}
	if os.is_file(options.sysroot + '/include/features.h')
		&& !os.read_file(options.sysroot + '/include/features.h')!.contains('__GLIBC__') {
		return error('GNU C++ requires a glibc sysroot')
	}
	mkdir(options.output)!
	mkdir(options.sources)!
	mut source_keys := map[string]string{}
	for i, artifact in gnu_cxx_artifacts {
		tools.fetch(options.sources + '/' + artifact.name, artifact)!
		name := ['libcxx', 'libcxxabi', 'libunwind'][i]
		destination := options.sources + '/' + name
		source_keys[name] = gnu_qualified_source(options.sources + '/' + artifact.name, destination, artifact)!
	}
	include := options.output + '/include/c++/v1'
	if os.exists(options.output + '/include') { os.rmdir_all(options.output + '/include')! }
	gnu_copy_headers(options.sources + '/libcxx/include', include)!
	ctype := os.read_file(tools.root + '/build-support/ios/cxx-ctype.inc')!
	patch_headers(include, ctype)!
	os.write_file(include + '/__config_site', gnu_cxx_config(options.sanitizers))!
	os.cp(options.sources + '/libcxx/vendor/llvm/default_assertion_handler.in', include + '/__assertion_handler')!
	for name in ['cxxabi.h', '__cxxabi_config.h'] {
		os.cp(options.sources + '/libcxxabi/include/' + name, include + '/' + name)!
	}
	os.write_file(options.output + '/apple-gnu-abi.h', gnu_cxx_preamble(options.sysroot)!)!
	os.write_file(options.output + '/gnu-cxx-abi-probe.cpp', gnu_cxx_abi_probe_source())!
	os.write_file(options.output + '/gnu-cxx-sanitizer-control.cpp', gnu_cxx_sanitizer_control_source())!
	compiler_hash := digest(options.compiler)!
	archiver_hash := digest(options.archiver)!
	compiler_version := tools.gnu_checked([options.compiler, '--version'], options.output + '/compiler-version.log')!
	resource_dir := gnu_safe_path(tools.gnu_checked([options.compiler, '--no-default-config',
		'-print-resource-dir'], options.output + '/compiler-resource.log')!.trim_space())!
	if !os.is_file(resource_dir + '/include/stddef.h') {
		return error('missing Clang resource headers: ' + resource_dir)
	}
	sysroot_headers := gnu_header_hashes(options.sysroot + '/include')!
	resource_headers := gnu_header_hashes(resource_dir + '/include')!
	archiver_version := tools.gnu_checked([options.archiver, '--version'], options.output + '/archiver-version.log')!
	consumer := gnu_cxx_consumer_flags(options)
	mut flags := map[string][]string{}
	flags['libcxx-ios'] = [...consumer, '-I', options.sources + '/libcxx/src', '-I',
		options.sources + '/libcxxabi/include', '-D_LIBCPP_BUILDING_LIBRARY',
		'-DLIBCXX_BUILDING_LIBCXXABI', '-std=c++23', if options.sanitizers { '-O1' } else { '-O2' },
		'-gline-tables-only', '-fPIC', '-fvisibility=hidden', '-fvisibility-inlines-hidden']
	flags['libc++abi'] = [...consumer, '-I', options.sources + '/libcxxabi/include', '-I',
		options.sources + '/libcxxabi/src', '-I', options.sources + '/libcxx/src', '-I',
		options.sources + '/libunwind/include', '-D_LIBCXXABI_BUILDING_LIBRARY',
		'-D_LIBCPP_BUILDING_LIBRARY', '-DLIBCXX_BUILDING_LIBCXXABI', '-DHAVE___CXA_THREAD_ATEXIT_IMPL',
		'-std=c++23', if options.sanitizers { '-O1' } else { '-O2' }, '-gline-tables-only', '-fPIC',
		'-fvisibility=hidden', '-fvisibility-inlines-hidden']
	flags['libunwind'] = ['--no-default-config', '--target=aarch64-linux-gnu',
		'--sysroot=' + options.sysroot, '-D_GNU_SOURCE', '-D_LIBUNWIND_IS_NATIVE_ONLY', '-I',
		options.sources + '/libunwind/include', '-I', options.sources + '/libunwind/src', '-nostdinc++',
		'-isystem', include, '-O2', '-gline-tables-only', '-fPIC', '-ffixed-x18', '-fno-exceptions',
		'-fno-rtti', '-funwind-tables', '-fvisibility=hidden']
	mut per_file_flags := map[string][]string{}
	if options.sanitizers {
		// The vptr checker calls __dynamic_cast. Instrumenting that same RTTI
		// implementation with vptr recursively re-enters the checker before its
		// cache can be populated. Keep ASan and every other UBSan check here.
		per_file_flags['libc++abi/private_typeinfo.cpp'] = [...flags['libc++abi'], '-fno-sanitize=vptr']
	}
	inputs := [options.sources + '/libcxx/src', options.sources + '/libcxxabi/src',
		options.sources + '/libcxxabi/include', options.sources + '/libunwind/src',
		options.sources + '/libunwind/include', include, options.output + '/apple-gnu-abi.h',
		options.sysroot + '/include', resource_dir + '/include']
	input_key := cachekey.tree_key(inputs, false, 'vinix-ios-gnu-cxx-inputs-v1')!
	stamp := sha256.hexhash('vinix-ios-gnu-cxx-v1\n' + input_key + compiler_hash + archiver_hash + json2.encode(flags) +
		if per_file_flags.len > 0 { json2.encode(per_file_flags) } else { '' })
	mut cached := map[string]string{}
	if (os.read_file(options.output + '/build-stamp') or { '' }) == stamp {
		cached = json2.decode[map[string]string](os.read_file(options.output + '/object-sha256.json') or { '' }) or { map[string]string{} }
	}
	sources := gnu_cxx_sources(options.sources)!
	mut hashes := map[string]string{}
	work := private_directory(options.output)!
	defer { os.rmdir_all(work) or {} }
	for component in ['libunwind', 'libc++abi', 'libcxx-ios'] {
		objects := options.output + '/objects/' + component
		mkdir(objects)!
		mut compiled := []string{}
		for path in sources[component] {
			cachecli.checkpoint()!
			name := path.all_after_last('/').all_before_last('.')
			object := objects + '/' + name + '.o'
			mut use_cache := false
			if expected := cached[object] {
				use_cache = os.is_file(object) && digest(object)! == expected
			}
			if !use_cache {
				mut selected := if individual := per_file_flags[component + '/' + path.all_after_last('/')] {
					individual.clone()
				} else {
					flags[component].clone()
				}
				if path.ends_with('.c') { selected << ['-x', 'c', '-std=c99'] }
				if path.ends_with('.cpp') && component == 'libunwind' { selected << ['-std=c++17'] }
				println('GNU C++ ' + component + '/' + name)
				tools.gnu_checked([options.compiler, ...selected, '-c', path, '-o', work + '/object.o'], objects + '/' + name + '.log')!
				gnu_object_valid(work + '/object.o')!
				cachecli.replace_file(work + '/object.o', object)!
			}
			hashes[object] = digest(object)!
			compiled << object
		}
		tools.gnu_checked([options.archiver, 'rcsD', work + '/' + component + '.a', ...compiled], options.output + '/' + component + '-archive.log')!
	}
	if cachekey.tree_key(inputs, false, 'vinix-ios-gnu-cxx-inputs-v1')! != input_key
		|| digest(options.compiler)! != compiler_hash || digest(options.archiver)! != archiver_hash {
		return error('GNU C++ inputs changed during compilation')
	}
	if gnu_header_hashes(options.sysroot + '/include')! != sysroot_headers
		|| gnu_header_hashes(resource_dir + '/include')! != resource_headers {
		return error('GNU C++ external headers changed during compilation')
	}
	for name, expected in source_keys {
		if gnu_source_key(options.sources + '/' + name)! != expected {
			return error('GNU C++ release sources changed during compilation: ' + name)
		}
	}
	for component in ['libunwind', 'libc++abi', 'libcxx-ios'] {
		cachecli.replace_file(work + '/' + component + '.a', options.output + '/' + component + '.a')!
	}
	mut artifacts := map[string]string{}
	mut headers := []string{}
	gnu_tree_files(include, '', mut headers)!
	for header in headers {
		artifacts['include/c++/v1/' + header] = digest(include + '/' + header)!
	}
	for name in ['apple-gnu-abi.h', 'gnu-cxx-abi-probe.cpp', 'gnu-cxx-sanitizer-control.cpp',
		'libcxx-ios.a', 'libc++abi.a', 'libunwind.a'] {
		artifacts[name] = digest(options.output + '/' + name)!
	}
	manifest := GnuCxxManifest{
		sanitizers:            options.sanitizers
		compiler:              options.compiler
		compiler_sha256:       compiler_hash
		compiler_version:      compiler_version
		compiler_resource_dir: resource_dir
		sysroot_headers:       sysroot_headers
		resource_headers:      resource_headers
		archiver:              options.archiver
		archiver_sha256:       archiver_hash
		archiver_version:      archiver_version
		sysroot:               options.sysroot
		consumer_flags:        consumer
		artifacts:             artifacts
		source_archives:       gnu_cxx_artifacts
		source_tree_keys:      source_keys
		input_key:             input_key
		build_flags:           flags
		per_file_flags:        per_file_flags
		instrumentation:       {
			'libcxx-ios': if options.sanitizers { 'ASan and UBSan' } else { 'none' }
			'libc++abi':  if options.sanitizers {
				'ASan and UBSan; private_typeinfo.cpp alone omits recursive vptr instrumentation in the RTTI implementation used by the checker'
			} else {
				'none'
			}
			'libunwind':  'none; low-level native ELF unwinder compiled with unwind tables'
		}
		scope:                 'Apple alternate string, 128-byte mbstate, 32-bit Darwin ctype masks and 64-bit TLS keys on GNU ARM64. Existing 47-source libc++ subset; no filesystem subdirectory. Native ELF exception runtime only; Mach-O exception unwinding remains unsupported.'
		provenance:            'LLVM llvmorg-19.1.7 official HTTPS release sources with explicit SHA-256 pins. libcxx pin pre-existed in the repository; libcxxabi and libunwind pins measured from official release assets, not independently signed checksum claims.'
	}
	publish(options.output + '/object-sha256.json', json2.encode(hashes, prettify: true))!
	publish(options.output + '/build-stamp', stamp)!
	publish(options.output + '/gnu-cxx.json', json2.encode(manifest, prettify: true))!
	return GnuCxxResult{include, options.output + '/libcxx-ios.a', options.output + '/libc++abi.a', options.output + '/libunwind.a', options.output + '/gnu-cxx.json', stamp}
}

pub fn build_gnu_cxx_cli(tools Tools, argv []string) !int {
	args := cachecli.arguments(argv, ['--output', '--sources', '--sysroot', '--compiler', '--archiver'], [], ['--sanitizers'], 0, 0,
		'Build GNU ARM64 LLVM 19.1.7 C++ archives with the Apple ABI.\nUsage: build-cxx --target aarch64-linux-gnu --output DIR --sources DIR --sysroot DIR --compiler CLANG++ --archiver LLVM-AR [--sanitizers]')!
	result := build_gnu_cxx(tools, GnuCxxOptions{
		output:     args.value('--output', tools.root + '/build/ios/cxx-gnu')
		sources:    args.value('--sources', '')
		sysroot:    args.value('--sysroot', '')
		compiler:   args.value('--compiler', 'clang++')
		archiver:   args.value('--archiver', 'llvm-ar')
		sanitizers: args.value('--sanitizers', '') == 'true'
	})!
	println('Built GNU ARM64 C++ profile: ' + result.manifest)
	return 0
}
