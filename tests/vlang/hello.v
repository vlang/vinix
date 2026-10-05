// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

fn main() {
	$if tinyc {
		println('V runs natively on Vinix')
	} $else {
		eprintln('V did not use Alpine TCC')
		exit(1)
	}
}
