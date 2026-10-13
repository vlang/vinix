// SPDX-License-Identifier: GPL-2.0-or-later
module main

import devcore
import sourcecore
import json2
import os

struct VStage {
	schema          int = 1
	architecture    string
	source_revision string
	source_sha256   string
	host_compiler   devcore.Pin
	cc              devcore.Pin
	cc_argv         []string
	translate_argv  []string
	compile_argv    []string
	link_argv       []string
	helper_argv     [][]string
mut:
	complete            bool
	generated_c_sha256  string
	compiler_sha256     string
	installation_sha256 string
	helper_sha256       map[string]string
}

// Include library/compiler production sources and headers without copying
// tests, untracked inputs, host TCC binaries or any Python source.
fn production_source(path string) bool {
	if path.starts_with('thirdparty/tcc/') || path.contains('/tests/')
		|| path.contains('/testdata/') || path.contains('/test_data/') || path.ends_with('_test.v') {
		return false
	}
	return path.ends_with('.v') || path.ends_with('.vh') || path.ends_with('.c')
		|| path.ends_with('.h') || path.ends_with('.inc') || path.ends_with('/v.mod')
		|| path == 'v.mod'
		|| (path.starts_with('vlib/v/help/') && path.ends_with('.txt'))
		|| os.file_name(path).starts_with('LICENSE')
}

fn stage_v() ! {
	args := os.args[1..]
	if args == ['--help'] || args.len == 0 {
		println('Usage: v run stage-v.v aarch64|x86_64 V-SOURCE-CHECKOUT FRESH-STAGING [CC-ARGV-JSON]')
		return
	}
	if args.len !in [3, 4] || args[0] !in ['aarch64', 'x86_64'] {
		return error('invalid arguments; use --help')
	}
	arch := args[0]
	source := os.real_path(args[1])
	commit := sourcecore.revision(source)!
	mut cc := if args.len == 4 {
		json2.decode[[]string](args[3])!
	} else {
		[arch + '-linux-musl-gcc']
	}
	if cc.len == 0 { return error('C compiler argv must not be empty') }
	cc[0] = os.find_abs_path_of_executable(cc[0])!
	v := os.find_abs_path_of_executable(os.getenv_opt('VINIX_V_COMPILER') or { @VEXE })!
	devcore.fresh_directory(args[2])!
	output := os.real_path(args[2])
	root := output + '/vlang'
	os.mkdir(root, mode: 0o755)!
	sourcecore.export(source, commit, ['cmd', 'vlib', 'thirdparty', 'LICENSE', 'v.mod'], root, production_source)!
	input_hash := devcore.tree_hash(root)!
	os.write_file(root + '/VERSION', commit + '\n')!
	work := output + '/.build'
	os.mkdir(work, mode: 0o700)!
	c := work + '/v.c'
	object := work + '/v.o'
	helper_sources := ['vlib/os/execute_capture_nix.c', 'vlib/v/pthread_helper.c',
		'vlib/v/bench/peak_rss.c', 'vlib/v/modulecache/file_metadata.c',
		'vlib/builtin/segfault_handler_nix.c']
	mut helper_objects := []string{}
	mut helper_commands := [][]string{}
	for helper in helper_sources {
		helper_object := root + '/' + helper.all_before_last('.') + '.o'
		helper_objects << helper_object
		helper_commands << [...cc, '-O2', '-std=gnu11', '-D_GNU_SOURCE', '-fPIC', '-c',
			root + '/' + helper, '-o', helper_object]
	}
	translate := [v, '-nocache', '-gc', 'none', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
		'-path', root + '/vlib|' + root, '-os', 'linux', '-arch',
		if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-o', c, root + '/cmd/v']
	compile := [...cc, '-O1', '-std=gnu11', '-D_GNU_SOURCE', '-DV_COMMIT_HASH="' + commit + '"',
		'-include', root + '/vlib/v/pthread_helper.h', '-c', c, '-o', object]
	link := [...cc, '-static', object, ...helper_objects, '-o', root + '/v', '-lm', '-lpthread']
	mut receipt := VStage{
		architecture:    arch
		source_revision: commit
		source_sha256:   input_hash
		host_compiler:   devcore.Pin{v, devcore.file_hash(v)!}
		cc:              devcore.Pin{cc[0], devcore.file_hash(cc[0])!}
		cc_argv:         cc
		translate_argv:  translate
		compile_argv:    compile
		link_argv:       link
		helper_argv:     helper_commands
	}
	manifest := output + '/native-v.json'
	mut environment := devcore.environment(1700000000)
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	println('Translating pinned V ${commit} for ${arch}')
	if devcore.run(translate, root, environment, 600, work + '/translate.log')! != 0 {
		return error('V compiler translation failed; see ' + work + '/translate.log')
	}
	receipt.generated_c_sha256 = devcore.file_hash(c)!
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	for i, helper in helper_sources {
		if devcore.run(helper_commands[i],
			root, environment, 120, work + '/helper-${i}.log')! != 0 {
			return error('native C helper failed: ' + helper)
		}
		os.chmod(helper_objects[i], 0o644)!
		receipt.helper_sha256[helper.all_before_last('.') + '.o'] = devcore.file_hash(helper_objects[i])!
	}
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	println('Compiling native V compiler object')
	if devcore.run(compile, root, environment, 1800, work + '/compile.log')! != 0 {
		return error('native V compiler object failed; see ' + work + '/compile.log')
	}
	println('Linking static native V compiler')
	if devcore.run(link, root, environment, 120, work + '/link.log')! != 0 {
		return error('native V compiler link failed; see ' + work + '/link.log')
	}
	os.chmod(root + '/v', 0o755)!
	mut binary := os.open(root + '/v')!
	mut header := []u8{len: 20}
	count := binary.read(mut header)!
	binary.close()
	if count != 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| (u16(header[18]) | u16(header[19]) << 8) != if arch == 'aarch64' {
			u16(183)
		} else {
			u16(62)
		} {
		return error('native V compiler has the wrong ELF architecture')
	}
	devcore.verify(receipt.host_compiler)!
	devcore.verify(receipt.cc)!
	receipt.compiler_sha256 = devcore.file_hash(root + '/v')!
	receipt.installation_sha256 = devcore.tree_hash(root)!
	receipt.complete = true
	os.write_file(manifest, json2.encode(receipt, prettify: true) + '\n')!
	println('Native V installation: ' + root)
}

fn main() {
	stage_v() or {
		eprintln(err)
		exit(1)
	}
}
