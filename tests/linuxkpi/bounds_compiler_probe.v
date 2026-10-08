// SPDX-License-Identifier: GPL-2.0-or-later
// Owned native fixture: run real Clang, then change one private compiler input.
module main

import os
import json2

fn main() {
	if os.args.len < 3 {
		eprintln('Compiler probe requires a mode and configuration')
		exit(1)
	}
	mode := os.args[1]
	configuration := json2.decode[map[string]json2.Any](os.read_file(os.args[2]) or {
		eprintln(err)
		exit(1)
	}) or {
		eprintln(err)
		exit(1)
	}
	command := (configuration['command'] or {
		eprintln('Missing compiler argv')
		exit(1)
	}).as_array().map(it.str())
	if command.len == 0 {
		eprintln('Empty compiler argv')
		exit(1)
	}
	mut child := os.new_process(command[0])
	child.set_args([...command[1..], ...os.args[3..]])
	defer { child.close() }
	child.run()
	if child.pid <= 0 {
		eprintln('Cannot start real compiler')
		exit(1)
	}
	child.wait()
	marker := (configuration['marker'] or {
		eprintln('Missing mutation marker')
		exit(1)
	}).str()
	if child.code == 0 && '-E' in os.args[3..] && !os.exists(marker) {
		if mode == 'profile' {
			header := (configuration['header'] or {
				eprintln('Missing owned header')
				exit(1)
			}).str()
			original := os.read_file(header) or {
				eprintln(err)
				exit(1)
			}
			changed := original.replace('#define CONFIG_NR_CPUS 256', '#define CONFIG_NR_CPUS 64')
			if changed == original {
				eprintln('Owned profile did not change')
				exit(1)
			}
			os.write_file(header, changed) or {
				eprintln(err)
				exit(1)
			}
			os.write_file(marker, 'real discovery completed before change\n') or {
				eprintln(err)
				exit(1)
			}
		} else if mode == 'compiler' {
			// Replace our owned executable rather than writing an executing inode.
			// The generator must reject its changed bytes before launching it again.
			path := os.real_path(os.executable())
			mut changed := os.read_bytes(path) or {
				eprintln(err)
				exit(1)
			}
			changed << '\nchanged compiler input\n'.bytes()
			replacement := path + '.replacement'
			os.write_file_array(replacement, changed) or {
				eprintln(err)
				exit(1)
			}
			os.chmod(replacement, 0o755) or {
				eprintln(err)
				exit(1)
			}
			os.mv(replacement, path) or {
				eprintln(err)
				exit(1)
			}
			os.write_file(marker, 'real discovery completed before compiler change\n') or {
				eprintln(err)
				exit(1)
			}
		} else {
			eprintln('Unknown mutation mode')
			exit(1)
		}
	}
	exit(child.code)
}
