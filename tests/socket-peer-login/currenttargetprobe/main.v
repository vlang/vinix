// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

fn main() {
	if sha256.hexhash('abc') != 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' {
		panic('private SHA256 result differs')
	}
	value := json2.decode[map[string]string]('{"private":"none-gc"}') or { panic(err) }
	if value['private'] != 'none-gc' { panic('private JSON decoder result differs') }
	if os.getenv('SDKROOT') != '/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk' {
		panic('canonical SDK environment differs')
	}
	if os.getenv('VEXE') != '/Users/alex/Library/Caches/vinix-codex/section14/current-target-v-2f91-20261105-01/toolchain/v' {
		panic('private compiler environment differs')
	}
	println('CURRENT TARGET PRIVATE STDLIB PASS')
}
