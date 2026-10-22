import crypto.sha256
import json2
import os
import time

fn main() {
	assert os.args.len == 2 && os.args[1] in ['before', 'after']
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	tag := 'diagnostic-kind2b-' + os.args[1] + '-x86'
	state := area + '/states/' + tag
	mut marker := ''
	mut sampled := i64(0)
	deadline := time.now().unix() + 7200
	for time.now().unix() < deadline {
		if os.is_file(state + '/receipt.json') { break }
		if os.exists(state + '/qmp.sock') {
			log := os.read_file(state + '/live.log') or { '' }
			mut latest := ''
			for line in log.split_into_lines() {
				if line.starts_with('PROCNS DIAG SNAPSHOT:') || line.starts_with('PROCNS DIAG PHASE:') { latest = line.trim_space() }
			}
			if latest != marker || time.now().unix() - sampled >= 15 {
				mut child := os.new_process(area + '/qmp-queue')
				child.set_args([tag])
				child.set_redirect_stdio_merged()
				child.run()
				out := child.stdout_slurp()
				child.wait()
				code := child.code
				child.close()
				path := area + '/queue-sample-' + tag + '-' + time.sys_mono_now().str() + '.json'
				os.write_file(path, json2.encode({'utc': time.utc().str(), 'marker': latest, 'sample_status': code.str(), 'qmp_output': out, 'live_log_sha256': sha256.sum(log.bytes()).hex(), 'live_log_bytes': log.len.str(), 'method': 'Serial marker observed then read-only QMP; diagnostic pauses30guestseconds after snapshots.'}, prettify: true))!
				println(path + ' ' + latest)
				marker = latest
				sampled = time.now().unix()
			}
		}
		time.sleep(500 * time.millisecond)
	}
}
