// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

fn test_sparse_disk_capacity_and_blockcount_limits() {
	assert filesystem_blocks('1024,4096,1024') or { panic(err) } == [1024, 4096, 1024]
	for text in ['', '512', '1024,', 'x', '4096,8192'] {
		if _ := filesystem_blocks(text) { assert false } else { assert err.code() == 2 }
	}
	filesystem_sparse_stat('Size: 17247252480\nBlockcount: 127\n', 1024) or { panic(err) }
	filesystem_sparse_stat('Size: 4402345721856\nBlockcount: 511\n', 4096) or { panic(err) }
	for pair in [['Size: 17247252480\nBlockcount: 128\n', '1024'],
		['Size: 4402345721856\nBlockcount: 512\n', '4096'], ['Size: 1\nBlockcount: 1\n', '1024'],
		['Size: 17247252480\nBlockcount: nope\n', '1024']] {
		if _ := filesystem_sparse_stat(pair[0], pair[1].int()) { assert false } else { assert err.msg() != '' }
	}
}
