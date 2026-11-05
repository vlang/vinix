// SPDX-License-Identifier: GPL-2.0-or-later
module compactproof

import os

fn test_compact_proof_controls() {
	run_controls(os.getenv('COMPACTPROOF_TEST_ROOT')) or { panic(err) }
}
