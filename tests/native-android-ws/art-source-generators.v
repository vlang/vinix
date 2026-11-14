// SPDX-License-Identifier: GPL-2.0-or-later
module main

import artgenerators
import crypto.sha256
import json2
import os

fn check_inputs(make_root string, header_root string, output string) ! {
	os.mkdir(output)!
	mut records := []map[string]string{}
	for group in ['runtime', 'libartbase', 'libdexfile', 'compiler', 'dex2oat'] {
		makefile := make_root + '/art/' + group + '/Android.mk'
		make_text := os.read_file(makefile)!
		lines := make_text.split_into_lines()
		mut inside := false
		mut count := 0
		os.mkdir(output + '/' + group)!
		for line in lines {
			if !inside {
				if line.contains('_srcs_SRCS') { inside = true }
				continue
			}
			if line.starts_with('define ') { break }
			name := line.trim(' \t\\')
			if name == '' { continue }
			if !name.ends_with('.h') || name.contains('..') || name.contains(' ') {
				return error('unexpected operator header list in ' + makefile)
			}
			local := header_root + '/art/' + group
			path := local + '/' + name
			generated := artgenerators.operators(local, [path])!
			target := output + '/' + group + '/' + name + '_operator_out.cc'
			os.mkdir_all(os.dir(target))!
			os.write_file(target, generated)!
			records << {'makefile': makefile, 'makefile_sha256': sha256.sum(make_text.bytes()).hex(),
				'header': path, 'header_sha256': sha256.sum(os.read_bytes(path)!).hex(),
				'output': target, 'output_sha256': sha256.sum(generated.bytes()).hex()}
			count++
		}
		if count == 0 { return error('no operator headers found for ' + group) }
		println('ART-OPERATOR-INPUT-PASS ${group} headers=${count}')
	}
	os.write_file(output + '/inputs.json', json2.encode(records, prettify: true) + '\n')!
	println('ART-OPERATOR-INPUTS-PASS headers=${records.len}')
}

fn check(root string) ! {
	os.mkdir(root)!
	// Independent expected constants include signed minima, unsigned wrapping,
	// large positive values, lexical sorting and all three immediate prefixes.
	input := '.ascii ">>Z #7 #0<<"\n.ascii ">>U $-1 $0<<"\n' +
		'.ascii ">>N -9223372036854775808 1<<"\n' +
		'.ascii ">>P 18446744073709551615 0<<"\n' +
		'.ascii ">>A 2 0<<"\n.ascii ">>A 10 0<<"\n' +
		'.ascii ">>M -9223372036854775808 0<<"\n.ascii ">>B -0 1<<"'
	expected := '#define A 0xa\n#define A 0x2\n#define B 0x0\n' +
		'#define M 0x8000000000000000\n#define N -0x8000000000000000\n' +
		'#define P 0xffffffffffffffff\n#define U 0xffffffffffffffff\n#define Z 0x7\n'
	assert artgenerators.asm_header(input)! == expected
	for bad in ['', 'unrelated assembly', '">>X #7 #2<<"', '">>X #x #0<<"',
		'">>X #18446744073709551616 #0<<"', '">>X #-9223372036854775809 #0<<"',
		'">>X #1 #0', '">>X Y #1 #0<<"'] {
		if _ := artgenerators.asm_header(bad) { return error('bad assembly accepted: ' + bad) }
	}
	os.write_file(root + '/constants.s', input)!
	for bad in ['">>X $#1 #0<<"', '">>X #1 $#0<<"'] {
		if _ := artgenerators.asm_header(bad) { return error('invalid immediate prefix accepted') }
	}
	os.write_file(root + '/constants.h', expected)!
	// Compile and execute the generated operators, with independently specified
	// stream results for aliases, scoped and nested enums, overrides and fallback.
	os.write_file(root + '/fixture.h', '#include <ostream>\nnamespace fixture {\n' +
		'enum {\n  kAnonymous = 3,\n};\n' +
		'class Forward;\nstruct Outer {\n  enum Kind {\n    kOne = 1,\n' +
		'    kAlias = kOne,\n    kTwo = 2, // <<second>>\n  };\n};\n' +
		'enum class Scoped : int {\n  kYes = -1,\n  kNo = 0x10,\n};\n' +
		'class Hidden {\n  enum Private { // private\n    kHidden,\n  };\n};\n' +
		'} // namespace fixture\n')!
	generated := artgenerators.operators(root, [root + '/fixture.h'])!
	assert !generated.contains('kAlias:') && !generated.contains('kHidden:') && !generated.contains('kAnonymous:')
	os.write_file(root + '/operators.cc', generated + '#include <sstream>\n' +
		'int main() {\n  std::ostringstream out;\n' +
		'  using namespace fixture;\n  out << Outer::kOne << "," << Outer::kTwo << ","\n' +
		'      << static_cast<Outer::Kind>(9) << "," << Scoped::kYes << "," << Scoped::kNo;\n' +
		'  return out.str() == "One,second,Outer::Kind[9],Yes,No" ? 0 : 1;\n}\n')!
	compiler := if os.getenv('CXX') != '' { os.getenv('CXX') } else { '/usr/bin/c++' }
	compiled := os.exec([compiler, '-std=c++17', '-Wall', '-Werror', root + '/operators.cc',
		'-o', root + '/operator-check'])
	if compiled.exit_code != 0 { return error('operator fixture compilation failed: ' + compiled.output) }
	assert os.exec([root + '/operator-check']).exit_code == 0
	// Exercise actual compiler emitted immediate syntax, not just test strings.
	os.write_file(root + '/asm-defines.cc', 'void constants() {\n' +
		'  asm volatile(".ascii \\\">>OBJECT_MASK %0 %1<<\\\"" : : "i"(7), "i"(0));\n' +
		'  asm volatile(".ascii \\\">>WRAP %0 %1<<\\\"" : : "i"(-1LL), "i"(0));\n' +
		'  asm volatile(".ascii \\\">>SIGNED %0 %1<<\\\"" : : "i"(-7LL), "i"(1));\n}\n')!
	assembly := os.exec([compiler, '-S', root + '/asm-defines.cc', '-o', root + '/asm-defines.s'])
	if assembly.exit_code != 0 { return error('assembly constant fixture compile failed: ' + assembly.output) }
	assert artgenerators.asm_header(os.read_file(root + '/asm-defines.s')!)! ==
		'#define OBJECT_MASK 0x7\n#define SIGNED -0x7\n#define WRAP 0xffffffffffffffff\n'
	os.write_file(root + '/bad-enum.h', 'namespace fixture {\nenum E {\nkBad = 1 << 2,\n};\n}\n')!
	if _ := artgenerators.operators(root, [root + '/bad-enum.h']) {
		return error('unsupported enum expression accepted')
	}
	for directory in ['a/child', 'b/deep/leaf', 'out/hidden', '.git/hidden'] {
		os.mkdir_all(root + '/' + directory)!
	}
	for directory in ['a', 'a/child', 'b/deep/leaf', 'out/hidden', '.git/hidden'] {
		os.write_file(root + '/' + directory + '/Android.mk', '# fixture\n')!
	}
	assert artgenerators.find_leaves(['--prune=out', '--prune=.git', root, root,
		'Android.mk'])! == [root + '/a/Android.mk', root + '/b/deep/leaf/Android.mk']
	assert artgenerators.find_leaves(['--mindepth=3', root + '/a', 'Android.mk'])!.len == 0
	assert artgenerators.find_leaves(['--mindepth=2', root + '/a', 'Android.mk'])! ==
		[root + '/a/child/Android.mk']
	os.symlink(root + '/a', root + '/alias')!
	assert artgenerators.find_leaves([root + '/alias', 'Android.mk'])! ==
		[root + '/alias/Android.mk']
	os.symlink(root + '/b', root + '/b/cycle')!
	if _ := artgenerators.find_leaves([root + '/b', 'Android.mk']) {
		return error('directory cycle accepted')
	}
	for args in [['--unknown', root, 'Android.mk'], ['--mindepth=x', root, 'Android.mk'],
		['--mindepth=-', root, 'Android.mk'], ['--mindepth=99999999999999', root, 'Android.mk'],
		['--prune=', root, 'Android.mk'], [root]] {
		if _ := artgenerators.find_leaves(args) { return error('invalid discovery args accepted') }
	}
	println('ART-SOURCE-GENERATORS-PASS constants, compiled operators, traversal, depth, pruning, aliases, cycles')
}

fn main() {
	if os.args.len < 3 { eprintln('usage: art-source-generators find-leaves [OPTIONS] DIR... NAME | asm-header INPUT | operators LOCAL HEADER... | --self-test FRESH_ROOT'); exit(2) }
	match os.args[1] {
		'find-leaves' {
			paths := artgenerators.find_leaves(os.args[2..]) or { eprintln(err); exit(1) }
			if paths.len > 0 { println(paths.join('\n')) }
		}
		'asm-header' {
			if os.args.len != 3 { exit(2) }
			input := os.read_file(os.args[2]) or { eprintln(err); exit(1) }
			result := artgenerators.asm_header(input) or { eprintln(err); exit(1) }
			print(result)
		}
		'operators' {
			if os.args.len < 4 { exit(2) }
			result := artgenerators.operators(os.args[2], os.args[3..]) or { eprintln(err); exit(1) }
			print(result)
		}
		'check-art-inputs' {
			if os.args.len != 5 { exit(2) }
			check_inputs(os.args[2], os.args[3], os.args[4]) or { eprintln(err); exit(1) }
		}
		'--self-test' {
			if os.args.len != 3 { exit(2) }
			check(os.abs_path(os.args[2])) or { eprintln(err); exit(1) }
		}
		else { eprintln('unknown generator mode'); exit(2) }
	}
}
