module sessioncore

fn test_linux_unit_import_preserves_argv_and_lifecycle() {
	unit := '[Unit]\nDescription=HTTP service\n[Service]\nType=simple\nExecStart=/usr/bin/busybox httpd -f -h "/home/user/My Files" "" \'literal;argument\'\nRestart=on-failure\nRestartSec=0.125s\nTimeoutStopSec=2s\n[Install]\nWantedBy=default.target\n'
	service := import_linux_service('http.service', unit, true)!
	assert service.executable.str() == '/usr/bin/busybox'
	assert service.argument_count == 6
	assert service.arguments[3].str() == '/home/user/My Files'
	assert service.arguments[4].len == 0 && service.arguments[5].str() == 'literal;argument'
	assert service.restart == .on_failure && service.restart_delay_ms == 125 && service.stop_timeout_ms == 2000
	mut supervisor := Supervisor{count: 1}
	supervisor.services[0] = service
	supervisor.validate()!
	assert supervisor.tick(0).count == 1
	supervisor.started(0, 42, 0)
	supervisor.exited(0, 1, 100)
	assert supervisor.services[0].state == .backoff
	assert supervisor.tick(224).count == 0 && supervisor.tick(225).count == 1
	record := supervisor.encode()
	restored := decode_services(record, false)!
	assert restored.services[0].arguments[3].str() == '/home/user/My Files'
	assert restored.services[0].enabled && !restored.services[0].system
}

fn test_linux_units_reject_unsupported_security_and_service_requirements() {
	base := '[Service]\nType=simple\nExecStart=/bin/sleep 60\n'
	for directive in ['User=nobody', 'Group=users', 'NoNewPrivileges=yes', 'PrivateNetwork=yes',
		'SystemCallFilter=@system-service', 'ProtectSystem=strict', 'Environment=A=B',
		'WorkingDirectory=/tmp', 'ExecStartPre=/bin/true', 'KillMode=process', 'RootDirectory=/srv'] {
		import_linux_service('test.service', base + directive + '\n', true) or { continue }
		assert false, 'silently discarded required unit semantics'
	}
	for unit in ['[Service]\nType=notify\nExecStart=/bin/sleep 60',
		base + 'ExecStart=/bin/true', base + 'RestartSec=0', base + 'TimeoutStopSec=90s',
		'[Unit]\nRequires=db.service\n' + base, base + '[Install]\nWantedBy=multi-user.target',
		'[Service]\nExecStart=/bin/sleep 60', '[Service]\nType=simple\nExecStart=-/bin/true',
		'[Service]\nType=simple\nExecStart=/bin/echo $HOME',
		'[Service]\nType=simple\nExecStart=/bin/echo %h',
		'[Service]\nType=simple\nExecStart=/bin/echo "unfinished',
		'[Service]\nType=simple\nExecStart=/bin/echo a"b"',
		'[Service]\nType=simple\nExecStart=/bin/echo "a"b',
		'[Service]\nType=simple\nExecStart=/bin/echo a ; /bin/true'] {
		import_linux_service('test.service', unit, true) or { continue }
		assert false, 'accepted an unsupported or invalid unit'
	}
	service := import_linux_service('test.service', base, false)!
	assert !service.enabled
}
