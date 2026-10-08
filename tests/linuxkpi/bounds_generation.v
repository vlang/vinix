// SPDX-License-Identifier: GPL-2.0-or-later
// Genuine pinned compiler generation with independent publication controls.
module main

import os
import json2
import hosttest

struct BoundsChecks {
	root      string
	work      string
	linux     string
	archive   string
	compiler  string
	generator string
	profiles  map[string]string
mut:
	results        []json2.Any
	stamp_commands []json2.Any
}

fn require(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn command(argv []string) !hosttest.Result {
	return hosttest.command(argv, '', -1, os.environ())
}

fn compile_host(source string, output string) ! {
	v := command(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v',
		hosttest.root()])!.stdout
	arch := $if arm64 { 'arm64' } $else $if amd64 { 'amd64' } $else {
		return error('Unsupported host architecture')
	}
	mut argv := [v, '-arch', arch, '-cc', 'cc']
	$if macos {
		// Make the fixture follow the actual controller ABI under Rosetta.
		target := if arch == 'amd64' { 'x86_64' } else { 'arm64' }
		argv << ['-cflags', '-target ' + target + '-apple-darwin', '-ldflags',
			'-target ' + target + '-apple-darwin']
	}
	argv << ['-o', output, source]
	mut env := os.environ()
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	hosttest.command(argv, '', -1, env)!
}

// Match the original physical-line replacements, preserving all other bytes.
fn replace_config(text string, name string, value string, remove bool) string {
	mut result := ''
	mut offset := 0
	for offset < text.len {
		end := offset + (text[offset..].index('\n') or { text.len - offset })
		line := text[offset..end]
		newline := if end < text.len { '\n' } else { '' }
		if line.starts_with('#define ' + name) && (!remove || newline != '') {
			if !remove { result += '#define ' + name + ' ' + value + newline }
		} else {
			result += line + newline
		}
		offset = end + 1
	}
	return result
}

fn (check &BoundsChecks) flags(profile string, standard string) []string {
	return ['--target=x86_64-unknown-none', '-std=' + standard, '-O2', '-ffreestanding', '-fwrapv',
		'-nostdinc', '-mno-red-zone', '-mcmodel=kernel', '-fno-PIC',
		'-Werror=implicit-function-declaration', '-Wno-unused-parameter', '-D__KERNEL__', '-include',
		'linux/kconfig.h', '-include', os.join_path(check.linux, 'include/linux/compiler_types.h'),
		'-isystem', os.join_path(check.root, 'kernel/freestnd-c-hdrs'), '-I', check.profiles[profile],
		'-I', os.join_path(check.root, 'kernel/linuxkpi/include'), '-I',
		os.join_path(check.root, 'kernel/c'), '-I', os.join_path(check.linux, 'include'), '-I',
		os.join_path(check.linux, 'include/uapi'), '-I', os.join_path(check.linux, 'arch/x86/include'),
		'-I', os.join_path(check.linux, 'arch/x86/include/uapi'), '-MMD', '-MP']
}

fn (mut check BoundsChecks) invoke(name string, output string, flags []string,
	source string, archive string, compiler string) !hosttest.Result {
	argv := [check.generator, '--source-dir', source, '--archive', archive, '--output', output,
		'--cc', compiler, '--', ...flags]
	completed := hosttest.capture(argv, '', -1, os.environ())!
	os.write_file(os.join_path(check.work, name + '.log'), completed.stdout + completed.stderr)!
	check.results << json2.Any(map[string]json2.Any{
		'name':          json2.Any(name)
		'command':       hosttest.strings(argv)
		'returncode':    completed.code
		'warnings':      completed.stderr.count('warning:')
		'errors':        hosttest.strings(completed.stderr.split_into_lines().filter(it.contains('error:')))
		'stderr_sha256': hosttest.text_sha(completed.stderr)
	})
	return completed
}

fn temporary_clean(directory string, name string) ! {
	require(!os.ls(directory)!.any(it.starts_with('.bounds-')), name + ' temporary cleanup')!
}

fn (mut check BoundsChecks) rejected(name string, output string, flags []string,
	expected string, bundle map[string][]u8, source string, archive string, compiler string) ! {
	completed := check.invoke(name, output, flags, source, archive, compiler)!
	require(completed.code != 0, 'bad generation unexpectedly passed: ' + name)!
	require(completed.stderr.contains(expected), 'missing rejection: ' + name + '\n' + completed.stderr)!
	for path, bytes in bundle {
		require(os.read_bytes(path)! == bytes, 'failed generation modified the previous bundle')!
	}
	temporary_clean(os.dir(output), 'failed ' + name)!
}

fn metadata(output string) !map[string]json2.Any {
	return hosttest.decode_json(os.read_file(output + '.json')!)!.as_map()
}

fn (mut check BoundsChecks) successful(reference string, schema_exists bool, pin map[string]json2.Any) !map[string]string {
	mut outputs := map[string]string{}
	compiler := hosttest.shell_split(check.compiler)!
	for profile in ['native', 'cpu64'] {
		output := os.join_path(check.work, profile + ' quoted # $ output', 'generated/bounds # $.h')
		outputs[profile] = output
		mut timestamp := json2.Any(json2.Null{})
		for standard in ['gnu99', 'gnu11'] {
			selected := check.flags(profile, standard)
			completed := check.invoke(profile + '-' + standard, output, selected, check.linux, check.archive, check.compiler)!
			require(completed.code == 0, completed.stderr)!
			temporary_clean(os.dir(output), 'successful')!
			provenance := metadata(output)!
			require(provenance['header_sha256']!.str() == hosttest.file_digest(output)!, 'header publication marker')!
			require(provenance['dependency_sha256']!.str() == hosttest.file_digest(output + '.d')!, 'dependency publication marker')!
			require(provenance['archive_sha256']! == pin['sha256']!, 'exact pinned archive')!
			require(provenance['configuration']!.as_map()['CONFIG_MMU']!.str() == '1', 'actual MMU config')!
			require(!provenance['flags']!.as_array().any(it.str() in ['-MD', '-MMD', '-MP']), 'caller dependency actions are replaced')!
			dependency := os.read_file(output + '.d')!
			require(!dependency.contains('.bounds-build-'), 'no cleaned source dependency')!
			for path in [check.archive, os.join_path(check.root, 'tests/linuxkpi/generate_bounds.v'),
				os.join_path(check.root, 'kernel/linuxkpi/upstream.json'),
				os.join_path(check.root, 'tests/linuxkpi/hosttest/upstream.v'),
				os.join_path(check.profiles[profile], 'generated/autoconf.h'),
				os.join_path(check.root, 'kernel/freestnd-c-hdrs/stdint.h')] {
				require(dependency.contains(hosttest.make_escape(path)), 'missing stable/all-header dependency: ' + path)!
			}
			mut hashed := [
				os.join_path(check.profiles[profile], 'generated/autoconf.h'),
				os.join_path(check.profiles[profile], 'vinix/atomic_exchange.h'),
				os.join_path(check.root, 'kernel/linuxkpi/include/linux/spinlock_types_raw.h'),
				check.archive,
				os.join_path(check.root, 'tests/linuxkpi/generate_bounds.v'),
				os.join_path(check.root, 'tests/linuxkpi/hosttest/upstream.v'),
				os.join_path(check.root, 'kernel/linuxkpi/upstream.json'),
				provenance['compiler_path']!.str(),
			]
			if schema_exists {
				hashed << os.join_path(check.profiles[profile], 'vinix/integer_policy.h')
			}
			inputs := provenance['input_sha256']!.as_map()
			for path in hashed {
				require(inputs[hosttest.resolve_path(path)!]!.str() == hosttest.file_digest(path)!, 'actual config/ABI input hash: ' + path)!
			}
			require(dependency.starts_with(hosttest.make_escape(output) + ':'), 'quoted dependency target')!
			state := hosttest.bounds_file_state(output)!
			current := state['st_mtime_ns']!
			if timestamp !is json2.Null {
				require(current == timestamp, 'unchanged header timestamp')!
			}
			timestamp = current
			passed := hosttest.capture([...compiler, ...selected.filter(it !in ['-MMD', '-MP']),
				'-DGENERATED_HEADER="' + output + '"', '-fsyntax-only', reference], '', -1, os.environ())!
			os.write_file(os.join_path(check.work, profile + '-' + standard + '-reference.log'), passed.stdout + passed.stderr)!
			require(passed.code == 0, passed.stderr)!
			mut result := check.results.last().as_map()
			result['reference_enums_and_sizes_passed'] = true
			result['header_sha256'] = hosttest.file_digest(output)!
			result['provenance_sha256'] = hosttest.file_digest(output + '.json')!
			check.results[check.results.len - 1] = result
		}
	}
	mut first := metadata(outputs['native'])!['bounds']!.as_map()
	mut second := metadata(outputs['cpu64'])!['bounds']!.as_map()
	require(first['NR_CPUS_BITS']! != second['NR_CPUS_BITS']!, 'configuration affects derived bounds')!
	first.delete('NR_CPUS_BITS')
	second.delete('NR_CPUS_BITS')
	require(first == second, 'unrelated bounds survive a CPU-bound change')!
	return outputs
}

fn hardlink_tree(source string, destination string) ! {
	os.mkdir(destination)!
	for path in os.walk_ext(source, '', hidden: true) {
		if !os.is_file(path) { continue }
		output := os.join_path(destination, os.path_rel(source, path)!)
		os.mkdir_all(os.dir(output))!
		os.link(path, output)!
	}
}

fn (mut check BoundsChecks) failures(probe string) ! {
	output := os.join_path(check.work, 'failure outputs/generated/bounds.h')
	os.mkdir_all(os.dir(output))!
	bundle := {
		output:           'old header\n'.bytes()
		output + '.d':    'old dependencies\n'.bytes()
		output + '.json': 'old provenance\n'.bytes()
	}
	for path, bytes in bundle { os.write_file_array(path, bytes)! }
	check.rejected('missing-mmu', output, check.flags('nommu', 'gnu99'), 'CONFIG_MMU must be 1', bundle, check.linux, check.archive, check.compiler)!
	check.rejected('zero-mmu', output, check.flags('mmu_zero', 'gnu11'), 'CONFIG_MMU must be 1', bundle, check.linux, check.archive, check.compiler)!
	mut wrong := check.flags('native', 'gnu99')
	wrong[0] = '--target=aarch64-unknown-none'
	wrong = wrong.filter(it !in ['-mno-red-zone', '-mcmodel=kernel', '-fno-PIC'])
	check.rejected('wrong-target', output, wrong, '__x86_64__ must be 1', bundle, check.linux, check.archive, check.compiler)!
	check.rejected('compiler-failure', output, [...check.flags('native', 'gnu99'), '-D__NR_PAGEFLAGS=('], 'compiler failed with exit status', bundle, check.linux, check.archive, check.compiler)!
	check.rejected('caller-output', output, [...check.flags('native', 'gnu99'), '-o',
		os.join_path(check.work, 'forbidden')], 'compiler output/action', bundle, check.linux, check.archive, check.compiler)!
	changed_archive := os.join_path(check.work, 'changed.tar.xz')
	os.write_file(changed_archive, 'changed archive bytes\n')!
	check.rejected('changed-archive', output, check.flags('native', 'gnu99'), 'archive SHA256 differs', bundle, check.linux, changed_archive, check.compiler)!
	changed_source := os.join_path(check.work, 'changed-source')
	hardlink_tree(check.linux, changed_source)!
	manifest := hosttest.decode_json(os.read_file(os.join_path(changed_source, '.vinix-upstream.json'))!)!.as_map()
	changed_name := manifest['files']!.as_map().keys()[0]
	altered := os.join_path(changed_source, changed_name)
	original_sha := hosttest.file_digest(os.join_path(check.linux, changed_name))!
	replacement := altered + '.replacement'
	mut altered_bytes := os.read_bytes(altered)!
	altered_bytes << '\n/* altered test copy */\n'.bytes()
	os.write_file_array(replacement, altered_bytes)!
	os.mv(replacement, altered)!
	check.rejected('changed-source', output, check.flags('native', 'gnu99'), 'modified upstream source', bundle, changed_source, check.archive, check.compiler)!
	require(hosttest.file_digest(os.join_path(check.linux, changed_name))! == original_sha, 'original source remained unchanged')!
	header := os.join_path(check.profiles['native'], 'generated/autoconf.h')
	header_hash := hosttest.file_digest(header)!
	protected := check.invoke('protected-header', header, check.flags('native', 'gnu99'), check.linux, check.archive, check.compiler)!
	require(protected.code != 0 && protected.stderr.contains('overlap discovered compiler inputs'), 'discovered input header must be protected')!
	require(hosttest.file_digest(header)! == header_hash, 'protected config remained unchanged')!
	require(!os.exists(header + '.d') && !os.exists(header + '.json'), 'no overlapping header sidecars')!
	temporary_clean(os.dir(header), 'overlap')!
	compiler_argv, compiler_path := hosttest.bounds_compiler(check.compiler)!
	protected_compiler := os.join_path(check.work, 'protected-compiler')
	os.cp(compiler_path, protected_compiler)!
	os.chmod(protected_compiler, 0o755)!
	compiler_hash := hosttest.file_digest(protected_compiler)!
	protected_binary := check.invoke('protected-compiler', protected_compiler, check.flags('native', 'gnu99'), check.linux, check.archive, protected_compiler)!
	require(protected_binary.code != 0 && protected_binary.stderr.contains('overlap each other or protected inputs'), 'compiler executable must be protected')!
	require(hosttest.file_digest(protected_compiler)! == compiler_hash, 'protected compiler remained unchanged')!
	marker := os.join_path(check.work, 'changed-profile-once')
	configuration := os.join_path(check.work, 'changing-profile.json')
	hosttest.write_json(configuration, map[string]json2.Any{
		'command': json2.Any(hosttest.strings(compiler_argv))
		'header':  header
		'marker':  marker
	})!
	saved := os.read_bytes(header)!
	mut restored := false
	defer { if !restored { os.write_file_array(header, saved) or { eprintln(err) } } }
	check.rejected('changing-profile-after-discovery', output, check.flags('native', 'gnu99'), 'preprocessed configuration changed during bounds generation', bundle, check.linux, check.archive,
		hosttest.shell_join([probe, 'profile', configuration]))!
	require(os.exists(marker), 'real after-discovery edit was exercised')!
	os.write_file_array(header, saved)!
	restored = true
	changing_compiler := os.join_path(check.work, 'changing-compiler')
	os.cp(probe, changing_compiler)!
	os.chmod(changing_compiler, 0o755)!
	compiler_marker := os.join_path(check.work, 'changed-compiler-once')
	compiler_configuration := os.join_path(check.work, 'changing-compiler.json')
	hosttest.write_json(compiler_configuration, map[string]json2.Any{
		'command': json2.Any(hosttest.strings(compiler_argv))
		'marker':  compiler_marker
	})!
	check.rejected('changing-compiler-after-discovery', output, check.flags('native', 'gnu99'), 'compiler inputs changed during bounds generation', bundle, check.linux, check.archive,
		hosttest.shell_join([changing_compiler, 'compiler', compiler_configuration]))!
	require(os.exists(compiler_marker), 'real compiler-input change was exercised')!
}

fn (mut check BoundsChecks) stamp_run(selected []string, compiler string, accepted bool, destination string) !hosttest.Result {
	argv := [check.generator, '--command-stamp', destination, '--source-dir',
		os.join_path(check.work, 'no-source'), '--archive', os.join_path(check.work, 'no-archive'),
		'--cc', compiler, '--', ...selected]
	completed := hosttest.capture(argv, '', -1, os.environ())!
	check.stamp_commands << json2.Any(map[string]json2.Any{
		'command':    json2.Any(hosttest.strings(argv))
		'returncode': completed.code
		'stderr':     completed.stderr
	})
	require((completed.code == 0) == accepted, completed.stderr)!
	return completed
}

fn (mut check BoundsChecks) stamps() ! {
	stamp := os.join_path(check.work, 'commands # $ space/compiler.json')
	selected := check.flags('native', 'gnu99')
	check.stamp_run(selected, check.compiler, true, stamp)!
	first := os.read_bytes(stamp)!
	first_state := hosttest.bounds_file_state(stamp)!
	stamped := hosttest.decode_json(first.bytestr())!.as_map()
	compiler_argv, executable := hosttest.bounds_compiler(check.compiler)!
	require(stamped['compiler']!.as_array()[0].str() == executable, 'stamp canonical compiler executable')!
	require(stamped['compiler_sha256']!.str() == hosttest.file_digest(executable)!, 'stamp compiler digest')!
	require(stamped['flags']!.as_array() == hosttest.strings(hosttest.bounds_native_flags(selected)!), 'stamp native flags')!
	check.stamp_run(selected, check.compiler, true, stamp)!
	second_state := hosttest.bounds_file_state(stamp)!
	require(os.read_bytes(stamp)! == first && second_state['st_mtime_ns']! == first_state['st_mtime_ns']!, 'unchanged command stamp timestamp')!
	check.stamp_run([...selected, '-DCHANGED_NATIVE_FLAG=1'], check.compiler, true, stamp)!
	changed := os.read_bytes(stamp)!
	require(changed != first, 'changed flags update command stamp')!
	check.stamp_run(selected, hosttest.shell_join([...compiler_argv, '-Qunused-arguments']), true, stamp)!
	before := os.read_bytes(stamp)!
	require(before != first && before != changed, 'changed compiler argv updates command stamp')!
	check.stamp_run([...selected, '-o', 'forbidden'], check.compiler, false, stamp)!
	require(os.read_bytes(stamp)! == before, 'invalid stamp flags preserve old stamp')!
	temporary_clean(os.dir(stamp), 'stamp')!
	source_destination := os.join_path(check.work, 'no-source/generated/forbidden-stamp.json')
	refused_source := check.stamp_run(selected, check.compiler, false, source_destination)!
	require(refused_source.stderr.contains('outside the verified import') && !os.exists(source_destination), 'stamp destination inside import is rejected without opening sources')!
	archive_destination := os.join_path(check.work, 'no-archive')
	refused_archive := check.stamp_run(selected, check.compiler, false, archive_destination)!
	require(refused_archive.stderr.contains('overlaps protected inputs') && !os.exists(archive_destination), 'stamp destination on archive is rejected without opening archive')!
}

fn run_profile(keep string) ! {
	root := hosttest.root()
	pin := hosttest.upstream_pin()!
	version := pin['version']!.str()
	linux := hosttest.resolve_path(hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(hosttest.upstream_default(), 'linux-' + version)))!
	archive := os.join_path(os.dir(linux), 'linux-' + version + '.tar.xz')
	compiler := hosttest.env_default('CC', 'clang')
	work := hosttest.work_dir(keep, 'vinix-bounds-generation-')!
	defer { if keep == '' { os.rmdir_all(work) or { eprintln(err) } } }
	mut guarded := [@FILE, os.join_path(root, 'tests/linuxkpi/bounds_compiler_probe.v'),
		os.join_path(root, 'tests/linuxkpi/generate_bounds.v'),
		os.join_path(root, 'tests/linuxkpi/generate_abi.v'),
		os.join_path(root, 'kernel/linuxkpi/upstream.json'),
		os.join_path(root, 'kernel/linuxkpi/include/generated/autoconf.h'),
		os.join_path(root, 'tests/linuxkpi/hosttest/archive_abi.h')]
	guarded << os.walk_ext(os.join_path(root, 'tests/linuxkpi/hosttest'), '.v')
	guarded << os.walk_ext(os.join_path(root, 'kernel/linuxkpi/abi'), '.json')
	initial := hosttest.hashes(guarded)!
	generator := os.join_path(work, 'bounds-generator')
	probe := os.join_path(work, 'compiler-probe')
	compile_host(os.join_path(root, 'tests/linuxkpi/generate_bounds.v'), generator)!
	compile_host(os.join_path(root, 'tests/linuxkpi/bounds_compiler_probe.v'), probe)!
	original_config := os.read_file(os.join_path(root, 'kernel/linuxkpi/include/generated/autoconf.h'))!
	configuration := replace_config(original_config, 'CONFIG_MMU', '', true)
	schema_exists := os.is_file(os.join_path(root, 'kernel/linuxkpi/abi/overflow.json'))
	mut adapters := {
		'spinlock.json':        'spinlock_adapters.h'
		'atomic-exchange.json': 'atomic_exchange.h'
	}
	if schema_exists { adapters['overflow.json'] = 'integer_policy.h' }
	mut profiles := map[string]string{}
	for name in ['native', 'cpu64', 'nommu', 'mmu_zero'] {
		include := os.join_path(work, name + ' inputs # $ space', 'include')
		os.mkdir_all(os.join_path(include, 'generated'))!
		mut selected := replace_config(configuration, 'CONFIG_NR_CPUS', if name == 'cpu64' {
			'64'
		} else {
			'256'
		}, false)
		if name != 'nommu' {
			selected += '\n#define CONFIG_MMU ' + if name == 'mmu_zero' { '0\n' } else { '1\n' }
		}
		os.write_file(os.join_path(include, 'generated/autoconf.h'), selected)!
		for schema, header in adapters {
			hosttest.generate_abi(os.join_path(root, 'kernel/linuxkpi/abi', schema),
				os.join_path(root, 'kernel/linuxkpi'), os.join_path(include, 'vinix', header))!
		}
		profiles[name] = include
	}
	mut check := BoundsChecks{ root: root, work: work, linux: linux, archive: archive, compiler: compiler, generator: generator, profiles: profiles }
	reference := os.join_path(work, 'reference.c')
	os.write_file(reference, reference_c)!
	check.successful(reference, schema_exists, pin)!
	check.failures(probe)!
	check.stamps()!
	for malformed in ['\t.ascii "->NR_PAGEFLAGS $1 enum"\n',
		'\t.ascii "->NR_PAGEFLAGS $1 enum"\n'.repeat(2), '\t.ascii "->NR_PAGEFLAGS guessed enum"\n'] {
		hosttest.bounds_offsets(malformed, {
			'CONFIG_SMP': '1'
		}) or { continue }
		return error('malformed compiler offsets accepted')
	}
	mut profile_hashes := map[string]string{}
	for name, path in profiles {
		profile_hashes[name] = hosttest.file_digest(os.join_path(path, 'generated/autoconf.h'))!
	}
	require(initial == hosttest.hashes(guarded)!, 'Production and controller inputs changed during isolated checks')!
	hosttest.write_json(os.join_path(work, 'result.json'), map[string]json2.Any{
		'scope':                      json2.Any('Real pinned native compiler generation and publication tests only')
		'generator_sha256':           hosttest.file_digest(os.join_path(root, 'tests/linuxkpi/generate_bounds.v'))!
		'test_sha256':                hosttest.file_digest(@FILE)!
		'config_source_sha256':       hosttest.text_sha(original_config)
		'archive_sha256':             pin['sha256']!
		'profiles':                   hosttest.string_map(profile_hashes)
		'successful_runs':            4
		'rejected_runs':              11
		'command_stamp_runs':         check.stamp_commands
		'malformed_offsets_rejected': 3
		'results':                    check.results
	})!
	println('LinuxKPI bounds: 4 real GNU99/GNU11 generations, 11 failure cases, 3 malformed offset cases and command stamps passed')
}

fn main() {
	options := hosttest.parse_path_options(os.args[1..], ['--keep-directory'],
		'Usage: bounds_generation.v [--keep-directory DIRECTORY]',
		'Check genuine pinned bounds generation and failure publication boundaries.') or {
		eprintln(err.msg())
		exit(2)
	}
	run_profile(options['--keep-directory']) or {
		eprintln(err.msg())
		exit(1)
	}
}

const reference_c = r'
#define __GENERATING_BOUNDS_H
#include <linux/page-flags.h>
#include <linux/mmzone.h>
#include <linux/log2.h>
#include <linux/spinlock_types.h>
#include GENERATED_HEADER
_Static_assert(NR_PAGEFLAGS == __NR_PAGEFLAGS, "page enum derived");
_Static_assert(MAX_NR_ZONES == __MAX_NR_ZONES, "zone enum derived");
_Static_assert(SPINLOCK_SIZE == sizeof(spinlock_t), "actual spinlock ABI");
#ifdef CONFIG_SMP
_Static_assert(NR_CPUS_BITS == order_base_2(CONFIG_NR_CPUS), "CPU bound derived");
#endif
#ifdef CONFIG_LRU_GEN
_Static_assert(LRU_GEN_WIDTH == order_base_2(MAX_NR_GENS + 1), "LRU bound derived");
_Static_assert(__LRU_REFS_WIDTH == MAX_NR_TIERS - 2, "LRU tier bound derived");
#else
_Static_assert(LRU_GEN_WIDTH == 0, "disabled LRU has no generation field");
_Static_assert(__LRU_REFS_WIDTH == 0, "disabled LRU has no reference field");
#endif
'
