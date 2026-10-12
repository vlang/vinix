// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import androidhost as ah
import gamehost
import os
import regex
import strconv

fn base64_line(line string) bool {
	plain := line.trim_right('=')
	return plain.len > 0 && line.len - plain.len <= 2 && plain.bytes().all(it.is_alnum() || it == `+` || it == `/`) && plain.bytes().all(it < 128)
}

fn capture_artifacts(tools gamehost.Tools, options DoomOptions, transcript string, operating_system string) !ah.Value {
	normalized := transcript.replace('\r', '')
	mut pairs := [['SHOT', operating_system + '.xwd']]
	if options.record { pairs.prepend(['DEMO', 'vinix-demo.demo']) }
	mut artifacts := []ah.Value{}
	for pair in pairs {
		begin := 'DHEWM3-' + pair[0] + '-BEGIN\n'
		end := 'DHEWM3-' + pair[0] + '-END'
		if !normalized.contains(begin) { return error('missing captured ' + pair[0]) }
		payload := normalized.all_after(begin).all_before(end)
		encoded := payload.split_into_lines().filter(base64_line(it)).join('')
		plain := encoded.trim_right('=')
		if !base64_line(encoded) && encoded != '' { return error('invalid base64 capture') }
		if plain.contains('=') { return error('invalid base64 capture padding') }
		target := gamehost.path(options.work, pair[1])
		os.write_file_array(target, gamehost.decode_base64(encoded)!)!
		artifacts << ah.Value(target)
	}
	if ffmpeg := os.find_abs_path_of_executable('ffmpeg') {
		png := gamehost.path(options.work, operating_system + '.png')
		tools.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-i',
			gamehost.path(options.work, operating_system + '.xwd'), '-frames:v', '1', png])!
		artifacts << ah.Value(png)
	}
	return ah.Value({
		'os':        ah.Value(operating_system)
		'artifacts': ah.Value(artifacts)
	})
}

fn numeric(value f64) ah.Value { return ah.Value(ah.Number{value.str()}) }

fn benchmark_result(options DoomOptions, transcript string, operating_system string) !ah.Value {
	mut pattern := regex.regex_opt(r'[0-9]+ frames rendered in [0-9.]+ seconds = [0-9.]+ fps')!
	mut rows := []map[string]ah.Value{}
	for match_ in pattern.find_all_str(transcript) {
		frame_text := match_.all_before(' frames rendered in ').trim_left('0')
		seconds := match_.all_after(' frames rendered in ').all_before(' seconds = ')
		fps := match_.all_after(' seconds = ').all_before(' fps')
		rows << {
			'frames':  ah.Value(ah.Number{if frame_text == '' { '0' } else { frame_text }})
			'seconds': numeric(strconv.atof64(seconds)!)
			'fps':     numeric(strconv.atof64(fps)!)
		}
	}
	mut elapsed_pattern := regex.regex_opt(r'DHEWM3-ELAPSED ns=[0-9]+ status=0')!
	elapsed := elapsed_pattern.find_all_str(transcript)
	if elapsed.len != rows.len { return error('Missing independent counter measurements') }
	for index, match_ in elapsed {
		ns := match_.all_after('DHEWM3-ELAPSED ns=').all_before(' status=0')
		rows[index]['process_seconds'] = numeric(strconv.atof64(ns)! / 1000000000)
	}
	mut frames := map[string]bool{}
	for row in rows { frames[ah.encode(row['frames']!)] = true }
	if rows.len != options.rounds + 1 || frames.len != 1 {
		return error('Incomplete or inconsistent timedemos: ' + ah.encode(ah.Value(rows.map(ah.Value(it)))))
	}
	runs := rows[1..].map(ah.Value(it))
	mut values := []f64{}
	for row in rows[1..] { values << strconv.atof64(ah.encode(row['fps']!))! }
	values.sort()
	middle := values.len / 2
	median := if values.len % 2 == 0 {
		(values[middle - 1] + values[middle]) / 2
	} else {
		values[middle]
	}
	return ah.Value({
		'os':         ah.Value(operating_system)
		'warmup':     ah.Value(rows[0])
		'runs':       ah.Value(runs)
		'median_fps': numeric(median)
	})
}

pub fn doom_result(tools gamehost.Tools, options DoomOptions, transcript string, operating_system string) !ah.Value {
	if !transcript.contains('DHEWM3-DONE') {
		return error('${operating_system} did not finish; inspect ${options.work}/${operating_system}.log')
	}
	if options.clock_only {
		return ah.Value({
			'os':          ah.Value(operating_system)
			'clock_probe': ah.Value('passed')
		})
	}
	if options.record || options.screenshot {
		return capture_artifacts(tools, options, transcript, operating_system)
	}
	return benchmark_result(options, transcript, operating_system)
}
