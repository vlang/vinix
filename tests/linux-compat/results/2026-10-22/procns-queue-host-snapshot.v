import crypto.sha256
import json2
import os
import time

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn checked(command string) string {
	result := os.execute(command)
	assert result.exit_code == 0, result.output
	return result.output.trim_space()
}

fn main() {
	processes := checked('ps -Ao pid,ppid,etime,time,pcpu,command')
	mut selected := []string{}
	for line in processes.split_into_lines() {
		if (line.contains('./qualify3 ') || line.contains('qemu-system-')) && line.contains('queue-after-') { selected << line }
	}
	data := {
		'observed_utc': time.utc().str()
		'uptime_and_load': checked('uptime')
		'logical_cpus': checked('sysctl -n hw.logicalcpu')
		'process_columns': 'PID PPID ELAPSED CPU_TIME PCPU COMMAND'
		'qualification_processes': selected.join('\n')
		'kernel_commit': os.read_file(area + '/queue-fix/commit.txt')!.trim_space()
		'profile': 'candidate-track'
		'configuration': 'ARM HVF4 CPUs; x86 TCG2 CPUs;1024MiB; no networking; host guest deadline7200seconds; unchanged frozen2 init ELF per architecture'
		'configuration_continuity': 'Pinned runner unchanged; final2 ARM before/after boot logs show4 CPUs; x86 runner explicitly2 CPUs'
		'snapshot_source_sha256': sha256.sum(os.read_bytes(area + '/queue-host-snapshot.v')!).hex()
	}
	path := area + '/queue-host-snapshot-' + time.utc().unix().str() + '.json'
	os.write_file(path, json2.encode(data, prettify: true) + '\n')!
	println(path)
	println(data['uptime_and_load'])
	println(data['qualification_processes'])
}
