// SPDX-License-Identifier: GPL-2.0-or-later
module utilitysource
import os

fn temporary() string {
	base := if os.getenv('TMPDIR') != '' { os.getenv('TMPDIR') } else { os.temp_dir() }
	return base + '/vinix-utility-source-' + os.getpid().str()
}

fn test_materialization_preserves_bytes_and_other_entries() {
	work := temporary()
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	os.write_file_array(work + '/source', [u8(0), 255, 13, 10])!
	os.symlink('source', work + '/link')!
	os.symlink('missing', work + '/dangling')!
	os.mkdir(work + '/directory')!
	os.symlink('directory', work + '/directory-link')!
	materialize(work)!
	assert !os.is_link(work + '/link') && os.read_bytes(work + '/link')! == [u8(0), 255, 13, 10]
	assert os.is_link(work + '/dangling') && os.is_link(work + '/directory-link')
	os.write_file(work + '/source', 'changed')!
	assert os.read_bytes(work + '/link')! == [u8(0), 255, 13, 10]
}

fn test_merge_preserves_source_bodies_and_sorted_unique_imports() {
	work := temporary()
	os.mkdir_all(work + '/desktop/tools/tests')!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/desktop/tools/tests/one_test.v', 'module ui\r\nimport z\r\n// café\u2028fn one() {}\r\n')!
	os.write_file(work + '/desktop/tools/tests/two_test.v', 'module main\nimport a\nimport z\n\nfn two() {}\n')!
	merge(work, work + '/merged.v', ['one', 'two'])!
	assert os.read_file(work + '/merged.v')! == 'module main\nimport a\nimport z\n\n// café\nfn one() {}\n\n\nfn two() {}'
}
