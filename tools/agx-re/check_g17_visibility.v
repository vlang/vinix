// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import encoding.hex
import g17decode as arm
import g17expr
import os
import traceanalysis as j

fn main() {
	if os.args.len != 2 {
		eprintln('usage: v run tools/agx-re/check_g17_visibility.v AGXG17X.macho')
		exit(2)
	}
	data := os.read_bytes(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
	result := g17expr.recover_render_visibility(data) or {
		eprintln(err)
		exit(1)
	}
	mut report := result.as_map().clone()
	hash := sha256.sum(data)
	report['schema'] = j.Value(1)
	report['driver_uuid'] = j.Value(arm.driver_uuid)
	report['driver_sha256'] = j.Value(hex.encode(hash[..]))
	println(j.encode(j.Value(report), true))
}
