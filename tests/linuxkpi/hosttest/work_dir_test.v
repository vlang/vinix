// SPDX-License-Identifier: GPL-2.0-or-later
module hosttest

import os

fn test_work_dir_kept_unix_literal_paths_and_retirement() {
	work := work_dir('', 'vinix-work-dir-test-') or { panic(err) }
	defer { remove_work_dir(work) or { panic(err) } }
	output := work + '/literal\\parent/new\\output'
	assert work_dir(output, 'unused-') or { panic(err) } == module_resolve(output) or { panic(err) }
	assert os.is_dir(output)
	assert !os.exists(work + '/literal/parent')
	os.mkdir(output + '/nested\\name') or { panic(err) }
	os.write_file(output + '/nested\\name/file\\name', 'owned') or { panic(err) }
	outside := work + '/protected'
	os.mkdir(outside) or { panic(err) }
	os.write_file(outside + '/keep', 'outside') or { panic(err) }
	os.symlink(outside, output + '/outside\\link') or { panic(err) }
	os.chmod(output + '/nested\\name', 0o500) or { panic(err) }
	remove_work_dir(output) or { panic(err) }
	assert !os.exists(output)
	assert os.read_file(outside + '/keep') or { panic(err) } == 'outside'
	link := work + '/root\\link'
	os.symlink(outside, link) or { panic(err) }
	remove_work_dir(link) or { panic(err) }
	assert !os.is_link(link)
	assert os.read_file(outside + '/keep') or { panic(err) } == 'outside'
}

fn test_work_dir_resolves_links_before_parent_components() {
	work := work_dir('', 'vinix-work-dir-test-') or { panic(err) }
	defer { remove_work_dir(work) or { panic(err) } }
	os.mkdir(work + '/target') or { panic(err) }
	os.mkdir(work + '/target/inside') or { panic(err) }
	os.symlink('target/inside', work + '/link') or { panic(err) }
	output := work_dir(work + '/link/../new\\output', '') or { panic(err) }
	assert output == module_resolve(work + '/target/new\\output') or { panic(err) }
	assert os.is_dir(output)
	assert !os.exists(work + '/new\\output')
}

fn test_work_dir_existing_output_remains_untouched() {
	work := work_dir('', 'vinix-work-dir-test-') or { panic(err) }
	defer { remove_work_dir(work) or { panic(err) } }
	output := work + '/existing\\output'
	os.write_file(output, 'retained') or { panic(err) }
	work_dir(output, '') or {
		assert err.msg() == 'Output directory already exists: ' + module_resolve(output) or { panic(err) }
		assert os.read_file(output) or { panic(err) } == 'retained'
		return
	}
	assert false
}

fn test_work_dir_temporary_prefix_preserves_literal_backslashes() {
	work := work_dir('', 'vinix-work\\literal-') or { panic(err) }
	defer { remove_work_dir(work) or { panic(err) } }
	assert work.all_after_last('/').starts_with('vinix-work\\literal-')
	os.write_file(work + '/literal\\child', 'scratch') or { panic(err) }
}

fn test_work_dir_temporary_prefix_rejects_embedded_null() {
	work_dir('', 'vinix-invalid\x00prefix-') or {
		assert err.msg() == 'embedded null byte'
		return
	}
	assert false
}
