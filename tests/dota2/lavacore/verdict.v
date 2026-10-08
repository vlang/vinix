// SPDX-License-Identifier: GPL-2.0-or-later
module lavacore

import androidhost as ah
import gapcore as gc

fn nullable_int(match_id string, group int) !string {
	if truth(match_id)! { return call('builtins.int', o(get(match_id, n(group))!))! }
	return null_id()!
}
fn passed(row string) !bool {
	return eq(get(row, s('exit_code'))!, n(0))! && eq(get(row, s('signal'))!, n(0))!
		&& !truth(get(row, s('native_watchdog'))!)! && truth(get(row, s('probe_passed'))!)!
		&& eq(get(row, s('stored'))!, v(ah.Value([ah.Value('00000000'), ah.Value('00000000'), ah.Value('56494e58')])))!
}
fn crashed(row string) !bool {
	return eq(get(row, s('exit_code'))!, n(-1))! && eq(get(row, s('signal'))!, n(11))!
		&& !truth(get(row, s('native_watchdog'))!)! && !truth(get(row, s('probe_passed'))!)!
}
fn verdict(transcript_arg string, status string, drivers string) !string {
	transcript := method(transcript_arg, 'replace', [s('\r'), s('')], {})!
	begins := call('builtins.list', o(call('re.finditer',
		s('VINIX-DOTA2-LVP-PAIR-BEGIN: driver=([a-z0-9-]+) mode=([a-z-]+)\n'), o(transcript))!))!
	end_id := method(transcript, 'find', [s('VINIX-DOTA2-LVP-PAIR-END')], {})!
	end := gc.integer(data(end_id)!)
	planned := list()!
	driver_iter := iter(drivers)!
	for {
		driver := next(driver_iter)!
		if driver.done { break }
		modes := iter(call('MODES')!)!
		for {
			mode := next(modes)!
			if mode.done { break }
			append(planned, o(pair(driver.id, mode.id)!))!
		}
	}
	actual := list()!
	bi := iter(begins)!
	for {
		row := next(bi)!
		if row.done { break }
		append(actual, o(method(row.id, 'groups', [], {})!))!
	}
	ordered := eq(actual, o(planned))! && end > 0
	observations := list()!
	count := gc.integer(gc.call('builtins.len', o(begins))!)
	for index in 0 .. count {
		begin := get(begins, n(index))!
		stop := if index + 1 < count {
			gc.integer(gc.method(get(begins, n(index + 1))!, 'start', [], {}, 'value')!)
		} else if end > 0 { end } else { gc.integer(gc.call('builtins.len', o(transcript))!) }
		start := gc.integer(gc.method(begin, 'end', [], {}, 'value')!)
		section := get(transcript, o(call('builtins.slice', n(start), n(stop))!))!
		groups := method(begin, 'groups', [], {})!
		driver, mode := get(groups, n(0))!, get(groups, n(1))!
		driver_text, mode_text := format(driver)!, format(mode)!
		result := call('re.search',
			s('VINIX-DOTA2-LVP-PAIR-RESULT: driver=' + driver_text + ' mode=' + mode_text + r' exit=(-?\d+) signal=(\d+) watchdog=(\d+)'),
			o(section))!
		values := call('re.search',
			s('VINIX-DOTA2-LVP-RESULT: mode=' + mode_text + ' set0=([0-9a-f]{8}) set1=([0-9a-f]{8}) set2=([0-9a-f]{8})'),
			o(section))!
		row := dict()!
		set(row, 'driver', o(driver))!
		set(row, 'mode', o(mode))!
		set(row, 'exit_code', o(nullable_int(result, 1)!))!
		set(row, 'signal', o(nullable_int(result, 2)!))!
		set(row, 'native_watchdog', o(nullable_int(result, 3)!))!
		stored := if truth(values)! { call('builtins.list', o(method(values, 'groups', [], {})!))! } else { null_id()! }
		set(row, 'stored', o(stored))!
		set(row, 'probe_passed', o(call('operator.contains', o(section), s('VINIX-DOTA2-LVP-PASS: ' + mode_text + '\n'))!))!
		append(observations, o(row))!
	}
	mut controls := ordered
	mut fixed := ordered
	if controls {
		rows := iter(observations)!
		for {
			row := next(rows)!
			if row.done { break }
			if eq(get(row.id, s('driver'))!, s('fixed'))! { continue }
			ok := if eq(get(row.id, s('mode'))!, s('bound'))! { passed(row.id)! } else { crashed(row.id)! }
			if !ok { controls = false; break }
		}
	}
	if fixed {
		rows := iter(observations)!
		for {
			row := next(rows)!
			if row.done { break }
			if !eq(get(row.id, s('driver'))!, s('fixed'))! { continue }
			if !passed(row.id)! { fixed = false; break }
		}
	}
	completed := eq(status, n(0))! && ordered
	report := dict()!
	set(report, 'passed', v(ah.Value(completed && controls && fixed)))!
	set(report, 'pair_completed', v(ah.Value(completed)))!
	set(report, 'controls_reproduced', v(ah.Value(controls)))!
	set(report, 'fixed_passed', v(ah.Value(fixed)))!
	set(report, 'observations', o(observations))!
	return report
}
