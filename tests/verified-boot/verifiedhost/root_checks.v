// SPDX-License-Identifier: GPL-2.0-or-later
module verifiedhost

import bundlehost as bh
import hosttest
import os
import verityimage

fn fixture(path string, blocks int) ! {
	mut stream := os.create(path)!
	defer { stream.close() }
	mut block := []u8{len: 4096}
	for index in 0 .. blocks {
		for byte in 0 .. 4096 { block[byte] = u8(u64(index) >> ((byte % 8) * 8)) }
		mut offset := 0
		for offset < block.len {
			n := stream.write(block[offset..])!
			if n <= 0 { return error('Fixture write stopped') }
			offset += n
		}
	}
}

fn root_test(args []string) ! {
	parsed := bh.parse(args, options(['--veritysetup']), [], 0, 'Usage: test [--veritysetup actual-cryptsetup-executable]')!
	bh.run([bh.root() + '/build-support/run-v-tool.sh',
		bh.root() + '/tools/verified-root/verityimage/core_test.v'])!
	if !parsed.has('--veritysetup') {
		println('Linux compatibility skipped: supply an actual --veritysetup executable.')
		return
	}
	work := temporary('vinix-veritysetup-')!
	defer { bh.retire(work) }
	executable := parsed.value('--veritysetup', '')
	for blocks in [1, 2, 128, 129, 16384, 16385] {
		fixture(work + '/data', blocks)!
		metadata := verityimage.build(work + '/data', work + '/vinix', false)!
		os.cp(work + '/data', work + '/linux')!
		flags := ['--no-superblock', '--format=1', '--hash=sha256', '--salt=-', '--data-block-size=4096',
			'--hash-block-size=4096', '--data-blocks=' + blocks.str(),
			'--hash-offset=' + (blocks * 4096).str()]
		output := bh.capture(joined([executable, 'format'], flags, [work + '/linux', work + '/linux']))!
		roots := output.split('\n').filter(it.starts_with('Root hash:')).map(it.all_after(':').trim_space())
		if roots.len != 1 || roots[0] != metadata.root_hash {
			return error('Linux root hash mismatch for ' + blocks.str() + ' blocks: ' + output)
		}
		if hosttest.file_digest(work + '/linux')! != hosttest.file_digest(work + '/vinix')! {
			return error('Linux hash tree differs for ' + blocks.str() + ' blocks')
		}
		bh.run(joined([executable, 'verify'], flags, [work + '/vinix', work + '/vinix',
			metadata.root_hash]))!
		os.rm(work + '/vinix')!
		println('PASS real Linux veritysetup: ' + blocks.str() + ' blocks, matching complete tree and root')
	}
}
