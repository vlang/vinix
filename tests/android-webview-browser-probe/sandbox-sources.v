// SPDX-License-Identifier: GPL-2.0-or-later
// Retain the exact primary sources used by the 2026-10-26 sandbox audit.
module main

import crypto.sha256
import json2
import net.http
import os

struct SandboxSource {
	filename string
	url      string
	revision string
	sha256   string
}

fn sources() []SandboxSource {
	return [
		SandboxSource{
			filename: 'BubblewrapLauncher.cpp'
			url:      'https://raw.githubusercontent.com/WebKit/WebKit/webkitgtk-2.48.1/Source/WebKit/UIProcess/Launcher/glib/BubblewrapLauncher.cpp'
			revision: 'webkitgtk-2.48.1'
			sha256:   '7a20312e8aafb7883c83f4d3913e34a1fb91cd58c7e6320cec45864954d4d1f8'
		},
		SandboxSource{
			filename: 'bubblewrap.c'
			url:      'https://raw.githubusercontent.com/containers/bubblewrap/v0.13.0/bubblewrap.c'
			revision: 'v0.13.0'
			sha256:   '534295b804fa3f5ddeb3ae275ce5a2113d468c72ec0a74fdad6003e0a67ee4ef'
		},
	]
}

fn verify(root string) ! {
	expected := sources()
	if os.read_file(root + '/sources.json')! != json2.encode(expected, prettify: true, legacy_layout: true, escape_unicode: true, time_as_unix: true) + '\n' {
		return error('source metadata differs from the pinned audit')
	}
	mut checksums := []string{}
	for source in expected {
		data := os.read_file(root + '/' + source.filename)!
		if sha256.hexhash(data) != source.sha256 {
			return error('source checksum mismatch: ' + source.filename)
		}
		checksums << source.sha256 + '  ' + source.filename
	}
	if os.read_file(root + '/sources.sha256')! != checksums.join('\n') + '\n' {
		return error('source checksum metadata differs from the pinned audit')
	}
	println('SANDBOX-SOURCES-PASS ' + root)
}

fn fetch(root string) ! {
	if !os.is_abs_path(root) || os.exists(root) || os.is_link(root) {
		return error('a new absolute output directory is required')
	}
	os.mkdir_all(root)!
	mut checksums := []string{}
	for source in sources() {
		response := http.get(source.url)!
		if response.status_code != 200 || sha256.hexhash(response.body) != source.sha256 {
			return error('HTTP status or source checksum mismatch: ' + source.url)
		}
		os.write_file(root + '/' + source.filename, response.body)!
		checksums << source.sha256 + '  ' + source.filename
	}
	os.write_file(root + '/sources.json', json2.encode(sources(), prettify: true, legacy_layout: true, escape_unicode: true, time_as_unix: true) + '\n')!
	os.write_file(root + '/sources.sha256', checksums.join('\n') + '\n')!
	os.write_file(root + '/sandbox-sources.v', os.read_file(@FILE)!)!
	verify(root)!
}

fn run() ! {
	if os.args.len != 3 || os.args[1] !in ['fetch', 'verify'] {
		return error('usage: sandbox-sources fetch NEW_ABSOLUTE_DIRECTORY | verify DIRECTORY')
	}
	if os.args[1] == 'fetch' {
		fetch(os.args[2])!
	} else {
		verify(os.args[2])!
	}
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
