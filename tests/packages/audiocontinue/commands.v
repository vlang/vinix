// SPDX-License-Identifier: GPL-2.0-or-later
// Pure command construction shared by production and frozen-receipt review.
// Observed JSON is compared with these specifications, never executed.
module audiocontinue

import json2
import os
import tests.packages.audioinputs

pub struct CommandContext2 {
pub:
	plan Plan2
	legacy LegacyPlan2
	donor Donor2
	plan_path string
	plan_sha256 string
}

pub struct CommandSpec2 {
pub:
	role string
	log_relative string
	argv []string
	environment map[string]string
}

// Real canonical paths, ownership, identities and complete inventories belong
// to admission. Here only lexical geometry is checked: a constructor must also
// work before the new state or its outputs exist and must perform no I/O.
fn command_path2(path string) ! {
	if !os.is_abs_path(path) || path == '/' || path.contains('\\') || path.contains('|')
		|| path.bytes().any(it < 32 || it == 127)
		|| path[1..].split('/').any(it in ['', '.', '..']) {
		return error('command specification requires an absolute component path')
	}
}

fn command_borrow2(ctx CommandContext2, name string) !string {
	role := ctx.donor.roles[name] or { return error('missing fixed command input role: ' + name) }
	shapes := expected_roles2()
	shape := shapes[name] or { return error('unknown command input role: ' + name) }
	if role.root != shape.root || role.path != shape.path || role.kind != shape.kind {
		return error('command input role geometry differs: ' + name)
	}
	root := ctx.donor.roots[role.root] or { return error('missing command input root') }
	command_path2(root)!
	return root + '/' + role.path
}

pub fn command_environment2(ctx CommandContext2) !map[string]string {
	if ctx.plan.format != 2 || ctx.plan.profile != format2_profile
		|| ctx.plan.architecture != 'aarch64' || ctx.donor.format != 2
		|| ctx.donor.profile != format2_profile || !hex2(ctx.plan_sha256, 64) {
		return error('command specifications require the fixed format-2 ARM profile')
	}
	out := ctx.plan.state_root
	compiler := ctx.legacy.roots['compiler']
	backend := ctx.legacy.files['backend']
	for path in [out, compiler, backend, ctx.legacy.files['clang'], ctx.plan_path] {
		command_path2(path)!
	}
	v := compiler + '/v'
	return {'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex', 'LANG': 'en_US.UTF-8',
		'PATH': '/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
		'V': v, 'VEXE': v, 'VINIX_V_COMPILER': v, 'V_MACOS_V3_CALLER_VEXE': v,
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0',
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1', 'VFLAGS': '-nocache',
		'VTMP': out + '/tmp', 'TMPDIR': out + '/tmp', 'VMODULES': out + '/modules',
		'VINIX_ROOT': out + '/inputs/source', 'VINIX_AUDIO_BACKEND_CC': backend,
		'VINIX_AUDIO_FROZEN_SYSROOT': command_borrow2(ctx, 'sysroot')!,
		'VINIX_AUDIO_FROZEN_GCC': command_borrow2(ctx, 'gcc')!,
		'VINIX_AARCH64_SYSROOT': command_borrow2(ctx, 'sysroot')!,
		'VINIX_AUDIO_KERNEL_EVIDENCE': command_borrow2(ctx, 'kernel-evidence')!,
		'VINIX_AUDIO_CC_SOURCE': out + '/inputs/source/tests/packages/audio-cross-cc.v',
		'CC_AARCH64': out + '/cross-cc', 'CFLAGS': '', 'CPPFLAGS': '', 'LDFLAGS': ''}
}

fn command_append2(mut specs []CommandSpec2, role string, argv []string,
	environment map[string]string) {
	specs << CommandSpec2{role: role, log_relative: role, argv: argv,
		environment: environment.clone()}
}

fn command_program2(mut specs []CommandSpec2, ctx CommandContext2, source string,
	relative string, name string, environment map[string]string) ! {
	out := ctx.plan.state_root
	root := out + '/inputs/source'
	base := relative + '/' + name
	lookup := ['@vlib', '@vmodules', root, root + '/tools/accounts',
		root + '/tools/security-events', root + '/tools/keyring']
	command_append2(mut specs, relative + '/generate.log',
		[ctx.legacy.roots['compiler'] + '/v', '-nocache', '-os', 'linux', '-arch', 'arm64',
		'-gc', 'none', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-prod',
		'-path', lookup.join('|'), '-o', out + '/' + base + '.c', root + '/' + source], environment)
	sysroot := command_borrow2(ctx, 'sysroot')!
	command_append2(mut specs, relative + '/build.log',
		[out + '/cross-cc', '--target=aarch64-linux-musl', '--sysroot=' + sysroot,
		'-static', '-O1', '-w', '-D_GNU_SOURCE', '-fno-stack-protector',
		'-L' + sysroot + '/lib', '-fuse-ld=lld', '-o', out + '/' + base,
		out + '/' + base + '.c', '-lm', '-lpthread'], environment)
}

// Exactly the twenty existing preparation commands, in their execution order.
// No role, source file, flags, scenario or argument vector is loaded from JSON.
pub fn command_specs2(ctx CommandContext2) ![]CommandSpec2 {
	environment := command_environment2(ctx)!
	out := ctx.plan.state_root
	root := out + '/inputs/source'
	v := ctx.legacy.roots['compiler'] + '/v'
	host_cc := ctx.legacy.files['clang']
	sysroot := command_borrow2(ctx, 'sysroot')!
	mut specs := []CommandSpec2{cap: 20}
	command_append2(mut specs, 'audits/before-owner.log',
		[out + '/inputs/controller', '--kernel-audit', ctx.plan_path, ctx.plan_sha256, 'before'], environment)
	command_append2(mut specs, 'cross-adapter-build.log',
		[v, '-prod', '-nocache', '-keepc', '-backend', 'c', '-cc', host_cc,
		'-o', out + '/cross-cc', root + '/tests/packages/audio-cross-cc.v'], environment)
	command_append2(mut specs, 'cross-probe-generate.log',
		[v, '-nocache', '-os', 'linux', '-arch', 'arm64', '-gc', 'none',
		'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-prod',
		'-path', '@vlib|@vmodules|' + root, '-o', out + '/cross-probe.c',
		root + '/tests/packages/audio-cross-probe.v'], environment)
	command_append2(mut specs, 'cross-search.log',
		[out + '/cross-cc', '-v', '-static', '-O1', '-w', '-D_GNU_SOURCE',
		'-fno-stack-protector', out + '/cross-probe.c', '-o', out + '/cross-probe',
		'-lm', '-lpthread'], environment)
	generator := out + '/sandbox-build/security-compiler'
	command_append2(mut specs, 'sandbox-build/generator-build.log',
		audioinputs.sandbox_generator_arguments(root, v, host_cc, generator)!, environment)
	command_append2(mut specs, 'sandbox-build/generate.log',
		[generator, 'security-compile', 'sandbox', out + '/sandbox-build/sandbox.c',
		'--arch', 'arm64'], environment)
	command_append2(mut specs, 'sandbox-build/build.log',
		[out + '/cross-cc', '--target=aarch64-linux-musl', '--sysroot=' + sysroot,
		'-L' + sysroot + '/lib', '-fuse-ld=lld', '-static', '-std=c11', '-O2',
		'-Wall', '-Wextra', '-Werror', '-D_GNU_SOURCE', '-DVINIX_V_RUNTIME',
		'-I', root + '/tools/sandbox', out + '/sandbox-build/sandbox.c',
		'-o', out + '/sandbox-build/vinix-sandbox'], environment)
	command_program2(mut specs, ctx, 'tests/packages/audio-portal-tone', 'tone-build', 'tone', environment)!
	command_program2(mut specs, ctx, 'tests/packages/audio-portal-guest', 'guest-build', 'init', environment)!
	sources := ['tools/packages/main.v', 'tools/accounts/account.v',
		'tools/accounts/session.v', 'tools/accounts/authd.v']
	names := ['vinix-package', 'vinix-account', 'vinix-session', 'vinix-authd']
	for index, source in sources {
		command_program2(mut specs, ctx, source, 'tools/program-' + index.str(), names[index], environment)!
	}
	command_append2(mut specs, 'audits/after-owner.log',
		[out + '/inputs/controller', '--kernel-audit', ctx.plan_path, ctx.plan_sha256, 'after'], environment)
	return specs
}

pub fn command_spec2(ctx CommandContext2, role string) !CommandSpec2 {
	for spec in command_specs2(ctx)! {
		if spec.role == role { return spec }
	}
	return error('unknown fixed preparation command role: ' + role)
}

// Full byte equality enforces the canonical typed representation as well as
// every argument and environment value. This is stronger than accepting a
// subset of flag/path tokens, and never promotes observed data to a command.
pub fn validate_command_spec2(ctx CommandContext2, role string, argv_text string,
	environment_text string) ! {
	spec := command_spec2(ctx, role)!
	if argv_text != json2.encode(spec.argv) + '\n'
		|| environment_text != json2.encode(spec.environment) + '\n' {
		return error('fixed command arguments or environment differ: ' + role)
	}
}
