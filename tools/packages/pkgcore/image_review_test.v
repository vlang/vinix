// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

fn test_iso_review_retires_first_plan_when_second_write_fails() {
	work := os.real_path(os.temp_dir()) + '/vinix-review-pair-' + os.getpid().str()
	os.mkdir(work, mode: 0o700)!
	defer { os.rmdir_all(work) or {} }
	target := work + '/reviewed'
	mut refused := false
	write_iso_package_review_pair(target, 'first\n', 'x'.repeat(max_metadata + 1)) or {
		assert err.msg().contains('metadata exceeds its size limit')
		refused = true
	}
	assert refused && os.ls(work)!.len == 0
	write_iso_package_review_pair(target, 'first\n', 'second\n')!
	assert os.read_file(target + '/amd64.json')! == 'first\n'
	assert os.read_file(target + '/arm64.json')! == 'second\n'
}
