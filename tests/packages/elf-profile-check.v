// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tests.packages.elffixture

fn invoke(cli string, args []string) !(int, string) {
	mut process := os.new_process(cli)
	process.set_args(args)
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	return code, output
}

fn command(profile string, roots string, destination string) []string {
	return if profile == 'native' { ['native-catalog', '1.0.0', roots, destination] }
		else { ['sqlite-catalog', '3.53.4', '1.0.0', roots, destination] }
}

fn prepare(profile string, roots string) ! {
	for architecture in ['aarch64', 'x86_64'] {
		root := roots + '/' + architecture
		for directory in ['bin', 'lib', 'licenses'] { os.mkdir_all(root + '/' + directory)! }
		files := if profile == 'native' { {'bin/package-hello': 'static', 'bin/counter': 'static', 'bin/memo': 'static'} }
			else { {'bin/sqlite3': 'pie', 'bin/vinix-linux-runner': 'static', 'lib/libc.so': 'shared', 'lib/libsqlite3.so.0': 'shared'} }
		for path, kind in files {
			os.write_file_array(root + '/' + path, elffixture.image(architecture, kind))!
			os.chmod(root + '/' + path, 0o755)!
		}
		notices := if profile == 'native' { ['application-sdk-MIT.txt', 'v-MIT.txt', 'musl-MIT.txt'] }
			else { ['sqlite-COPYRIGHT', 'musl-COPYRIGHT', 'vinix-COPYING'] }
		for name in notices { os.write_file(root + '/licenses/' + name, 'structural fixture notice ' + name)! }
	}
}

fn check() ! {
	if os.args.len !in [3, 4] || (os.args.len == 4 && os.args[3] != '--before') {
		return error('usage: elf-profile-check CLI NEW_WORK_DIRECTORY [--before]')
	}
	cli := os.real_path(os.args[1])
	work := os.abs_path(os.args[2])
	before := os.args.len == 4
	if os.exists(work) || os.is_link(work) { return error('qualification work directory must be new') }
	os.mkdir(work)!
	mut cases := 0
	for profile in ['native', 'sqlite'] {
		roots := work + '/' + profile + '/roots'
		prepare(profile, roots)!
		baseline := work + '/' + profile + '/baseline'
		code, output := invoke(cli, command(profile, roots, baseline))!
		assert code == 0, output
		canonical := os.read_file(baseline + '/catalog.json')!
		println('PASS ${profile} valid structural fixtures')
		for architecture in ['aarch64', 'x86_64'] {
			kind := if profile == 'native' { 'static' } else { 'pie' }
			path := roots + '/' + architecture + if profile == 'native' { '/bin/memo' } else { '/bin/sqlite3' }
			original := os.read_bytes(path)!
			fields := if profile == 'native' { ['no-load', 'outside-entry', 'truncated-load', 'invalid-alignment', 'invalid-header-size'] }
				else { ['empty-interpreter', 'relative-interpreter', 'unterminated-interpreter', 'embedded-nul', 'duplicate-interpreter'] }
			for field in fields {
				mut bytes := elffixture.image(architecture, kind)
				match field {
					'no-load' { bytes[64] = 4 }
					'outside-entry' { elffixture.put(mut bytes, 24, 0x200000) }
					'truncated-load' { elffixture.put(mut bytes, 96, u64(bytes.len + 1)) }
					'invalid-alignment' { elffixture.put(mut bytes, 112, 3) }
					'invalid-header-size' { bytes[52] = 0 }
					'empty-interpreter' { elffixture.put(mut bytes, 152, 0) }
					'relative-interpreter' { bytes[320] = `l` }
					'unterminated-interpreter' { bytes[320 + int(bytes[152]) - 1] = `x` }
					'embedded-nul' { bytes[321] = 0 }
					'duplicate-interpreter' { bytes[56] = 3; for i in 0 .. 56 { bytes[176 + i] = bytes[120 + i] } }
					else { return error('unknown fixture mutation') }
				}
				os.write_file_array(path, bytes)!
				destination := work + '/' + profile + '/' + architecture + '-' + field
				status, diagnostic := invoke(cli, command(profile, roots, destination))!
				assert status == if before { 0 } else { 1 }, diagnostic
				assert os.exists(destination) == before
				assert os.ls(os.dir(roots))!.all(!it.starts_with('.vinix-'))
				println('${profile}/${architecture}/${field}: exit=${status} published=${before}')
				if !before {
					assert diagnostic.contains('ELF profile'), diagnostic
					println(diagnostic.trim_space())
				}
				os.write_file_array(path, original)!
				if !before {
					retry_code, retry_output := invoke(cli, command(profile, roots, destination))!
					assert retry_code == 0, retry_output
					assert os.read_file(destination + '/catalog.json')! == canonical
					println('PASS restored exact lock at refused destination')
				}
				cases += 1
			}
		}
	}
	println('PASS ${cases} malformed ELF cases (${if before { 'before-change admission' } else { 'refusal, cleanup and restored retry' }})')
}

fn main() { check() or { eprintln(err); exit(1) } }
