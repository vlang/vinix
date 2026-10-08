// SPDX-License-Identifier: GPL-2.0-or-later
// Pinned Kbuild/header compiler controls; no mapping or MMIO runtime is supplied.
module main

import os
import json2
import hosttest

fn require(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn command(argv []string, cwd string) !hosttest.Result {
	return hosttest.capture_in(argv, '', -1, os.environ(), cwd)
}

fn entries(path string, variable string) ![]string {
	text := os.read_file(path)!
	mut found := []string{}
	for line in text.split_into_lines() {
		if !line.starts_with(variable) { continue }
		remaining := line[variable.len..].trim_left(' \t\r\n')
		if !remaining.starts_with('+=') { continue }
		words := remaining[2..].fields()
		if words.len == 1 && words[0] !in found { found << words[0] }
	}
	return found
}

fn uncomment(text string) string {
	mut remaining := text
	mut result := ''
	for {
		first := remaining.index('/*') or { break }
		last := remaining[first + 2..].index('*/') or { break }
		result += remaining[..first]
		remaining = remaining[first + 2 + last + 2..]
	}
	return (result + remaining).trim_left(' \t\r\n\v\f')
}

fn derive_wrappers(work string, linux string, archive string, owned []string, pin map[string]json2.Any) !map[string]json2.Any {
	require(hosttest.file_digest(archive)! == pin['sha256']!.str(), 'Kbuild wrapper archive differs from the pinned source')!
	reference := os.join_path(work, 'kbuild-reference')
	scripts := ['scripts/Kbuild.include', 'scripts/Makefile.asm-generic']
	prefix := 'linux-' + pin['version']!.str() + '/'
	members := hosttest.archive_members(archive, scripts.map(prefix + it))!
	for script in scripts {
		bytes := members[prefix + script] or { return error('Missing original Kbuild script: ' + script) }
		target := os.join_path(reference, script)
		os.mkdir_all(os.dir(target))!
		os.write_file_array(target, bytes)!
	}
	// Only borrowed input directories are links. Kbuild's generated sibling is private.
	os.symlink(os.join_path(linux, 'include'), os.join_path(reference, 'include'))!
	arch_include := os.join_path(reference, 'arch/x86/include')
	os.mkdir_all(arch_include)!
	os.symlink(os.join_path(linux, 'arch/x86/include/asm'), os.join_path(arch_include, 'asm'))!
	argv := [hosttest.env_default('MAKE', 'make'), '-f', 'scripts/Makefile.asm-generic',
		'srctree=' + reference, 'obj=arch/x86/include/generated/asm', 'generic=include/asm-generic',
		'SRCARCH=x86']
	built := command(argv, reference)!
	os.write_file(os.join_path(reference, 'make.log'), built.stdout + built.stderr)!
	require(built.code == 0, 'Original Kbuild wrapper generation failed:\n' + built.stderr)!
	mut wrappers := map[string]json2.Any{}
	for path in owned {
		original := os.join_path(arch_include, 'generated/asm', os.file_name(path))
		generated := os.read_bytes(original)!
		require(uncomment(os.read_file(path)!).bytes() == generated, 'Overlay differs from original Kbuild wrapper: ' + os.file_name(path))!
		wrappers[os.file_name(path)] = map[string]json2.Any{
			'bytes':  json2.Any(generated.bytestr())
			'sha256': hosttest.file_digest(original)!
		}
	}
	mut script_hashes := map[string]string{}
	for script in scripts {
		script_hashes[script] = hosttest.file_digest(os.join_path(reference, script))!
	}
	return {
		'argv':           json2.Any(hosttest.strings(argv))
		'archive_sha256': pin['sha256']!
		'scripts_sha256': hosttest.string_map(script_hashes)
		'wrappers':       wrappers
	}
}

struct Probe {
	name     string
	body     string
	expected []string
}

struct Rejection {
	name  string
	body  string
	extra []string
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	here := hosttest.upstream_here()
	pin := hosttest.upstream_pin()!
	linux := hosttest.resolve_path(hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(hosttest.upstream_default(), 'linux-' + pin['version']!.str())))!
	hosttest.verify_upstream(linux, pin)!
	archive := os.join_path(os.dir(linux), 'linux-' + pin['version']!.str() + '.tar.xz')
	x86_kbuild := os.join_path(linux, 'arch/x86/include/asm/Kbuild')
	generic_kbuild := os.join_path(linux, 'include/asm-generic/Kbuild')
	require('early_ioremap.h' in entries(x86_kbuild, 'generic-y')!, 'Pinned x86 Kbuild no longer selects generic early_ioremap')!
	for name in ['kmap_size.h', 'mmiowb.h'] {
		require(name in entries(generic_kbuild, 'mandatory-y')!, 'Pinned generic Kbuild no longer requires ' + name)!
	}
	for name in ['early_ioremap.h', 'kmap_size.h', 'mmiowb.h'] {
		require(!os.exists(os.join_path(linux, 'arch/x86/include/asm', name)), 'Pinned x86 now owns the header: ' + name)!
		require(name !in entries(x86_kbuild, 'generated-y')!, 'Pinned x86 now generates the header itself: ' + name)!
	}
	owned := ['early_ioremap.h', 'kmap_size.h', 'mmiowb.h'].map(os.join_path(here, 'include/asm', it))
	originals := owned.map(os.join_path(linux, 'include/asm-generic', os.file_name(it)))
	fixmap := os.join_path(linux, 'arch/x86/include/asm/fixmap.h')
	compiler := hosttest.env_default('CC', 'clang')
	compiler_argv := hosttest.shell_split(compiler)!
	nm := hosttest.tool(hosttest.env_default('NM', 'llvm-nm'))
	work := hosttest.work_dir(keep, 'vinix-asm-generated-headers-')!
	defer { if keep == '' { os.rmdir_all(work) or { eprintln(err) } } }
	mut guarded := [@FILE, os.join_path(here, 'upstream.json'),
		os.join_path(here, 'include/generated/autoconf.h'), x86_kbuild, generic_kbuild, fixmap,
		...owned, ...originals]
	guarded << os.walk_ext(os.join_path(root, 'tests/linuxkpi/hosttest'), '.v')
	guarded << os.walk_ext(os.join_path(here, 'abi'), '.json')
	before := hosttest.hashes(guarded)!
	kbuild := derive_wrappers(work, linux, archive, owned, pin)!
	include := os.join_path(work, 'include')
	hosttest.audit_headers(include)!
	mut results := []json2.Any{}
	for standard in ['gnu99', 'gnu11'] {
		for profile in ['production', 'original-debug-and-generic-init'] {
			tag := standard + '-' + profile
			mut flags := ['--target=x86_64-unknown-none', '-std=' + standard, '-O2', '-ffreestanding',
				'-fwrapv', '-nostdinc', '-mno-red-zone', '-mcmodel=kernel', '-fno-PIC', '-Wall',
				'-Wextra', '-Werror', '-Wno-unused-parameter', '-Wno-unused-function', '-D__KERNEL__',
				'-include', 'linux/kconfig.h', '-include',
				os.join_path(linux, 'include/linux/compiler_types.h'), '-isystem',
				os.join_path(root, 'kernel/freestnd-c-hdrs')]
			if profile != 'production' {
				flags << ['-DCONFIG_KMAP_LOCAL=1', '-DCONFIG_DEBUG_KMAP_LOCAL=1',
					'-DCONFIG_DEBUG_KMAP_LOCAL_FORCE_MAP=1', '-DCONFIG_GENERIC_EARLY_IOREMAP=1']
			}
			for path in [include, os.join_path(here, 'include'), os.join_path(root, 'kernel/c'),
				os.join_path(linux, 'include'), os.join_path(linux, 'include/uapi'),
				os.join_path(linux, 'arch/x86/include'), os.join_path(linux, 'arch/x86/include/uapi')] {
				flags << ['-I', path]
			}
			bounds := os.join_path(include, 'generated/bounds.h')
			raw_provenance := hosttest.generate_bounds(linux, archive, bounds, bounds + '.d', bounds + '.json', compiler, flags)!
			provenance := hosttest.decode_json(hosttest.bounds_metadata_json(raw_provenance))!.as_map()
			enabled := 'CONFIG_GENERIC_EARLY_IOREMAP' in provenance['configuration']!.as_map()
			require(enabled == (profile != 'production'), 'Generic early-remap configuration differs from profile')!
			probes := [
				Probe{'declarations', '', []string{}},
				Probe{'mapping-references', mapping_references, ['early_ioremap', 'early_memremap',
					'early_memremap_ro', 'early_memremap_prot', 'early_iounmap', 'early_memunmap']},
				Probe{'initialization-references', initialization_references, if enabled {
					['early_ioremap_init', 'early_ioremap_setup', 'early_ioremap_reset',
						'copy_from_early_mem']
				} else {
					[]string{}
				}},
				Probe{'mmiowb-tracking-references', mmiowb_tracking_references, []string{}},
			]
			mut probe_results := []json2.Any{}
			for probe in probes {
				source := os.join_path(work, tag + '-' + probe.name + '.c')
				os.write_file(source, declarations + probe.body)!
				obj := source.all_before_last('.') + '.o'
				dependencies := source.all_before_last('.') + '.d'
				argv := [...compiler_argv, ...flags, '-MD', '-MF', dependencies, '-MQ', obj, '-c',
					source, '-o', obj]
				compiled := command(argv, '')!
				os.write_file(source.all_before_last('.') + '.log', compiled.stdout + compiled.stderr)!
				require(compiled.code == 0, 'Original asm header probe failed:\n' + compiled.stderr)!
				symbols := command([nm, obj], '')!
				imports := command([nm, '-u', obj], '')!
				require(symbols.code == 0 && imports.code == 0, 'Object symbol inspection failed')!
				mut imported := []string{}
				for line in imports.stdout.split_into_lines() {
					words := line.fields()
					if words.len != 0 && words.last() !in imported { imported << words.last() }
				}
				imported.sort()
				mut expected := probe.expected.clone()
				expected.sort()
				require(imported == expected && (probe.name != 'declarations' || symbols.stdout.trim_space() == ''), 'Probe supplied storage or changed runtime symbols:\n' + symbols.stdout)!
				inputs := hosttest.dependency_paths(os.read_file(dependencies)!, obj)!
				for path in [...owned, ...originals, fixmap] {
					require(hosttest.resolve_path(path)! in inputs, 'Compiler omitted actual header: ' + path)!
				}
				probe_results << json2.Any(map[string]json2.Any{
					'probe':              json2.Any(probe.name)
					'argv':               hosttest.strings(argv)
					'symbols':            symbols.stdout
					'unresolved_symbols': hosttest.strings(imported)
					'object_sha256':      hosttest.file_digest(obj)!
					'input_sha256':       hosttest.string_map(hosttest.hashes(inputs)!)
				})
			}
			mut rejected := []json2.Any{}
			for probe in [
				Rejection{'mmiowb-runtime-absent', mmiowb_runtime_reference, []string{}},
				Rejection{'mmiowb-enabled-unsupported', '#include <asm/mmiowb.h>\n' + mmiowb_tracking_references, ['-DCONFIG_MMIOWB=1']},
			] {
				source := os.join_path(work, tag + '-' + probe.name + '.c')
				os.write_file(source, probe.body)!
				obj := source.all_before_last('.') + '.o'
				argv := [...compiler_argv, ...flags, ...probe.extra, '-c', source, '-o', obj]
				compiled := command(argv, '')!
				os.write_file(source.all_before_last('.') + '.log', compiled.stdout + compiled.stderr)!
				require(compiled.code != 0 && !os.exists(obj), 'Unsupported MMIOWB service compiled: ' + probe.name)!
				require(compiled.stderr.contains("error: call to undeclared function 'mmiowb'"), 'Original missing MMIOWB barrier was hidden:\n' + compiled.stderr)!
				rejected << json2.Any(map[string]json2.Any{
					'probe':       json2.Any(probe.name)
					'argv':        hosttest.strings(argv)
					'exit':        compiled.code
					'diagnostics': compiled.stderr
				})
			}
			results << json2.Any(map[string]json2.Any{
				'standard':        json2.Any(standard)
				'profile':         profile
				'bounds':          provenance
				'probes':          probe_results
				'rejected_probes': rejected
			})
			println(tag + ': original ABI/enums and disabled MMIOWB tracking passed; unsupported mapping/barrier services remain unavailable')
		}
	}
	require(before == hosttest.hashes(guarded)!, 'Production/controller inputs changed during isolated checks')!
	hosttest.write_json(os.join_path(work, 'result.json'), map[string]json2.Any{
		'scope':            json2.Any('Compiler-only generated-header forwarding. No early mapping, MMIO cache policy, native fixmap/page ownership or GPU runtime is supplied. Production initialization and MMIOWB tracking are original configuration-disabled no-ops; the additional profile checks declarations only.')
		'linux_version':    pin['version']!
		'kbuild_selection': hosttest.string_map({
			'early_ioremap.h': 'x86 generic-y'
			'kmap_size.h':     'mandatory-y with no x86 implementation'
			'mmiowb.h':        'mandatory-y with no x86 implementation'
		})
		'original_kbuild':  kbuild
		'source_sha256':    hosttest.string_map(hosttest.hashes([x86_kbuild, generic_kbuild, fixmap,
			...owned, ...originals, @FILE])!)
		'results':          results
	})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..], 'Usage: asm_generated_headers.v [--keep-dir DIRECTORY]', 'Compile pinned generated asm headers without inventing mapping services.') or {
		eprintln(err.msg())
		exit(2)
	}
	run_profile(keep) or {
		eprintln(err.msg())
		exit(1)
	}
}

const declarations = '
#include <linux/threads.h>
#include <asm/early_ioremap.h>
#include <asm/kmap_size.h>
#include <asm/fixmap.h>
#include <asm/mmiowb.h>
/* Repeated use relies on the original headers\' include guards. */
#include <asm/kmap_size.h>
#include <asm/early_ioremap.h>
#include <asm/mmiowb.h>

#if defined(CONFIG_MMIOWB) || defined(CONFIG_ARCH_HAS_MMIOWB)
#error production x86 has no MMIO write-barrier tracking configuration
#endif
#ifdef mmiowb
#error no replacement mmiowb runtime macro is provided
#endif

_Static_assert(CONFIG_MMU == 1 && CONFIG_X86_5LEVEL == 1 &&
               CONFIG_PGTABLE_LEVELS == 5, "production MMU/type profile");
#define FUNCTION_ABI(name, type) \\
    _Static_assert(__builtin_types_compatible_p(__typeof__(&(name)), type), \\
                   "original " #name " ABI")
FUNCTION_ABI(early_ioremap, void *(*)(resource_size_t, unsigned long));
FUNCTION_ABI(early_memremap, void *(*)(resource_size_t, unsigned long));
FUNCTION_ABI(early_memremap_ro, void *(*)(resource_size_t, unsigned long));
FUNCTION_ABI(early_memremap_prot,
             void *(*)(resource_size_t, unsigned long, unsigned long));
FUNCTION_ABI(early_iounmap, void (*)(void *, unsigned long));
FUNCTION_ABI(early_memunmap, void (*)(void *, unsigned long));
FUNCTION_ABI(early_ioremap_init, void (*)(void));
FUNCTION_ABI(early_ioremap_setup, void (*)(void));
FUNCTION_ABI(early_ioremap_reset, void (*)(void));
#ifdef CONFIG_GENERIC_EARLY_IOREMAP
FUNCTION_ABI(copy_from_early_mem, void (*)(void *, phys_addr_t, unsigned long));
#endif

/* These expectations check the original configured header and enum, not a
 * substitute kmap implementation. The debug profile is compiler-only. */
#ifdef CONFIG_DEBUG_KMAP_LOCAL
_Static_assert(KM_MAX_IDX == 33, "original debug guard slots");
#else
_Static_assert(KM_MAX_IDX == 16, "original ordinary slots");
#endif
#ifdef CONFIG_KMAP_LOCAL
_Static_assert(FIX_KMAP_END - FIX_KMAP_BEGIN + 1 == KM_MAX_IDX * NR_CPUS,
               "original per-CPU fixmap enum");
#endif
#ifdef CONFIG_DEBUG_KMAP_LOCAL_FORCE_MAP
_Static_assert(FIXMAP_PMD_NUM == KM_MAX_IDX * ((CONFIG_NR_CPUS + 511) / 512) + 2,
               "original forced-map PMD count");
#else
_Static_assert(FIXMAP_PMD_NUM == 2, "original ordinary PMD count");
#endif
_Static_assert(FIX_BTMAP_BEGIN - FIX_BTMAP_END + 1 == TOTAL_FIX_BTMAPS,
               "original early mapping enum span");
_Static_assert((FIX_BTMAP_BEGIN / PTRS_PER_PTE) == (FIX_BTMAP_END / PTRS_PER_PTE),
               "original boot slots fit one PTE table");
'

const mapping_references = '
void reference_mapping_services(resource_size_t address, unsigned long size,
                                unsigned long protection) {
    void *io = early_ioremap(address, size);
    void *rw = early_memremap(address, size);
    void *ro = early_memremap_ro(address, size);
    void *protected = early_memremap_prot(address, size, protection);
    early_iounmap(io, size);
    early_memunmap(rw, size);
    early_memunmap(ro, size);
    early_memunmap(protected, size);
}
'

const initialization_references = '
void reference_original_initializers(void) {
    early_ioremap_init();
    early_ioremap_setup();
    early_ioremap_reset();
}
#ifdef CONFIG_GENERIC_EARLY_IOREMAP
void reference_early_copy(void *destination, phys_addr_t address,
                          unsigned long size) {
    copy_from_early_mem(destination, address, size);
}
#endif
'

const mmiowb_tracking_references = '
void reference_original_tracking(void) {
    mmiowb_set_pending();
    mmiowb_spin_lock();
    mmiowb_spin_unlock();
}
'

const mmiowb_runtime_reference = '
#include <asm/mmiowb.h>
void reference_missing_runtime(void) { mmiowb(); }
'
