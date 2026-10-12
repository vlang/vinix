// SPDX-License-Identifier: GPL-2.0-or-later
module kpihost

import cachecli
import gamehost
import hosttest
import json2
import os
import sourcecommand
import strconv

pub struct AuditOptions {
pub:
	source           string
	archive          string
	compiler         string = 'clang'
	make             string = 'make'
	jobs             int    = 4
	output           string
	schema_directory string
}

pub struct AuditHooks {
pub:
	sources fn (string, string, voidptr) ![]string = unsafe { nil }
	observe fn ([]string, voidptr) !               = unsafe { nil }
	context voidptr
}

fn audit_source_list(tools Tools, source string, make string) ![]string {
	work := sourcecommand.temporary('vinix-i915-kbuild-')!
	defer { gamehost.remove(work) or {} }
	driver := source + '/drivers/gpu/drm/i915'
	script := work + '/Makefile'
	os.write_file(script, ['src := ' + driver, 'srctree := ' + source, 'CONFIG_X86 := y',
		'CONFIG_ACPI := y', 'CONFIG_DRM_I915 := y', 'CONFIG_DRM_FBDEV_EMULATION := y',
		'include ' + driver + '/Makefile', '.PHONY: vinix-source-list', 'vinix-source-list:',
		"\t@printf '%s\\n' $(i915-y)", ''].join('\n'))!
	result := tools.command([make, '-s', '-f', script, 'vinix-source-list'], os.environ())!
	if result.status != 0 { return error('Kbuild expansion failed: ' + result.stderr) }
	mut sources := []string{}
	for object in result.stdout.fields() {
		if object.ends_with('.o') {
			path := driver + '/' + object[..object.len - 2] + '.c'
			if path !in sources { sources << path }
		}
	}
	sources.sort()
	return sources
}

fn audit_flags(tools Tools, source string, generated string) []string {
	return ['--target=x86_64-unknown-none', '-std=gnu11', '-ffreestanding', '-fwrapv', '-nostdinc',
		'-fsyntax-only', '-ferror-limit=5', '-Werror=implicit-function-declaration',
		'-Wno-unused-parameter', '-D__KERNEL__', '-include', 'linux/kconfig.h', '-include',
		source + '/include/linux/compiler_types.h', '-DCONFIG_X86=1', '-DCONFIG_X86_64=1',
		'-DCONFIG_ACPI=1', '-DCONFIG_DRM_I915=1', '-DCONFIG_DRM_FBDEV_EMULATION=1', '-isystem',
		tools.root + '/kernel/freestnd-c-hdrs', '-I', generated, '-I',
		tools.root + '/kernel/linuxkpi/include', '-I', tools.root + '/kernel/c', '-I',
		source + '/include', '-I', source + '/include/uapi', '-I', source + '/arch/x86/include',
		'-I', source + '/arch/x86/include/uapi', '-I', source + '/drivers/gpu/drm/i915']
}

struct AuditUnit {
	source      string
	passed      bool
	diagnostics string
}

fn audit_compile(tools Tools, compiler []string, flags []string, root string, source string) !AuditUnit {
	result := tools.command([...compiler, ...flags, source], os.environ())!
	return AuditUnit{
		source:      if source.starts_with(root + '/') {
			source[root.len + 1..]
		} else {
			source
		}
		passed:      result.status == 0
		diagnostics: gamehost.decode_utf8(result.stderr.bytes())
	}
}

pub fn execute_audit(tools Tools, options AuditOptions, hooks AuditHooks) !int {
	if options.jobs < 1 { return error_with_code('--jobs must be positive', 2) }
	pin := hosttest.upstream_pin()!
	root := hosttest.module_resolve(options.source)!
	hosttest.verify_upstream(root, pin)!
	sources := if hooks.sources != unsafe { nil } {
		hooks.sources(root, options.make, hooks.context)!
	} else {
		audit_source_list(tools, root, options.make)!
	}
	if sources.len == 0 { return error('upstream Kbuild returned no i915 sources') }
	private := sourcecommand.temporary('vinix-i915-audit-')!
	defer { gamehost.remove(private) or {} }
	generated := private + '/include'
	here := if options.schema_directory == '' {
		tools.root + '/kernel/linuxkpi'
	} else {
		options.schema_directory
	}
	for adapter in [['spinlock', 'spinlock_adapters'], ['atomic-exchange', 'atomic_exchange'],
		['overflow', 'integer_policy']] {
		schema := adapter[0]
		header := adapter[1]
		path := here + '/abi/' + schema + '.json'
		if schema == 'overflow' && !os.is_file(path) { continue }
		if hooks.observe != unsafe { nil } {
			hooks.observe([tools.root + '/kernel/linuxkpi/generate-abi', path,
				generated + '/vinix/' + header + '.h'], hooks.context)!
		}
		hosttest.generate_abi(path, tools.root + '/kernel/linuxkpi', generated + '/vinix/' + header + '.h')!
	}
	flags := audit_flags(tools, root, generated)
	bounds_path := generated + '/generated/bounds.h'
	compiler := hosttest.shell_split(options.compiler)!
	if compiler.len == 0 { return error('compiler command is empty') }
	if hooks.observe != unsafe { nil } {
		hooks.observe([...compiler, ...flags.filter(it != '-fsyntax-only'), '-S'], hooks.context)!
	}
	bounds := hosttest.generate_bounds(root, options.archive, bounds_path, bounds_path + '.d', bounds_path + '.json', options.compiler, flags.filter(it != '-fsyntax-only'))!
	mut results := []AuditUnit{}
	mut offset := 0
	for offset < sources.len {
		cachecli.checkpoint()!
		mut pending := []thread !AuditUnit{}
		mut failure := ''
		for offset < sources.len && pending.len < options.jobs {
			if hooks.observe != unsafe { nil } {
				hooks.observe([...compiler, ...flags, sources[offset]], hooks.context) or {
					failure = err.msg()
					break
				}
			}
			pending << spawn audit_compile(tools, compiler, flags, root, sources[offset])
			offset++
		}
		for task in pending {
			unit := task.wait() or {
				if failure == '' { failure = err.msg() }
				continue
			}
			results << unit
		}
		if failure != '' { return error(failure) }
	}
	mut blockers := map[string]int{}
	mut compiled := 0
	for result in results {
		if result.passed {
			compiled++
			continue
		}
		mut first := 'compiler failed without an error diagnostic'
		for line in result.diagnostics.split_into_lines() {
			if line.contains('error:') {
				first = line.all_after('error: ').trim_space()
				break
			}
		}
		blockers[first]++
	}
	mut blocker_values := map[string]json2.Any{}
	for name, count in blockers { blocker_values[name] = json2.Any(count) }
	report := json2.Any({
		'linux_version': pin['version']!
		'pci_id':        json2.Any('8086:9a49')
		'stage':         json2.Any('syntax-only; link/runtime readiness is not checked')
		'bounds':        hosttest.decode_json(hosttest.bounds_metadata_json(bounds))!
		'compiled':      json2.Any(compiled)
		'total':         json2.Any(results.len)
		'blockers':      json2.Any(blocker_values)
		'results':       json2.Any(results.map(json2.Any({
			'source':      json2.Any(it.source)
			'passed':      json2.Any(it.passed)
			'diagnostics': json2.Any(it.diagnostics)
		})))
	})
	gamehost.mkdir(gamehost.parent(options.output))!
	cachecli.publish(options.output, json2.encode(report, prettify: true) + '\n')!
	println('i915 syntax readiness: ${compiled}/${results.len} translation units pass')
	mut ranked := blockers.keys().map(AuditBlocker{it, blockers[it]})
	ranked.sort(a.count > b.count)
	for item in ranked { println('  ' + item.count.str() + ': ' + item.name) }
	println('Full diagnostics: ' + options.output)
	return if compiled == results.len { 0 } else { 1 }
}

struct AuditBlocker {
	name  string
	count int
}

pub fn audit_cli(tools Tools, argv []string) !int {
	args := cachecli.arguments(argv, ['--source-dir', '--cc', '--archive', '--make', '--jobs',
		'--output'], [], [], 0, 0, 'Compile the original upstream Kbuild i915 units against native Vinix headers.\nUsage: audit [--source-dir DIR --cc COMPILER --archive FILE --make MAKE --jobs 4 --output FILE]') or { return error_with_code(err.msg(), 2) }
	pin := hosttest.upstream_pin()!
	source := hosttest.module_resolve(args.value('--source-dir', tools.root + '/third_party/linux-i915/linux-' + pin['version']!.str()))!
	jobs := strconv.atoi(args.value('--jobs', '4')) or { return error_with_code(err.msg(), 2) }
	if jobs <= 0 { return error_with_code('--jobs must be positive', 2) }
	result := execute_audit(tools, AuditOptions{ source: source, compiler: args.value('--cc', 'clang'), archive: args.value('--archive', gamehost.parent(source) + '/linux-' + pin['version']!.str() + '.tar.xz'), make: args.value('--make', 'make'), jobs: jobs, output: hosttest.module_resolve(args.value('--output', tools.root + '/build/linuxkpi/i915-audit.json'))! }, AuditHooks{}) or {
		eprintln('i915 audit failed: ' + err.msg())
		return 2
	}
	return result
}
