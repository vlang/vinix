// SPDX-License-Identifier: GPL-2.0-or-later
import storagehost

fn main() {
	storagehost.run() or {
		eprintln(err.msg())
		exit(1)
	}
}
