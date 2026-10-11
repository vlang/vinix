// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import net
import os
import strconv
import time

const catalog = ['sqlite', 'media', 'office', 'chromium', 'firefox', 'go', 'java', 'v', 'server',
	'runtime', 'portal', 'games']

struct CommandResult {
	argv              []string
	executable_sha256 string
	environment_overrides map[string]string
	environment_unset []string
	exit_code         int
	timed_out         bool
	output_limited    bool
	stdout            string
	stderr            string
}

struct Verdict {
	name   string
	status string
	detail string
}

struct ServiceResult {
	argv              []string
	executable_sha256 string
	response          string
	exit_code         int
	retired           bool
}

struct Report {
	context                      string
	execution_path               string
	kernel                       string
	suite_sha256                 string
	runtime_probe_sha256         string
	complete_lifecycle_qualified bool
	results                      []Verdict
	commands                     []CommandResult
	services                     []ServiceResult
}

struct Suite {
	work    string
	path    string
	timeout int
	install bool
	runtime string
mut:
	environment map[string]string
	commands []CommandResult
	services []ServiceResult
}

fn stop(mut child os.Process) {
	if child.pid > 0 { child.signal_pgkill() }
	child.wait()
	child.close()
}

fn (suite Suite) command(program string, arguments []string) ![]string {
	if suite.path in ['translated-x86_64', 'translated-i386'] {
		wrapper := if suite.path == 'translated-x86_64' {
			'/usr/bin/run-x86-64'
		} else {
			'/usr/bin/run-x86-32'
		}
		if !os.is_executable(wrapper) {
			return error('unsupported: translator is missing: ' + wrapper)
		}
		if suite.path == 'translated-x86_64' && program == suite.runtime {
			return [wrapper, '--direct', program, ...arguments]
		}
		if suite.path == 'translated-i386' && program == suite.runtime {
			// The static probe has no PT_DYNAMIC for the wrapper's musl loader.
			// Ordinary applications still use the existing private-loader path.
			emulator := os.getenv_opt('VINIX_I386_EMULATOR') or { '/usr/bin/qemu-i386' }
			if !os.is_executable(emulator) {
				return error('unsupported: translator is missing: ' + emulator)
			}
			runtime := os.getenv_opt('VINIX_I386_ROOT') or { '/usr/libexec/vinix-i386/root' }
			return [emulator, '-L', runtime, '-0', program, program, ...arguments]
		}
		return [wrapper, program, ...arguments]
	}
	resolved := if program.contains('/') {
		os.real_path(program)
	} else {
		os.find_abs_path_of_executable(program) or { return error('unsupported: executable is missing: ' + program) }
	}
	if !os.is_executable(resolved) {
		return error('unsupported: executable is missing: ' + resolved)
	}
	return [resolved, ...arguments]
}

fn (mut suite Suite) execute(program string, arguments []string) !string {
	command := suite.command(program, arguments)!
	mut child := os.new_process(command[0])
	child.set_args(command[1..])
	mut overrides := suite.environment.clone()
	mut unset := []string{}
	if suite.path == 'translated-i386' && program == suite.runtime {
		// Match the translator launcher's opt-in without changing the parent
		// environment or leaking a foreign library path to native descendants.
		overrides['VINIX_ALLOW_WX'] = '1'
		unset = ['LD_LIBRARY_PATH', 'QEMU_LD_PREFIX', 'QEMU_SET_ENV']
	}
	if overrides.len > 0 || unset.len > 0 {
		mut environment := os.environ()
		for name, value in overrides { environment[name] = value }
		for name in unset { environment.delete(name) }
		child.set_environment(environment)
	}
	child.set_work_folder(suite.work)
	child.set_redirect_stdio()
	child.use_pgroup = true
	child.run()
	defer { stop(mut child) }
	mut out := ''
	mut err := ''
	watch := time.new_stopwatch()
	mut timed_out := false
	mut output_limited := false
	for {
		if child.is_pending(.stdout) { out += child.stdout_read() }
		if child.is_pending(.stderr) { err += child.stderr_read() }
		if out.len + err.len > 4 * 1024 * 1024 {
			output_limited = true
			child.signal_pgkill()
			break
		}
		if !child.is_alive() { break }
		if watch.elapsed() > suite.timeout * time.second {
			timed_out = true
			child.signal_pgkill()
			break
		}
		time.sleep(10 * time.millisecond)
	}
	child.wait()
	// Retire descendants before collecting the final output; a lingering
	// helper must not keep a pipe or service alive after this workload.
	child.signal_pgkill()
	for child.is_pending(.stdout) {
		block := child.stdout_read()
		if block == '' { break }
		out += block
		if out.len + err.len > 4 * 1024 * 1024 {
			output_limited = true
			break
		}
	}
	for child.is_pending(.stderr) {
		block := child.stderr_read()
		if block == '' { break }
		err += block
		if out.len + err.len > 4 * 1024 * 1024 {
			output_limited = true
			break
		}
	}
	result := CommandResult{
		argv: command
		executable_sha256: sha256.sum(os.read_bytes(command[0])!).hex()
		environment_overrides: overrides
		environment_unset: unset
		exit_code: child.code
		timed_out: timed_out
		output_limited: output_limited
		stdout: out
		stderr: err
	}
	suite.commands << result
	os.write_file('${suite.work}/command-${suite.commands.len}.json', json2.encode(result,
		prettify: true
	) + '\n')!
	if timed_out || output_limited || child.code != 0 {
		return error('command failed: ${command} exit=${child.code} timeout=${timed_out} output_limit=${output_limited}')
	}
	return out
}

fn expect(ok bool, detail string) ! { if !ok { return error(detail) } }

fn native_path() string {
	$if arm64 {
		return 'native-aarch64'
	}
	return 'native-x86_64'
}

fn (mut suite Suite) package(name string) ! {
	if suite.install {
		if suite.path.starts_with('translated-') {
			return error('unsupported: foreign package installation needs a matching private runtime repository')
		}
		suite.execute('/usr/bin/pkg', ['install', name])!
	}
}

fn (mut suite Suite) run(name string) ! {
	suite.environment.clear()
	match name {
		'sqlite' {
			suite.package('sqlite')!
			suite.execute('sqlite3', ['--version'])!
			db := suite.work + '/transaction.db'
			output := suite.execute('sqlite3', ['-batch', db,
				'PRAGMA journal_mode=WAL; CREATE TABLE t(v INTEGER); BEGIN; INSERT INTO t VALUES(19),(23); COMMIT; SELECT sum(v) FROM t;'])!
			expect(output.trim_space() == 'wal\n42', 'SQLite WAL transaction returned incorrect data')!
			reopened := suite.execute('sqlite3', ['-batch', db,
				'PRAGMA integrity_check; SELECT sum(v) FROM t;'])!
			expect(reopened.trim_space() == 'ok\n42', 'SQLite reopen/integrity failed')!
		}
		'media' {
			suite.package('ffmpeg')!
			suite.execute('ffmpeg', ['-version'])!
			video := suite.work + '/video.avi'
			suite.execute('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i',
				'testsrc2=size=64x48:rate=10:duration=1', '-c:v', 'mpeg4', '-threads', '2', '-y',
				video])!
			probe := suite.execute('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries',
				'stream=codec_name,width,height,nb_frames', '-of', 'csv=p=0', video])!
			expect(probe.trim_space() == 'mpeg4,64,48,10', 'encoded video content is incorrect')!
		}
		'office' {
			suite.package('gnumeric')!
			suite.execute('ssconvert', ['--version'])!
			csv := suite.work + '/sheet.csv'
			sheet := suite.work + '/sheet.gnumeric'
			os.write_file(csv, 'value\n42\n')!
			suite.execute('ssconvert', [csv, sheet])!
			suite.execute('ssconvert', [sheet, suite.work + '/reopened.csv'])!
			expect(os.read_file(suite.work + '/reopened.csv')!.trim_space() == 'value\n42', 'spreadsheet save/reopen changed cells')!
		}
		'chromium', 'firefox' {
			suite.package(name)!
			suite.execute(name, ['--version'])!
			page := suite.work + '/page.html'
			os.write_file(page, '<!doctype html><meta charset="utf-8"><p id="verdict">pending</p><script>document.getElementById("verdict").textContent=6*7;</script>')!
			if name == 'chromium' {
				dom := suite.execute(name, ['--headless', '--dump-dom', 'file://' + page])!
				expect(dom.contains('id="verdict">42</p>'), 'browser did not execute page JavaScript')!
			} else {
				png := suite.work + '/firefox.png'
				suite.execute(name, ['--headless', '--screenshot', png, 'file://' + page])!
				bytes := os.read_bytes(png)!
				expect(bytes.len > 256 && bytes[..8] == [u8(137), 80, 78, 71, 13, 10, 26, 10], 'Firefox did not render a PNG')!
			}
		}
		'go' {
			if suite.path != 'native-aarch64' {
				return error('unsupported: existing Go application fixture asserts GOARCH=arm64')
			}
			suite.package('go')!
			// Alpine trims the compiled-in GOROOT. PID 1 does not source the
			// login profile used by the existing Go smoke script.
			if os.is_dir('/usr/lib/go') { suite.environment['GOROOT'] = '/usr/lib/go' }
			suite.environment['GOCACHE'] = suite.work + '/go-cache'
			suite.environment['CGO_ENABLED'] = '0'
			suite.execute('go', ['version'])!
			os.write_file(suite.work + '/smoke.go', $embed_file('../../../tests/go/smoke.go').to_string())!
			suite.execute('go', ['build', '-o', suite.work + '/go-smoke', suite.work + '/smoke.go'])!
			output := suite.execute(suite.work + '/go-smoke', [])!
			expect(output.contains('GO SMOKE PASS'), 'Go application did not pass')!
		}
		'java' {
			if suite.path != 'native-aarch64' {
				return error('unsupported: existing Java application fixture asserts os.arch=aarch64')
			}
			suite.package('openjdk21-jdk')!
			// HotSpot needs writable executable code pages. Request the existing
			// compatibility exception only for these children; exec still
			// requires a privileged launcher or an administrator's wxallowed mount.
			suite.environment['VINIX_ALLOW_WX'] = '1'
			suite.execute('java', ['-version'])!
			os.write_file(suite.work + '/VinixJavaSmoke.java', $embed_file('../../../tests/java/VinixJavaSmoke.java').to_string())!
			suite.execute('javac', [suite.work + '/VinixJavaSmoke.java'])!
			output := suite.execute('java', ['-Xms16m', '-Xmx128m', '-cp', suite.work, 'VinixJavaSmoke'])!
			expect(output.contains('on Vinix: PASS'), 'Java application did not pass')!
			archive := suite.work + '/vinix-java-smoke.jar'
			suite.execute('jar', ['--create', '--file', archive, '-C', suite.work, 'VinixJavaSmoke.class'])!
			archived := suite.execute('java', ['-Xms16m', '-Xmx128m', '-cp', archive, 'VinixJavaSmoke'])!
			expect(archived.contains('on Vinix: PASS'), 'Java JAR application did not pass')!
		}
		'v' {
			suite.execute('v', ['version'])!
			os.write_file(suite.work + '/program.v', "import os\nfn main() { os.write_file(os.args[1], '42')!; println(os.read_file(os.args[1])!) }\n")!
			suite.execute('v', ['-o', suite.work + '/v-smoke', suite.work + '/program.v'])!
			expect(suite.execute(suite.work + '/v-smoke', [suite.work + '/v-data'])!.trim_space() == '42', 'V compile/file workload failed')!
		}
		'server' { suite.server()! }
		'runtime' {
			if suite.runtime == '' {
				return error('unsupported: supply --runtime-probe with the matching ELF fixture')
			}
			output := suite.execute(suite.runtime, ['--once'])!
			expect(output.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && output.contains('LINUX RUNTIME PASS: JIT page sizes') && output.contains('LINUX RUNTIME PASS: wide offsets time64') && output.contains('LINUX RUNTIME: PASS'), 'runtime predicates did not all pass')!
		}
		'portal' {
			suite.execute('gdbus', ['call', '--session', '--dest', 'org.freedesktop.portal.Desktop',
				'--object-path', '/org/freedesktop/portal/desktop', '--method',
				'org.freedesktop.DBus.Properties.Get', 'org.freedesktop.portal.FileChooser', 'version'])!
			return error('unsupported: portal discovery does not qualify a user-mediated file chooser/save workflow')
		}
		'games' {
			return error('unsupported: title-specific licensed assets, GPU/input/audio, save and anti-cheat qualification are required; see docs/linux-posix-compatibility.md')
		}
		else { return error('unknown workload: ' + name) }
	}
}

fn (mut suite Suite) server() ! {
	// This is ordinary CLI service supervision, independent of systemd units.
	if suite.path.starts_with('translated-') {
		return error('unsupported: translated server service lifecycle needs its own integration')
	}
	mut server := 'busybox'
	mut applets := suite.execute(server, ['--list'])!
	if 'httpd' !in applets.split_into_lines() {
		suite.package('busybox-extras')!
		server = 'busybox-extras'
		applets = suite.execute(server, ['--list'])!
		if 'httpd' !in applets.split_into_lines() {
			return error('unsupported: installed BusyBox and BusyBox Extras lack the httpd applet')
		}
	}
	os.mkdir(suite.work + '/www')!
	content := 'vinix-server-42-' + sha256.sum(suite.work.bytes()).hex()
	os.write_file(suite.work + '/www/index.html', content)!
	command := suite.command(server, ['httpd', '-f', '-p', '127.0.0.1:19015', '-h',
		suite.work + '/www'])!
	executable_hash := sha256.sum(os.read_bytes(command[0])!).hex()
	mut response := ''
	mut child := os.new_process(command[0])
	child.set_args(command[1..])
	child.use_pgroup = true
	child.run()
	defer {
		stop(mut child)
		suite.services << ServiceResult{command, executable_hash, response, child.code, !child.is_alive()}
	}
	watch := time.new_stopwatch()
	for {
		if !child.is_alive() { return error('HTTP service exited before readiness') }
		mut conn := net.dial_tcp('127.0.0.1:19015') or {
			if watch.elapsed() > 5 * time.second {
				return error('HTTP service was not ready after five seconds')
			}
			time.sleep(20 * time.millisecond)
			continue
		}
		conn.set_read_timeout(2 * time.second)
		conn.write_string('GET / HTTP/1.0\r\nHost: localhost\r\n\r\n')!
		mut bytes := [4096]u8{}
		for {
			n := conn.read(mut bytes) or { break }
			if n == 0 { break }
			response += bytes[..n].bytestr()
			if response.len > 65536 {
				conn.close()!
				return error('unbounded HTTP response')
			}
		}
		conn.close()!
		expect((response.starts_with('HTTP/1.0 200 ') || response.starts_with('HTTP/1.1 200 ')) && response.all_after('\r\n\r\n') == content, 'HTTP service returned incorrect content')!
		break
	}
}

fn main() {
	mut values := map[string]string{}
	for arg in os.args[1..] {
		key := arg.all_before('=')
		if key !in ['--work', '--cases', '--path', '--timeout', '--runtime-probe', '--host', '--install'] || key in values {
			eprintln('Usage: workloads --work=FRESH-DIR [--cases=sqlite,media,...] [--path=native-aarch64|native-x86_64|translated-x86_64|translated-i386] [--timeout=SECONDS] [--runtime-probe=ELF] [--host] [--install]')
			exit(2)
		}
		if (key in ['--host', '--install'] && arg.contains('=')) || (key !in ['--host', '--install'] && (!arg.contains('=') || arg.all_after('=') == '')) {
			eprintln('invalid option value: ' + arg)
			exit(2)
		}
		values[key] = if arg.contains('=') { arg.all_after('=') } else { 'true' }
	}
	work := values['--work'] or {
		eprintln('--work=FRESH-DIR is required')
		exit(2)
	}
	path := values['--path'] or { native_path() }
	if path !in ['native-aarch64', 'native-x86_64', 'translated-x86_64', 'translated-i386'] {
		eprintln('invalid execution path')
		exit(2)
	}
	$if arm64 {
		if path == 'native-x86_64' {
			eprintln('native path does not match the driver architecture')
			exit(2)
		}
	} $else {
		if path != 'native-x86_64' {
			eprintln('this driver requires native x86-64 execution')
			exit(2)
		}
	}
	timeout := strconv.atoi(values['--timeout'] or { '120' }) or {
		eprintln('invalid timeout')
		exit(2)
	}
	cases := (values['--cases'] or { catalog.join(',') }).split(',')
	mut seen := map[string]bool{}
	for name in cases {
		if name in seen {
			eprintln('duplicate workload')
			exit(2)
		}
		seen[name] = true
	}
	if timeout <= 0 || cases.len == 0 || cases.any(it !in catalog) {
		eprintln('invalid timeout/cases')
		exit(2)
	}
	host := '--host' in values
	if host && '--install' in values {
		eprintln('--install is permitted only inside Vinix')
		exit(2)
	}
	version := os.read_file('/proc/version') or { os.uname().sysname }
	if !host && !version.to_lower().contains('vinix') {
		eprintln('run inside Vinix, or use --host for explicitly host-only evidence')
		exit(2)
	}
	if os.exists(work) {
		eprintln('work directory must be fresh')
		exit(2)
	}
	os.mkdir_all(work) or {
		eprintln(err.msg())
		exit(1)
	}
	mut suite := Suite{ work: os.real_path(work), path: path, timeout: timeout, install: '--install' in values, runtime: values['--runtime-probe'] or { '' } }
	mut verdicts := []Verdict{}
	for name in cases {
		suite.run(name) or {
			status := if err.msg().starts_with('unsupported:') { 'unsupported' } else { 'failed' }
			verdicts << Verdict{name, status, err.msg()}
			println('${name}: ${status}: ${err.msg()}')
			continue
		}
		verdicts << Verdict{name, 'passed', 'workload predicates passed; full install/update/desktop lifecycle remains separate'}
		println(name + ': passed')
	}
	runtime_hash := if suite.runtime != '' {
		sha256.sum(os.read_bytes(suite.runtime) or { []u8{} }).hex()
	} else {
		''
	}
	report := Report{if host { 'host' } else { 'vinix-guest' }, path, version, sha256.sum(os.read_bytes(os.executable()) or { []u8{} }).hex(), runtime_hash, false, verdicts, suite.commands, suite.services}
	os.write_file(suite.work + '/report.json', json2.encode(report, prettify: true) + '\n') or {
		eprintln(err.msg())
		exit(1)
	}
	if verdicts.any(it.status != 'passed') { exit(1) }
}
