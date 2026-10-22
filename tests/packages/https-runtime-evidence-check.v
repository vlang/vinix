// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strings
import time
import tlsruntime

const digest = '0123456789abcdef'.repeat(4)
const pass = 'GUEST TLS 23 cases with 8 measured cycles preserve authenticated state, certificate policy, bounded recovery and retired replies PASS'

struct Controls {
	program string
	work    string
mut:
	count  int
	report strings.Builder
}

fn (mut c Controls) check(name string, kind string, text string, repetitions int, accepted bool) ! {
	path := c.work + '/' + c.count.str() + '.txt'
	os.write_file(path, text)!
	mut child := os.new_process(c.program)
	child.set_args(if kind == 'native' {
		['--check-native', path]
	} else {
		['--check-requests', path, digest, repetitions.str()]
	})
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	code := child.code
	child.close()
	assert (code == 0) == accepted, name + ': unexpected exit ' + code.str() + '\n' + output
	if accepted {
		assert output.contains('GUEST TLS ' + kind + ' evidence PASS'), output
	}
	c.count++
	c.report.writeln('EVIDENCE ' + name + if accepted { ' accepted PASS' } else { ' rejected PASS' })
}

fn native() string {
	mut text := strings.new_builder(8192)
	text.writeln('HWTEST START packages-https-runtime')
	text.writeln('curl 8.14.1 (aarch64-unknown-vinix) libcurl/8.14.1 OpenSSL/3.5.0 zlib/1.3.1')
	text.writeln('GUEST TLS file baseline=1000000 ceiling=1131072')
	for mode in tlsruntime.modes() {
		text.writeln('GUEST TLS ' + mode + ' retained 0 tracked bytes')
		text.writeln('COLLECTION STRESS settled ' + mode + ': initial=1200000 bytes=1100000 waits=1')
	}
	text.writeln(pass)
	text.writeln('HWTEST PASS packages-https-runtime')
	return text.str()
}

fn request_log(repetitions int) string {
	mut text := strings.new_builder(8192)
	for _ in 0 .. repetitions {
		for mode in tlsruntime.modes() {
			if !mode.starts_with('fetch-') {
				text.writeln(mode + ' setup index.json -')
				text.writeln(mode + ' setup index.sig -')
			}
			for cycle in 0 .. tlsruntime.cycles + tlsruntime.warmups {
				_ = cycle
				for step in 0 .. tlsruntime.requests(mode) {
					route := if mode.ends_with('-corrupt') {
						'no-range-corrupt'
					} else if mode.ends_with('-fallback') {
						'no-range'
					} else if mode.ends_with('-truncated') {
						'truncated'
					} else if mode.ends_with('-http') {
						'forbidden'
					} else if mode.ends_with('-redirect') {
						'insecure-redirect'
					} else if mode.ends_with('-size') {
						'oversized'
					} else {
						'ranges'
					}
					resource := if mode.starts_with('refresh-') {
						if step == 0 { 'index.json' } else { 'index.sig' }
					} else if mode.starts_with('install-') || mode.ends_with('-http') || mode.ends_with('-redirect') {
						'objects/' + digest
					} else {
						'payload'
					}
					range := if mode.starts_with('refresh-') || mode.ends_with('-fresh') || mode.ends_with('-size') {
						'-'
					} else if mode.ends_with('-truncated') && step == 1 {
						'bytes=1536-'
					} else if step == 1 {
						'-'
					} else {
						'bytes=512-'
					}
					text.writeln(mode + ' ' + route + ' ' + resource + ' ' + range)
				}
			}
		}
	}
	return text.str()
}

fn run() ! {
	assert os.args.len in [2, 3], 'usage: https-runtime-evidence-check RETAINER_BINARY [REPORT_PATH]'
	program := os.abs_path(os.args[1])
	work := os.join_path(os.temp_dir(), 'vinix-tls-evidence-' + os.getpid().str() + '-' + time.now().unix_milli().str())
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	mut c := Controls{ program: program, work: work, report: strings.new_builder(4096) }
	serial := native()
	c.check('native-complete', 'native', serial, 1, true)!
	c.check('native-reservation-boundary', 'native', serial.replace('bytes=1100000 waits=1', 'bytes=1131072 waits=30'), 1, true)!
	c.check('native-certificate-diagnostic', 'native', serial + 'curl failed to verify the legitimacy of the server and therefore could not\n', 1, true)!
	c.check('native-duplicate-version', 'native', serial + 'curl 8.14.1 (fixture) libcurl/8.14.1 OpenSSL/3.5.0\n', 1, false)!
	c.check('native-malformed-version', 'native', serial.replace('curl 8.14.1 ', 'curl invalid '), 1, false)!
	c.check('native-missing-case', 'native', serial.replace('GUEST TLS fetch-fresh retained 0 tracked bytes\n', ''), 1, false)!
	c.check('native-missing-settlement', 'native', serial.replace('COLLECTION STRESS settled fetch-fresh: initial=1200000 bytes=1100000 waits=1\n', ''), 1, false)!
	c.check('native-excess-reservations', 'native', serial.replace('bytes=1100000 waits=1', 'bytes=1131073 waits=1'), 1, false)!
	c.check('native-excess-waits', 'native', serial.replace('waits=1', 'waits=31'), 1, false)!
	c.check('native-nonzero-heap', 'native', serial.replace('fetch-fresh retained 0 tracked', 'fetch-fresh retained 16 tracked'), 1, false)!
	c.check('native-hidden-nonzero-heap', 'native', serial + 'GUEST TLS fetch-fresh retained 16 tracked bytes\n', 1, false)!
	c.check('native-duplicate-heap', 'native', serial + 'GUEST TLS fetch-fresh retained 0 tracked bytes\n', 1, false)!
	c.check('native-unknown-case', 'native', serial.replace('fetch-fresh', 'fetch-unknown'), 1, false)!
	c.check('native-duplicate-settlement', 'native', serial + 'COLLECTION STRESS settled fetch-fresh: initial=1200000 bytes=1100000 waits=1\n', 1, false)!
	c.check('native-bad-ceiling', 'native', serial.replace('ceiling=1131072', 'ceiling=1131073'), 1, false)!
	c.check('native-duplicate-baseline', 'native', serial + 'GUEST TLS file baseline=1000000 ceiling=1131072\n', 1, false)!
	c.check('native-overflow-baseline', 'native', serial.replace('baseline=1000000 ceiling=1131072', 'baseline=18446744073709551615 ceiling=131071'), 1, false)!
	c.check('native-missing-tls', 'native', serial.replace('OpenSSL/3.5.0', ''), 1, false)!
	c.check('native-empty-tls-version', 'native', serial.replace('OpenSSL/3.5.0', 'OpenSSL/'), 1, false)!
	c.check('native-missing-curl-version', 'native', serial.replace('libcurl/8.14.1', 'libcurl/'), 1, false)!
	c.check('native-missing-pass', 'native', serial.replace(pass, ''), 1, false)!
	c.check('native-failure-marker', 'native', serial + 'HWTEST FAIL packages-https-runtime\n', 1, false)!
	requests := request_log(1)
	c.check('requests-native-complete', 'request', requests, 1, true)!
	c.check('requests-host-complete', 'request', request_log(2), 2, true)!
	c.check('requests-missing-case', 'request', requests.replace('fetch-fresh ranges payload -\n', ''), 1, false)!
	c.check('requests-extra-attempt', 'request', requests + 'fetch-fresh ranges payload -\n', 1, false)!
	c.check('requests-bad-resume-range', 'request', requests.replace('fetch-resume ranges payload bytes=512-', 'fetch-resume ranges payload -'), 1, false)!
	c.check('requests-bad-truncated-retry', 'request', requests.replace('bytes=1536-', 'bytes=512-'), 1, false)!
	c.check('requests-unbounded-tls-refusal', 'request', requests + 'fetch-untrusted ranges payload bytes=512-\n', 1, false)!
	c.check('requests-missing-setup', 'request', requests.replace('refresh-fresh setup index.json -\n', ''), 1, false)!
	c.check('requests-bad-resource', 'request', requests.replace('objects/' + digest, 'objects/invalid'), 1, false)!
	c.check('requests-bad-route', 'request', requests.replace('fetch-fallback no-range ', 'fetch-fallback ranges '), 1, false)!
	c.check('requests-unknown-mode', 'request', requests + 'fetch-unknown ranges payload -\n', 1, false)!
	c.check('requests-invalid-repetitions', 'request', requests, 0, false)!
	c.report.writeln('GUEST TLS evidence controls PASS')
	report := c.report.str()
	print(report)
	if os.args.len == 3 {
		os.mkdir_all(os.dir(os.abs_path(os.args[2])))!
		os.write_file(os.args[2], report)!
	}
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
