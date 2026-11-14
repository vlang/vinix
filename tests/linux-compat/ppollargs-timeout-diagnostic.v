// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the selecttimeout oracle while recording values behind a refusal.
module main

import os

fn run() ! {
	if os.args.len != 3 { return error('Usage: ppollargs-timeout-diagnostic REPOSITORY FRESH-OUTPUT-ROOT') }
	repo := os.real_path(os.args[1])
	root := os.args[2]
	if os.exists(root) { return error('Fresh output root required') }
	for module_name in ['selecttimeoutfixture','selecttimeoutreferenceinit'] {
		os.mkdir_all(root+'/tests/linux-compat/'+module_name)!
		for source in os.walk_ext(repo+'/tests/linux-compat/'+module_name,'.v') {
			mut text := os.read_file(source)!
			if module_name == 'selecttimeoutfixture' && os.file_name(source) == 'core.v' {
				anchor := 'check(mut total,time_good,7,report)'
				if text.count(anchor) != 1 { return error('Ambiguous timeout diagnostic anchor') }
				text = text.replace(anchor,"if !time_good && report { C.printf(c'TIMEOUT DIAGNOSTIC: uid=%u api=%d mode=%d readonly=%d original=%ld/%ld actual=%ld/%ld start=%ld/%ld stop=%ld/%ld\\n',C.getuid(),api,mode,readonly,original.tv_sec,original.tv_nsec,timer.value.tv_sec,timer.value.tv_nsec,started.tv_sec,started.tv_nsec,stopped.tv_sec,stopped.tv_nsec) }\n\t\t"+anchor)
			}
			os.write_file(root+'/tests/linux-compat/'+module_name+'/'+os.file_name(source),text)!
		}
	}
}
fn main() { run() or { eprintln(err.msg()); exit(1) } }
