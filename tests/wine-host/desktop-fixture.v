// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import json2
import desktop.packagecore

struct HostedChildReceipt {
	arguments []string
	home string
	display string
	authority string
	input string
}

fn check_hosted_literal_child() ! {
	root := os.temp_dir() + '/vinix-hosted-argv-' + os.getpid().str()
	os.mkdir(root)!
	os.chmod(root, 0o700)!
	defer { os.rmdir_all(root) or {} }
	path := root + '/fresh'
	values := ['run', 'org.example.signed-app', '/home/alex/é space; $(literal).txt', '', '--uid', '$(touch /tmp/forbidden-x11-argv)']
	child := desktop_spawn_x11_program(os.executable(), path, 900, 660, '/usr/bin/true', values, true, false, false, false) or { return error('host spawn failed') }
	assert C.write(child.input, c'ping', 4) == 4
	C.close(child.input)
	mut status := 0
	assert C.waitpid(child.pid, &status, 0) == child.pid && status == 0
	receipt := json2.decode[HostedChildReceipt](os.read_file(path+'.log')!)!
	assert receipt.arguments.len == 12
	assert receipt.arguments[1].starts_with(':') && receipt.arguments[2] == path
	assert receipt.arguments[3..] == ['900x660x24', '--package', '/usr/bin/true', ...values]
	assert receipt.home == desktop_home && receipt.display == '' && receipt.authority == ''
	assert receipt.input == 'ping'
	assert os.stat(path+'.log')!.mode & 0o777 == 0o600
	assert !os.exists('/tmp/forbidden-x11-argv')
	// Existing diagnostics are never truncated or followed and no child runs.
	os.write_file(root+'/victim', 'unchanged')!
	os.symlink(root+'/victim', root+'/blocked.log')!
	blocked := desktop_spawn_x11_program(os.executable(), root+'/blocked', 1, 1, '/usr/bin/true', values, true, false, false, false) or { return error('refusal child missing') }
	C.close(blocked.input)
	assert C.waitpid(blocked.pid, &status, 0) == blocked.pid && status == 126 << 8
	assert os.read_file(root+'/victim')! == 'unchanged'
	println('HOSTED ARGV PASS: real execve child receives literal package/document vector, private input/log and account home; ambient display/authority omitted; preexisting log refused')
}

fn check_hosted_software_boundary() ! {
	mut app := SoftwareApp{}
	if _ := app.open_hosted_package(packagecore.Request{ id: '../invalid' }) { assert false }
	assert app.hosted_app == unsafe { nil } && app.worker == unsafe { nil }
	if C.geteuid() != 0 {
		request := packagecore.Request{ id: 'org.example.editor'.clone(), document: '/home/alex/a space; $literal.txt'.clone() }
		app.open_hosted_package(request)!
		assert request.id == 'org.example.editor' && request.document == '/home/alex/a space; $literal.txt'
		unsafe { request.id.free(); request.document.free() }
		assert app.hosted_app != unsafe { nil } && app.hosted_app.package_session
		assert !app.hosted_app.portal_open
		app.hosted_app.handle('wine.open-file')!
		assert !app.hosted_app.portal_open
		app.hosted_app.key_input('\x0f')
		assert !app.hosted_app.portal_open
		app.close_hosted_package()
		assert app.hosted_app == unsafe { nil }
	}
	println('HOSTED SOFTWARE PASS: signed request validation and hosted document portal isolation; no package worker on refusal')
}

fn check_hosted_translations() {
	mut fonts := load_fonts()
	defer { free_fonts(mut fonts) }
	for key in ['wine.package.starting', 'wine.package.missing', 'wine.package.exited', 'wine.package.back'] {
		for language in desktop_languages {
			text := desktop_translations[language.code()][key]
			assert text.len > 0, '${language.code()} lacks ${key}'
			for point in text.runes() {
				if point in [` `, `\n`, `\t`, `\r`] { continue }
				for face in fonts {
					glyph := face.glyph_for(u32(point))
					assert glyph.width > 0 && glyph.height > 0, '${language.code()} ${key}: no glyph for ${point}'
				}
			}
		}
	}
	println('HOSTED I18N PASS: four explicit keys in all six languages render with every bundled font')
}

fn main() {
	if os.args.len >= 6 && os.args[4] == '--package' {
		mut bytes := [4]u8{}
		n := C.read(0, &bytes[0], 4)
		assert n == 4
		println(json2.encode(HostedChildReceipt{ arguments: os.args, home: os.getenv('HOME'),
			display: os.getenv('DISPLAY'), authority: os.getenv('XAUTHORITY'), input: bytes[..4].bytestr() }))
		return
	}
	os.setenv('DISPLAY', ':ambient', true)
	os.setenv('XAUTHORITY', '/ambient/secret', true)
	check_hosted_literal_child() or { eprintln(err); exit(1) }
	check_hosted_software_boundary() or { eprintln(err); exit(1) }
	check_hosted_translations()
}
