// SPDX-License-Identifier: GPL-2.0-or-later
module sessiondaemon

import desktop.sessioncore
import desktop.sessionipc
import desktop.serviceprocess
import os
import time

struct SessionMixerValue {
mut:
	device    i32
	control   i32 = 2
	value     i32
	flags     i32
	timestamp i32
	filler    [8]i32
}

fn session_volume(value int) !int {
	fd := sessionipc.desktop_open_rw('/dev/mixer')
	if fd < 0 { return error('No supported output mixer') }
	defer { sessionipc.desktop_close(fd) }
	mut setting := SessionMixerValue{ value: value }
	if value >= 0 && sessionipc.desktop_ioctl(fd, u64(0xc0345806), &setting) < 0 {
		return error('Output level refused by the mixer')
	}
	if sessionipc.desktop_ioctl(fd, u64(0xc0345805), &setting) < 0 {
		return error('Output mixer cannot be read')
	}
	return setting.value
}

fn session_tool(name string) string {
	for directory in ['/usr/bin', '/usr/sbin', '/bin', '/sbin']! {
		path := '${directory}/${name}'
		if C.access(&char(path.str), C.X_OK) == 0 { return path }
		unsafe { path.free() }
	}
	return ''
}

fn session_has_tool(name string) bool {
	path := session_tool(name)
	defer { unsafe { path.free() } }
	return path.len > 0
}

fn (mut daemon SessionDaemon) settings_status(category string) string {
	mut s := sessioncore.SettingsStatus{}
	match category {
		'sound' {
			level := session_volume(-1) or {
				s.line(err.msg())
				s.line('Input and recording are unavailable without an input driver.')
				return s.encode()
			}
			label := 'Output level: ${level}%'
			s.line(label)
			unsafe { label.free() }
			for i, title in ['Mute', '25%', '50%', '75%', '100%']! {
				action := 'sound.${i}'
				s.control(action, title, true, (i == 0 && level == 0) || (i > 0 && level == i * 25))
				unsafe { action.free() }
			}
		}
		'bluetooth' {
			available := session_has_tool('bluetoothctl') && os.is_dir('/sys/class/bluetooth')
			s.line(if available {
				'Bluetooth controller service is installed.'
			} else {
				'Bluetooth is unavailable: no controller backend.'
			})
			s.control('bluetooth.on', 'Turn on', available, false)
			s.control('bluetooth.off', 'Turn off', available, false)
			s.control('bluetooth.scan', 'Scan devices', available, false)
			s.control('bluetooth.pair', 'Pair address below', available, false)
			s.control('bluetooth.remove', 'Remove address below', available, false)
		}
		'printers' {
			available := session_has_tool('lpstat') && session_has_tool('lpadmin')
			s.line(if available {
				'CUPS printer service is installed. Results appear in operation logs.'
			} else {
				'Printing is unavailable: CUPS is not installed.'
			})
			s.control('printers.list', 'List printers', available, false)
			s.control('printers.default', 'Set default queue below', available, false)
			s.control('printers.enable', 'Enable queue below', available, false)
			s.control('printers.disable', 'Pause queue below', available, false)
			s.control('printers.remove', 'Remove queue below', available && C.getuid() == 0, false)
		}
		'users' {
			label := 'Session UID: ${C.getuid()}'
			s.line(label)
			unsafe { label.free() }
			s.line('Account changes use the installed account service and kernel permissions.')
			s.control('users.home', 'Open home folder', true, false)
			s.control('users.password', 'Change password', session_has_tool('passwd'), false)
			s.control('users.add', 'Add account named below', C.getuid() == 0 && session_has_tool('useradd'), false)
			s.control('users.lock', 'Lock account named below', C.getuid() == 0 && session_has_tool('usermod'), false)
		}
		'network' {
			s.line(if os.exists('/proc/net/dev') {
				'Network interfaces are available. Wi-Fi controls are on the Wi-Fi page.'
			} else {
				'Network interface status is unavailable.'
			})
			s.control('network.status', 'Show interfaces', session_has_tool('ifconfig'), false)
			s.control('network.up', 'Enable interface below', C.getuid() == 0 && session_has_tool('ifconfig'), false)
			s.control('network.down', 'Disable interface below', C.getuid() == 0 && session_has_tool('ifconfig'), false)
			s.control('network.dhcp', 'Renew DHCP on interface below', C.getuid() == 0 && session_has_tool('dhclient'), false)
		}
		'privacy' {
			s.line('These permissions control compositor clipboard and screen capture services.')
			s.line('Clipboard history is held in memory and can be cleared at any time.')
			s.control('privacy.history', 'Clipboard history', true, daemon.policy.clipboard_history)
			s.control('privacy.clipboard', 'App clipboard access', true, daemon.policy.clipboard_apps)
			s.control('privacy.capture', 'Screen capture', true, daemon.policy.allow_capture)
			s.control('privacy.clear', 'Clear clipboard', true, false)
		}
		'storage' {
			s.line('Disk Utility manages real disks, mounts and partitions.')
			s.control('storage.disks', 'Open Disk Utility', true, false)
			s.control('storage.usage', 'Open Disk Usage', true, false)
			s.control('storage.mounts', 'View mounted filesystems', os.exists('/proc/mounts'), false)
		}
		'updates' {
			release_record := sessioncore.load('/etc/vinix-release', 256) or { '' }
			release := release_record.trim_space().clone()
			unsafe { release_record.free() }
			if release.len > 0 {
				s.line(release)
			} else {
				s.line('Development image: no release channel.')
			}
			unsafe { release.free() }
			s.line('Release checks report a new ISO. In-place system updates are unavailable.')
			s.control('updates.check', 'Check releases', session_has_tool('vinix-version-check'), false)
		}
		'accessibility' {
			s.line('Display scale changes text and control size together.')
			s.control('accessibility.100', '100% scale', true, false)
			s.control('accessibility.200', '200% scale', true, false)
			s.line('Screen reading is unavailable until an accessibility speech service is installed.')
		}
		'clock' {
			label := 'UTC offset: ${daemon.policy.timezone_minutes} minutes'
			s.line(label)
			unsafe { label.free() }
			for i in 0 .. daemon.supervisor.count {
				if daemon.supervisor.services[i].name.str() == 'clock-sync' {
					s.line(if daemon.supervisor.services[i].state == .running {
						'Network clock service running; see clock-sync.log for last result.'
					} else {
						'Network clock service stopped.'
					})
					s.control('clock.sync', 'Network time synchronization', true, daemon.supervisor.services[i].enabled)
				}
			}
			s.line('Enter an installed timezone (Europe/Moscow) or UTC offset in minutes.')
			s.control('clock.zone', 'Set timezone or UTC offset below', true, false)
			s.control('clock.set', 'Set Unix epoch seconds below', C.getuid() == 0, false)
		}
		'session' {
			s.line('Workspaces, notifications, clipboard, services and help share one session.')
			s.control('session.shell', 'Open Desktop & Session', true, false)
			s.control('session.startup', 'Startup applications', true, false)
		}
		'shortcuts' {
			s.line('Select an action, then press its new shortcut. Escape cancels.')
			for name in ['shell', 'overview', 'close', 'minimize', 'show-desktop', 'help']! {
				action := 'shortcut.${name}'
				s.control(action, name, true, false)
				unsafe { action.free() }
			}
			s.control('shortcut.reset', 'Restore default shortcuts', true, false)
		}
		'gestures' {
			s.control('gestures.enable', 'Pointer gestures', true, daemon.policy.gestures)
			s.line('Middle-button horizontal swipe changes workspace; upward swipe opens overview.')
			for i in 0 .. 4 {
				action := 'corner.${i}'
				label := 'Corner ${i + 1}: ${if daemon.policy.corners[i].len > 0 {
					daemon.policy.corners[i].str()
				} else {
					'Off'
				}}'
				s.control(action, label, true, daemon.policy.corners[i].len > 0)
				unsafe {
					action.free()
					label.free()
				}
			}
			s.line('Corners cycle: Off, Overview, Desktop, Notifications. Dwell for 600 ms.')
		}
		else { s.line('Unknown settings category.') }
	}
	if daemon.settings_result.len > 0 { s.line(daemon.settings_result.str()) }
	return s.encode()
}

fn (mut daemon SessionDaemon) save_policy() ! {
	path := '${daemon.home}/.vinix-shell-policy'
	record := daemon.policy.encode()
	defer {
		unsafe {
			path.free()
			record.free()
		}
	}
	sessioncore.save(path, record)!
}

fn (mut daemon SessionDaemon) settings_apply(message sessionipc.SessionMessage) ! {
	previous := daemon.policy
	daemon.settings_apply_inner(message) or {
		daemon.policy = previous
		if previous.timezone.len > 0 {
			os.setenv('TZ', previous.timezone.str(), true)
		} else {
			os.setenv('TZ', 'UTC', true)
		}
		C.tzset()
		return err
	}
}

fn (mut daemon SessionDaemon) settings_apply_inner(message sessionipc.SessionMessage) ! {
	action := message.fields[1].str()
	value := if message.count > 2 { message.fields[2].str() } else { '' }
	if action.starts_with('sound.') {
		_ = session_volume(int(sessioncore.number(action['sound.'.len..], 0, 4)!) * 25)!
	} else if action.starts_with('privacy.') {
		match action {
			'privacy.history' { daemon.policy.clipboard_history = !daemon.policy.clipboard_history }
			'privacy.clipboard' { daemon.policy.clipboard_apps = !daemon.policy.clipboard_apps }
			'privacy.capture' { daemon.policy.allow_capture = !daemon.policy.allow_capture }
			else { return error('unknown privacy control') }
		}
		if !daemon.policy.clipboard_apps {
			daemon.exchange.clear()
			daemon.offers = [8]sessioncore.Clip{}
		}
		if !daemon.policy.clipboard_history {
			daemon.exchange.history = [sessioncore.clipboard_history_limit]sessioncore.Clip{}
			daemon.exchange.count = 0
		}
		daemon.save_policy()!
	} else if action == 'clock.zone' {
		if sessioncore.timezone_name(value) && value.contains('/') {
			path := '/usr/share/zoneinfo/${value}'
			exists := os.is_file(path)
			unsafe { path.free() }
			if !exists { return error('timezone database entry is unavailable') }
			daemon.policy.timezone.set(value)!
			os.setenv('TZ', value, true)
			C.tzset()
			daemon.policy.timezone_minutes = time.offset() / 60
		} else {
			daemon.policy.timezone_minutes = int(sessioncore.number(value, -720, 840)!)
			daemon.policy.timezone = sessioncore.Text{}
		}
		daemon.save_policy()!
	} else if action == 'clock.set' {
		stamp := C.timespec{ tv_sec: sessioncore.number(value, 1577836800, 4102444799)! }
		if C.clock_settime(C.CLOCK_REALTIME, &stamp) != 0 { return error('clock change refused') }
	} else if action == 'clock.sync' {
		for i in 0 .. daemon.supervisor.count {
			if daemon.supervisor.services[i].name.str() == 'clock-sync' {
				enabled := daemon.supervisor.services[i].enabled
				daemon.supervisor.enable(i, !enabled)!
				daemon.save_services() or {
					daemon.supervisor.enable(i, enabled) or {}
					return err
				}
				return
			}
		}
		return error('network clock service unavailable')
	} else if action == 'gestures.enable' {
		daemon.policy.gestures = !daemon.policy.gestures
		daemon.save_policy()!
	} else if action.starts_with('corner.') {
		i := int(sessioncore.number(action['corner.'.len..], 0, 3)!)
		next := match daemon.policy.corners[i].str() {
			'' { 'overview' }
			'overview' { 'show-desktop' }
			'show-desktop' { 'notifications' }
			else { '' }
		}
		daemon.policy.corners[i].set(next)!
		daemon.save_policy()!
	} else if action == 'shortcut.reset' {
		daemon.policy.bindings = [64]sessioncore.Binding{}
		daemon.policy.count = 0
		daemon.save_policy()!
	} else if action == 'shortcut.bind' && message.count == 4 {
		daemon.policy.bind(value, message.fields[3].str())!
		daemon.save_policy()!
	} else {
		mut tool := ''
		mut args := []string{}
		defer { unsafe { (&array(&args)).free() } }
		if action.starts_with('bluetooth.') {
			tool = 'bluetoothctl'
			if action in ['bluetooth.pair', 'bluetooth.remove'] {
				if value.len != 17 { return error('enter a Bluetooth device address') }
				for i, byte in value {
					if i % 3 == 2 {
						if byte != `:` { return error('invalid Bluetooth address') }
					} else if !((byte >= `0` && byte <= `9`) || (byte >= `a` && byte <= `f`) || (byte >= `A` && byte <= `F`)) {
						return error('invalid Bluetooth address')
					}
				}
			}
			match action {
				'bluetooth.on' { args = ['power', 'on'] }
				'bluetooth.off' { args = ['power', 'off'] }
				'bluetooth.scan' { args = ['--timeout', '10', 'scan', 'on'] }
				'bluetooth.pair' { args = ['pair', value] }
				'bluetooth.remove' { args = ['remove', value] }
				else { return error('unknown Bluetooth control') }
			}
		} else if action.starts_with('printers.') {
			if action != 'printers.list' && (!sessioncore.identifier(value) || value.starts_with('-')) {
				return error('invalid printer queue')
			}
			match action {
				'printers.list' {
					tool = 'lpstat'
					args = ['-p', '-d']
				}
				'printers.default' {
					tool = 'lpoptions'
					args = ['-d', value]
				}
				'printers.enable' {
					tool = 'cupsenable'
					args = [value]
				}
				'printers.disable' {
					tool = 'cupsdisable'
					args = [value]
				}
				'printers.remove' {
					tool = 'lpadmin'
					args = ['-x', value]
				}
				else { return error('unknown printer control') }
			}
		} else if action.starts_with('network.') {
			if action != 'network.status' && (!sessioncore.identifier(value) || value.starts_with('-')) {
				return error('invalid network interface')
			}
			match action {
				'network.status' {
					tool = 'ifconfig'
					args = ['-a']
				}
				'network.up' {
					tool = 'ifconfig'
					args = [value, 'up']
				}
				'network.down' {
					tool = 'ifconfig'
					args = [value, 'down']
				}
				'network.dhcp' {
					tool = 'dhclient'
					args = [value]
				}
				else { return error('unknown network control') }
			}
		} else if action.starts_with('users.') {
			if !sessioncore.identifier(value) || value.starts_with('-') || value == 'root' {
				return error('invalid account name')
			}
			match action {
				'users.add' {
					tool = 'useradd'
					args = ['-m', value]
				}
				'users.lock' {
					tool = 'usermod'
					args = ['-L', value]
				}
				else { return error('unknown account control') }
			}
		} else if action == 'updates.check' {
			tool = 'vinix-version-check'
		} else {
			return error('unknown settings control')
		}
		program := session_tool(tool)
		defer { unsafe { program.free() } }
		if program.len == 0 { return error('backend unavailable') }
		if daemon.operation_pid > 0 { return error('another settings operation is running') }
		mut service := sessioncore.Service{ name: sessioncore.text('settings-operation')!, executable: sessioncore.text(program)! }
		for i, arg in args { service.arguments[i].set(arg)! }
		service.argument_count = args.len
		process := serviceprocess.start(service, daemon.home)
		daemon.operation_pid = process.pid
		daemon.operation_lease = process.lease
		if daemon.operation_pid <= 0 { return error('could not start settings operation') }
		daemon.operation_deadline = sessionipc.monotonic_millis() + 30000
		daemon.settings_result.set('Operation running. View settings-operation.log for details.')!
		return
	}
	daemon.settings_result.set('Setting applied.')!
}
