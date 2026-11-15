// SPDX-License-Identifier: GPL-2.0-or-later
// Library graph mutations are independent of linker load-trace assertions.
module main

import os
import json2
import tests.packages.winelink
import tests.packages.winesdk

fn run() ! {
	if os.args.len !in [3, 5] { return error('usage: SDK_CONTROLS ORIGINAL_HOST_BUILD FRESH_OUTPUT [SDK_CHECK ORIGINAL_HOST_BUILDER]') }
	out := os.abs_path(os.args[2])
	if os.exists(out) || os.is_link(out) { return error('fresh SDK controls required') }
	bytes := os.read_bytes(os.args[1] + '/link-inputs.tar')!
	archive := winelink.parse(bytes)!
	baseline := winesdk.graph(archive, bytes)!
	winesdk.verify_sources(baseline)!
	mut passed := []string{}
	for name in ['reexport-omission', 'alias-omission', 'source-pin', 'outside-sdk'] {
		mut members := archive.members.clone()
		prefix := 'link-inputs/' + winesdk.sdk[1..] + '/usr/lib/'
		mut expected := ''
		match name {
			'reexport-omission' { members.delete(prefix + 'system/libcache.tbd'); expected = 'SDK declared reexport stub absent or mismatched' }
			'alias-omission' { members.delete(prefix + 'libm.tbd'); expected = 'SDK direct alias identity differs' }
			'source-pin' {
				path := prefix + 'libSystem.tbd'
				members[path] = winelink.Member{...members[path], sha256: 'wrong'}
				expected = 'SDK source target or bytes differ'
			}
			'outside-sdk' { members['link-inputs/foreign/stub.tbd'] = members[prefix + 'libm.tbd']; expected = 'SDK stub member namespace differs' }
			else { return error('unknown SDK graph control') }
		}
		mut refused := false
		winesdk.graph(winelink.Archive{...archive, members: members}, bytes) or { refused = err.msg() == expected }
		if !refused { return error('SDK graph control reached wrong gate: ' + name) }
		passed << name
	}
	os.mkdir_all(out)!
	if os.args.len == 5 {
		incomplete := out + '/incomplete-host'
		os.mkdir_all(incomplete)!
		os.cp(os.args[1] + '/host-build.json', incomplete + '/host-build.json')!
		for name in ['wrong-checker', 'incomplete-host'] {
			target := out + '/' + name + '-result'
			mut child := os.new_process(os.real_path(os.args[3]))
			defer { child.close() }
			child.set_args([if name == 'wrong-checker' { '/usr/bin/true' } else { os.real_path(os.args[4]) },
				if name == 'wrong-checker' { os.real_path(os.args[1]) } else { incomplete }, target])
			child.set_redirect_stdio_merged(); child.run()
			C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
			text := child.stdout_slurp(); child.wait()
			os.write_file(out + '/' + name + '.log', text)!
			expected := if name == 'wrong-checker' { 'original format-3 host checker required' } else { 'original host admission refused:' }
			if child.code != 1 || !text.contains(expected) || os.exists(target) { return error('SDK original-admission control failed: ' + name) }
			passed << name
		}
	}
	os.write_file(out + '/result.json', json2.encode(passed) + '\n')!
	println('WINE SDK GRAPH CONTROLS PASS original graph and ' + passed.len.str() + ' exact refusals')
}

fn main() { run() or { eprintln(err); exit(1) } }
