// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import androidtools
import androidfixtures
import cachecli
import os

fn main() {
	if os.args.len == 3 && os.args[1] in ['--child-runtime', '--child-atl', '--child-boot', '--child-musl'] {
		androidfixtures.fixture_child(os.args[1], os.args[2]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len < 3 { eprintln('usage: android-tool COMMAND ORIGIN [arguments]'); exit(2) }
	guard := cachecli.own_commands()
	defer { guard.close() }
	status := if os.args[1] == 'fixtures' {
		androidfixtures.fixtures_cli(os.args[3..]) or { eprintln(err); exit(androidtools.failure_status(err)) }
	} else if os.args[1] == 'binding' {
		if os.args.len != 4 { eprintln('binding needs one JSON request'); exit(2) }
		androidtools.binding_cli(os.args[3]) or { eprintln(err); exit(1) }
	} else if os.args[1] in ['resolve', 'verify-source', 'verify-atl-inputs', 'source-key', 'compile-args', 'link-args', 'copy-installed', 'configuration-probe-key', 'art-build-manifest', 'bionic-build-manifest', 'atl-build-manifest'] {
		androidtools.build_metadata_cli(os.args[1], os.args[3..]) or { eprintln(err); exit(androidtools.failure_status(err)) }
	} else if os.args[1] == 'atl-configuration' {
		androidtools.atl_configuration_cli(os.args[3..]) or { eprintln(err); exit(androidtools.failure_status(err)) }
	} else if os.args[1] == 'run-runtime-vm' {
		androidtools.runtime_vm_cli(os.args[3..]) or { eprintln(err); exit(androidtools.failure_status(err)) }
	} else if os.args[1] == 'test-runtime-v' {
		androidtools.runtime_host_cli(os.args[3..]) or { eprintln(err); exit(androidtools.failure_status(err)) }
	} else if os.args[1] == 'build' {
		androidtools.runtime_cli(os.args[3..]) or { eprintln(err); exit(androidtools.failure_status(err)) }
	} else if os.args[1] == 'extend-framework' {
		androidtools.framework_cli(os.args[3..]) or { eprintln(err); exit(androidtools.failure_status(err)) }
	} else if os.args[1] == 'art-bootclasspath' {
		androidtools.boot_cli(os.args[3..]) or { eprintln(err); exit(androidtools.failure_status(err)) }
	} else if os.args[1] == 'atl-dex' {
		androidtools.dex_compile(os.args[3..], os.getenv('VINIX_ATL_R8'), os.getenv('VINIX_ATL_CORE_CLASSES'), if os.getenv('VINIX_ATL_JAVA_D8') != '' { os.getenv('VINIX_ATL_JAVA_D8') } else { 'java' }) or { eprintln('atl-dex: ' + err.msg()); exit(androidtools.failure_status(err)) }
		0
	} else if os.args[1] in ['compile-runtime', 'compile-framework', 'compile-atl-configuration', 'runtime-inputs'] {
		androidtools.generation_cli(os.args[1], os.args[3..]) or {
			eprintln(err)
			exit(androidtools.failure_status(err))
		}
	} else { androidtools.probe_cli(os.args[1], os.real_path(os.args[2]), os.args[3..]) or {
		eprintln(err)
		exit(androidtools.failure_status(err))
	} }
	exit(status)
}
