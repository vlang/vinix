// SPDX-License-Identifier: GPL-2.0-or-later
// Pure string/map controls. Synthetic paths remain below the caller's charged
// fixture parent. No executable, fixture file or serialized command is run.
module audiocontinue

import json2
import os

fn commands2_context() !CommandContext2 {
	parent := os.getenv('AUDIO_CONTINUATION_TEST_ROOT')
	if parent == '' { return error('command v2 tests require charged AUDIO_CONTINUATION_TEST_ROOT') }
	ordinary2(parent, 'directory')!
	base := parent + '/commands2-intentional-fixture'
	return CommandContext2{
		plan: Plan2{state_root: base + '/state', source_root: base + '/source'}
		legacy: LegacyPlan2{roots: {'compiler': base + '/qualified-compiler'},
			files: {'clang': base + '/original-host-clang', 'backend': base + '/original-backend'},
			charged_roots: [parent]}
		donor: Donor2{roots: {'capture': base + '/donor', 'store': base + '/store'},
			roles: expected_roles2()}
		plan_path: base + '/reviewed-plan.json'
		plan_sha256: '0123456789abcdef'.repeat(4)
	}
}

fn commands2_refuses(ctx CommandContext2, role string, argv string, environment string) {
	mut refused := false
	validate_command_spec2(ctx, role, argv, environment) or { refused = true }
	assert refused
}

fn test_commands2_all_twenty_roles_have_exact_canonical_positive_receipts() {
	ctx := commands2_context() or { panic(err) }
	specs := command_specs2(ctx) or { panic(err) }
	assert specs.map(it.role) == ['audits/before-owner.log', 'cross-adapter-build.log',
		'cross-probe-generate.log', 'cross-search.log', 'sandbox-build/generator-build.log',
		'sandbox-build/generate.log', 'sandbox-build/build.log', 'tone-build/generate.log',
		'tone-build/build.log', 'guest-build/generate.log', 'guest-build/build.log',
		'tools/program-0/generate.log', 'tools/program-0/build.log',
		'tools/program-1/generate.log', 'tools/program-1/build.log',
		'tools/program-2/generate.log', 'tools/program-2/build.log',
		'tools/program-3/generate.log', 'tools/program-3/build.log', 'audits/after-owner.log']
	for spec in specs {
		assert spec.log_relative == spec.role
		assert (command_spec2(ctx, spec.role) or { panic(err) }) == spec
		validate_command_spec2(ctx, spec.role, json2.encode(spec.argv) + '\n',
			json2.encode(spec.environment) + '\n') or { panic(err) }
	}
}

fn test_commands2_select_only_current_fresh_sources_and_pinned_original_host_tools() {
	ctx := commands2_context() or { panic(err) }
	out := ctx.plan.state_root
	root := out + '/inputs/source'
	for role, source in {
		'cross-adapter-build.log': 'tests/packages/audio-cross-cc.v'
		'cross-probe-generate.log': 'tests/packages/audio-cross-probe.v'
		'sandbox-build/generator-build.log': 'build-support/native-compat-tools/main.v'
		'tone-build/generate.log': 'tests/packages/audio-portal-tone'
		'guest-build/generate.log': 'tests/packages/audio-portal-guest'
		'tools/program-0/generate.log': 'tools/packages/main.v'
		'tools/program-1/generate.log': 'tools/accounts/account.v'
		'tools/program-2/generate.log': 'tools/accounts/session.v'
		'tools/program-3/generate.log': 'tools/accounts/authd.v'
	} {
		spec := command_spec2(ctx, role) or { panic(err) }
		assert spec.argv[0] == ctx.legacy.roots['compiler'] + '/v'
		assert spec.argv.last() == root + '/' + source
		assert '-nocache' in spec.argv
		assert '-prod' in spec.argv
		commands2_refuses(ctx, role, json2.encode(spec.argv.map(
			if it == root + '/' + source { ctx.donor.roots['capture'] + '/inputs/source/' + source } else { it })) + '\n',
			json2.encode(spec.environment) + '\n')
	}
	for role in ['cross-adapter-build.log', 'sandbox-build/generator-build.log'] {
		spec := command_spec2(ctx, role) or { panic(err) }
		assert '-keepc' in spec.argv
		position := spec.argv.index('-cc')
		assert position >= 0
		assert spec.argv[position + 1] == ctx.legacy.files['clang']
	}
	for label in ['before', 'after'] {
		spec := command_spec2(ctx, 'audits/' + label + '-owner.log') or { panic(err) }
		assert spec.argv == [out + '/inputs/controller', '--kernel-audit',
			ctx.plan_path, ctx.plan_sha256, label]
	}
}

fn test_commands2_preserve_strict_sandbox_flags_and_exact_target_outputs() {
	ctx := commands2_context() or { panic(err) }
	out := ctx.plan.state_root
	sandbox := command_spec2(ctx, 'sandbox-build/build.log') or { panic(err) }
	for flag in ['-static', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
		'-D_GNU_SOURCE', '-DVINIX_V_RUNTIME'] { assert flag in sandbox.argv }
	assert '-fpermissive' !in sandbox.argv
	for role, binary in {
		'cross-search.log': 'cross-probe'
		'sandbox-build/build.log': 'sandbox-build/vinix-sandbox'
		'tone-build/build.log': 'tone-build/tone'
		'guest-build/build.log': 'guest-build/init'
		'tools/program-0/build.log': 'tools/program-0/vinix-package'
		'tools/program-1/build.log': 'tools/program-1/vinix-account'
		'tools/program-2/build.log': 'tools/program-2/vinix-session'
		'tools/program-3/build.log': 'tools/program-3/vinix-authd'
	} {
		spec := command_spec2(ctx, role) or { panic(err) }
		assert spec.argv[0] == out + '/cross-cc'
		position := spec.argv.index('-o')
		assert position >= 0
		assert spec.argv[position + 1] == out + '/' + binary
		assert '-static' in spec.argv
		mut changed := spec.argv.clone()
		changed[position + 1] = ctx.donor.roots['capture'] + '/' + binary
		commands2_refuses(ctx, role, json2.encode(changed) + '\n', json2.encode(spec.environment) + '\n')
	}
}

fn test_commands2_every_argument_and_flag_is_bound_in_all_twenty_roles() {
	ctx := commands2_context() or { panic(err) }
	for spec in command_specs2(ctx) or { panic(err) } {
		environment := json2.encode(spec.environment) + '\n'
		for index, argument in spec.argv {
			mut changed := spec.argv.clone()
			changed[index] = argument + '-intentional-mutation'
			commands2_refuses(ctx, spec.role, json2.encode(changed) + '\n', environment)
		}
		mut appended := spec.argv.clone()
		appended << '-fpermissive'
		commands2_refuses(ctx, spec.role, json2.encode(appended) + '\n', environment)
		commands2_refuses(ctx, spec.role, json2.encode(spec.argv[..spec.argv.len - 1]) + '\n', environment)
	}
}

fn test_commands2_environment_is_complete_and_private_for_every_role() {
	ctx := commands2_context() or { panic(err) }
	out := ctx.plan.state_root
	environment := command_environment2(ctx) or { panic(err) }
	assert environment.len == 29
	assert environment['V'] == ctx.legacy.roots['compiler'] + '/v'
	assert environment['VINIX_AUDIO_BACKEND_CC'] == ctx.legacy.files['backend']
	assert environment['VINIX_AUDIO_FROZEN_SYSROOT'] == ctx.donor.roots['capture'] + '/inputs/cross-sysroot'
	assert environment['VINIX_AUDIO_FROZEN_GCC'] == ctx.donor.roots['capture'] + '/inputs/cross-gcc'
	assert environment['VINIX_AUDIO_KERNEL_EVIDENCE'] == ctx.donor.roots['capture'] + '/inputs/kernel-evidence'
	assert environment['VINIX_ROOT'] == out + '/inputs/source'
	assert environment['VMODULES'] == out + '/modules'
	assert environment['VTMP'] == out + '/tmp'
	assert environment['TMPDIR'] == out + '/tmp'
	for key in ['CFLAGS', 'CPPFLAGS', 'LDFLAGS'] { assert environment[key] == '' }
	for spec in command_specs2(ctx) or { panic(err) } {
		assert spec.environment == environment
		argv := json2.encode(spec.argv) + '\n'
		for key, value in spec.environment {
			mut changed := spec.environment.clone()
			changed[key] = value + '-intentional-mutation'
			commands2_refuses(ctx, spec.role, argv, json2.encode(changed) + '\n')
			mut missing := spec.environment.clone()
			missing.delete(key)
			commands2_refuses(ctx, spec.role, argv, json2.encode(missing) + '\n')
		}
		mut extra := spec.environment.clone()
		extra['DYLD_INSERT_LIBRARIES'] = '/intentional/foreign.dylib'
		commands2_refuses(ctx, spec.role, argv, json2.encode(extra) + '\n')
	}
}

fn test_commands2_role_rebinding_and_unknown_roles_are_refused() {
	ctx := commands2_context() or { panic(err) }
	specs := command_specs2(ctx) or { panic(err) }
	for index, spec in specs {
		other_role := specs[(index + 1) % specs.len].role
		commands2_refuses(ctx, other_role, json2.encode(spec.argv) + '\n',
			json2.encode(spec.environment) + '\n')
	}
	for role in ['', 'unknown', '../cross-search.log', '/cross-search.log',
		'cross-search.log/extra', 'cross-search.log\n'] {
		mut refused := false
		_ := command_spec2(ctx, role) or { refused = true; CommandSpec2{} }
		assert refused
		commands2_refuses(ctx, role, '[]\n', '{}\n')
	}
}

fn test_commands2_noncanonical_or_wrong_typed_json_never_becomes_an_observation() {
	ctx := commands2_context() or { panic(err) }
	for spec in command_specs2(ctx) or { panic(err) } {
		argv := json2.encode(spec.argv) + '\n'
		environment := json2.encode(spec.environment) + '\n'
		for changed in [argv.trim_space(), ' ' + argv, argv + '\n', '[]\n', '[1]\n', '{}\n'] {
			commands2_refuses(ctx, spec.role, changed, environment)
		}
		for changed in [environment.trim_space(), ' ' + environment,
			environment + '\n', '{}\n', '{"PATH":1}\n', '[]\n'] {
			commands2_refuses(ctx, spec.role, argv, changed)
		}
	}
}

fn test_commands2_context_relocation_or_alias_geometry_cannot_rebind_old_receipts() {
	ctx := commands2_context() or { panic(err) }
	for spec in command_specs2(ctx) or { panic(err) } {
		other := CommandContext2{...ctx,
			plan: Plan2{...ctx.plan, state_root: ctx.plan.state_root + '-other'}}
		commands2_refuses(other, spec.role, json2.encode(spec.argv) + '\n',
			json2.encode(spec.environment) + '\n')
	}
	for path in ['relative', ctx.plan.state_root + '/../escape', ctx.plan.state_root + '|/other'] {
		mut refused := false
		_ := command_specs2(CommandContext2{...ctx, plan: Plan2{...ctx.plan, state_root: path}}) or {
			refused = true
			[]CommandSpec2{}
		}
		assert refused
	}
	mut roles := ctx.donor.roles.clone()
	roles['sysroot'] = Borrow2{root: 'store', path: 'inputs/cross-sysroot', kind: 'directory'}
	mut refused := false
	_ := command_environment2(CommandContext2{...ctx, donor: Donor2{...ctx.donor, roles: roles}}) or {
		refused = true
		map[string]string{}
	}
	assert refused
}
