import os
import json2
import compress.gzip

struct InputEvent {
mut:
	sequence                  int
	loop_id                   int
	kind                      int
	x                         int
	y                         int
	value                     int
	payload_bytes             int
	read_ms                   i64
	done_ms                   i64
	dispatch_ms               i64
	ready_after_dispatch      int
	poll_revents_after_dispatch int
	pause_after_ready_ms      i64 = -1
	same_loop_as_previous     bool
}

struct Observations {
	variant                    string
	input_events               []InputEvent
	maximum_input_events_one_loop int
	loops_with_multiple_input_events int
	maximum_pause_after_ready_ms i64
	scope                      string
}

fn fields(line string) map[string]string {
	mut row := map[string]string{}
	for part in line.split(' ') {
		if part.contains('=') { row[part.all_before('=')] = part.all_after('=') }
	}
	return row
}

fn main() {
	assert os.args.len == 2 && os.args[1] in ['231', '232', '233']
	version := os.args[1]
	path := os.dir(@FILE) + '/' + version
	serial := gzip.decompress(os.read_bytes(path + '/serial.log.gz')!)!.bytestr()
	mut events := []InputEvent{}
	mut by_sequence := map[int]int{}
	for line in serial.split_into_lines() {
		if line.contains('WS-TIMING231 input_read ') {
			row := fields(line)
			sequence := row['sequence'].int()
			assert sequence !in by_sequence
			by_sequence[sequence] = events.len
			events << InputEvent{
				sequence: sequence
				loop_id: row['loop'].int()
				kind: row['kind'].int()
				x: row['x'].int()
				y: row['y'].int()
				value: row['value'].int()
				payload_bytes: row['length'].int()
				read_ms: row['now_ms'].i64()
			}
		} else if line.contains('WS-TIMING231 input_done ') {
			row := fields(line)
			index := by_sequence[row['sequence'].int()] or { panic('completion without read') }
			assert events[index].loop_id == row['loop'].int()
			events[index].done_ms = row['now_ms'].i64()
			events[index].dispatch_ms = row['duration_ms'].i64()
			events[index].ready_after_dispatch = row['ready'].int()
			events[index].poll_revents_after_dispatch = row['revents'].int()
		}
	}
	mut maximum_pause := i64(0)
	for i in 0 .. events.len {
		assert events[i].done_ms >= events[i].read_ms
		assert events[i].done_ms - events[i].read_ms == events[i].dispatch_ms
		if i == 0 { continue }
		assert events[i].read_ms >= events[i - 1].done_ms
		events[i].same_loop_as_previous = events[i].loop_id == events[i - 1].loop_id
		if events[i - 1].ready_after_dispatch > 0 && (events[i - 1].poll_revents_after_dispatch & 1) != 0 {
			pause := events[i].read_ms - events[i - 1].done_ms
			events[i].pause_after_ready_ms = pause
			if pause > maximum_pause { maximum_pause = pause }
		}
	}
	assert events.len > 0
	mut counts := map[int]int{}
	for event in events { counts[event.loop_id]++ }
	mut maximum_per_loop := 0
	mut multiple_event_loops := 0
	for _, count in counts {
		if count > maximum_per_loop { maximum_per_loop = count }
		if count > 1 { multiple_event_loops++ }
	}
	os.write_file(path + '/input-observations.json', json2.encode(Observations{
		variant: version
		input_events: events
		maximum_input_events_one_loop: maximum_per_loop
		loops_with_multiple_input_events: multiple_event_loops
		maximum_pause_after_ready_ms: maximum_pause
		scope: 'Guest input-read and dispatch timestamps, with pauses only where the previous completion reported queued input. These pauses include all intervening native work. Host injection timestamps use a different clock; these values are not end-to-end input latency or a controlled benchmark.'
	}, prettify: true) + '\n')!
	println('MAPS-INPUT-OBSERVATIONS ' + version + ' events=' + events.len.str() + ' maximum_pause_after_ready_ms=' + maximum_pause.str())
}
