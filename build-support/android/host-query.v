module main

import androidhost
import os

fn main() {
	if os.args.len == 4 && os.args[1] == '--command' {
		response := androidhost.query(os.args[3]) or {
			os.write_file(os.args[2], androidhost.error_json(err)) or { panic(err) }
			return
		}
		os.write_file(os.args[2], '{"result":' + response + '}') or { panic(err) }
		return
	}
	if os.args.len == 3 && os.args[1] == '--install-query' {
		os.cp(os.executable(), os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		os.chmod(os.args[2], 0o700) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	for {
		line := os.get_raw_line()
		if line.len == 0 { break }
		response := androidhost.query(line) or {
			println(androidhost.error_json(err))
			continue
		}
		println('{"result":' + response + '}')
	}
}
