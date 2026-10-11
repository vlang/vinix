// SPDX-License-Identifier: GPL-2.0-or-later
// Local package-frontend fixture; never downloads game files.
module main

import os

fn setup(work string) ! {
	tools := os.join_path(work, 'minecraft-tools')
	os.mkdir_all(tools)!
	program := os.join_path(tools, 'fetch-minecraft')
	os.cp(os.executable(), program)!
	os.chmod(program, 0o755)!
	certificates := os.join_path(work, 'root/usr/share/ca-certificates/mozilla')
	os.mkdir_all(certificates)!
	os.write_file(os.join_path(certificates, 'fixture.crt'),
		'-----BEGIN CERTIFICATE-----\nYWJj\n-----END CERTIFICATE-----\n')!
}

fn fetch(arguments []string) ! {
	mut options := map[string]string{}
	mut index := 0
	for index < arguments.len {
		if arguments[index] == '--no-assets' {
			index++
			continue
		}
		if index + 1 >= arguments.len { return error('missing fixture argument') }
		options[arguments[index]] = arguments[index + 1]
		index += 2
	}
	for name in ['--staging', '--game-root', '--max-java'] {
		if name !in options { return error('missing fixture option ${name}') }
	}
	root := os.join_path(options['--staging'], options['--game-root'].trim_left('/'))
	libraries := os.join_path(root, 'libraries/org/lwjgl/lwjgl/3.3.3')
	versions := os.join_path(root, 'versions/1.21.5')
	os.mkdir_all(libraries)!
	os.mkdir_all(versions)!
	os.write_file(os.join_path(libraries, 'lwjgl-3.3.3.jar'), 'core\n')!
	os.write_file(os.join_path(libraries, 'lwjgl-3.3.3-natives-linux-arm64.jar'), 'native\n')!
	os.write_file(os.join_path(versions, '1.21.5.jar'), 'client\n')!
	os.write_file(os.join_path(root, 'launch.env'), "MC_VERSION='1.21.5'\n" +
		"MC_VERSION_TYPE='release'\nMC_ASSET_INDEX='17'\nMC_JAVA_MAJOR='21'\n" +
		"MC_CLASSPATH='/usr/share/minecraft/libraries/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar:/usr/share/minecraft/libraries/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-linux-arm64.jar'\n")!
	os.write_file(os.getenv('VINIX_TEST_MINECRAFT_FETCH_LOG'),
		arguments.join(' ') + '\nmax-java=${options['--max-java']}\n')!
}

fn main() {
	if os.args.len == 3 && os.args[1] == 'setup' {
		setup(os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len < 2 {
		eprintln('missing fixture arguments')
		exit(2)
	}
	fetch(os.args[1..]) or {
		eprintln(err)
		exit(1)
	}
}
