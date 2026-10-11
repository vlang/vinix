// SPDX-License-Identifier: GPL-2.0-or-later
import verifiedhost

fn main() {
	verifiedhost.native_contracts() or {
		eprintln(err)
		exit(1)
	}
}
