// SPDX-License-Identifier: MIT
import asahiuapi
import os

fn main() {
	if os.args.len != 4 || os.args[1] !in ['generate', 'check', 'oracle'] {
		eprintln('usage: generate_asahi_uapi generate|check|oracle HEADER OUTPUT')
		exit(2)
	}
	header := os.read_file(os.args[2])!
	generated := if os.args[1] == 'oracle' {
		asahiuapi.oracle(header)!
	} else {
		asahiuapi.generate(header)!
	}
	if os.args[1] == 'check' {
		if os.read_file(os.args[3])! != generated {
			eprintln('Asahi UAPI definitions differ from reference')
			exit(1)
		}
		println('Asahi UAPI definitions match reference')
	} else {
		os.write_file(os.args[3], generated)!
	}
}
