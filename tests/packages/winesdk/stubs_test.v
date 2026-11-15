// SPDX-License-Identifier: GPL-2.0-or-later
module winesdk

fn require(ok bool) { if !ok { panic('SDK declaration control failed') } }

const fixture = "--- !tapi-tbd\ntbd-version: 4\ntargets: [ arm64-macos, x86_64-macos ]\ninstall-name: '/usr/lib/libSystem.B.dylib'\nreexported-libraries:\n  - targets: [ arm64-macos ]\n    libraries: [ '/usr/lib/system/liba.dylib',\n                 '/usr/lib/system/libb.dylib' ]\nexports:\n  - targets: [ arm64-macos ]\n    symbols: [ _example ]\n...\n"

fn test_conservative_target_union_and_inline_documents() {
	docs := documents(fixture)!
	require(docs.len == 1 && docs[0].name == '/usr/lib/libSystem.B.dylib'
		&& docs[0].reexports == ['/usr/lib/system/liba.dylib', '/usr/lib/system/libb.dylib'])
	second := "--- !tapi-tbd\ntbd-version: 4\ntargets: [ x86_64-macos ]\ninstall-name: '/usr/lib/system/liba.dylib'\n...\n"
	require(documents(fixture.replace('...\n', second))!.len == 2)
	multiple := fixture.replace('exports:\n', "  - targets: [ x86_64-macos ]\n    libraries: [ '/usr/lib/system/libc.dylib' ]\nexports:\n")
	require(documents(multiple)![0].reexports == ['/usr/lib/system/liba.dylib', '/usr/lib/system/libb.dylib', '/usr/lib/system/libc.dylib'])
}

fn test_unsupported_and_ambiguous_declarations_refuse_in_production() {
	for bad in [fixture.replace('tbd-version: 4', 'tbd-version: 5'),
		fixture.replace('targets: [ arm64-macos, x86_64-macos ]', 'targets: []'),
		fixture.replace('tbd-version: 4', 'tbd-version: 4\ntbd-version: 4'),
		fixture.replace('reexported-libraries:', 'unknown-libraries:'),
		fixture.replace("'/usr/lib/system/liba.dylib'", "'/usr/lib/../liba.dylib'"),
		fixture.replace("'/usr/lib/system/libb.dylib'", "'/usr/lib/system/liba.dylib'"),
		fixture.replace('    libraries:', '    paths:'), fixture.replace('...\n', ''),
		fixture.replace('\n', '\r\n'), fixture + '\x00',
		fixture.replace('exports:\n', 'exports:\n    libraries: [ bad ]\n'),
		fixture.replace('...\n', fixture)] {
		mut refused := false
		documents(bad) or { refused = true }
		require(refused)
	}
}
