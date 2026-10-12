// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidhost as ah
import androidtools
import boothost
import os

fn qualify(work string) ! {
	os.mkdir(work)!
	path := work + '/fonts.xml'
	for source in ['<familyset><family><font>Roboto.ttf</font></family></familyset>', '<familyset><family/><family><font>Roboto.ttf</font></family></familyset>', '<familyset><family><font><![CDATA[Roboto.ttf]]></font></family></familyset>', '<familyset><family><font>Ro<!-- ignored -->boto.ttf</font></family></familyset>', '<familyset xmlns:android="urn:android"><family><font>Roboto.ttf</font></family></familyset>'] {
		os.write_file(path, source)!
		androidtools.validate_fonts(path)!
	}
	for source in ['<familyset><family><font>\u0085\u00a0\u2009</font></family></familyset>', '<familyset><family/></familyset>', '<wrong><family><font>Roboto.ttf</font></family></wrong>', '<familyset xmlns="urn:other"><family><font>Roboto.ttf</font></family></familyset>', '<familyset><family><font><nested>Roboto.ttf</nested></font></family></familyset>', '<familyset><family><font>malformed</family></familyset>'] {
		os.write_file(path, source)!
		mut refused := false
		androidtools.validate_fonts(path) or { refused = true }
		assert refused, source
	}
	art := ah.Value({'androidfw_configuration_api': ah.Value(1), 'patch_sha256': ah.Value('patch'), 'files': ah.Value([ah.Value({'path': ah.Value('usr/include/androidfw/androidfw_c_api.h'), 'sha256': ah.Value('header')}), ah.Value({'path': ah.Value('usr/lib/art/libandroidfw.so'), 'sha256': ah.Value('library')})])})
	atl := ah.Value({'androidfw_configuration_api': ah.Value(ah.Number{'1.0'}), 'androidfw_patch_sha256': ah.Value('patch'), 'androidfw_header_sha256': ah.Value('header'), 'androidfw_library_sha256': ah.Value('library')})
	androidtools.validate_art_pair(art, atl)!
	assert boothost.receipt_equal(ah.Value(1), ah.Value(true))
	assert !boothost.receipt_equal(ah.Value('1'), ah.Value(1))
	for key in ['androidfw_configuration_api', 'androidfw_patch_sha256', 'androidfw_header_sha256', 'androidfw_library_sha256'] {
		mut altered := atl.object().clone()
		altered[key] = 'independent mismatch'
		mut refused := false
		androidtools.validate_art_pair(art, ah.Value(altered)) or { refused = true }
		assert refused, key
	}
	os.write_file(work + '/passed', 'PASS\n')!
	println('NATIVE OVERLAY METADATA / original direct font path and first-match policy / XML, namespace and Unicode whitespace failures / numeric source receipts / independent ART header, provider, API and patch mismatches: PASS')
	flush_stdout()
}

fn main() {
	if os.args.len != 2 { eprintln('usage: test-manifests NEW_STATE'); exit(2) }
	qualify(os.args[1]) or { eprintln(err); exit(1) }
}
