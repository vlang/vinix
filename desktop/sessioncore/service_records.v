// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

pub fn (s &Supervisor) encode() string {
	mut w := Writer{}
	w.add('vinix-services\t1\n')
	for i in 0 .. s.count {
		v := s.services[i]
		w.add('service\t')
		w.field(v.name.str())
		w.add('\t')
		w.field(v.executable.str())
		for n in [i64(v.dependencies), i64(v.restart), i64(v.restart_limit), v.restart_delay_ms,
			v.stop_timeout_ms, i64(int(v.enabled)), i64(int(v.system))]! {
			w.add('\t')
			w.number(n)
		}
		for a in 0 .. v.argument_count {
			w.add('\t')
			w.field(v.arguments[a].str())
		}
		w.add('\n')
	}
	return w.finish()
}

pub fn decode_services(record string, allow_system bool) !Supervisor {
	if record.len == 0 || record.len > 64 * 1024 { return error('invalid service record size') }
	mut s := Supervisor{}
	mut start := 0
	mut header := false
	for end in 0 .. record.len + 1 {
		if end < record.len && record[end] != `\n` { continue }
		if end == start {
			start = end + 1
			continue
		}
		f := fields(unsafe { tos(&record.str[start], end - start) })!
		start = end + 1
		if !header {
			if f.count != 2 || f.values[0] != 'vinix-services' || f.values[1] != '1' {
				return error('invalid service header')
			}
			header = true
			continue
		}
		if f.values[0] != 'service' || f.count < 10 || f.count > 26 || s.count == max_services {
			return error('invalid service row')
		}
		mut v := Service{ name: unfield(f.values[1])!, executable: unfield(f.values[2])!, dependencies: u32(number(f.values[3], 0, 4294967295)!), restart: unsafe { Restart(number(f.values[4], 0, 2)!) }, restart_limit: int(number(f.values[5], 0, 100)!), restart_delay_ms: number(f.values[6], 100, 60000)!, stop_timeout_ms: number(f.values[7], 100, 60000)!, enabled: number(f.values[8], 0, 1)! != 0, system: number(f.values[9], 0, 1)! != 0 }
		if v.system && !allow_system {
			return error('user configuration cannot define system services')
		}
		v.argument_count = f.count - 10
		for i in 0 .. v.argument_count { v.arguments[i] = unfield(f.values[i + 10])! }
		s.services[s.count] = v
		s.count++
	}
	if !header { return error('missing service header') }
	s.validate()!
	return s
}
