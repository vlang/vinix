// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Account and privilege tests: boot a kernel in QEMU with the account
// tools in its root file system and a V test program as init, and judge
// what it prints. README.md says what is covered.
//
// The machine-booting half is the hardware tests' (hwhost); this file is
// the suite: the scenarios, the programs and the files.
module main

import hwhost
import os

const programs = [
	hwhost.Program{
		source: 'tools/accounts/authd.v'
		path:   'usr/sbin/vinix-authd'
	},
	hwhost.Program{
		source: 'tools/accounts/account.v'
		path:   'usr/sbin/vinix-account'
	},
	hwhost.Program{
		source: 'tools/accounts/session.v'
		path:   'usr/sbin/vinix-session'
	},
	hwhost.Program{
		source: 'tools/accounts/system.v'
		path:   'usr/sbin/vinix-system'
	},
	hwhost.Program{
		source: 'tools/accounts/auth.v'
		path:   'usr/bin/vinix-auth'
	},
	hwhost.Program{
		source: 'tools/security-events/events.v'
		path:   'usr/sbin/vinix-security-events'
	},
]

// Actions only the tests have: something harmless to be allowed or refused.
const test_actions = {
	'test-session': 'description = Say a word, for whoever is at the machine\nauth = session\nexec = /sbin/init\narg = probe\narg = say\nparam = text\n'
	'test-self':    'description = Say who asked\nauth = self\nexec = /sbin/init\narg = probe\narg = who\n'
	'test-input':   'description = Say what was sent\nauth = admin\nexec = /sbin/init\narg = probe\narg = input\ninput = secret\n'
}

fn scenario(name string, about string) hwhost.Scenario {
	// Under emulation one password check takes seconds, and a scenario makes
	// dozens. VINIX_ACCOUNTS_TIMEOUT shortens the wait while a hang is looked
	// into.
	asked := os.getenv('VINIX_ACCOUNTS_TIMEOUT').int()
	timeout := if asked > 0 { asked } else { 420 }
	return hwhost.Scenario{
		name:     name
		about:    about
		arches:   ['aarch64', 'x86_64']
		required: ['HWTEST START ${name}', 'HWTEST PASS ${name}']
		ending:   .poweroff
		timeout:  timeout
	}
}

fn main() {
	checkout := os.dir(os.dir(os.dir(@FILE)))
	actions := os.join_path(checkout, 'tools', 'accounts', 'actions')
	mut files := [
		hwhost.RootFile{
			path: 'etc/passwd'
			text: 'root:x:0:0:root:/root:/bin/sh\n'
		},
		hwhost.RootFile{
			path: 'etc/group'
			text: 'root:x:0:\ntty:x:5:\n'
		},
	]
	// Password records at the least cost the tools accept: an emulated
	// processor takes most of a minute for one at the default.
	files << hwhost.RootFile{
		path: 'etc/vinix/auth.conf'
		text: '# for the tests only
scrypt_ln = 10
'
	}
	for name in os.ls(actions) or { []string{} } {
		files << hwhost.RootFile{
			path: 'usr/share/vinix/actions/${name}'
			text: os.read_file(os.join_path(actions, name)) or { '' }
		}
	}
	for name, text in test_actions {
		files << hwhost.RootFile{
			path: 'usr/share/vinix/actions/${name}'
			text: text
		}
	}
	if os.getenv('VINIX_ACCOUNTS_ECHO') != '' {
		// The guest then repeats on the serial port what the programs it runs
		// print.
		files << hwhost.RootFile{
			path: 'etc/hwtest-echo'
			text: '1
'
		}
	}
	suite := hwhost.Suite{
		name:        'accounts'
		guest:       'tests/accounts/guest'
		module_paths: ['tools/accounts', 'tools/security-events']
		programs:    programs
		files:       files
		directories: ['run', 'home', 'var/log', 'usr/share/vinix/actions', 'tmp:1777']
		scenarios:   [
			scenario('accounts', 'the account database, homes nobody else can read, and sessions that are not root'),
			scenario('elevation', 'the authentication service: passwords, throttling, actions and who may run them'),
			hwhost.Scenario{
				...scenario('unprivileged', 'what an ordinary account is refused by the kernel')
				// A disk, for the account to be refused: reading it would
				// be reading every file on it.
				qemu_aarch64: ['-drive', 'if=none,id=acct0,format=raw,file={state}/disk.raw', '-device',
					'virtio-blk-device,drive=acct0']
				qemu_x86_64:  ['-drive', 'if=ide,format=raw,file={state}/disk.raw']
				disks:        [
					hwhost.Disk{
						name:      'disk.raw'
						size_mib:  8
						header:    'vinix account test disk: not blank'
						untouched: true
					},
				]
			},
			scenario('seat', 'login sessions the kernel knows, and devices that follow who is at the machine'),
			scenario('sessions', 'the session manager: a login screen, a session, switching to another and back, logging out'),
			scenario('audit', 'the record of security decisions: attributed to logins, closed to accounts, kept on disk'),
		]
	}
	exit(hwhost.run_suite(suite, os.args[1..], @FILE))
}
