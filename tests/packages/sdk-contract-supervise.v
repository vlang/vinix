// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed native qualification profiles; arbitrary commands are refused.
module main

import crypto.sha256
import json2
import nativeguard
import os
import recoveryguard
import time

#include <errno.h>

const sdk_root = '/Users/alex/Library/Caches/vinix-codex/section14/sdk-contract-20261026/worktree'
const sdk_arm_namespace = '/Users/alex/.cache/vinix-sdk-arm-20261026-04'
const sdk_x86_namespace = '/Users/alex/.cache/vinix-sdk-x86-20261026-03'
const sdk_x86_failed_namespace = '/Users/alex/.cache/vinix-sdk-x86-20261026-01'
const sdk_x86_interrupted_namespace = '/Users/alex/.cache/vinix-sdk-x86-20261026-02'
const sdk_host_namespace = '/Users/alex/.cache/vinix-sdk-arm-20261026-03'
const sdk_controller = sdk_host_namespace + '/host/controller-prod'
const sdk_compiler = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const sdk_controller_hash = 'b28d7ca7199a22e7bddf0a20d4a157ec45410c00a75db90fa90150a662dde902'
const sdk_width = '/Users/alex/.cache/vinix-waitpid-width-20261026-02'
const sdk_clang = '/opt/homebrew/opt/llvm/bin/clang'
const sdk_musl = '/opt/homebrew/Cellar/musl-cross/0.9.11'
const sdk_limine = '/Users/alex/code/vinix/build-amd64-iso/limine'
const sdk_cap = u64(768) << 20
const sdk_reserve = u64(4) << 20

struct SdkProfile {
	arch string
	namespace string
	kernel string
	kernel_sha256 string
	inputs []string
	environment map[string]string
}

fn sdk_profile(arch string) !SdkProfile {
	if arch == 'aarch64' {
		return SdkProfile{
			arch: arch, namespace: sdk_arm_namespace
			kernel: '/Users/alex/code/vinix/build/package-update-qualification/kernels/aarch64-7ac619bd'
			kernel_sha256: '66fda62176a422dbcc891e3f10e95d3a15add95b97beceb9c4451ca1775651d9'
			inputs: ['/Users/alex/code/vinix/build/package-rollback-transaction-work/sysroot',
				'/opt/homebrew/share/qemu/edk2-aarch64-code.fd', '/opt/homebrew/share/qemu/edk2-arm-vars.fd',
				'/Users/alex/code/vinix/boot-image/limine-bin/BOOTAA64.EFI']
			environment: {
				'VINIX_AARCH64_SYSROOT': '/Users/alex/code/vinix/build/package-rollback-transaction-work/sysroot'
				'CC_AARCH64': sdk_clang
				'VINIX_QEMU_AARCH64': '/opt/homebrew/bin/qemu-system-aarch64'
				'VINIX_OVMF_CODE_AARCH64': '/opt/homebrew/share/qemu/edk2-aarch64-code.fd'
				'VINIX_OVMF_VARS_AARCH64': '/opt/homebrew/share/qemu/edk2-arm-vars.fd'
				'VINIX_LIMINE_BOOTAA64': '/Users/alex/code/vinix/boot-image/limine-bin/BOOTAA64.EFI'
			}
		}
	}
	if arch == 'x86_64' {
		return SdkProfile{
			arch: arch, namespace: sdk_x86_namespace
			kernel: '/Users/alex/Library/Caches/vinix-codex/section14/audio-peer-login-20261026/baseline-kernel-source/kernel/bin/vinix'
			kernel_sha256: '348b1204b78afe70f847b1cb5ebb1dd06dfac17add8dab672bb781baf5b6f78e'
			// Includes GCC's baked sysroot, cc1, assembler, linker and wrappers.
			inputs: [sdk_musl, '/opt/homebrew/share/qemu/edk2-x86_64-code.fd', sdk_limine]
			environment: {
				'CC_AMD64': '/opt/homebrew/bin/x86_64-linux-musl-gcc'
				'VINIX_QEMU_X86_64': '/opt/homebrew/bin/qemu-system-x86_64'
				'VINIX_OVMF_CODE_X86_64': '/opt/homebrew/share/qemu/edk2-x86_64-code.fd'
				'VINIX_AMD64_LIMINE_DIR': sdk_limine
			}
		}
	}
	return error('unsupported fixed SDK architecture')
}

fn sdk_charged_roots(profile SdkProfile) []string {
	mut paths := [os.dir(sdk_root), sdk_x86_namespace, sdk_x86_namespace + '-seal',
		sdk_x86_failed_namespace, sdk_x86_failed_namespace + '-seal',
		sdk_x86_interrupted_namespace, sdk_x86_interrupted_namespace + '-seal']
	for suffix in ['01', '02', '03', '04'] {
		path := '/Users/alex/.cache/vinix-sdk-arm-20261026-' + suffix
		paths << [path, path + '-seal']
	}
	if profile.namespace !in paths { paths << profile.namespace }
	return paths
}

fn sdk_tools(profile SdkProfile) map[string]string {
	mut tools := {'git': '/usr/bin/git', 'df': '/bin/df', 'cp': '/bin/cp',
		'tar': '/usr/bin/tar', 'clang': sdk_clang, 'gtimeout': '/opt/homebrew/bin/gtimeout'}
	if profile.arch == 'aarch64' {
		for name, path in {'ld.lld': '/opt/homebrew/bin/ld.lld',
			'qemu-system-aarch64': '/opt/homebrew/bin/qemu-system-aarch64',
			'mformat': '/opt/homebrew/bin/mformat', 'mmd': '/opt/homebrew/bin/mmd',
			'mcopy': '/opt/homebrew/bin/mcopy'} { tools[name] = path }
	} else {
		for name, path in {'cc': '/usr/bin/cc', 'curl': '/usr/bin/curl',
			'x86_64-linux-musl-gcc': '/opt/homebrew/bin/x86_64-linux-musl-gcc',
			'qemu-system-x86_64': '/opt/homebrew/bin/qemu-system-x86_64',
			'xorriso': '/opt/homebrew/bin/xorriso', 'mkdir': '/bin/mkdir',
			'mktemp': '/usr/bin/mktemp', 'rm': '/bin/rm', 'install': '/usr/bin/install',
			'sed': '/usr/bin/sed', 'grep': '/usr/bin/grep', 'sha256sum': '/sbin/sha256sum',
			'awk': '/usr/bin/awk', 'cut': '/usr/bin/cut', 'gzip': '/usr/bin/gzip',
			'od': '/usr/bin/od', 'tr': '/usr/bin/tr', 'cat': '/bin/cat',
			'tail': '/usr/bin/tail', 'mv': '/bin/mv', 'wc': '/usr/bin/wc',
			'dirname': '/usr/bin/dirname'} { tools[name] = path }
	}
	return tools
}

fn sdk_tool_binding(profile SdkProfile) ! {
	for name, expected in sdk_tools(profile) {
		if os.find_abs_path_of_executable(name)! != expected { return error('foreground tool resolution differs: ' + name) }
	}
}

struct SdkPin {
	path string
	value string
}
struct SdkWidthPin { path string sha256 string }

fn sdk_sha(path string) !string {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return sha256.sum(bytes).hex()
}

fn sdk_walk(path string, depth int, started i64, mut pins []SdkPin) ! {
	if depth > 64 || pins.len >= 200000 || recoveryguard.deadline_expired(started, 120000) {
		return error('input inventory exceeds bounded scope')
	}
	// These target loaders refer to the target's root, not the host's root.
	if path in [sdk_musl + '/libexec/aarch64-linux-musl/lib/ld-musl-aarch64.so.1',
		sdk_musl + '/libexec/arm-linux-musleabihf/lib/ld-musl-armhf.so.1',
		sdk_musl + '/libexec/x86_64-linux-musl/lib/ld-musl-x86_64.so.1'] {
		if !os.is_link(path) || os.readlink(path)! != '/lib/libc.so'
			|| os.exists('/lib/libc.so') || os.is_link('/lib/libc.so') {
			return error('fixed target-loader link or absent host target differs: ' + path)
		}
		pins << SdkPin{path + ':link', '/lib/libc.so\nresolved=absent'}
		return
	}
	if os.is_link(path) {
		pins << SdkPin{path + ':link', os.readlink(path)! + '\nresolved=' + os.real_path(path)}
	}
	if os.is_dir(path) {
		pins << SdkPin{path, 'directory'}
		mut names := os.ls(path)!
		names.sort()
		for name in names { sdk_walk(path + '/' + name, depth + 1, started, mut pins)! }
	} else if os.is_file(path) {
		pins << SdkPin{path, sdk_sha(path)!}
	} else {
		return error('input is missing or not a regular file/directory: ' + path)
	}
}

fn sdk_inputs(profile SdkProfile, include_controller bool) ![]SdkPin {
	sdk_tool_binding(profile)!
	mut paths := [os.dir(sdk_compiler), '/opt/homebrew/opt/llvm/lib/clang/23/include', profile.kernel,
		sdk_width + '/changes.json', sdk_width + '/overlay-before.json', sdk_width + '/bundle.json',
		profile.namespace + '/modules', os.executable(), sdk_root + '/.git']
	paths << profile.inputs
	for _, path in sdk_tools(profile) { paths << path }
	if profile.arch == 'x86_64' { paths << '/bin/bash' }
	for relative in ['tools/packages', 'tools/accounts/authclient', 'tools/accounts/authproto',
		'compat/ios/plist', 'tests/hardware-platform/hwhost',
		'tests/software-hosted-x11/nativeguard', 'tests/software-hosted-x11/diagnostics/recoveryguard',
		'tests/packages/sdk-contract-runtime-check.v', 'tests/packages/sdk-contract-supervise.v',
		'tests/packages/sdk-contract-state-check.v',
		'tests/packages/sdk-contract-guest', 'tests/packages/capabilities-check.v',
		'tests/packages/deployment-writer-check.v', 'tests/packages/repository-url-check.v',
		'tests/packages/policy-writer-check.v', 'build-support/build-amd64-iso.sh',
		'build-support/limine-binary.sh', 'build-support/limine.conf'] {
		paths << sdk_root + '/' + relative
	}
	if include_controller { paths << sdk_controller }
	mut pins := []SdkPin{}
	started := time.sys_mono_now()
	for path in paths { sdk_walk(path, 0, started, mut pins)! }
	pins.sort(a.path < b.path)
	return pins
}

fn sdk_binding(profile SdkProfile, include_controller bool) ! {
	mut fixed := {
		sdk_compiler: 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		sdk_width + '/bundle.json': '32d8bc5f46c953aeb5e9ad1ad63e182f10752fe270983943a22c040016617976'
		sdk_width + '/changes.json': '4941c055c018c321d7a4cc94c054b26ba6494bc6be7fa508d99a1bb10b7b2b21'
		sdk_width + '/overlay-before.json': '65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f'
		profile.kernel: profile.kernel_sha256
		'/opt/homebrew/bin/gtimeout': '4e2e9df29ad628bd6bf94d0be194833683c3a12eb4fd578d3983b6afafdbeabb'
	}
	if profile.arch == 'x86_64' {
		for path, expected in {
			'/opt/homebrew/bin/x86_64-linux-musl-gcc': 'b36dc26ec4f18d72cd9eb9667dd718baeece2120e94b6142ec8131073b2926cf'
			sdk_musl + '/libexec/libexec/gcc/x86_64-linux-musl/14.2.0/cc1': '27b5a3822b06b55544fc8cd93dd1d4ea198325e568a0ccd84798788d2d3876b6'
			sdk_musl + '/libexec/x86_64-linux-musl/bin/as': 'c324d87edc56344a4c39c3afefd2713276ca8f7296b5638ea3cfcba6658cd802'
			sdk_musl + '/libexec/x86_64-linux-musl/bin/ld': '23f7efe70705ee57be00d094ea958983f4ed10040b30adc1ede7bed04a6c0e21'
			sdk_musl + '/libexec/x86_64-linux-musl/lib/libc.a': '44880a08bc6c6161120a87784ac5411e90b1b17fb3f2a5b5cc420409b087b3ea'
			'/opt/homebrew/bin/qemu-system-x86_64': '25afcb2986e4a0f2c567de17273f55de3c99792b78a07c99e923bb62024c088f'
			'/opt/homebrew/share/qemu/edk2-x86_64-code.fd': '33090cc07675baa5190d9f1e84bf5176b33bcbfa9bacac522961150cdb6dbb2a'
			'/opt/homebrew/bin/xorriso': 'd217ca8e759699dcaf36953822bd508f13587c57a890d2c1a71b19f6d0e8da86'
			'/sbin/sha256sum': '881f3812ac7be70d99bf635e5322b63f565af66f502be3b464036fef8f927300'
			sdk_limine + '/limine-12.9.3': 'b91a6c7c407bef973a03c17052df4efc37e385756f102bdec308b0338ab13b04'
			sdk_limine + '/limine-binary-12.9.3.tar.gz': '9f42fe9ea2e84d71056529969b1d5c24ba9a2287ffcc01bcce58b0ef8aa98b1d'
			sdk_limine + '/limine-binary-12.9.3/.verified': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
		} { fixed[path] = expected }
		for path in [sdk_limine + '/limine-12.9.3', sdk_limine + '/limine-binary-12.9.3/.verified'] {
			if os.is_link(path) || !os.is_file(path) { return error('requires ordinary cached Limine input: ' + path) }
		}
		if !os.is_executable(sdk_limine + '/limine-12.9.3') { return error('cached Limine installer is not executable') }
	}
	for path, expected in fixed { if sdk_sha(path)! != expected { return error('fixed input differs: ' + path) } }
	if include_controller && (sdk_controller_hash == '' || sdk_sha(sdk_controller)! != sdk_controller_hash) {
		return error('qualified controller binding is missing or changed')
	}
	mut actual := []SdkPin{}
	started := time.sys_mono_now()
	compiler_root := os.dir(sdk_compiler)
	mut names := os.ls(compiler_root)!
	names.sort()
	if os.is_link(compiler_root) || os.real_path(compiler_root) != compiler_root
		|| names != ['snapshot.json', 'thirdparty', 'v', 'v.mod', 'vlib'] {
		return error('complete compiler root has unexpected top-level entries or aliases')
	}
	sdk_walk(compiler_root, 0, started, mut actual)!
	mut expected := [SdkPin{compiler_root, 'directory'}]
	for pin in json2.decode[[]SdkWidthPin](os.read_file(sdk_width + '/overlay-before.json')!)! {
		expected << SdkPin{os.dir(sdk_compiler) + '/' + pin.path, pin.sha256}
	}
	actual.sort(a.path < b.path); expected.sort(a.path < b.path)
	if actual != expected { return error('complete compiler root differs from qualified wait-width overlay') }
	for path, embedded in {
		sdk_root + '/tests/packages/sdk-contract-supervise.v': $embed_file('sdk-contract-supervise.v').to_string()
		sdk_root + '/tests/packages/sdk-contract-runtime-check.v': $embed_file('sdk-contract-runtime-check.v').to_string()
		sdk_root + '/tests/packages/sdk-contract-state-check.v': $embed_file('sdk-contract-state-check.v').to_string()
		sdk_root + '/tests/software-hosted-x11/nativeguard/guard.v': $embed_file('../software-hosted-x11/nativeguard/guard.v').to_string()
		sdk_root + '/tests/software-hosted-x11/diagnostics/recoveryguard/recoveryguard.v': $embed_file('../software-hosted-x11/diagnostics/recoveryguard/recoveryguard.v').to_string()
	} { if sdk_sha(path)! != sha256.hexhash(embedded) { return error('supervisor source binding differs: ' + path) } }
}

fn sdk_environment(profile SdkProfile, temp string) !map[string]string {
	for name, _ in os.environ() { os.unsetenv(name) }
	mut environment := {
		'HOME': '/Users/alex'
		'USER': 'alex'
		'LOGNAME': 'alex'
		'LANG': 'en_US.UTF-8'
		'TERM': 'dumb'
		'PATH': '/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'
		'TMPDIR': temp
		'VTMP': temp
		'VMODULES': profile.namespace + '/modules'
		'V': sdk_compiler
		'VEXE': sdk_compiler
		'V_MACOS_V3_CALLER_VEXE': sdk_compiler
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1'
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0'
		'V_MACOS_V3_NO_FALLBACK': '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK': '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1'
		'V_C_ERROR_BUG_REPORT_DISABLED': '1'
		'VFLAGS': ''
		'VINIX_ROOT': sdk_root
	}
	for name, value in profile.environment { environment[name] = value }
	for name, value in environment { os.setenv(name, value, true) }
	sdk_tool_binding(profile)!
	return environment
}

fn sdk_host_command(profile SdkProfile, label string, arguments []string) ! {
	sdk_namespace := profile.namespace
	log := sdk_namespace + '/host-guard/' + label
	os.write_file(log + '.argv.json', json2.encode(arguments))!
	mut run_error := ''
	result := nativeguard.supervise(arguments, sdk_root, sdk_namespace, sdk_charged_roots(profile),
		log + '.log', log + '-df', nativeguard.Limits{start_bytes: u64(2) << 30,
			floor_bytes: u64(1) << 30, cap_bytes: sdk_cap - sdk_reserve,
			wall_ms: 300000, sample_ms: 1000}) or {
		run_error = recoveryguard.bounded_message(err.msg()); nativeguard.Result{}
	}
	os.write_file(log + '.result.json', json2.encode(result))!
	os.write_file(log + '.error.json', json2.encode({'error': run_error}))!
	if run_error != '' || result.reason != '' || result.cleanup.exit_code != 0
		|| !result.group_observed || !result.cleanup.reaped || !result.cleanup.group_empty
		|| result.cleanup.final_wait != -1 || result.cleanup.final_errno != C.ECHILD {
		return error('host state command or cleanup refused: ' + label)
	}
	if nativeguard.allocated(sdk_charged_roots(profile), os.lstat(sdk_namespace)!.dev)! > sdk_cap - sdk_reserve {
		return error('host state namespace exceeds sampled cap')
	}
}

fn sdk_host_state(profile SdkProfile) ! {
	sdk_namespace := profile.namespace
	for name in ['host', 'host-guard', 'host-tmp', 'modules'] {
		path := sdk_namespace + '/' + name
		if os.exists(path) || os.is_link(path) { return error('host profile requires new path: ' + path) }
	}
	sdk_binding(profile, false)!
	nativeguard.watch_interrupts()!
	admission := nativeguard.actual_df(sdk_namespace, sdk_namespace + '/host-admission-df.log')!
	if admission.available < u64(2) << 30 { return error('actual df below2GiB start') }
	for name in ['host', 'host-guard', 'host-tmp', 'modules'] { os.mkdir(sdk_namespace + '/' + name, mode: 0o700)! }
	environment := sdk_environment(profile, sdk_namespace + '/host-tmp')!
	before := sdk_inputs(profile, false)!
	os.write_file(sdk_namespace + '/host-guard/inputs-before.json', json2.encode(before))!
	os.write_file(sdk_namespace + '/host-guard/environment.json', json2.encode(environment))!
	os.mkdir(sdk_namespace + '/host/source')!
	source_copy := sdk_namespace + '/host/source/sdk-contract-runtime-check.v'
	os.cp(sdk_root + '/tests/packages/sdk-contract-runtime-check.v', source_copy)!
	os.write_file(sdk_namespace + '/host-guard/controller-source-before.sha256', sdk_sha(source_copy)!)!
	for mode in ['normal', 'prod'] {
		mut flags := ['-nocache', '-enable-globals', '-gc', 'none', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
			'-showcc', '-keepc', '-cc', sdk_clang, '-path', '@vlib|@vmodules|' + sdk_root + '|' + sdk_root + '/tests/hardware-platform']
		if mode == 'prod' { flags << '-prod' }
		controller := sdk_namespace + '/host/controller-' + mode
		fixture := sdk_namespace + '/host/fixture-' + mode
		source := if mode == 'normal' { source_copy } else { sdk_root + '/tests/packages/sdk-contract-runtime-check.v' }
		sdk_host_command(profile, mode + '-controller-compile', [sdk_compiler, ...flags, '-o', controller, source])!
		sdk_host_command(profile, mode + '-fixture-compile', [sdk_compiler, ...flags, '-o', fixture, sdk_root + '/tests/packages/sdk-contract-state-check.v'])!
		sdk_host_command(profile, mode + '-fixture-run', [fixture, controller, sdk_namespace + '/host/cases-' + mode])!
		if os.read_file(sdk_namespace + '/host-guard/' + mode + '-fixture-run.log')!
			!= 'SDK STATE real controller nine unchanged refusals and retained fresh state/work kernel PASS\n' {
			return error('missing exact host state marker: ' + mode)
		}
		if mode == 'prod' {
			// Development $embed_file reloads from disk. Exercise stale-source
			// rejection with a separate production binary whose payload is embedded,
			// leaving the production controller for the target bound to its source.
			source_control := sdk_namespace + '/host/controller-source-control'
			sdk_host_command(profile, 'source-control-compile', [sdk_compiler, ...flags, '-o', source_control, source_copy])!
			os.write_file(source_copy, os.read_file(source_copy)! + '\n// Retained stale-source refusal control.\n')!
			os.write_file(sdk_namespace + '/host-guard/controller-source-after.sha256', sdk_sha(source_copy)!)!
			sdk_host_command(profile, 'source-refusal', [fixture, '--source-refusal', source_control, sdk_namespace + '/host/case-source'])!
			if os.read_file(sdk_namespace + '/host-guard/source-refusal.log')!
				!= 'SDK STATE real controller stale source refuses before state writes PASS\n' {
				return error('missing exact source refusal marker')
			}
		}
	}
	after := sdk_inputs(profile, false)!
	os.write_file(sdk_namespace + '/host-guard/inputs-after.json', json2.encode(after))!
	if after != before { return error('host state selected inputs changed') }
	mut roots := map[string][]string{}
	sdk_generated_roots(sdk_namespace + '/host-tmp', time.sys_mono_now(), 0, mut roots)!
	os.write_file(sdk_namespace + '/host-guard/generated-c-vlib-roots.json', json2.encode(roots))!
	for name in ['controller-normal', 'controller-prod', 'fixture-normal', 'fixture-prod', 'controller-source-control'] {
		mut found := false
		for path, observed in roots {
			if !path.contains('/' + name + '.') { continue }
			found = true
			if observed != [os.dir(sdk_compiler) + '/vlib'] { return error('host generated C has an unqualified library root: ' + path) }
		}
		if !found { return error('missing host generated C: ' + name) }
	}
	os.write_file(sdk_namespace + '/host/controller-prod.sha256', sdk_sha(sdk_controller)!)!
	sdk_binding(profile, false)!
	final_df := nativeguard.actual_df(sdk_namespace, sdk_namespace + '/host-guard/final-df.log')!
	allocation := nativeguard.allocated(sdk_charged_roots(profile), os.lstat(sdk_namespace)!.dev)!
	os.write_file(sdk_namespace + '/host-guard/final-budget.json', json2.encode({
		'allocated_bytes_before_final_receipt': allocation.str()
		'available_bytes': final_df.available.str()
		'namespace_cap_bytes': sdk_cap.str()
		'sampling_limit': 'Namespace allocation is sampled, not a filesystem quota; inherited groups only, no daemon tracking.'
	}))!
	if final_df.available < u64(1) << 30 || nativeguard.allocated(sdk_charged_roots(profile), os.lstat(sdk_namespace)!.dev)! > sdk_cap {
		return error('final host namespace cap or actual df floor refused')
	}
	println('PASS SDK state normal/prod real controller refusals, retained kernel work and stale source control; no target or guest executed')
}

// Production C retains encoded source paths in anonymous type names. Record
// those observations instead of inferring the vlib root from the V executable.
fn sdk_generated_roots(path string, started i64, depth int, mut observations map[string][]string) ! {
	if depth > 64 || observations.len > 2000 || recoveryguard.deadline_expired(started, 120000) {
		return error('generated C inventory exceeds bounded scope')
	}
	if os.is_dir(path) {
		for name in os.ls(path)! { sdk_generated_roots(path + '/' + name, started, depth + 1, mut observations)! }
	} else if path.ends_with('.c') {
		text := os.read_file(path)!
		defer { unsafe { text.free() } }
		mut roots := []string{}
		for line in text.split_into_lines() {
			if !line.starts_with('typedef struct ') || !line.contains('_x2f_vlib_x2f_') { continue }
			start := line.index('_x2f_') or { continue }
			encoded := line[start..].all_before('_x2f_vlib_x2f_')
			root := encoded.replace('_x2f_', '/').replace('_x2d_', '-').replace('_x2e_', '.') + '/vlib'
			if root !in roots { roots << root }
		}
		roots.sort()
		observations[path] = roots
	}
}

fn sdk_run() ! {
	$if prod {} $else { return error('compile supervisor with -prod') }
	if os.args.len != 2 || os.args[1] !in ['--host-state-check', '--arm', '--x86'] {
		return error('requires exact --host-state-check, --arm or --x86 profile; arbitrary commands refused')
	}
	profile := sdk_profile(if os.args[1] == '--x86' { 'x86_64' } else { 'aarch64' })!
	sdk_namespace := profile.namespace
	if !os.is_dir(sdk_namespace) || os.is_link(sdk_namespace) || os.real_path(sdk_namespace) != sdk_namespace
		|| os.real_path(os.dir(sdk_namespace)) != os.dir(sdk_namespace) {
		return error('requires the fresh ordinary canonical bootstrap namespace')
	}
	if os.args[1] == '--host-state-check' {
		if sdk_controller_hash != '' { return error('host qualification is sealed; use its retained source profile') }
		sdk_host_state(profile)!; return
	}
	for path in [sdk_namespace + '/s', sdk_namespace + '/guard', sdk_namespace + '/tmp',
		sdk_namespace + '/admission-df.log', sdk_namespace + '/admission-df.log.barrier.json',
		sdk_namespace + '/admission-df.log.cleanup.json', sdk_namespace + '/admission-df.log.barrier-cleanup.json'] {
		if os.exists(path) || os.is_link(path) { return error('requires new output path: ' + path) }
	}
	sdk_binding(profile, true)!
	if !os.is_dir(sdk_namespace + '/modules') || os.is_link(sdk_namespace + '/modules')
		|| os.ls(sdk_namespace + '/modules')!.len != 0 { return error('requires the existing empty private module directory') }
	environment := sdk_environment(profile, sdk_namespace + '/tmp')!
	nativeguard.watch_interrupts()!
	admission := nativeguard.actual_df(sdk_namespace, sdk_namespace + '/admission-df.log')!
	if admission.available < u64(2) << 30 { return error('actual df below2GiB start') }
	os.mkdir(sdk_namespace + '/guard')!
	os.mkdir(sdk_namespace + '/tmp')!
	guard := sdk_namespace + '/guard'
	before := sdk_inputs(profile, true)!
	before_text := json2.encode(before)
	os.write_file(guard + '/inputs-before.json', before_text)!
	os.write_file(guard + '/environment.json', json2.encode(environment))!
	os.write_file(guard + '/admission.json', json2.encode(admission))!
	os.write_file(guard + '/charged-roots.json', json2.encode(sdk_charged_roots(profile)))!
	args := [sdk_controller, '--arch', profile.arch, '--kernel', profile.kernel,
		'--state-dir', sdk_namespace + '/s', '--timeout', '600']
	os.write_file(guard + '/argv.json', json2.encode(args))!
	mut guard_error := ''
	result := nativeguard.supervise(args, sdk_root, sdk_namespace, sdk_charged_roots(profile),
		guard + '/controller.log', guard + '/df', nativeguard.Limits{
			start_bytes: u64(2) << 30, floor_bytes: u64(1) << 30,
			cap_bytes: sdk_cap - sdk_reserve, wall_ms: 1000000, sample_ms: 1000
		}) or { guard_error = recoveryguard.bounded_message(err.msg()); nativeguard.Result{} }
	// Preserve the cleanup/result observation even if a post-run input has
	// disappeared or the generated-C inventory cannot be read.
	result_text := json2.encode(result)
	if u64(result_text.len) > sdk_reserve - 65536 { return error('result exceeds reserved allocation budget') }
	os.write_file(guard + '/result.json', result_text)!
	os.write_file(guard + '/guard-error.json', json2.encode({'error': guard_error}))!
	after := sdk_inputs(profile, true) or {
		os.write_file(guard + '/inputs-after-error.json', json2.encode({'error': recoveryguard.bounded_message(err.msg())}))!
		return err
	}
	mut changed := []string{}
	mut expected := map[string]string{}
	for pin in before { expected[pin.path] = pin.value }
	for pin in after {
		if pin.path !in expected || expected[pin.path] != pin.value { changed << pin.path }
		expected.delete(pin.path)
	}
	for path, _ in expected { changed << path }
	changed.sort()
	after_text := json2.encode(after)
	mut observations := map[string][]string{}
	generated_started := time.sys_mono_now()
	// Only these directories receive V-generated C. The staged ISO also
	// contains upstream Limine C sources, which are not V compiler output.
	for path in [sdk_namespace + '/bootstrap-tmp', sdk_namespace + '/s/run/guest'] {
		sdk_generated_roots(path, generated_started, 0, mut observations) or {
			os.write_file(guard + '/generated-c-error.json', json2.encode({'error': recoveryguard.bounded_message(err.msg())}))!
			return err
		}
	}
	after_receipt := json2.encode({'before_sha256': sha256.hexhash(before_text),
		'after_sha256': sha256.hexhash(after_text), 'changed': json2.encode(changed),
		'error': guard_error, 'generated_c_vlib_roots': json2.encode(observations)})
	if u64(result_text.len + after_text.len + after_receipt.len) > sdk_reserve - 65536 {
		return error('final receipts exceed reserved allocation budget')
	}
	os.write_file(guard + '/inputs-after-map.json', after_text)!
	os.write_file(guard + '/inputs-after.json', after_receipt)!
	sdk_binding(profile, true)!
	final_df := nativeguard.actual_df(sdk_namespace, guard + '/receipt-df.log')!
	allocation := nativeguard.allocated(sdk_charged_roots(profile), os.lstat(sdk_namespace)!.dev)!
	os.write_file(guard + '/final-budget.json', json2.encode({'allocated_bytes_before_final_receipt': allocation.str(),
		'available_bytes': final_df.available.str(), 'namespace_cap_bytes': sdk_cap.str(),
		'sampling_limit': 'Namespace allocation is sampled, not a filesystem quota; inherited groups only, no daemon tracking.'}))!
	if final_df.available < u64(1) << 30 || nativeguard.allocated(sdk_charged_roots(profile), os.lstat(sdk_namespace)!.dev)! > sdk_cap {
		return error('final namespace cap or actual df floor refused')
	}
	if guard_error != '' || result.reason != '' || result.cleanup.exit_code != 0 || changed.len != 0
		|| !result.group_observed || !result.cleanup.reaped || !result.cleanup.group_empty
		|| result.cleanup.final_wait != -1 || result.cleanup.final_errno != C.ECHILD {
		return error('SDK ' + profile.arch + ' attempt refused; complete failed namespace retained')
	}
	for path, roots in observations {
		if roots != [os.dir(sdk_compiler) + '/vlib'] {
			return error('generated C has unqualified vlib roots: ' + path)
		}
	}
	mut bootstrap := []string{}
	for path, _ in observations {
		if path.starts_with(sdk_namespace + '/bootstrap-tmp/') { bootstrap << path }
	}
	if bootstrap.len != 1 || !os.file_name(bootstrap[0]).starts_with('supervisor-host.')
		|| !bootstrap[0].ends_with('.tmp.c') {
		return error('bootstrap generated C differs from the single retained supervisor program')
	}
	mut required_targets := []string{}
	for relative in ['init.c', 'program-0/vinix-package.c', 'program-1/capabilities.c',
		'program-2/deployment-writer.c', 'program-3/repository-url.c', 'program-4/policy-writer.c'] {
		path := sdk_namespace + '/s/run/guest/' + relative
		if path !in observations { return error('missing required target generated C: ' + path) }
		required_targets << path
	}
	mut actual_targets := []string{}
	for path, _ in observations {
		if path.starts_with(sdk_namespace + '/s/run/guest/') { actual_targets << path }
	}
	required_targets.sort(); actual_targets.sort()
	if actual_targets != required_targets { return error('target generated C set differs from the exact six programs') }
	println('PASS bounded SDK ' + profile.arch + ' supervisor; full input inventory unchanged')
}

fn main() { sdk_run() or { eprintln(recoveryguard.bounded_message(err.msg())); exit(1) } }
