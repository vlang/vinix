// SPDX-License-Identifier: GPL-2.0-or-later
module allocationhost

import generators
import json2
import os

const benchmark_entry = "module guestentry\n#include <entry-abi.h>\nfn C.alloc_bench_native_main(i32, &&char) i32\nfn C.fflush(voidptr) i32\nfn C.pause() i32\n@[export: 'main']\npub fn run() i32 {\n unsafe {\n args := [&char(c'alloc-bench'), &char(c'--iterations'), &char(c'65'), &char(c'--samples'), &char(c'6'), &char(c'--label'), &char(c'native'), &char(nil)]!\n result := C.alloc_bench_native_main(7, &args[0])\n C.fflush(nil)\n if result == 0 { for { C.pause() } }\n return result\n }\n}\n"
const sampler_original_entry = "module originalentry\n#include <entry-abi.h>\nfn C.sampler_original_main() i32\nfn C.fflush(voidptr) i32\nfn C.pause() i32\n@[export: 'main']\npub fn run() i32 { result := C.sampler_original_main(); C.fflush(unsafe { nil }); if result == 0 { for { C.pause() } }; return result }\n"

fn entry(work string, name string, source string, header string, arch string, flags []string) !string {
	directory := work + '/' + name
	os.mkdir(directory)!
	os.write_file(directory + '/core.v', source)!
	os.write_file(directory + '/entry-abi.h', header)!
	generated := work + '/' + name + '.c'
	object := work + '/' + name + '.o'
	generators.generate_module(directory, generated, arch, []string{})!
	run([...flags, '-Wno-unused-function', '-Wno-unused-parameter', '-I', directory, '-c', generated,
		'-o', object])!
	return object
}

pub fn build_benchmark(work string, flags []string, arch string, original string, model bool, guest bool) !string {
	source := work + '/bench.c'
	mut manifest := if original != '' {
		os.cp(original, source)!
		{
			'source_sha256': json2.Any(digest(source)!)
			'original':      json2.Any(original)
		}
	} else {
		generators.generate_bench(source, arch)!
	}
	compile_flags := object_flags(flags, false)
	object := work + '/bench.o'
	mut defines := []string{}
	if model {
		for name in ['malloc', 'free', 'mmap', 'munmap', 'pipe', 'close', 'clock_gettime',
			'clock_getres', 'uname', 'sysconf'] {
			defines << '-D' + name + '=vab_fixture_' + name
		}
	}
	if guest { defines << '-Dmain=alloc_bench_native_main' }
	run([...compile_flags, ...defines, '-I', work, '-c', source, '-o', object])!
	imports := checked([os.getenv_opt('NM') or { 'nm' }, '-u', object])!.stdout
	if implicit_allocations(imports, ['malloc', 'free']) {
		return error('benchmark has implicit allocation imports: ' + imports)
	}
	if forbidden_generated_calls(os.read_file(source)!, ['memdup', 'new_array', 'v_malloc']) {
		return error('benchmark has implicit generated allocations')
	}
	mut objects := [object]
	if model {
		provider := work + '/provider.c'
		provider_object := work + '/provider.o'
		generators.generate_module(here() + '/benchfixture', provider, arch, []string{})!
		run([...compile_flags, '-Wno-unused-function', '-Wno-unused-parameter', '-I',
			here() + '/benchfixture', '-c', provider, '-o', provider_object])!
		objects << provider_object
	}
	if guest {
		objects << entry(work, 'guestentry', benchmark_entry, '#include <stdio.h>\n#include <unistd.h>\nint alloc_bench_native_main(int, char **);\n', arch, compile_flags)!
		objects << generators.compile_fixture(root() + '/tests/kernel-gaps/serialcore', work + '/serial.o', if arch == 'arm64' {
			'aarch64'
		} else {
			'x86_64'
		}, flags)!
	}
	executable := work + '/test'
	run([...flags, ...if guest { ['-static'] } else { []string{} }, ...objects, '-o', executable])!
	manifest['compiler_flags'] = flags.map(json2.Any(it))
	manifest['arch'] = arch
	manifest['model'] = model
	manifest['guest'] = guest
	manifest['executable_sha256'] = digest(executable)!
	manifest['imports'] = imports.split_into_lines().map(json2.Any(it))
	write_json(work + '/inputs.json', manifest)!
	return executable
}

pub fn build_sampler(work string, arch string, flags []string, original string, guest bool) !string {
	v_arch := if arch == 'aarch64' { 'arm64' } else { 'amd64' }
	compile_flags := object_flags(flags, true)
	sampler := work + '/sampler.c'
	object := work + '/sampler.o'
	generators.generate_sampler(sampler, v_arch, true)!
	run([...compile_flags, '-DVINIX_KALLOC_HOST_TEST', '-I', root() + '/kernel/c', '-c', sampler,
		'-o', object])!
	imports := checked([os.getenv_opt('NM') or { 'nm' }, '-u', object])!.stdout
	if implicit_allocations(imports, []string{}) || forbidden_generated_calls(os.read_file(sampler)!, [
		'memdup',
		'new_array',
	]) {
		return error('sampler has implicit allocation imports: ' + imports)
	}
	mut objects := [object]
	if original != '' {
		fixture := work + '/original-fixture.o'
		run([...compile_flags, ...if guest { ['-Dmain=sampler_original_main'] } else { []string{} },
			'-c', original, '-o', fixture])!
		objects << fixture
		if guest {
			objects << entry(work, 'originalentry', sampler_original_entry, '#include <stdio.h>\n#include <unistd.h>\nint sampler_original_main(void);\n', v_arch, compile_flags)!
		}
	} else {
		generated := work + '/fixture.c'
		fixture := work + '/fixture.o'
		generators.generate_module(here() + '/samplerfixture', generated, v_arch, if guest {
			['sampler_guest']
		} else {
			[]string{}
		})!
		run([...compile_flags, '-Wno-unused-function', '-Wno-unused-parameter', '-I',
			here() + '/samplerfixture', '-c', generated, '-o', fixture])!
		fixture_imports := checked([os.getenv_opt('NM') or { 'nm' }, '-u', fixture])!.stdout
		if implicit_allocations(fixture_imports, ['calloc', 'free']) {
			return error('fixture has implicit allocation imports: ' + fixture_imports)
		}
		text := os.read_file(generated)!
		if generated_call_count(text, 'calloc') != 1 || generated_call_count(text, 'free') != 1 {
			return error('sampler fixture allocation/free site mismatch')
		}
		objects << fixture
		assembly := work + '/varargs.o'
		run([...compile_flags, '-c', here() + '/samplerfixture/varargs-' + v_arch + '.S', '-o',
			assembly])!
		objects << assembly
	}
	if guest {
		objects << generators.compile_fixture(root() + '/tests/kernel-gaps/serialcore', work + '/serial.o', arch, flags)!
	}
	executable := work + '/test'
	run([...flags, ...if guest { ['-static'] } else { []string{} }, ...objects, '-o', executable])!
	write_json(work + '/inputs.json', {
		'arch':                     json2.Any(arch)
		'native_model':             json2.Any(guest)
		'compiler_flags':           json2.Any(flags.map(json2.Any(it)))
		'original':                 if original == '' {
			json2.Any(json2.Null{})
		} else {
			json2.Any(original)
		}
		'original_sha256':          if original == '' {
			json2.Any(json2.Null{})
		} else {
			json2.Any(digest(original)!)
		}
		'sampler_generated_sha256': json2.Any(digest(sampler)!)
		'executable_sha256':        json2.Any(digest(executable)!)
		'sampler_imports':          json2.Any(imports.split_into_lines().map(json2.Any(it)))
	})!
	return executable
}
