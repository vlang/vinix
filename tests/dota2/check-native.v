// SPDX-License-Identifier: GPL-2.0-or-later
import hosttest
import json2
import math.big
import nativehost
import os
import policyhost
import transcriptcore
import time

#include <fcntl.h>

fn C.fcntl(int, int, ...int) int

fn fd_count() int {
	mut count := 0
	for fd in 0 .. 1024 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn environment_text() string {
	mut text := 'VINIX-DOTA2-ENV-PAIR-BEGIN: old\nVINIX-DOTA2-ENV-START\nVINIX-DOTA2-ENV-LIBC: 2.36\nVINIX-DOTA2-ENV-PAIR-RESULT: variant=old exit=-1 signal=11 watchdog=0\nVINIX-DOTA2-ENV-PAIR-BEGIN: new\nVINIX-DOTA2-ENV-START\nVINIX-DOTA2-ENV-LIBC: 2.41\n'
	for round in 1 .. 33 {
		text += 'VINIX-DOTA2-ENV-ROUND: round=' + round.str() + ' writes=' + (round * 1000).str() + ' checks=3 overlap=2\n'
	}
	return text + 'VINIX-DOTA2-ENV-PASS: rounds=32 writes=32000 checks=96 overlap=64\nVINIX-DOTA2-ENV-PAIR-RESULT: variant=new exit=0 signal=0 watchdog=0\nVINIX-DOTA2-ENV-PAIR-END\n'
}

fn lava_text(drivers []string) string {
	mut text := ''
	for driver in drivers {
		for mode in nativehost.lava_modes {
			text += 'VINIX-DOTA2-LVP-PAIR-BEGIN: driver=' + driver + ' mode=' + mode + '\n'
			passed := driver == 'fixed' || mode == 'bound'
			if passed {
				text += 'VINIX-DOTA2-LVP-RESULT: mode=' + mode + ' set0=00000000 set1=00000000 set2=56494e58\nVINIX-DOTA2-LVP-PASS: ' + mode + '\n'
			}
			text += 'VINIX-DOTA2-LVP-PAIR-RESULT: driver=' + driver + ' mode=' + mode + if passed {
				' exit=0 signal=0 watchdog=0\n'
			} else {
				' exit=-1 signal=11 watchdog=0\n'
			}
		}
	}
	return text + 'VINIX-DOTA2-LVP-PAIR-END\n'
}

fn checked() ! {
	guard := policyhost.own_commands()
	defer { guard.close() }
	work := hosttest.work_dir(if os.args.len == 2 { os.args[1] } else { '' }, 'vinix-dota-native-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	source := work + '/source'
	target := work + '/target'
	os.write_file(source, 'new desktop')!
	os.chmod(source, 0o555)!
	os.write_file(target, 'old desktop')!
	os.chmod(target, 0o555)!
	for _ in 0 .. 4 { nativehost.install(source, target)! }
	assert os.read_file(source)! == 'new desktop' && os.read_file(target)! == 'new desktop'
	assert os.stat(source)!.mode & 0o777 == 0o555 && os.stat(target)!.mode & 0o777 == 0o555
	nativehost.install(source, source)!
	os.rm(target)!
	os.symlink(source, target)!
	os.write_file(work + '/replacement', 'replacement')!
	nativehost.install(work + '/replacement', target)!
	assert !os.is_link(target) && os.read_file(source)! == 'new desktop'
	mut header := []u8{len: 64}
	for index, byte in [u8(0x7f), `E`, `L`, `F`, 2, 1] { header[index] = byte }
	header[16] = 3
	header[18] = 62
	os.write_file_array(work + '/elf', header)!
	before := fd_count()
	for _ in 0 .. 200 {
		pin := nativehost.elf_input(work + '/elf', 62, 64)!
		assert pin.bytes == 64
		nativehost.install_pin(pin, work + '/pin')!
		mut rejected := false
		nativehost.elf_input(work + '/elf', 183, 64) or {
			rejected = true
			nativehost.Pin{}
		}
		assert rejected
	}
	assert before == fd_count()
	os.mkdir_all(work + '/runtime/lib/x86_64-linux-gnu')!
	os.mkdir_all(work + '/runtime/lib64')!
	nativehost.install(work + '/elf', work + '/runtime/lib/x86_64-linux-gnu/libc.so.6')!
	nativehost.install(work + '/elf', work + '/runtime/lib64/ld-linux-x86-64.so.2')!
	runtime := nativehost.runtime_inputs(work + '/runtime')!
	assert runtime.libc.sha256 == runtime.loader.sha256
	original := environment_text()
	verdict := transcriptcore.environment_verdict(original, true)
	assert verdict.passed && !transcriptcore.environment_verdict(original, false).passed
	assert !transcriptcore.environment_verdict(original.replace('round=16 writes=16000', 'round=16 writes=15000'), true).passed
	assert !transcriptcore.environment_verdict(original.replace('signal=11', 'signal=0'), true).passed
	assert !transcriptcore.environment_verdict(original.replace('checks=96 overlap=64', 'checks=95 overlap=64'), true).passed
	report := json2.decode[json2.Any](nativehost.environment_json(verdict))!.as_map()
	assert report['new_counts']!.as_map()['checks']!.i64() == 96
	assert report['observations']!.as_map()['old']!.as_map()['signal']!.i64() == 11
	huge := big.integer_from_string('12345678901234567890123456789012345678901234567890')!
	encoded := nativehost.environment_json(transcriptcore.EnvResult{
		observations: {
			'new': transcriptcore.EnvObservation{huge, big.zero_int, big.zero_int}
		}
	})
	assert encoded.contains('"exit_code":' + huge.str()) && !encoded.contains('digits')
	drivers := ['control-1', 'control-2', 'fixed']
	lava := lava_text(drivers)
	assert nativehost.lava_verdict(lava, 0, drivers)!.passed
	assert !nativehost.lava_verdict(lava, 1, drivers)!.passed
	assert !nativehost.lava_verdict(lava.replace('56494e58', '00000000'), 0, drivers)!.passed
	assert !nativehost.lava_verdict(lava.replace('watchdog=0', 'watchdog=1'), 0, drivers)!.passed
	assert !nativehost.lava_verdict(lava, 0, ['fixed', 'control-1', 'control-2'])!.passed
	assert nativehost.lava_verdict(lava.replace('signal=11', 'signal=١١'), 0, drivers)!.passed
	assert nativehost.lava_verdict(lava.replace('exit=0', 'exit=' + huge.str()), 0, drivers)!.json().contains('"exit_code":' + huge.str())
	assert nativehost.lava_verdict(lava.replace('PAIR-END', 'missing'), 0, drivers)!.observations.len == 12
	env := nativehost.game_environment(['A=with spaces', "Q=a'b", 'A=replaced'])!
	assert env == {
		'A': 'replaced'
		'Q': "a'b"
	}
	for value in ['bad-name=x', 'A', '=x', 'A=a,b', 'A=a\x00b'] {
		mut rejected := false
		nativehost.game_environment([value]) or {
			rejected = true
			map[string]string{}
		}
		assert rejected
	}
	println('PASS native Dota pins, install/source safety, FD retirement and independent environment/Lavapipe verdicts')
}

fn model() ! {
	family := os.getenv('VINIX_DOTA_FAMILY')
	failure := os.getenv('VINIX_DOTA_FAILURE') == '1'
	os.write_file(os.getenv('VINIX_DOTA_ARGV'), os.args[1..].join('\n'))!
	os.write_file(os.getenv('VINIX_DOTA_PID'), os.getpid().str())!
	mut text := match family {
		'env-run' { environment_text() }
		'lavapipe-run' { lava_text(['control-1', 'control-2', 'fixed']) }
		'wake-op-run' {
			mut wake := 'WAKE-OP-VARIANT-BEGIN:old\nWAKE-OP SMC result=-1 errno=14 word=17\n'
			for name in ['write-only-secondary', 'write-only-operation-stored-value',
				'read-only-primary-wake', 'read-only-primary-wake-op', 'read-only-secondary',
				'prot-none-secondary', 'unmapped-secondary'] {
				wake += 'WAKE-OP CHECK ' + name + ' PASS\n'
			}
			wake + 'WAKE-OP-VARIANT-EXIT:old:1\nWAKE-OP-VARIANT-BEGIN:new\nWAKE-OP PASS failures=0\nWAKE-OP-VARIANT-EXIT:new:0\nWAKE-OP-GUEST-END\n'
		}
		'run-mmap32' { 'MMAP-VARIANT-PASS:v-v\nMMAP-TRANSLATED-GUEST-END\n' }
		'steam-smoke-run' {
			'VINIX-DOTA2-STEAM-SMOKE-LOAD-PASS\nVINIX-DOTA2-STEAM-SMOKE-EXIT: 0\nVINIX-DOTA2-STEAM-SMOKE-END\n'
		}
		else { return error('Unknown model family') }
	}
	if failure {
		text = match family {
			'env-run' { text.replace('signal=11', 'signal=0') }
			'lavapipe-run' { text.replace('56494e58', '00000000') }
			'wake-op-run' { text.replace('failures=0', 'failures=1') }
			'run-mmap32' { 'VINIX-DOTA2-MMAP32-FAIL\n' }
			else { text.replace('EXIT: 0', 'EXIT: 1') }
		}
	}
	if os.getenv('VINIX_DOTA_HANG') != '1' {
		print(text)
		flush_stdout()
	}
	for { time.sleep(20 * time.millisecond) }
}

fn main() {
	if os.getenv('VINIX_DOTA_FAMILY') != '' {
		model() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	checked() or {
		eprintln(err)
		exit(1)
	}
}
