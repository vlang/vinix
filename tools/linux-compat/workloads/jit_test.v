module main

fn test_jit_selection_is_explicit_native_and_scoped_to_selected_workloads() {
	assert parse_jit_runtimes('', ['firefox'], 'native-x86_64')! == []string{}
	assert parse_jit_runtimes('firefox,java', ['firefox', 'java', 'server'], 'native-aarch64')! == ['firefox', 'java']
	for value in ['firefox,firefox', 'firefox,', 'server', '/usr', 'chromium'] {
		if _ := parse_jit_runtimes(value, ['firefox', 'java'], 'native-x86_64') {
			assert false, 'invalid JIT selection accepted: ' + value
		}
	}
	if _ := parse_jit_runtimes('firefox', ['firefox'], 'translated-x86_64') {
		assert false, 'foreign executable chains need separate mount qualification'
	}
}

fn test_jit_receipt_requires_the_actual_most_specific_mount_policy() {
	root := '1 0 0:1 / / rw,wxallowed - tmpfs tmpfs rw'
	approved := '2 1 0:1 /usr/lib/firefox-esr /usr/lib/firefox-esr ro,nosuid,nodev,wxallowed - tmpfs /usr/lib/firefox-esr rw'
	assert jit_mount_row(root + '\n' + approved, '/usr/lib/firefox-esr/firefox-esr')! == approved
	for info in [root, approved.replace('ro,', 'rw,'), approved.replace(',nosuid', ''),
		approved.replace(',nodev', ''), approved.replace(',wxallowed', ''),
		approved.replace('ro,', 'ro,noexec,'),
		approved + '\n3 2 0:1 / /usr/lib/firefox-esr/sub rw - tmpfs tmpfs rw'] {
		if _ := jit_mount_row(info, '/usr/lib/firefox-esr/sub/program') {
			assert false, 'unapproved executable mount accepted: ' + info
		}
	}
	if _ := jit_mount_row(approved, '/usr/lib/firefox-esr-other/firefox') {
		assert false, 'mount prefix must end at a path component'
	}
}
