// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

// Embedded modules and assertions are the independent original V fixtures.
// Keep the two phases around Python's metadata-preserving production copies.
fn stubs(work string) ! {
	names := ['stat/stat.v', 'errno/errno.v', 'klock/klock.v', 'resource/stub.v',
		'security/level.v']
	contents := [$embed_file('hosttemplates/stat/stat.v').to_string(),
		$embed_file('hosttemplates/errno/errno.v').to_string(),
		$embed_file('hosttemplates/klock/klock.v').to_string(),
		$embed_file('hosttemplates/resource/stub.v').to_string(),
		$embed_file('hosttemplates/security/level.v').to_string()]
	for i, name in names {
		target := os.join_path(work, name)
		os.mkdir_all(os.dir(target))!
		mut content := contents[i]
		if name in ['klock/klock.v', 'resource/stub.v'] {
			module_name := name.split('/')[0]
			content = content.replace('module ' + module_name,
				'module ' + module_name + '\n#flag -I' + work + '\n#include "host.h"')
		}
		os.write_file(target, content)!
	}
}

fn finish(work string) ! {
	content := $embed_file('hosttemplates/main.v').to_string()
	os.write_file(os.join_path(work, 'main.v'), content.replace('module main',
		'module main\n#flag -I' + work + '\n#include "host.h"'))!
	os.write_file(os.join_path(work, 'v.mod'), "Module { name: 'blockpolicy_host' }\n")!
}

fn main() {
	if os.args.len != 3 {
		eprintln('Usage: host-generator --install DEST | --stubs WORK | --finish WORK')
		exit(2)
	}
	match os.args[1] {
		'--install' {
			os.cp(os.executable(), os.args[2]) or { eprintln(err); exit(1) }
			os.chmod(os.args[2], 0o700) or { eprintln(err); exit(1) }
		}
		'--stubs' { stubs(os.args[2]) or { eprintln(err); exit(1) } }
		'--finish' { finish(os.args[2]) or { eprintln(err); exit(1) } }
		else { eprintln('Unknown generator phase: ' + os.args[1]); exit(2) }
	}
}
