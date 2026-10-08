module runhost

import androidhost as ah
import crypto.sha256
import encoding.hex

struct Verification {
	name    string
	marker  string
	message string
	exact   bool
}

fn finalize(args map[string]ah.Value, session map[string]ah.Value) !ah.Value {
	transcript := hex.decode(text(session, 'transcript_hex'))!.bytestr()
	lines := transcript.replace('\r', '').split('\n')
	mut passed := truth(ah.field(session, 'passed'))
	mut observed := truth(ah.field(session, 'observed'))
	mut reason := text(session, 'failure')
	for line in lines {
		if line.contains('ANDROID-FAIL ') {
			if !passed && !observed {
				body := line.all_after('ANDROID-FAIL ').trim(' \t\n\r\x0b\x0c')
				reason = callback('bytes_decode', {
					'data':    ah.Value(body.bytes().hex())
					'options': ah.Value({
						'errors': ah.Value('replace')
					})
				})!.text()
			}
			break
		}
	}
	mut verified := map[string]ah.Value{}
	mut queue_status := null()
	for probe in [
		Verification{'boot_probe', 'ANDROID-BOOTCLASSPATH-VERIFIED', 'native Java bootclasspath', true},
		Verification{'loader_probe', 'ANDROID-BIONIC-LOADER-VERIFIED', 'native Bionic nested loader', false},
		Verification{'tls_probe', 'ANDROID-TLS-VERIFIED', 'native Java HTTPS trust', false},
		Verification{'layout_probe', 'ANDROID-LAYOUT-FOCUS-VERIFIED', 'native framework layout focus', false},
		Verification{'pointer_probe', 'ANDROID-POINTER-CAPTURE-VERIFIED', 'native framework pointer capture', false},
		Verification{'lifecycle_probe', 'ANDROID-ACTIVITY-LIFECYCLE-VERIFIED', 'native framework activity lifecycle', false},
		Verification{'egl_probe', 'ANDROID-EGL-VERIFIED', 'native EGL and GTK texture', false},
		Verification{'cookie_probe', 'ANDROID-COOKIE-VERIFIED', 'native framework cookie', false},
		Verification{'autofill_probe', 'ANDROID-AUTOFILL-VERIFIED', 'native framework disabled autofill', true},
		Verification{'location_probe', 'ANDROID-LOCATION-VERIFIED', 'native framework unavailable location providers', true},
		Verification{'egl_queue_probe', 'ANDROID-EGL-QUEUE-VERIFIED', 'native EGL buffer queue', true},
		Verification{'split_probe', 'ANDROID-SPLIT-VERIFIED', 'native configuration split APK', false},
	] {
		verified[probe.name] = null()
		if !truth(attribute(args, probe.name)!) { continue }
		if probe.name == 'egl_queue_probe' {
			prefix := 'ANDROID-EGL-QUEUE-CHILD status='
			for line in lines {
				if line.starts_with(prefix) {
					digits := line[prefix.len..]
					if digits.len != 0 && digits.bytes().all(it in `0` .. `9` + 1) {
						queue_status = callback('bytes_int', {
							'data': ah.Value(digits.bytes().hex())
						})!
						break
					}
				}
			}
		}
		ok := if probe.exact { probe.marker in lines } else { transcript.contains(probe.marker) }
		verified[probe.name] = ah.Value(ok)
		if !ok {
			if passed || observed { reason = probe.message + ' probe did not pass' }
			passed = false
			observed = false
		}
	}
	interactive := truth(attribute(args, 'interactive')!)
	observe := truth(attribute(args, 'observe')!)
	mut result := map[string]ah.Value{}
	result['passed'] = if interactive || (observe && observed) { null() } else { ah.Value(passed) }
	result['observed'] = ah.Value(observed)
	result['check'] = ah.Value(if interactive {
		'interactive-observation'
	} else if observe {
		'window-observation'
	} else {
		'calculator'
	})
	result['failure'] = if passed || observed { null() } else { ah.Value(reason) }
	result['mode'] = attribute(args, 'mode')!
	result['launcher'] = attribute(args, 'launcher')!
	result['apk'] = attribute_string('apk')!
	payload := hex.decode(callback('attribute_bytes', {
		'name': ah.Value('apk')
	})!.text())!
	result['apk_sha256'] = ah.Value(sha256.sum(payload).hex())
	splits := attribute(args, 'split_apk')!.items()
	checksums := attribute(args, 'split_apk_sha256')!.items()
	mut split_rows := []ah.Value{}
	for index in 0 .. int_min(splits.len, checksums.len) {
		split_rows << ah.Value({
			'path':   callback('str_attribute', {
				'name':  ah.Value('split_apk')
				'index': ah.Value(index)
			})!
			'sha256': checksums[index]
		})
	}
	result['split_apks'] = ah.Value(split_rows)
	result['initramfs'] = attribute_string('initramfs')!
	result['runtime_arch'] = attribute(args, 'runtime_arch')!
	result['memory_mb'] = attribute(args, 'memory')!
	result['desktop'] = attribute_string('desktop')!
	result['kernel_dir'] = attribute_string('kernel_dir')!
	result['keys'] = if observe { null() } else { attribute(args, 'keys')! }
	result['expected'] = if observe { null() } else { attribute(args, 'expect')! }
	result['screenshot'] = if interactive { null() } else { attribute_string('screenshot')! }
	retries := ah.field(session, 'input_retries').items()
	result['key_retries'] = if retries.len != 0 { retries[0] } else { null() }
	result['runtime_arguments'] = attribute(args, 'runtime_arg')!
	for name in ['layout_probe', 'pointer_probe', 'lifecycle_probe', 'cookie_probe', 'autofill_probe',
		'location_probe', 'egl_queue_probe', 'split_probe', 'egl_probe', 'tls_probe'] {
		present := truth(attribute(args, name)!)
		result[name] = if present { attribute_string(name)! } else { null() }
		result[name + '_sha256'] = if present { attribute(args, name + '_sha256')! } else { null() }
		result[name + '_passed'] = ah.field(verified, name)
		if name == 'egl_queue_probe' { result['egl_queue_probe_exit_status'] = queue_status }
	}
	result['linker_diagnostics'] = attribute(args, 'linker_diagnostics')!
	loader := truth(attribute(args, 'loader_probe')!)
	result['loader_probe'] = if loader { attribute_string('loader_probe')! } else { null() }
	result['loader_probe_sha256'] = if loader {
		attribute(args, 'loader_probe_sha256')!
	} else {
		null()
	}
	result['loader_probe_passed'] = ah.field(verified, 'loader_probe')
	architecture := attribute_text(args, 'runtime_arch')!
	result['netdb_probe_passed'] = if architecture == 'aarch64' {
		ah.Value(transcript.contains('ANDROID-NETDB-PASS '))
	} else {
		null()
	}
	boot := truth(attribute(args, 'boot_probe')!)
	result['boot_probe'] = if boot { attribute_string('boot_probe')! } else { null() }
	result['boot_probe_sha256'] = if boot { attribute(args, 'boot_probe_sha256')! } else { null() }
	result['boot_probe_passed'] = ah.field(verified, 'boot_probe')
	for name, marker in {
		'configuration_probe_passed': 'ATL-CONFIGURATION-PASS '
		'fortify_probe_passed':       'ANDROID-FORTIFY-PASS '
		'mallinfo_probe_passed':      'ANDROID-MALLINFO-PASS '
	} {
		result[name] = if architecture == 'aarch64' {
			ah.Value(transcript.contains(marker))
		} else {
			null()
		}
	}
	state := text(session, 'state')
	serial := join([state, 'serial.log'])!
	result['serial_log'] = ah.Value(serial)
	if interactive { result['functionality'] = ah.Value('unchecked') }
	output := callback('json_dumps', {
		'data':    ah.Value(result)
		'options': ah.Value({
			'indent': ah.Value(2)
		})
	})!.text()
	status := join([state, 'result.json'])!
	write(status, output + '\n')!
	if interactive {
		callback('print', {
			'data': ah.Value('Interactive Android session ended; application functionality is unchecked. Status: ' + status)
		})!
		return ah.Value(if observed && !truth(ah.field(session, 'guest_failed')) { 0 } else { 1 })
	}
	if !passed && !observed {
		callback('print', {
			'data':   ah.Value('Android smoke test failed (' + reason + '); inspect ' + serial)
			'stderr': ah.Value(true)
		})!
		return ah.Value(1)
	}
	message := if observed {
		"Observed the APK's X11 window; application functionality was not checked. Screenshot: " + attribute_string('screenshot')!.text()
	} else {
		'Android calculator displayed ' + attribute_string('expect')!.text() + '; screenshot: ' + attribute_string('screenshot')!.text()
	}
	callback('print', {
		'data': ah.Value(message)
	})!
	return ah.Value(0)
}

fn int_min(left int, right int) int { return if left < right { left } else { right } }
