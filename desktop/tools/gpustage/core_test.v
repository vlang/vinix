// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gpustage
import os
import sourcecommand
fn test_bad_options_fail_without_staging() {
	work := sourcecommand.temporary('vinix-gpu-options')!
	defer { os.rmdir_all(work) or {} }
	for args in [[work + '/never-created', '--unknown'], [work + '/never-created', '--v'], []string{}] {
		assert cli(args) == 2
		assert !os.exists(work + '/never-created')
	}
}
