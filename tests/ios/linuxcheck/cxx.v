// SPDX-License-Identifier: GPL-2.0-or-later
module linuxcheck

import os
import json2

struct CxxBuildManifest {
	target                string
	llvm_version          string
	sanitizers            bool
	compiler              string
	compiler_sha256       string
	compiler_resource_dir string
	sysroot               string
	sysroot_headers       map[string]string
	resource_headers      map[string]string
	consumer_flags        []string
	artifacts             map[string]string
}

struct CxxProfile {
	enabled   bool
	root      string
	include   string
	preamble  string
	probe     string
	libraries []string
	manifest  CxxBuildManifest
}

fn cxx_mode(mode string) bool {
	return mode in ['cxx', 'cxx-gles', 'build-run-ios-cxx', 'build-run-ios-cxx-gles', 'probe-no-ads']
}

fn cxx_profile(mode string) !CxxProfile {
	if !cxx_mode(mode) { return CxxProfile{} }
	value := os.getenv('VINIX_IOS_LINUX_CXX_ROOT')
	if value == '' {
		return error('C++ modes require VINIX_IOS_LINUX_CXX_ROOT from the adapted GNU ARM64 C++ builder')
	}
	return cxx_profile_at(value, mode in ['cxx', 'cxx-gles'])
}

fn cxx_regular(root string, relative string) !string {
	if relative == '' || os.is_abs_path(relative) || relative.contains_any('\\\x00\r\n') {
		return error('unsafe GNU C++ input path: ' + relative)
	}
	mut path := root
	parts := relative.split('/')
	for i, part in parts {
		if part in ['', '.', '..'] { return error('unsafe GNU C++ input path: ' + relative) }
		path += '/' + part
		kind := os.lstat(path)!.get_filetype()
		if (i == parts.len - 1 && kind != .regular) || (i != parts.len - 1 && kind != .directory) {
			return error('GNU C++ inputs must be regular files below real directories: ' + path)
		}
	}
	return path
}

// These are the external declaration inputs consumed by Clang when building
// the conversion binding and native fixture. Match the producer's complete
// include-tree inventories, including hidden headers; this is not a pin of
// other compiler resources, target libraries or the dynamic loader closure.
fn cxx_recorded_headers(prefix string, expected map[string]string, label string) ![]FileDigest {
	if prefix == '' || !os.is_abs_path(prefix) || prefix.contains_any('\\\x00\r\n') {
		return error('GNU C++ ${label} requires an explicit absolute header prefix')
	}
	if expected.len == 0 {
		return error('GNU C++ ${label} header inventory is missing')
	}
	root := prefix + '/include'
	if os.lstat(root)!.get_filetype() != .directory {
		return error('GNU C++ ${label} include root must be a real directory')
	}
	for relative in expected.keys() { cxx_regular(root, relative)! }
	mut headers := []FileDigest{}
	inventory_files(root, '', mut headers)!
	if headers.len != expected.len {
		return error('GNU C++ ${label} header set differs from its build manifest')
	}
	mut inputs := []FileDigest{cap: headers.len}
	for header in headers {
		if header.sha256 != expected[header.path] {
			return error('GNU C++ ${label} header differs from its build manifest: ' + header.path)
		}
		inputs << FileDigest{ path: root + '/' + header.path, sha256: header.sha256 }
	}
	return inputs
}

fn cxx_external_headers(manifest CxxBuildManifest) ![]FileDigest {
	mut inputs := cxx_recorded_headers(manifest.sysroot, manifest.sysroot_headers, 'sysroot')!
	inputs << cxx_recorded_headers(manifest.compiler_resource_dir, manifest.resource_headers,
		'Clang resource')!
	return inputs
}

fn cxx_profile_at(path string, sanitized bool) !CxxProfile {
	root := os.real_path(path)
	manifest_path := cxx_regular(root, 'gnu-cxx.json')!
	manifest := json2.decode[CxxBuildManifest](os.read_file(manifest_path)!)!
	if manifest.target != 'aarch64-linux-gnu' || manifest.llvm_version != '19.1.7' {
		return error('GNU C++ profile requires the adapted LLVM 19.1.7 ARM64/glibc build')
	}
	if manifest.sanitizers != sanitized {
		return error('GNU C++ sanitizer profile must match the selected fixture/runner mode')
	}
	mut libraries := []string{}
	for name in ['libcxx-ios.a', 'libc++abi.a', 'libunwind.a'] {
		library := cxx_regular(root, name)!
		mut file := os.open(library)!
		header := file.read_bytes(8)
		file.close()
		if header.bytestr() != '!<arch>\n' {
			return error('GNU C++ input is not a static archive: ' + library)
		}
		if digest(library)!.sha256 != manifest.artifacts[name] {
			return error('GNU C++ archive differs from its build manifest: ' + name)
		}
		libraries << library
	}
	preamble := cxx_regular(root, 'apple-gnu-abi.h')!
	if digest(preamble)!.sha256 != manifest.artifacts['apple-gnu-abi.h'] {
		return error('GNU C++ ABI preamble differs from its build manifest')
	}
	probe := cxx_regular(root, 'gnu-cxx-abi-probe.cpp')!
	if digest(probe)!.sha256 != manifest.artifacts['gnu-cxx-abi-probe.cpp'] {
		return error('GNU C++ conversion probe differs from its build manifest')
	}
	control := cxx_regular(root, 'gnu-cxx-sanitizer-control.cpp')!
	if digest(control)!.sha256 != manifest.artifacts['gnu-cxx-sanitizer-control.cpp'] {
		return error('GNU C++ sanitizer control differs from its build manifest')
	}
	for name in ['__config', '__config_site', '__locale', '__thread/support/pthread.h', 'string',
		'sstream'] {
		cxx_regular(root, 'include/c++/v1/' + name)!
	}
	for name, expected in manifest.artifacts {
		if digest(cxx_regular(root, name)!)!.sha256 != expected {
			return error('GNU C++ input differs from its build manifest: ' + name)
		}
	}
	mut headers := []FileDigest{}
	inventory_files(root + '/include/c++/v1', '', mut headers)!
	if manifest.artifacts.len != headers.len + 6 {
		return error('GNU C++ manifest must cover exactly the complete header tree, ABI preamble, conversion probe, sanitizer control and three archives')
	}
	for header in headers {
		if header.sha256 != manifest.artifacts['include/c++/v1/' + header.path] {
			return error('GNU C++ header differs from its build manifest: ' + header.path)
		}
	}
	cxx_external_headers(manifest)!
	return CxxProfile{
		enabled:   true
		root:      root
		include:   root + '/include/c++/v1'
		preamble:  preamble
		probe:     probe
		libraries: libraries
		manifest:  manifest
	}
}

fn cxx_inputs(profile CxxProfile) ![]FileDigest {
	mut items := []FileDigest{}
	if !profile.enabled { return items }
	for name in ['gnu-cxx.json', 'apple-gnu-abi.h', 'gnu-cxx-abi-probe.cpp',
		'gnu-cxx-sanitizer-control.cpp', 'libcxx-ios.a', 'libc++abi.a', 'libunwind.a'] {
		items << digest(cxx_regular(profile.root, name)!)!
	}
	mut headers := []FileDigest{}
	inventory_files(profile.include, '', mut headers)!
	for header in headers {
		items << FileDigest{ path: profile.include + '/' + header.path, sha256: header.sha256 }
	}
	items << cxx_external_headers(profile.manifest)!
	items.sort(a.path < b.path)
	return items
}

fn cxx_link(profile CxxProfile) []string {
	if !profile.enabled { return []string{} }
	// Mesa can load libstdc++. Keep the adapted LLVM ABI local to this
	// executable; exporting __cxa/new/delete would interpose on GNU libraries.
	return ['-Wl,--exclude-libs,libcxx-ios.a:libc++abi.a:libunwind.a:libubsan.a', '-Wl,--start-group',
		...profile.libraries, '-Wl,--end-group']
}

fn cxx_consumer_flags(profile CxxProfile) ![]string {
	mut expected := ['--no-default-config', '--target=aarch64-linux-gnu',
		'--sysroot=' + profile.manifest.sysroot, '-D_GNU_SOURCE', '-nostdinc++', '-isystem',
		profile.include, '-include', profile.preamble, '-D_LIBCPP_ABI_ALTERNATE_STRING_LAYOUT',
		'-D_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE', '-DVINIX_IOS_CXX_ABI', '-ffixed-x18',
		'-fno-omit-frame-pointer']
	if profile.manifest.sanitizers {
		expected << '-fsanitize=address,undefined'
	}
	if profile.manifest.consumer_flags != expected {
		return error('GNU C++ consumer flags do not match the qualified Apple ABI and sanitizer profile')
	}
	return expected
}

fn cxx_readelf_decimal(value string) bool {
	return value != '' && value.len <= 18 && value.bytes().all(it >= `0` && it <= `9`)
}

fn cxx_readelf_hex(value string) bool {
	return value != '' && value.len <= 16 && value.bytes().all((it >= `0` && it <= `9`)
		|| (it >= `a` && it <= `f`) || (it >= `A` && it <= `F`))
}

fn cxx_readelf_count(value string) !int {
	if !cxx_readelf_decimal(value) || value.len > 9 || value.int() < 1 {
		return error('readelf reported an invalid table entry count')
	}
	return value.int()
}

// A successful reader process is not enough: require complete populated GNU
// or LLVM readelf tables before accepting the absence of incompatible names.
fn cxx_validate_dynamic_output(output string) ! {
	lines := output.split_into_lines().map(it.trim_space()).filter(it != '')
	if lines.len < 3 { return error('readelf did not report a populated dynamic section') }
	header := lines[0].fields()
	if header.len != 8 || header[..4] != ['Dynamic', 'section', 'at', 'offset']
		|| !header[4].starts_with('0x') || !cxx_readelf_hex(header[4][2..])
		|| header[5] != 'contains' || header[7] != 'entries:'
		|| lines[1].fields() != ['Tag', 'Type', 'Name/Value'] {
		return error('readelf reported a malformed dynamic-section header')
	}
	expected := cxx_readelf_count(header[6])!
	if lines.len - 2 != expected {
		return error('readelf dynamic-section entry count is incomplete')
	}
	mut libc := false
	mut symbols := false
	mut strings := false
	mut null_entry := false
	for line in lines[2..] {
		fields := line.fields()
		if fields.len < 3 || !fields[0].starts_with('0x') || !cxx_readelf_hex(fields[0][2..])
			|| fields[1].len < 3 || !fields[1].starts_with('(') || !fields[1].ends_with(')') {
			return error('readelf reported a malformed dynamic entry')
		}
		match fields[1] {
			'(NEEDED)' {
				if line.count('Shared library: [') != 1 || !line.ends_with(']') {
					return error('readelf reported a malformed needed-library entry')
				}
				name := line.all_after('Shared library: [').all_before_last(']')
				if name == '' { return error('readelf reported an empty needed-library name') }
				if name.starts_with('libubsan.so') || name.starts_with('libstdc++.so') {
					return error('adapted C++ executable directly depends on an incompatible shared GNU C++ or UBSan runtime')
				}
				libc = libc || name == 'libc.so.6'
			}
			'(SYMTAB)' { symbols = true }
			'(STRTAB)' { strings = true }
			'(NULL)' { null_entry = true }
			else {}
		}
	}
	if !libc || !symbols || !strings || !null_entry {
		return error('readelf omitted required GNU dynamic dependencies or tables')
	}
}

fn cxx_validate_symbol_output(output string) ! {
	lines := output.split_into_lines().map(it.trim_space()).filter(it != '')
	if lines.len < 4 { return error('readelf did not report a populated dynamic symbol table') }
	header := lines[0].fields()
	if header.len != 6 || header[..4] != ['Symbol', 'table', "'.dynsym'", 'contains']
		|| header[5] != 'entries:'
		|| lines[1].fields() != ['Num:', 'Value', 'Size', 'Type', 'Bind', 'Vis', 'Ndx', 'Name'] {
		return error('readelf reported a malformed dynamic-symbol header')
	}
	expected := cxx_readelf_count(header[4])!
	if expected < 2 || lines.len - 2 != expected {
		return error('readelf dynamic-symbol entry count is incomplete')
	}
	mut named := false
	for index, line in lines[2..] {
		fields := line.fields()
		if fields.len < 7 || fields[0] != '${index}:' || !cxx_readelf_hex(fields[1])
			|| !cxx_readelf_decimal(fields[2])
			|| fields[3] !in ['NOTYPE', 'OBJECT', 'FUNC', 'SECTION', 'FILE', 'COMMON', 'TLS', 'IFUNC',
				'GNU_IFUNC']
			|| fields[4] !in ['LOCAL', 'GLOBAL', 'WEAK', 'UNIQUE']
			|| fields[5] !in ['DEFAULT', 'INTERNAL', 'HIDDEN', 'PROTECTED']
			|| (fields[6] !in ['UND', 'ABS', 'COM'] && !cxx_readelf_decimal(fields[6]))
			|| (index > 0 && fields.len < 8) {
			return error('readelf reported a malformed dynamic symbol entry')
		}
		if fields.len < 8 { continue }
		named = true
		if fields[6] == 'UND' { continue }
		name := fields[7]
		if name.starts_with('_Z') || name.starts_with('__cxa_') || name.starts_with('_Unwind_') {
			return error('adapted C++ ABI was exported into the native DSO namespace: ' + name)
		}
	}
	if !named { return error('readelf dynamic symbol table has no named entries') }
}

fn cxx_verify_linkage(out string, label string, binary_path string, env map[string]string) ! {
	reader := executable('VINIX_IOS_LINUX_READELF', 'readelf')!
	mut reader_env := env.clone()
	reader_env['LC_ALL'] = 'C'
	os.write_file(out + '/' + label + '-readelf-input.json', json2.encode(digest(reader)!,
		prettify: true
	))!
	needed := checked(out, label + '-needed', [reader, '-d', binary_path], out, reader_env)!
	cxx_validate_dynamic_output(needed)!
	symbols := checked(out, label + '-dynamic-symbols', [reader, '--dyn-syms', '--wide', binary_path], out, reader_env)!
	cxx_validate_symbol_output(symbols)!
}

fn cxx_probe_header(out string) ! {
	os.write_file(out + '/payload/gnu-cxx-abi-probe.h', '#include <stdint.h>\nint vinix_ios_gnu_cxx_abi_probe(uint64_t*, uint64_t, unsigned char*, uint64_t);\n')!
}

fn cxx_probe_object(profile CxxProfile, out string, env map[string]string) !string {
	compiler := os.find_abs_path_of_executable(profile.manifest.compiler)!
	if digest(compiler)!.sha256 != profile.manifest.compiler_sha256 {
		return error('GNU C++ compiler differs from the selected backend build')
	}
	// Keep the generated dependency binding with the V assertions it serves.
	// The adapter contains no expected-value checks and is never a runner input.
	input := out + '/payload/gnu-cxx-abi-probe.cpp'
	os.cp(profile.probe, input)!
	object := out + '/payload/gnu-cxx-abi-probe.o'
	mut command := [compiler]
	command << cxx_consumer_flags(profile)!
	command << ['-std=c++17', '-O1', '-g', '-c', input, '-o', object]
	checked(out, 'cxx-abi-probe-object', command, out, env)!
	if digest(compiler)!.sha256 != profile.manifest.compiler_sha256 {
		return error('GNU C++ compiler changed while compiling the conversion binding')
	}
	return object
}

// The historical fixture invokes private constructor entry points over two
// already default-constructed strings. LLVM 19 annotates those live empty
// strings, so that is not valid constructor storage. Keep the repository's
// reference and every comparison intact; adapt only those two lifetimes in
// the external compilation input and destroy each successfully initialized
// object once, including when a later comparison returns early.
pub fn cxx_native_fixture_source(original string) !string {
	anchor := 'static int strings() {'
	storage := 'struct VinixLegacyStringStorage {\n' +
		'    alignas(std::string) unsigned char bytes[sizeof(std::string)] = {};\n' +
		'    bool initialized = false;\n' +
		'    ~VinixLegacyStringStorage() { if (initialized) string_destroy_base(bytes); }\n' +
		'};\n\n' + anchor
	short_before := '    std::string short_string;\n    string_init(&short_string, binary, sizeof(binary));'
	short_after := '    VinixLegacyStringStorage short_storage;\n' +
		'    std::string& short_string = *reinterpret_cast<std::string*>(short_storage.bytes);\n' +
		'    string_init(&short_string, binary, sizeof(binary));\n' +
		'    short_storage.initialized = true;'
	fill_before := "    std::string filled;\n    string_fill(&filled, 100, 'x');"
	fill_after := '    VinixLegacyStringStorage filled_storage;\n' +
		'    std::string& filled = *reinterpret_cast<std::string*>(filled_storage.bytes);\n' +
		"    string_fill(&filled, 100, 'x');\n" +
		'    filled_storage.initialized = true;'
	for expected in [anchor, short_before, fill_before] {
		if original.count(expected) != 1 {
			return error('native C++ reference changed at a required constructor-lifetime anchor')
		}
	}
	return original.replace(anchor, storage).replace(short_before, short_after).replace(fill_before, fill_after)
}

// Native ELF exception checks do not exercise Mach-O unwind registration.
// The V fixture separately calls the app resolver on guarded raw storage.
fn cxx_native_fixture(profile CxxProfile, sanitizer CxxSanitizer, out string, root string, cc string, sysroot string,
	invocation []string, build_env map[string]string, run_env map[string]string) ! {
	compiler := os.find_abs_path_of_executable(profile.manifest.compiler)!
	compiler_before := digest(compiler)!
	if compiler_before.sha256 != profile.manifest.compiler_sha256 {
		return error('GNU C++ compiler differs from the selected backend build')
	}
	os.write_file(out + '/cxx-compiler-input.json', json2.encode(compiler_before, prettify: true))!
	checked(out, 'cxx-compiler-version', [compiler, '--version'], root, build_env)!
	fixture_path := root + '/tests/ios/cxx-extended.cpp'
	fixture_source := out + '/payload/cxx-native-fixture.cpp'
	os.write_file(fixture_source, cxx_native_fixture_source(os.read_file(fixture_path)!)!)!
	os.write_file(out + '/cxx-native-source-inputs.json', json2.encode([
		digest(fixture_path)!,
		digest(fixture_source)!,
	], prettify: true))!
	object := out + '/payload/cxx-native.o'
	mut compile := [compiler]
	compile << cxx_consumer_flags(profile)!
	compile << ['-DIOS_CXX_NATIVE', '-std=c++17', '-O1', '-g', '-c', fixture_source, '-o', object]
	checked(out, 'cxx-native-object', compile, out, build_env)!
	binary_path := out + '/cxx-native'
	mut link := [cc, '-g', '-no-pie', '-fsanitize=address,undefined']
	link << cxx_sanitizer_link_flags(sanitizer, out)
	if sysroot != '' { link << '--sysroot=' + sysroot }
	link << object
	link << cxx_link(profile)
	link << ['-pthread', '-ldl', '-lm', '-o', binary_path]
	checked(out, 'cxx-native-link', link, out, build_env)!
	require_arm64_elf(binary_path)!
	cxx_verify_linkage(out, 'cxx-native', binary_path, build_env)!
	mut native := invocation[..invocation.len - 1].clone()
	native << binary_path
	output := checked(out, 'cxx-native-runtime', native, out, run_env)!
	for marker in ['IOS-CXX-EXTENDED: native vector exception types and messages',
		'IOS-CXX-EXTENDED: legacy strings, integer sorts, futures and weak ownership',
		'IOS-CXX-EXTENDED: long ostream 1099511627776'] {
		if output.split_into_lines().filter(it == marker).len != 1 {
			return error('native C++ fixture omitted coverage: ' + marker)
		}
	}
	if digest(compiler)! != compiler_before {
		return error('GNU C++ compiler changed during the native fixture build')
	}
}
