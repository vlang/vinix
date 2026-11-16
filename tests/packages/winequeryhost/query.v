// SPDX-License-Identifier: GPL-2.0-or-later
// Required query evidence is ordinary serialized observations, not live xattrs.
module winequeryhost

import os
import json2
import tests.packages.winemetaclosure
import tests.packages.winequeryclosure
import tests.packages.winequeryprobe

pub const marker = 'temporary query control\n'

pub struct Fixture {
pub mut:
	key string
	value string
	paths []string
}

pub struct Declaration {
pub mut:
	format int
	policies map[string]string
	execution_queries []string
	temporary_queries string
	attributes Fixture
}

pub struct Control {
pub:
	mode string
	operation string
	path string
	name string
}

pub fn lookalikes(directory string) []string {
	cwd := directory + '/replay/link-inputs'
	return [cwd + '/program.tmp-not-hex', cwd + '/program.tmp00000000', cwd + '/program.tmp000000g']
}

pub fn temporary(directory string) string { return directory + '/replay/link-inputs/program.tmp0123abc' }

pub fn declaration(directory string, object string, files []string, aliases []string) !Declaration {
	if object !in files { return error('captured query object absent') }
	cwd := directory + '/replay/link-inputs'
	writes := [directory + '/captured-closed.exec.json', directory + '/hidden-closed.exec.json', cwd + '/program']
	temp := winequeryclosure.temporary_queries(cwd + '/program')!
	return Declaration{format: 1, execution_queries: writes, temporary_queries: temp,
		policies: {'metadata-policy.sb': winemetaclosure.policy(files, aliases)!,
			'existence-policy.sb': winequeryclosure.existence_policy(files, aliases)! + winequeryclosure.writes(writes)! + temp,
			'xattr-policy.sb': winequeryclosure.xattr_policy(files, aliases)!},
		attributes: Fixture{key: winequeryprobe.key, value: winequeryprobe.value,
			paths: [object, cwd, directory + '/uncaptured-object.o', directory + '/unlisted-directory', ...lookalikes(directory), temporary(directory)]}}
}

pub fn policy(decl Declaration, files []string, aliases []string) !string {
	return winequeryclosure.policy(files, aliases)! + winequeryclosure.writes(decl.execution_queries)! + decl.temporary_queries
}

pub fn prepare(directory string, decl Declaration) ! {
	os.write_file(directory + '/query.json', json2.encode(decl) + '\n')!
	os.write_file(directory + '/attribute-fixture.json', json2.encode(decl.attributes) + '\n')!
	for name, text in decl.policies { os.write_file(directory + '/' + name, text)! }
}

pub fn seed(directory string, decl Declaration) ! {
	for path in [...lookalikes(directory), temporary(directory)] { os.write_file(path, marker)! }
	for path in decl.attributes.paths { winequeryprobe.seed(path)! }
}

pub fn verify_live(decl Declaration) ! {
	for path in decl.attributes.paths {
		if !winequeryprobe.allowed(winequeryprobe.read('getxattr', path)!) { return error('query fixture value changed') }
	}
}

pub fn is_query(mode string) bool {
	return mode in ['probe-query-allowed', 'probe-query-denied', 'query-counterfactual', 'xattr-isolated', 'existence-isolated', 'output-query-only']
}

pub fn policy_file(mode string) string {
	return match mode {
		'query-counterfactual' { 'metadata-policy.sb' }
		'xattr-isolated' { 'xattr-policy.sb' }
		'existence-isolated' { 'existence-policy.sb' }
		else { 'policy.sb' }
	}
}

fn operations(control Control) []string {
	return match control.mode {
		'probe-query-allowed' { ['exists', 'getxattr', 'listxattr'] }
		'query-counterfactual', 'xattr-isolated', 'output-query-only' { ['exists', 'getxattr'] }
		'existence-isolated' { ['exists'] }
		else { [control.operation] }
	}
}

pub fn (control Control) code() int {
	return match control.mode {
		'probe-query-allowed' { 83 }
		'probe-query-denied' { 84 }
		'query-counterfactual' { 85 }
		'xattr-isolated' { 86 }
		'output-query-only' { 88 }
		else { 87 }
	}
}

pub fn (control Control) arguments() []string {
	return if control.mode == 'probe-query-denied' { [control.mode, control.operation, control.path] } else { [control.mode, control.path] }
}

fn results(control Control, actual []winequeryprobe.Result) ! {
	ops := operations(control)
	if actual.len != ops.len { return error('query result count differs') }
	for index, result in actual {
		deny := control.mode in ['probe-query-denied', 'existence-isolated'] || (control.mode in ['xattr-isolated', 'output-query-only'] && index == 1)
		if result.operation != ops[index] || result.path != control.path
			|| (if deny { !winequeryprobe.denied(result) } else { !winequeryprobe.allowed(result) }) {
			return error('query result differs')
		}
	}
}

pub fn child(mode string, operation string, path string) ! {
	control := Control{mode: mode, operation: operation, path: path}
	mut actual := []winequeryprobe.Result{}
	for op in operations(control) { actual << winequeryprobe.read(op, path)! }
	results(control, actual)!
	println(json2.encode(actual)); println('QUERY CONTROL PASS ' + mode)
	exit(control.code())
}

pub fn validate(control Control, text string) ! {
	lines := text.split_into_lines()
	if lines.len != 2 || lines[1] != 'QUERY CONTROL PASS ' + control.mode { return error('query marker differs') }
	results(control, json2.decode[[]winequeryprobe.Result](lines[0])!)!
}

pub fn baseline(control Control) ! {
	if control.mode != 'probe-query-denied' { return }
	if !winequeryprobe.allowed(winequeryprobe.read(control.operation, control.path)!) { return error('unrestricted query baseline differs') }
}

pub fn controls(directory string, object string) []Control {
	mut selected := []Control{}
	for index, path in [object, directory + '/replay/link-inputs'] {
		selected << Control{mode: 'probe-query-allowed', path: path, name: 'allowed-query-' + index.str()}
	}
	hidden := directory + '/uncaptured-object.o'
	for index, path in [hidden, directory + '/uncaptured-alias.o', '/System/Volumes/Data' + hidden,
		directory + '/unlisted-directory', directory + '/unlisted-alias', '/System/Volumes/Data' + directory + '/unlisted-directory'] {
		for op in ['exists', 'getxattr', 'listxattr'] {
			selected << Control{mode: 'probe-query-denied', operation: op, path: path, name: 'denied-query-' + index.str() + '-' + op}
		}
	}
	for mode in ['query-counterfactual', 'xattr-isolated', 'existence-isolated'] { selected << Control{mode: mode, path: hidden, name: mode} }
	for index, path in lookalikes(directory) { selected << Control{mode: 'probe-query-denied', operation: 'exists', path: path, name: 'denied-temporary-' + index.str()} }
	selected << Control{mode: 'output-query-only', path: temporary(directory), name: 'output-query-only'}
	return selected
}

pub fn files() []string {
	return ['query.json', 'attribute-fixture.json', 'metadata-policy.sb', 'existence-policy.sb', 'xattr-policy.sb',
		'replay/link-inputs/program.tmp-not-hex', 'replay/link-inputs/program.tmp00000000',
		'replay/link-inputs/program.tmp000000g', 'replay/link-inputs/program.tmp0123abc']
}
