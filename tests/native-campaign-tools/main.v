// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import allocationhost
import campaignhost
import os

fn main() {
	argv := campaignhost.saved_arguments(os.args[1..]) or { eprintln(err); exit(2) }
	if argv.len >= 1 && argv[0] == 'allocation-vinix-saved' {
		exit(allocationhost.vinix_cli(argv[1..], .saved_final))
	}
	if argv.len >= 1 && argv[0] == 'allocation-measure' {
		exit(allocationhost.console_cli(argv[1..], true))
	}
	if argv.len < 2 {
		eprintln('usage: campaign-tool COMMAND ORIGIN [--root DIR --state-dir DIR]')
		exit(2)
	}
	command := argv[0]
	origin := campaignhost.resolve(argv[1]) or {
		eprintln(err)
		exit(1)
	}
	args := cachecli.arguments(argv[2..], ['--root', '--state-dir', '--version', '--guest',
		'--arch'], []string{}, []string{}, 0, 3,
		'usage: campaign-tool COMMAND ORIGIN [--root DIR --state-dir DIR]') or {
		eprintln(err)
		exit(2)
	}
	default_root := if command == 'run-diagnostic' {
		os.dir(os.dir(os.dir(origin)))
	} else if command.starts_with('cohort') {
		os.dir(os.dir(origin))
	} else {
		'/Users/alex/code/vinix'
	}
	root := campaignhost.resolve(args.value('--root', default_root)) or {
		eprintln(err)
		exit(1)
	}
	state := campaignhost.resolve(args.value('--state-dir', os.dir(origin))) or {
		eprintln(err)
		exit(1)
	}
	context := campaignhost.Context{ root: root, state: state, origin: origin }
	if args.positional.len > 0 && command !in ['perf-final', 'perf-v4', 'x86-v3', 'x86-v4', 'x86-v6', 'socket-probe'] {
		eprintln('unexpected positional arguments for ' + command)
		exit(2)
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	status := match command {
		'correctness-arm', 'correctness-x86' {
			campaignhost.correctness_driver(context, if command == 'correctness-arm' { 'aarch64' } else { 'x86_64' }) or { exit(campaignhost.interrupted_status(err)) }
		}
		'final-controller' { campaignhost.final_controller(context) or { exit(campaignhost.interrupted_status(err)) } }
		'settlement-after-core' { campaignhost.settlement_after_core(context) or { exit(campaignhost.interrupted_status(err)) } }
		'socket-probe' {
			if args.positional.len !in [1, 2] { eprintln('KIND [KERNEL] required'); 2 }
			else { campaignhost.run_socket_probe(context, args.positional[0], if args.positional.len == 2 { args.positional[1] } else { root + '/third_party/useralloc-vm-next/kernel' }) or { exit(campaignhost.interrupted_status(err)) } }
		}
		'run-diagnostic' {
			campaignhost.run_diagnostic(context) or { exit(campaignhost.interrupted_status(err)) }
		}
		'audit-v5', 'audit-v5-baseline' {
			campaignhost.allocation_audit(context, command == 'audit-v5-baseline') or { exit(campaignhost.interrupted_status(err)) }
		}
		'audit-diagnostic' {
			campaignhost.capture_allocation_diagnostic(context) or { exit(campaignhost.interrupted_status(err)) }
		}
		'production-packaging' {
			campaignhost.production_packaging(context, args.value('--arch', 'both')) or { exit(campaignhost.interrupted_status(err)) }
		}
		'static-desktop' {
			campaignhost.static_desktop(context) or { exit(campaignhost.interrupted_status(err)) }
		}
		'perf-final', 'perf-v4' {
			campaignhost.perf_driver(context, if command == 'perf-final' { 'final' } else { 'v4' }, args.positional) or { exit(campaignhost.interrupted_status(err)) }
		}
		'perf-validate' {
			campaignhost.perf_validate(context) or { exit(campaignhost.interrupted_status(err)) }
		}
		'x86-v3', 'x86-v4', 'x86-v6' {
			version := command.all_after('x86-')
			if args.positional == ['prepare'] {
				campaignhost.prepare_x86(context, version) or { exit(campaignhost.interrupted_status(err)) }
			} else if args.positional.len == 2 && args.positional[0] == 'run' {
				campaignhost.run_x86(context, version, args.positional[1]) or { exit(campaignhost.interrupted_status(err)) }
			} else { eprintln('prepare | run KERNEL'); 2 }
		}
		'prepare-arm-v5', 'prepare-arm-v6' {
			campaignhost.prepare_arm(context, command.all_after('prepare-arm-')) or { exit(campaignhost.interrupted_status(err)) }
		}
		'arm-v4', 'arm-v5', 'arm-v6', 'arm-socket' {
			campaignhost.run_arm_saved(context, if command == 'arm-socket' { 'v5' } else { command.all_after('arm-') }, command == 'arm-socket') or { exit(campaignhost.interrupted_status(err)) }
		}
		'core-audit' {
			campaignhost.core_evidence_audit(context) or { exit(campaignhost.interrupted_status(err)) }
		}
		'core-driver' {
			campaignhost.core_driver(context) or { exit(campaignhost.interrupted_status(err)) }
		}
		'core-mode' {
			mode := args.value('--arch', os.base(context.state).all_after('core-'))
			parent := campaignhost.Context{...context, state: os.dir(context.state)}
			arch := if mode == 'aarch64' { 'aarch64' } else { 'x86_64' }
			base := campaignhost.read_json(parent.state + '/core-' + arch + '/compile.json') or { exit(campaignhost.interrupted_status(err)) }
			image := campaignhost.read_json(parent.state + '/core-x86_64/embedded-input-check.json') or { exit(campaignhost.interrupted_status(err)) }
			result := campaignhost.run_core_mode(parent, mode, base, image) or { exit(campaignhost.interrupted_status(err)) }
			result['exit_code'] or { exit(1) }.int()
		}
		'summarize-diagnostic' {
			campaignhost.summarize_diagnostic(context) or { exit(campaignhost.interrupted_status(err)) }
		}
		'collect-objects' {
			campaignhost.collect_objects(context) or { exit(campaignhost.interrupted_status(err)) }
		}
		'collect-verification' {
			campaignhost.collect_verification(context, args.value('--arch', 'x86_64')) or { exit(campaignhost.interrupted_status(err)) }
		}
		'readiness-v6' {
			campaignhost.readiness(context) or { exit(campaignhost.interrupted_status(err)) }
		}
		'cohorts-v4', 'cohorts-v4-guard', 'cohorts-v5', 'cohorts-v6' {
			campaignhost.run_cohorts(context, command.all_after('cohorts-')) or { exit(campaignhost.interrupted_status(err)) }
		}
		'cohort-driver' {
			campaignhost.cohort_driver(context, args.value('--version', 'v6'), args.value('--guest', 'vinix')) or { exit(campaignhost.interrupted_status(err)) }
		}
		'audit-final' {
			campaignhost.audit_final(context) or { exit(campaignhost.interrupted_status(err)) }
		}
		'core-recorded', 'core-supplement', 'core-final-arm' {
			campaignhost.recorded_core(context, command == 'core-supplement', command == 'core-final-arm') or { exit(campaignhost.interrupted_status(err)) }
		}
		else {
			eprintln('unknown campaign command')
			2
		}
	}
	exit(status)
}
