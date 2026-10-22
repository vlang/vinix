// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import crypto.sha256
import json2

struct ClosureCase {
	architecture string
	name string
	status int
	diagnostic string
}

struct ClosureReceipt {
	format int = 1
	scope string = 'host publisher admission, real cross-compiled ELF64; no guest execution'
	inputs map[string]string
	cases []ClosureCase
}

fn invoke(executable string, arguments []string) !(int, string) {
	mut process := os.new_process(executable)
	process.set_args(arguments); process.set_redirect_stdio_merged(); process.run()
	output := process.stdout_slurp(); process.wait(); code := process.code; process.close()
	return code, output
}

fn command(executable string, arguments []string) !string {
	code, output := invoke(executable, arguments)!
	if code != 0 { return error(executable + ': ' + output) }
	return output.trim_space()
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

// Pin each exact root input against the file identity admitted into the lock.
// These qualification roots contain ordinary files, so host path resolution is
// sufficient here; production import_node supplies the guest-root semantics.
fn pin_catalog_inputs(mut pins map[string]string, profile string, roots string, catalog string) ! {
	document := json2.decode[json2.Any](catalog)!.as_map()
	for item in document['packages']!.as_array() {
		package := item.as_map(); source := package['source']!.str()
		recipe := package['recipe']!.as_map(); manifest := recipe['manifest']!.as_map()
		mut expected := map[string]string{}
		for item_file in manifest['files']!.as_array() {
			file := item_file.as_map(); expected[file['path']!.str()] = file['sha256']!.str()
		}
		for item_entry in recipe['entries']!.as_array() {
			entry := item_entry.as_map(); relative := entry['source']!.str()
			actual := digest(roots + '/' + source + '/' + relative)!
			assert actual == expected[entry['path']!.str()]!
			pins['real-' + profile + '/' + source + '/' + relative] = actual
		}
	}
}

fn compile_library(cc string, root string, source string, soname string, extra []string) ! {
	command(cc, ['-shared', '-fPIC', '-Wl,-soname,' + soname, '-o', root + '/lib/libsqlite3.so.0', source, ...extra])!
}

fn run() ! {
	$if prod { return error('compile the ELF closure check without -prod; assertions are required') }
	if os.args.len !in [3, 7] { return error('usage: elf-closure-check VINIX_PACKAGE NEW_WORK_DIRECTORY [SQLITE_ROOTS SQLITE_LOCK FFMPEG_ROOTS FFMPEG_LOCK]') }
	cli := os.real_path(os.args[1]); work := os.abs_path(os.args[2])
	if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
	os.mkdir(work)!
	mut pins := {'cli': digest(cli)!, 'driver': digest(os.executable())!, 'driver-source': digest(@FILE)!, 'v-compiler': digest(@VEXE)!}
	for path in ['tools/packages/pkgcore/elf_closure.v', 'tools/packages/pkgcore/elf_profile.v',
		'tools/packages/pkgcore/sqlite_profile.v', 'tools/packages/pkgcore/ffmpeg_profile.v', 'tools/packages/main.v',
		'tools/packages/pkgcore/elf_closure_test.v', 'tests/packages/elffixture/image.v',
		'tools/packages/pkgcore/sqlite_builder_ownership_test.v', 'tools/packages/pkgcore/ffmpeg_builder_ownership_test.v',
		'tools/packages/pkgcore/sqlite_profile_test.v', 'tools/packages/pkgcore/ffmpeg_profile_test.v',
		'tools/packages/pkgcore/elf_profile_test.v', 'tools/packages/pkgcore/elf_profile_ownership_test.v',
		'tests/packages/elf-profile-check.v', 'desktop/tools/tests/heap_tracker.h'] {
		pins[path] = digest(path)!
	}
	mut cases := []ClosureCase{}
	for architecture in ['aarch64', 'x86_64'] {
		cc := os.find_abs_path_of_executable(os.getenv_opt(if architecture == 'aarch64' { 'CC_AARCH64' } else { 'CC_X86_64' }) or { architecture + '-linux-musl-gcc' })!
		pins['compiler-' + architecture] = digest(os.real_path(cc))!
		root := work + '/roots/' + architecture
		for directory in ['bin', 'lib', 'licenses'] { os.mkdir_all(root + '/' + directory)! }
		source := work + '/' + architecture; os.mkdir(source)!
		os.write_file(source + '/runner.c', 'int main(void) { return 0; }\n')!
		os.write_file(source + '/app.c', 'extern int sqlite_fixture(void); int main(void) { return sqlite_fixture(); }\n')!
		os.write_file(source + '/direct.c', 'extern int sqlite_fixture(void); extern int leaf(void); int main(void) { return sqlite_fixture() + leaf(); }\n')!
		os.write_file(source + '/library.c', 'extern int getpid(void); int sqlite_fixture(void) { return getpid(); }\n')!
		os.write_file(source + '/transitive.c', 'extern int leaf(void); int sqlite_fixture(void) { return leaf(); }\n')!
		os.write_file(source + '/leaf.c', 'int leaf(void) { return 7; }\n')!
		command(cc, ['-static', '-no-pie', '-o', root + '/bin/vinix-linux-runner', source + '/runner.c'])!
		command(cc, ['-shared', '-fPIC', '-Wl,-soname,libleaf.so.1', '-o', root + '/lib/libleaf.so.1', source + '/leaf.c'])!
		compile_library(cc, root, source + '/library.c', 'libsqlite3.so.0', []string{})!
		command(cc, ['-fPIE', '-pie', '-o', root + '/bin/sqlite3', source + '/app.c', '-L' + root + '/lib', '-Wl,--no-as-needed', '-l:libsqlite3.so.0'])!
		libc := command(cc, ['-print-file-name=libc.so'])!
		os.cp(os.real_path(libc), root + '/lib/libc.so')!
		for notice in ['sqlite-COPYRIGHT', 'musl-COPYRIGHT', 'vinix-COPYING'] { os.write_file(root + '/licenses/' + notice, 'ELF admission fixture only; not an application release.\n')! }
		for file in ['bin/sqlite3', 'bin/vinix-linux-runner', 'lib/libsqlite3.so.0', 'lib/libc.so', 'lib/libleaf.so.1'] { pins[architecture + '/' + file] = digest(root + '/' + file)! }
	}
	baseline := work + '/baseline'
	command(cli, ['sqlite-catalog', '3.53.4', '1.0.0', work + '/roots', baseline])!
	canonical := os.read_file(baseline + '/catalog.json')!
	pins['fixture-catalog'] = digest(baseline + '/catalog.json')!
	for architecture in ['aarch64', 'x86_64'] {
		cc := os.find_abs_path_of_executable(os.getenv_opt(if architecture == 'aarch64' { 'CC_AARCH64' } else { 'CC_X86_64' }) or { architecture + '-linux-musl-gcc' })!
		root := work + '/roots/' + architecture; source := work + '/' + architecture
		original_app := os.read_bytes(root + '/bin/sqlite3')!; original_library := os.read_bytes(root + '/lib/libsqlite3.so.0')!
		for fault in ['missing-direct', 'missing-transitive', 'ambiguous-soname', 'ambient-runpath'] {
			match fault {
				'missing-direct' { command(cc, ['-fPIE', '-pie', '-o', root + '/bin/sqlite3', source + '/direct.c', '-L' + root + '/lib', '-Wl,--no-as-needed', '-l:libsqlite3.so.0', '-l:libleaf.so.1'])! }
				'missing-transitive' { compile_library(cc, root, source + '/transitive.c', 'libsqlite3.so.0', ['-L' + root + '/lib', '-l:libleaf.so.1'])! }
				'ambiguous-soname' { compile_library(cc, root, source + '/library.c', 'libc.so', []string{})! }
				'ambient-runpath' { command(cc, ['-fPIE', '-pie', '-Wl,-rpath,/usr/lib', '-o', root + '/bin/sqlite3', source + '/app.c', '-L' + root + '/lib', '-l:libsqlite3.so.0'])! }
				else {}
			}
			pins[architecture + '/' + fault + '/app'] = digest(root + '/bin/sqlite3')!
			pins[architecture + '/' + fault + '/library'] = digest(root + '/lib/libsqlite3.so.0')!
			destination := work + '/' + architecture + '-' + fault
			status, diagnostic := invoke(cli, ['sqlite-catalog', '3.53.4', '1.0.0', work + '/roots', destination])!
			expected := if fault.starts_with('missing-') { 'ELF closure missing library libleaf.so.1' }
				else if fault == 'ambiguous-soname' { 'ELF closure has ambiguous SONAME libc.so' }
				else { 'ELF closure refuses a search path outside' }
			assert status == 1 && diagnostic.contains(expected), diagnostic
			assert !os.exists(destination) && !os.is_link(destination)
			assert os.ls(work)!.all(!it.starts_with('.vinix-'))
			cases << ClosureCase{architecture, fault, status, diagnostic.trim_space()}
			os.write_file_array(root + '/bin/sqlite3', original_app)!; os.write_file_array(root + '/lib/libsqlite3.so.0', original_library)!
			command(cli, ['sqlite-catalog', '3.53.4', '1.0.0', work + '/roots', destination])!
			assert os.read_file(destination + '/catalog.json')! == canonical
			println('PASS ' + architecture + '/' + fault + ': refuses, cleans staging, restored retry matches exact lock')
		}
		command(cc, ['-fPIE', '-pie', '-Wl,-rpath,$ORIGIN/../lib', '-o', root + '/bin/sqlite3', source + '/app.c', '-L' + root + '/lib', '-l:libsqlite3.so.0'])!
		command(cli, ['sqlite-catalog', '3.53.4', '1.0.0', work + '/roots', work + '/' + architecture + '-origin'])!
		cases << ClosureCase{architecture, 'packaged-origin-runpath', 0, ''}
		os.write_file_array(root + '/bin/sqlite3', original_app)!
	}
	if os.args.len == 7 {
		for index, profile in ['sqlite', 'ffmpeg'] {
			roots := os.real_path(os.args[3 + index * 2]); previous := os.real_path(os.args[4 + index * 2])
			destination := work + '/replay-' + profile
			argv := if profile == 'sqlite' { ['sqlite-catalog', '3.53.4', '1.0.0', roots, destination] }
				else { ['ffmpeg-catalog', '1.0.0', roots, destination] }
			command(cli, argv)!
			assert os.read_file(destination + '/catalog.json')! == os.read_file(previous)!, profile + ' replay changed the canonical catalog'
			pin_catalog_inputs(mut pins, profile, roots, os.read_file(destination + '/catalog.json')!)!
			pins['previous-' + profile + '-catalog'] = digest(previous)!
			pins['replay-' + profile + '-catalog'] = digest(destination + '/catalog.json')!
			cases << ClosureCase{'aarch64,x86_64', 'real-' + profile + '-replay', 0, 'exact historical canonical catalog preserved'}
			println('PASS real ' + profile + ' both architectures: complete graph accepted; exact historical catalog preserved')
		}
	}
	os.write_file(work + '/qualification.json', json2.encode(ClosureReceipt{inputs: pins, cases: cases}) + '\n')!
	println('PASS real aarch64/x86_64 PIE/shared/static ELF: 8 refusals with exact restored retries; 2 packaged origin-runpath admissions')
}

fn main() { run() or { eprintln(err); exit(1) } }
