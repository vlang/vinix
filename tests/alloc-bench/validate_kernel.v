module main

import kernelcompare
import os
import strings

fn main() {
	if os.args.len != 3 {
		eprintln('usage: validate-kernel LOG PLATFORM')
		exit(2)
	}
	text := input_text(os.args[1]) or {
		eprintln(err.msg())
		exit(2)
	}
	kernelcompare.parse_log(kernelcompare.log_text(text), os.args[2]) or {
		eprintln(err.msg())
		exit(2)
	}
}

fn input_text(path string) !string {
	if path != '--stdin' { return os.read_file(path) }
	mut output := strings.new_builder(4096)
	for {
		text, count := os.fd_read(0, 65536)
		if count == 0 { break }
		if count < 0 {
			if os.last_error().code() == 4 { continue }
			return error('cannot read validation input')
		}
		output.write_string(text)
	}
	return output.str()
}
