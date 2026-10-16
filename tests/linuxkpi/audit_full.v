// SPDX-License-Identifier: GPL-2.0-or-later
// Complete original i915 Kbuild syntax audit with checked compiler inputs.
// No Python façade or shared kernel build objects are used.
module main

import os
import json2
import hosttest
import strconv

struct Configuration {
	source   string
	archive  string
	compiler string
	make     string
	keep     string
	output   string
	jobs     int = 4
	timeout  int = 180
}

struct KbuildSources {
	sources    []string
	metadata   map[string][]string
	provenance json2.Any
}

struct Unit {
	source                  string
	passed                  bool
	code                    int
	diagnostics             string
	stdout                  string
	argv                    []string
	log                     string
	dependencies            map[string]string
	dependency_file_present bool
}

struct Blocker {
	name  string
	count int
}

fn require(condition bool, reason string) ! {
	if !condition { return error(reason) }
}

fn require_kbuild_path(path string) ! {
	// Upstream Kbuild does not support whitespace in source roots. Restrict
	// generated Make values to literal path bytes before writing any recipe.
	require(path != '' && path.bytes().all(it.is_alnum() || it in [`/`, `.`, `_`, `-`, `+`]),
		'Unsupported Kbuild path: only ASCII letters, digits, / . _ - + are accepted: ' + path)!
}

fn capture(argv []string, log string, cwd string, timeout int) !hosttest.Result {
	result := hosttest.capture_in(argv, '', timeout, os.environ(), cwd)!
	os.write_file(log, json2.encode(argv) + '\n' + result.stdout + result.stderr)!
	return result
}

fn driver_sources(linux string, state string, make string, archive string, pin map[string]json2.Any, timeout int) !KbuildSources {
	for path in [linux, state] {
		require_kbuild_path(path)!
	}
	driver := os.join_path(linux, 'drivers/gpu/drm/i915')
	script := os.join_path(state, 'source-list.Makefile')
	os.write_file(script, ['src := ' + driver, 'srctree := ' + linux, 'CONFIG_X86 := y',
		'CONFIG_ACPI := y', 'CONFIG_DRM_I915 := y', 'CONFIG_DRM_FBDEV_EMULATION := y',
		'include ' + hosttest.make_escape(os.join_path(driver, 'Makefile')), '.PHONY: vinix-source-list',
		'vinix-source-list:', "\t@printf '%s\\n' $(i915-y)", ''].join('\n'))!
	result := capture([make, '-s', '-f', script, 'vinix-source-list'], os.join_path(state, 'source-list.log'), '', timeout)!
	require(result.code == 0, 'Original Kbuild object-list expansion failed:\n' + result.stderr)!
	mut sources := []string{}
	for object in result.stdout.fields() {
		if !object.ends_with('.o') { continue }
		path := os.join_path(driver, object[..object.len - 2] + '.c')
		require(os.is_file(path), 'Original Kbuild selected a missing source: ' + path)!
		if path !in sources { sources << path }
	}
	sources.sort()
	require(sources.len != 0, 'Original Kbuild selected no i915 sources')!
	require(hosttest.file_digest(archive)! == pin['sha256']!.str(), 'Kbuild archive differs from upstream.json')!
	reference := os.join_path(state, 'original-kbuild')
	scripts := ['scripts/Kbuild.include', 'scripts/Makefile.lib']
	prefix := 'linux-' + pin['version']!.str() + '/'
	members := hosttest.archive_members(archive, scripts.map(prefix + it))!
	for name in scripts {
		path := os.join_path(reference, name)
		os.mkdir_all(os.dir(path))!
		os.write_file_array(path, members[prefix + name] or { return error('Missing pinned Kbuild source: ' + name) })!
	}
	// These are the original per-target metadata rules, including membership in
	// the composite i915 object. The recipe prints their expanded compiler args.
	metadata_script := os.join_path(state, 'module-metadata.Makefile')
	os.write_file(metadata_script, ['obj := drivers/gpu/drm/i915', 'src := ' + driver,
		'srctree := ' + linux, 'CONFIG_X86 := y', 'CONFIG_ACPI := y', 'CONFIG_DRM_I915 := y',
		'CONFIG_DRM_FBDEV_EMULATION := y',
		'include ' + hosttest.make_escape(os.join_path(reference, 'scripts/Kbuild.include')),
		'include ' + hosttest.make_escape(os.join_path(driver, 'Makefile')),
		'include ' + hosttest.make_escape(os.join_path(reference, 'scripts/Makefile.lib')),
		'.PHONY: FORCE', 'FORCE:', '$(obj)/%.o: FORCE',
		"\t@printf '%s\\t%s\\t%s\\t%s\\t%s\\n' '$*.o' $(basename_flags) $(modname_flags) $(modfile_flags)",
		''].join('\n'))!
	mut targets := []string{}
	for source in sources {
		targets << 'drivers/gpu/drm/i915/' + os.path_rel(driver, source)!.all_before_last('.') + '.o'
	}
	metadata_argv := [make, '-s', '-f', metadata_script, ...targets]
	expanded := capture(metadata_argv, os.join_path(state, 'module-metadata.log'), reference, timeout)!
	require(expanded.code == 0, 'Original Kbuild module metadata failed:\n' + expanded.stderr)!
	mut metadata := map[string][]string{}
	for line in expanded.stdout.split_into_lines() {
		if line == '' { continue }
		columns := line.split('\t')
		require(columns.len == 5 && columns[0].ends_with('.o'), 'Invalid Kbuild metadata row: ' + line)!
		path := os.join_path(driver, columns[0].all_before_last('.') + '.c')
		require(path in sources && path !in metadata, 'Kbuild metadata source mismatch or duplicate: ' + path)!
		for index, name in ['KBUILD_BASENAME', 'KBUILD_MODNAME', '__KBUILD_MODNAME', 'KBUILD_MODFILE'] {
			require(columns[index + 1].starts_with('-D' + name + '='), 'Original Kbuild omitted ' + name)!
		}
		metadata[path] = columns[1..].clone()
	}
	require(metadata.len == sources.len, 'Original Kbuild metadata omitted a source')!
	return KbuildSources{
		sources:    sources
		metadata:   metadata
		provenance: map[string]json2.Any{
			'archive_sha256':              pin['sha256']!
			'script_sha256':               hosttest.string_map(hosttest.hashes(scripts.map(os.join_path(reference, it)))!)
			'object_list_makefile_sha256': hosttest.sha(script)!
			'metadata_makefile_sha256':    hosttest.sha(metadata_script)!
			'metadata_argv':               hosttest.strings(metadata_argv)
			'metadata_stdout_sha256':      hosttest.text_sha(expanded.stdout)
		}
	}
}

fn compile_source(linux string, source string, argv []string, output string, index int, timeout int) !Unit {
	tag := os.join_path(output, 'unit-' + index.str())
	depfile := tag + '.d'
	command := [...argv, '-MD', '-MF', depfile, '-MT', source, source]
	result := capture(command, tag + '.log', '', timeout)!
	mut dependencies := map[string]string{}
	if os.is_file(depfile) {
		dependencies = hosttest.hashes(hosttest.dependency_paths(os.read_file(depfile)!, source)!)!
	}
	return Unit{
		source:                  os.path_rel(linux, source)!
		passed:                  result.code == 0
		code:                    result.code
		diagnostics:             result.stderr
		stdout:                  result.stdout
		argv:                    command
		log:                     tag + '.log'
		dependencies:            dependencies
		dependency_file_present: os.is_file(depfile)
	}
}

fn unit_json(unit Unit) json2.Any {
	return map[string]json2.Any{
		'source':                   json2.Any(unit.source)
		'passed':                   unit.passed
		'exit':                     unit.code
		'diagnostics':              unit.diagnostics
		'stdout':                   unit.stdout
		'argv':                     hosttest.strings(unit.argv)
		'log':                      unit.log
		'actual_dependency_sha256': hosttest.string_map(unit.dependencies)
		'dependency_file_present':  unit.dependency_file_present
	}
}

fn guarded_paths(root string, linux string, archive string, compiler string, make string) ![]string {
	manifest_path := os.join_path(linux, '.vinix-upstream.json')
	manifest := hosttest.decode_json(os.read_file(manifest_path)!)!.as_map()
	mut paths := [@FILE, compiler, make, archive, manifest_path,
		os.join_path(root, 'kernel/linuxkpi/upstream.json')]
	for path in manifest['files']!.as_map().keys() { paths << os.join_path(linux, path) }
	for directory in ['kernel/linuxkpi', 'tests/linuxkpi/hosttest', 'kernel/freestnd-c-hdrs'] {
		for extension in ['.v', '.h', '.json'] {
			paths << os.walk_ext(os.join_path(root, directory), extension)
		}
	}
	paths << os.walk_ext(os.join_path(root, 'kernel/c'), '.h')
	paths.sort()
	return paths
}

fn run(configuration Configuration) !int {
	root := hosttest.root()
	pin := hosttest.upstream_pin()!
	source_arg := if configuration.source == '' {
		hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(root, 'third_party/linux-i915/linux-' + pin['version']!.str()))
	} else {
		configuration.source
	}
	// Reject raw bytes too: native path normalization may turn a backslash
	// into a separator before the canonical-path validation can observe it.
	require_kbuild_path(source_arg)!
	if configuration.keep != '' { require_kbuild_path(configuration.keep)! }
	if os.getenv('TMPDIR') != '' { require_kbuild_path(os.getenv('TMPDIR'))! }
	linux := hosttest.resolve_path(source_arg)!
	require_kbuild_path(linux)!
	if configuration.keep != '' { require_kbuild_path(hosttest.resolve_path(configuration.keep)!)! }
	if os.getenv('TMPDIR') != '' {
		require_kbuild_path(hosttest.resolve_path(os.getenv('TMPDIR'))!)!
	}
	hosttest.verify_upstream(linux, pin)!
	state := hosttest.work_dir(configuration.keep, 'vinix-i915-audit-v-')!
	require_kbuild_path(state)!
	mut complete := false
	defer {
		// Explicit retained state owns failed diagnostics. Unrequested temporary
		// state is removed on infrastructure failure, after all jobs are joined.
		if !complete && configuration.keep == '' {
			hosttest.remove_work_dir(state) or { eprintln(err.msg()) }
		}
	}
	compiler_text := if configuration.compiler == '' {
		hosttest.env_default('CC', 'clang')
	} else {
		configuration.compiler
	}
	compiler := hosttest.shell_split(compiler_text)!
	require(compiler.len != 0, 'Compiler command is empty')!
	compiler_path := os.real_path(os.find_abs_path_of_executable(compiler[0]) or { return error('Missing compiler') })
	make := if configuration.make == '' {
		hosttest.env_default('MAKE', 'make')
	} else {
		configuration.make
	}
	make_path := os.real_path(os.find_abs_path_of_executable(make) or { return error('Missing GNU make') })
	archive := hosttest.resolve_path(if configuration.archive == '' {
		os.join_path(os.dir(linux), 'linux-' + pin['version']!.str() + '.tar.xz')
	} else {
		configuration.archive
	})!
	guarded := guarded_paths(root, linux, archive, compiler_path, make_path)!
	initial_state := hosttest.bounds_snapshot(guarded)!
	mut initial := map[string]string{}
	for path, record in initial_state { initial[path] = record.as_map()['sha256']!.str() }
	output := hosttest.resolve_path(if configuration.output == '' {
		os.join_path(state, 'i915-audit.json')
	} else {
		configuration.output
	})!
	require(output != linux && !output.starts_with(linux + '/') && output !in guarded,
		'Audit report must not overwrite imported or guarded inputs')!
	head := capture(['git', 'rev-parse', 'HEAD'], os.join_path(state, 'head-before.log'), root, configuration.timeout)!
	require(head.code == 0, 'Cannot record current HEAD')!
	dirty := capture(['git', 'status', '--short', '--', 'kernel/linuxkpi', 'tests/linuxkpi'], os.join_path(state, 'owned-status-before.log'), root, configuration.timeout)!
	require(dirty.code == 0, 'Cannot record compatibility worktree status')!
	hosttest.write_json(os.join_path(state, 'source-freeze.json'), map[string]json2.Any{
		'head':             json2.Any(head.stdout.trim_space())
		'input_sha256':     hosttest.string_map(initial)
		'worktree_status':  dirty.stdout
		'input_state':      initial_state
		'controller_scope': 'Maintained V controller directly uses original Kbuild object and module-metadata expansion, V ABI/bounds generators and compiler subprocesses. No Python transport or shared build objects are used.'
	})!
	kbuild := driver_sources(linux, state, make, archive, pin, configuration.timeout)!
	sources := kbuild.sources
	include := os.join_path(state, 'include')
	hosttest.audit_headers_from_source(include, linux)!
	flags := ['--target=x86_64-unknown-none', '-std=gnu11', '-ffreestanding', '-fwrapv', '-nostdinc',
		'-fsyntax-only', '-ferror-limit=5', '-Werror=implicit-function-declaration',
		'-Wno-unused-parameter', '-D__KERNEL__', '-include', 'linux/kconfig.h', '-include',
		os.join_path(linux, 'include/linux/compiler_types.h'), '-DCONFIG_X86=1', '-DCONFIG_X86_64=1',
		'-DCONFIG_ACPI=1', '-DCONFIG_DRM_I915=1', '-DCONFIG_DRM_FBDEV_EMULATION=1', '-isystem',
		os.join_path(root, 'kernel/freestnd-c-hdrs'), '-I', include, '-I',
		os.join_path(root, 'kernel/linuxkpi/include'), '-I', os.join_path(root, 'kernel/c'), '-I',
		os.join_path(linux, 'include'), '-I', os.join_path(linux, 'include/uapi'), '-I',
		os.join_path(linux, 'arch/x86/include'), '-I', os.join_path(linux, 'arch/x86/include/uapi'),
		'-I', os.join_path(linux, 'drivers/gpu/drm/i915')]
	bounds_path := os.join_path(include, 'generated/bounds.h')
	bounds := hosttest.generate_bounds(linux, archive, bounds_path, bounds_path + '.d',
		bounds_path + '.json', compiler_text, flags.filter(it != '-fsyntax-only'))!
	version := capture([...compiler, '--version'], os.join_path(state, 'compiler-version.log'), '', configuration.timeout)!
	require(version.code == 0, 'Compiler version query failed')!
	os.mkdir(os.join_path(state, 'units'))!
	mut results := []Unit{}
	mut index := 0
	for index < sources.len {
		mut pending := []thread !Unit{}
		for index < sources.len && pending.len < configuration.jobs {
			pending << spawn compile_source(linux, sources[index], [...compiler, ...flags,
				...kbuild.metadata[sources[index]]], os.join_path(state, 'units'), index, configuration.timeout)
			index++
		}
		mut failure := ''
		for job in pending {
			unit := job.wait() or {
				if failure == '' { failure = err.msg() }
				continue
			}
			results << unit
		}
		if failure != '' { return error(failure) }
		println('Audited ' + results.len.str() + '/' + sources.len.str() + ' original translation units')
	}
	mut blocker_counts := map[string]int{}
	mut compiled := 0
	for unit in results {
		if unit.passed {
			compiled++
			continue
		}
		mut first := 'compiler failed without an error diagnostic'
		for line in unit.diagnostics.split_into_lines() {
			if line.contains('error:') {
				first = line.all_after('error: ').trim_space()
				break
			}
		}
		blocker_counts[first]++
	}
	require(results.len == sources.len, 'Audit omitted a Kbuild source')!
	if guarded != guarded_paths(root, linux, archive, compiler_path, make_path)! || initial_state != hosttest.bounds_snapshot(guarded)! {
		os.write_file(os.join_path(state, 'INPUTS-CHANGED'), 'Audit result rejected: source/compiler input changed during the isolated replay\n')!
		return error('Source or compiler changed during audit; retained diagnostics are not a coherent result')
	}
	hosttest.verify_upstream(linux, pin)!
	final_head := capture(['git', 'rev-parse', 'HEAD'], os.join_path(state, 'head-after.log'), root, configuration.timeout)!
	require(final_head.code == 0, 'Cannot record final HEAD')!
	mut generated := os.walk_ext(include, '.h')
	generated << os.walk_ext(include, '.json')
	generated << os.join_path(state, 'source-list.Makefile')
	generated << os.join_path(state, 'module-metadata.Makefile')
	mut blockers := map[string]json2.Any{}
	for name, count in blocker_counts { blockers[name] = count }
	report := map[string]json2.Any{
		'linux_version':      pin['version']!
		'pci_id':             '8086:9a49'
		'identity_confirmed': false
		'stage':              'syntax-only; link/runtime readiness is not checked'
		'compiled':           compiled
		'total':              results.len
		'expected_exit':      if compiled == results.len { 0 } else { 1 }
		'head_before':        head.stdout.trim_space()
		'head_after':         final_head.stdout.trim_space()
		'bounds':             hosttest.decode_json(hosttest.bounds_metadata_json(bounds))!
		'compiler_version':   version.stdout
		'flags':              hosttest.strings(flags)
		'input_sha256':       hosttest.string_map(initial)
		'generated_sha256':   hosttest.string_map(hosttest.hashes(generated)!)
		'input_state':        initial_state
		'kbuild':             kbuild.provenance
		'blockers':           blockers
		'results':            results.map(unit_json(it))
		'python_executed':    false
	}
	hosttest.bounds_publish(output, (json2.encode(report, prettify: true, indent_string: '  ') + '\n').bytes())!
	complete = true
	mut ranked := blocker_counts.keys().map(Blocker{it, blocker_counts[it]})
	ranked.sort(a.count > b.count)
	println('i915 syntax readiness: ' + compiled.str() + '/' + results.len.str() + ' translation units pass')
	for blocker in ranked { println('  ' + blocker.count.str() + ': ' + blocker.name) }
	println('Full diagnostics: ' + output)
	println('Private generated inputs and logs: ' + state)
	return if compiled == results.len { 0 } else { 1 }
}

fn main() {
	args := hosttest.parse_arguments(os.args[1..], [
		hosttest.Option{'--source-dir', true, []string{}},
		hosttest.Option{'--archive', true, []string{}},
		hosttest.Option{'--cc', true, []string{}},
		hosttest.Option{'--make', true, []string{}},
		hosttest.Option{'--output', true, []string{}},
		hosttest.Option{'--keep-dir', true, []string{}},
		hosttest.Option{'--jobs', true, []string{}},
		hosttest.Option{'--timeout', true, []string{}},
	], 0,
		'Usage: audit_full.v [--source-dir DIRECTORY] [--archive FILE] [--cc COMMAND] [--make EXECUTABLE] [--jobs N] [--timeout SECONDS] [--keep-dir NEW-DIRECTORY] [--output FILE]',
		'Compile all original i915 Kbuild units with V generators and original module metadata. Default reports and logs stay in a private retained directory; --output explicitly publishes a report elsewhere. Exit 0 means syntax success only, 1 means driver errors, and 2 means infrastructure/changed-input failure. Compiler and make subprocesses default to a 180-second timeout; the checked V bounds generator keeps its existing process policy.') or {
		eprintln(err.msg())
		exit(2)
	}
	jobs := strconv.parse_int(args.options['--jobs'] or { '4' }, 10, 32) or {
		eprintln('--jobs must be a positive integer')
		exit(2)
	}
	timeout := strconv.parse_int(args.options['--timeout'] or { '180' }, 10, 32) or {
		eprintln('--timeout must be a positive integer')
		exit(2)
	}
	if jobs < 1 || timeout < 1 {
		eprintln('--jobs and --timeout must be positive integers')
		exit(2)
	}
	status := run(Configuration{
		source:   args.options['--source-dir']
		archive:  args.options['--archive']
		compiler: args.options['--cc']
		make:     args.options['--make']
		keep:     args.options['--keep-dir']
		output:   args.options['--output']
		jobs:     int(jobs)
		timeout:  int(timeout)
	}) or {
		eprintln(err.msg())
		exit(2)
	}
	exit(status)
}
