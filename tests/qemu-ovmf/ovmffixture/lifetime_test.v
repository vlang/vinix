// SPDX-License-Identifier: GPL-2.0-only
module ovmffixture

import fixturehost
import hosttest
import os

fn test_private_context_constructor_failure_retires_created_directory() ! {
	parent := hosttest.work_dir('', 'ovmf-owned-')!
	defer { hosttest.remove_work_dir(parent) or { panic(err) } }
	previous_work := os.getenv_opt('VINIX_OVMF_WORK') or { '' }
	previous_root := os.getenv_opt('VINIX_OVMF_ROOT') or { '' }
	defer {
		if previous_work == '' { os.unsetenv('VINIX_OVMF_WORK') } else { os.setenv('VINIX_OVMF_WORK', previous_work, true) }
		if previous_root == '' { os.unsetenv('VINIX_OVMF_ROOT') } else { os.setenv('VINIX_OVMF_ROOT', previous_root, true) }
	}
	os.setenv('VINIX_OVMF_WORK', parent, true)
	os.setenv('VINIX_OVMF_ROOT', parent + '/missing-source', true)
	before := os.ls('/dev/fd')!
	context('constructor-error') or {
		assert !os.exists(parent + '/constructor-error')
		assert os.ls('/dev/fd')! == before
		return
	}
	assert false
}

fn test_independent_assertion_failure_retires_context_and_descriptors() ! {
	parent := hosttest.work_dir('', 'ovmf-assert-')!
	defer { hosttest.remove_work_dir(parent) or { panic(err) } }
	previous_work := os.getenv_opt('VINIX_OVMF_WORK') or { '' }
	previous_root := os.getenv_opt('VINIX_OVMF_ROOT') or { '' }
	defer {
		if previous_work == '' { os.unsetenv('VINIX_OVMF_WORK') } else { os.setenv('VINIX_OVMF_WORK', previous_work, true) }
		if previous_root == '' { os.unsetenv('VINIX_OVMF_ROOT') } else { os.setenv('VINIX_OVMF_ROOT', previous_root, true) }
	}
	broken := parent + '/broken-builder'
	mkdirs(broken + '/scripts')!
	mkdirs(broken + '/patches/edk2')!
	fixturehost.write(broken + '/scripts/build-qemu-ovmf-aarch64.sh', '#!/bin/bash\nexit 0\n')!
	hosttest.module_copy_file(repository() + '/' + patch_path, broken + '/' + patch_path)!
	os.setenv('VINIX_OVMF_WORK', parent, true)
	os.setenv('VINIX_OVMF_ROOT', broken, true)
	before := os.ls('/dev/fd')!
	run_case('test_incompatible_source_reports_git_diagnostic') or {
		assert err.msg().contains('Firmware fixture check failed')
		assert !os.exists(parent + '/test_incompatible_source_reports_git_diagnostic')
		assert os.ls('/dev/fd')! == before
		return
	}
	assert false
}

fn test_fixture_uris_keep_literal_filename_bytes() {
	assert file_uri('/tmp/a b\\name/中') == 'file:///tmp/a%20b%5Cname/%E4%B8%AD'
	assert file_uri('/tmp/a%?#:') == 'file:///tmp/a%25%3F%23%3A'
}
