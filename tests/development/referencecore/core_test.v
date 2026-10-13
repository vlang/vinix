// SPDX-License-Identifier: GPL-2.0-or-later
module referencecore

import json2
import os
import tools.sourcecommand
import tools.development.devcore

fn sdk_fixture(root string) ! {
	os.mkdir_all(root + '/bin')!
	os.mkdir(root + '/lib')!
	mut header := []u8{len: 64}
	for i, byte in [u8(0x7f), `E`, `L`, `F`, 2, 1] { header[i] = byte }
	header[18] = 183
	for path in ['/bin/sqlite3', '/lib/libc.so'] {
		os.write_file_array(root + path, header)!
		os.chmod(root + path, 0o755)!
	}
}

fn test_reference_options_reject_incomplete_duplicate_and_unknown_selections() {
	assert options('', '', 'aarch64')!.root == ''
	root := sourcecommand.temporary('vinix-reference-options')!
	defer { os.rmdir_all(root) or {} }
	sdk_fixture(root)!
	assert options(root, 'sqlite', 'aarch64')!.tools['sqlite3'].sha256.len == 64
	for profile in ['sqlite,sqlite', 'sqlite,', 'python', ' sqlite'] {
		if _ := options(root, profile, 'aarch64') { assert false, 'invalid reference profile accepted' }
	}
	if _ := options(root, '', 'aarch64') { assert false }
	if _ := options('', 'sqlite', 'aarch64') { assert false }
	if _ := options(root, 'sqlite', 'x86_64') { assert false, 'wrong target accepted' }
	if _ := options(root, 'make', 'aarch64') { assert false, 'missing tools accepted' }
}

fn test_reference_tools_cannot_escape_the_sdk_or_gain_set_id_privileges() {
	root := sourcecommand.temporary('vinix-reference-links')!
	defer { os.rmdir_all(root) or {} }
	sdk_fixture(root)!
	os.chmod(root + '/bin/sqlite3', 0o4755)!
	if _ := options(root, 'sqlite', 'aarch64') { assert false, 'set-ID tool accepted' }
	os.chmod(root + '/bin/sqlite3', 0o755)!
	os.rename(root + '/bin/sqlite3', root + '/outside')!
	os.symlink('../outside', root + '/bin/sqlite3')!
	assert options(root, 'sqlite', 'aarch64')!.tools.len == 1
	os.mkdir(root + '/nested')!
	os.mkdir(root + '/nested/bin')!
	os.symlink('../../outside', root + '/nested/bin/sqlite3')!
	if _ := options(root + '/nested', 'sqlite', 'aarch64') { assert false, 'escaping tool link accepted' }
}

fn test_a_version_command_or_forged_executable_pin_cannot_qualify_a_project() {
	work := '/home/developer/reference-a/work'
	qualifier := 'a'.repeat(64)
	tool_hash := 'b'.repeat(64)
	tools := { 'node': devcore.Pin{'/opt/reference/bin/node', tool_hash} }
	mut report := Report{schema: 1, kernel: 'Vinix', architecture: 'aarch64', uid: 1000,
		context: 'vinix-native', runner_sha256: qualifier, requested: ['node'],
		command_timeout_seconds: 600, complete: true, all_selected_passed: true,
		results: [Verdict{profile: 'node', status: 'passed', commands: [Command{
			argv: ['/opt/reference/bin/node', '--version'], executable_sha256: tool_hash,
			log: work + '/qualification/node/command-0.log'
		}]}]}
	if _ := verify_report(json2.encode(report), 'aarch64', ['node'], qualifier, tools, work, {}) {
		assert false, 'version output substituted for a project'
	}
	report = Report{...report, results: [Verdict{profile: 'node', status: 'passed', commands: [Command{
		argv: ['/opt/reference/bin/node', 'project.js'], executable_sha256: 'c'.repeat(64),
		log: work + '/qualification/node/command-0.log'
	}]}]}
	if _ := verify_report(json2.encode(report), 'aarch64', ['node'], qualifier, tools, work, {}) {
		assert false, 'changed tool pin accepted'
	}
	if _ := verify_report(json2.encode(report), 'x86_64', ['node'], qualifier, tools, work, {}) {
		assert false, 'foreign architecture accepted'
	}
}

fn test_go_receipts_require_the_trimmed_build_and_execution_of_its_exact_artifact() {
	work := '/home/developer/reference-a/work'
	project := work + '/qualification/go'
	qualifier := 'a'.repeat(64)
	tool_hash := 'b'.repeat(64)
	artifact := 'c'.repeat(64)
	tools := { 'go': devcore.Pin{'/opt/reference/bin/go', tool_hash} }
	report := Report{schema: 1, kernel: 'Vinix', architecture: 'aarch64', uid: 1000,
		context: 'vinix-native', runner_sha256: qualifier, requested: ['go'],
		command_timeout_seconds: 600, complete: true, all_selected_passed: true,
		results: [Verdict{profile: 'go', status: 'passed', commands: [
			Command{argv: ['/opt/reference/bin/go', 'build', '-trimpath', '-buildvcs=false', '-o', 'project', 'main.go'],
				executable_sha256: tool_hash, log: project + '/command-0.log'},
			Command{argv: [project + '/project'], executable_sha256: artifact, log: project + '/command-1.log'}
		]}]}
	outputs := { 'qualification/go/project': artifact }
	verify_report(json2.encode(report), 'aarch64', ['go'], qualifier, tools, work, outputs)!
	mut changed := report.results[0].commands.clone()
	changed[0] = Command{...changed[0], argv: ['/opt/reference/bin/go', 'version']}
	forged := Report{...report, results: [Verdict{...report.results[0], commands: changed}]}
	if _ := verify_report(json2.encode(forged), 'aarch64', ['go'], qualifier, tools, work, outputs) {
		assert false, 'Go version substituted for a native project build'
	}
	if _ := verify_report(json2.encode(report), 'aarch64', ['go'], qualifier, tools, work, {}) {
		assert false, 'execution accepted without a recorded Go artifact'
	}
}

fn test_java_receipts_require_compilation_deterministic_packing_and_jar_execution() {
	work := '/home/developer/reference-a/work'
	project := work + '/qualification/java'
	qualifier := 'a'.repeat(64)
	mut tools := map[string]devcore.Pin{}
	for name in ['java', 'javac', 'jar'] { tools[name] = devcore.Pin{'/opt/reference/bin/' + name, 'b'.repeat(64)} }
	argv := [[tools['java'].path, '--version'], [tools['javac'].path, '--version'], [tools['jar'].path, '--version'],
		[tools['javac'].path, 'Project.java'],
		[tools['jar'].path, '--create', '--date=2023-11-14T22:13:20Z', '--file', 'project.jar', '--main-class', 'Project', 'Project.class'],
		[tools['java'].path, '-jar', 'project.jar']]
	mut executed := []Command{}
	for i, args in argv { executed << Command{argv: args, executable_sha256: 'b'.repeat(64), log: project + '/command-' + i.str() + '.log'} }
	report := Report{schema: 1, kernel: 'Vinix', architecture: 'aarch64', uid: 1000,
		context: 'vinix-native', runner_sha256: qualifier, requested: ['java'],
		command_timeout_seconds: 600, complete: true, all_selected_passed: true,
		results: [Verdict{profile: 'java', status: 'passed', commands: executed}]}
	outputs := {'qualification/java/Project.class': 'c'.repeat(64), 'qualification/java/project.jar': 'd'.repeat(64),
		'qualification/java/project.data': 'e'.repeat(64)}
	verify_report(json2.encode(report), 'aarch64', ['java'], qualifier, tools, work, outputs)!
	if _ := verify_report(json2.encode(report), 'aarch64', ['java'], qualifier, tools, work, {}) {
		assert false, 'Java run accepted without its produced class and JAR pins'
	}
	for replacement in [[tools['jar'].path, '--create', '--file', 'project.jar', '--main-class', 'Project', 'Project.class'],
		[tools['jar'].path, '--version']] {
		mut changed := executed.clone()
		changed[4] = Command{...changed[4], argv: replacement}
		forged := Report{...report, results: [Verdict{...report.results[0], commands: changed}]}
		if _ := verify_report(json2.encode(forged), 'aarch64', ['java'], qualifier, tools, work, outputs) {
			assert false, 'incomplete or changing JAR build accepted'
		}
	}
	mut changed := executed.clone()
	changed[5] = Command{...changed[5], executable_sha256: 'c'.repeat(64)}
	forged := Report{...report, results: [Verdict{...report.results[0], commands: changed}]}
	if _ := verify_report(json2.encode(forged), 'aarch64', ['java'], qualifier, tools, work, outputs) {
		assert false, 'changed JVM pin accepted'
	}
	mut requested := executed.clone()
	for i in 0 .. requested.len { requested[i] = Command{...requested[i], environment_overrides: {'VINIX_ALLOW_WX': '1'}} }
	approved := Report{...report, jit_requested: true, results: [Verdict{...report.results[0], commands: requested}]}
	verify_report_jit(json2.encode(approved), 'aarch64', ['java'], qualifier, tools, work, outputs, true)!
	if _ := verify_report(json2.encode(approved), 'aarch64', ['java'], qualifier, tools, work, outputs) {
		assert false, 'JIT request accepted without the selected authorization workflow'
	}
	if _ := verify_report_jit(json2.encode(report), 'aarch64', ['java'], qualifier, tools, work, outputs, true) {
		assert false, 'JIT report accepted without the actual requested child environments'
	}
}
