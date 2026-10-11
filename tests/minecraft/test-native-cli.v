// SPDX-License-Identifier: GPL-2.0-or-later
// Run against separately cold-built binaries: FETCH LOGIN [STAGER].
import bundlehost as bh
import json2
import minecraftnative as mc
import os
import time

#include <unistd.h>
#include <signal.h>

fn C.fork() int
fn C.getpid() int
fn C.kill(int, int) int

fn parse(text string) !json2.Any { return json2.decode[json2.Any](text)! }

fn write(path string, content string) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, content)!
}

fn payload(root string, name string, content string) !string {
	write(root + '/' + name, content)!
	return 'file://' + root + '/' + name
}

fn checked(argv []string, status int) !string {
	result := os.exec(argv)
	if result.exit_code != status {
		return error(argv[0] + ' returned ' + result.exit_code.str() + ' instead of ' + status.str() + ': ' + result.output)
	}
	return result.output
}

fn combined(first []string, second []string) []string {
	mut result := first.clone()
	result << second
	return result
}

fn fixture(root string, hang bool) ![]string {
	client := payload(root, 'client', 'fixture-client')!
	core := payload(root, 'core', 'fixture-core')!
	asset_hash := mc.digest('fixture-asset'.bytes())
	payload(root, 'assets/' + asset_hash[..2] + '/' + asset_hash, 'fixture-asset')!
	index := '{"objects":{"first":{"hash":"' + asset_hash + '"},"alias":{"hash":"' + asset_hash + '"}}}'
	index_url := payload(root, 'index', index)!
	native := 'maven/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-linux-arm64.jar'
	payload(root, native, 'fixture-native')!
	payload(root, native + '.sha1', mc.digest('fixture-native'.bytes()) + '\n')!
	mut libraries := []json2.Any{}
	if hang {
		for i in 0 .. 12 {
			libraries << parse('{"name":"fixture:core' + i.str() + ':1","downloads":{"artifact":{"path":"core' + i.str() + '.jar","url":"https://fixture.invalid/hang/core' + i.str() + '","sha1":"' + mc.digest('fixture-core'.bytes()) + '"}}}')!
		}
	} else {
		libraries << parse('{"name":"org.lwjgl:lwjgl:3.3.3:unsafe","downloads":{"artifact":{"path":"core.jar","url":"' + core + '","sha1":"' + mc.digest('fixture-core'.bytes()) + '"}}}')!
		libraries << parse('{"name":"org.lwjgl:lwjgl:3.3.3:natives-linux","downloads":{"artifact":{"path":"foreign.jar","url":"file:///missing","sha1":"bad"}}}')!
	}
	mut version := parse('{"id":"fixture","type":"release","mainClass":"net.minecraft.client.main.Main","javaVersion":{"majorVersion":21},"downloads":{"client":{"url":"' + client + '","sha1":"' + mc.digest('fixture-client'.bytes()) + '"}},"assetIndex":{"id":"fixture-index","url":"' + index_url + '","sha1":"' + mc.digest(index.bytes()) + '"}}}')!.as_map()
	version['libraries'] = json2.Any(libraries)
	version['arguments'] = parse(r'{"jvm":["-Xmx2G","-cp","${classpath}"],"game":["--username","${auth_player_name}",{"rules":[{"action":"allow","features":{"is_demo_user":true}}],"value":"--demo"},{"rules":[{"action":"allow","features":{"has_custom_resolution":true}}],"value":["--width","${resolution_width}","--height","${resolution_height}"]}]}')!
	low := json2.encode(json2.Any(version))
	version['javaVersion'] = parse('{"majorVersion":25}')!
	high := json2.encode(json2.Any(version))
	low_url := payload(root, 'version21', low)!
	high_url := payload(root, 'version25', high)!
	manifest := '{"latest":{"release":"high"},"versions":[{"id":"high","type":"release","url":"' + high_url + '","sha1":"' + mc.digest(high.bytes()) + '"},{"id":"fixture","type":"release","url":"' + low_url + '","sha1":"' + mc.digest(low.bytes()) + '"}]}'
	manifest_url := payload(root, 'manifest', manifest)!
	return ['--manifest', manifest_url, '--maven', 'file://' + root + '/maven', '--assets',
		'file://' + root + '/assets', '--max-java', '21', '--jobs', '8', '--game-root',
		'/usr/share/game with space']
}

fn cli(work string, fetch string, login string) ! {
	args := fixture(work + '/source', false)!
	stage := work + '/staging'
	full := checked(combined([fetch, '--staging', stage], args), 0)!
	assert full.contains('Minecraft fixture') && full.contains('1 downloaded')
	root := stage + '/usr/share/game with space'
	assert os.read_file(root + '/versions/fixture/fixture.jar')! == 'fixture-client'
	assert os.read_file(root + '/libraries/core.jar')! == 'fixture-core'
	assert os.read_file(root + '/libraries/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-linux-arm64.jar')! == 'fixture-native'
	assert !os.exists(root + '/libraries/foreign.jar')
	assert os.walk_ext(root + '/assets/objects', '').len == 1
	env := os.read_file(root + '/launch.env')!
	assert env.contains("MC_JVM_ARGS='-Xmx2G'") && env.contains(r'${resolution_width}')
	assert env.split_into_lines().filter(it.starts_with('MC_GAME_ARGS_DEMO='))[0].contains('--demo')
	assert !env.split_into_lines().filter(it.starts_with('MC_GAME_ARGS_FULL='))[0].contains('--demo')
	assert checked(combined([fetch, '--staging', stage], args), 0)!.contains('0 downloaded')
	no_assets := work + '/index-only'
	checked(combined([fetch, '--staging', no_assets, '--no-assets'], args), 0)!
	assert os.exists(no_assets + '/usr/share/game with space/assets/indexes/fixture-index.json')
	assert !os.exists(no_assets + '/usr/share/game with space/assets/objects')
	write(work + '/source/client', 'corrupted')!
	write(root + '/versions/fixture/fixture.jar', 'previous')!
	assert checked(combined([fetch, '--staging', stage], args), 1)!.contains('checksum mismatch')
	assert os.read_file(root + '/versions/fixture/fixture.jar')! == 'previous'
	for invalid in [['--jobs', '0'], ['--jobs', '65'], ['--game-root', 'relative'], ['--unknown'],
		['--max-java', 'invalid']] {
		checked(combined([fetch, '--staging', stage], invalid), 2)!
	}
	checked([fetch, '--help'], 0)!
	checked([login, '--help'], 0)!
	checked([login], 2)!
	assert checked([login, '--session', work + '/no-account', '--client-id='], 1)!.contains('no Microsoft application id')
	assert !os.exists(work + '/no-account')
	assert os.walk_ext(work, '').all(!it.contains('.minecraft-download-'))
	println('PASS real curl full/cache/index-only, assets/native substitution, checksum rollback, CLI statuses and sign-in preflight')
}

fn curl_shim() ! {
	if os.args.any(it.contains('/hang/core')) {
		pids := os.getenv('MINECRAFT_TEST_PIDS')
		write(pids + '/' + C.getpid().str(), 'worker')!
		child := C.fork()
		if child < 0 { return error('Cannot fork curl fixture descendant') }
		if child == 0 { write(pids + '/' + C.getpid().str(), 'descendant')! }
		for { time.sleep(50 * time.millisecond) }
	}
	os.execvp('/usr/bin/curl', os.args[1..])!
}

fn interrupts(work string, fetch string) ! {
	args := fixture(work + '/interrupt-source', true)!
	os.mkdir_all(work + '/shim')!
	os.symlink(os.executable(), work + '/shim/curl')!
	for signal in [C.SIGINT, C.SIGTERM] {
		stage := work + '/interrupted-' + signal.str()
		pids := work + '/pids-' + signal.str()
		os.mkdir_all(pids)!
		mut child := os.new_process(fetch)
		child.set_args(combined(['--staging', stage], args))
		mut environment := os.environ()
		environment['PATH'] = work + '/shim:' + os.getenv('PATH')
		environment['MINECRAFT_TEST_PIDS'] = pids
		child.set_environment(environment)
		child.set_redirect_stdio()
		child.run()
		defer { child.close() }
		deadline := time.sys_mono_now() + u64(10 * time.second)
		for os.ls(pids)!.len < 16 && child.is_alive() && time.sys_mono_now() < deadline {
			time.sleep(10 * time.millisecond)
		}
		if os.ls(pids)!.len != 16 {
			child.signal_kill()
			child.wait()
			return error('Did not observe eight concurrent curl workers and descendants: ' + child.stdout_slurp() + child.stderr_slurp())
		}
		C.kill(child.pid, signal)
		limit := time.sys_mono_now() + u64(5 * time.second)
		for child.is_alive() && time.sys_mono_now() < limit { time.sleep(10 * time.millisecond) }
		if child.is_alive() {
			child.signal_kill()
			child.wait()
			return error('Interrupted fetcher did not terminate')
		}
		child.wait()
		assert child.code == 128 + signal
		for name in os.ls(pids)! {
			pid := name.int()
			for C.kill(pid, 0) == 0 && time.sys_mono_now() < limit {
				time.sleep(10 * time.millisecond)
			}
			assert C.kill(pid, 0) != 0
		}
		assert os.walk_ext(stage, '').all(!it.contains('.minecraft-download-'))
		println('PASS signal ' + signal.str() + ': status ' + child.code.str() + ', sixteen worker/descendant PIDs retired and no partial downloads')
	}
}

fn stage(work string, stager string) ! {
	for arch in ['aarch64', 'x86_64'] {
		directory := work + '/guest-' + arch
		os.mkdir_all(directory)!
		checked([stager, '--arch', arch, '--staging', directory], 0)!
		for tool in ['fetch-minecraft', 'minecraft-login'] {
			path := directory + '/usr/libexec/vinix-minecraft/' + tool
			mut file := os.open(path)!
			header := file.read_bytes(64)
			file.close()
			assert header[..6] == [u8(0x7f), `E`, `L`, `F`, 2, 1]
			assert int(header[18]) | (int(header[19]) << 8) == if arch == 'aarch64' {
				183
			} else {
				62
			}
			assert os.stat(path)!.mode & 0o777 == 0o755
		}
		path := directory + '/usr/libexec/vinix-minecraft/fetch-minecraft'
		previous := os.read_bytes(path)!
		checked([stager, '--arch', arch, '--staging', directory, '--cc', '/usr/bin/clang'], 1)!
		assert os.read_bytes(path)! == previous
	}
	println('PASS both static guest architectures, fetcher/sign-in ELF identities and failed-build preservation')
}

fn main() {
	if os.base(os.args[0]) == 'curl' {
		curl_shim() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len !in [3, 4] {
		eprintln('Usage: test-native-cli FETCH LOGIN [STAGER]')
		exit(2)
	}
	work := bh.temporary(os.temp_dir(), 'vinix-minecraft-cli-tests-') or { panic(err) }
	defer { bh.retire(work) }
	cli(work, os.args[1], os.args[2]) or { panic(err) }
	interrupts(work, os.args[1]) or { panic(err) }
	if os.args.len == 4 { stage(work, os.args[3]) or { panic(err) } }
	println('MINECRAFT NATIVE CLI PASS')
}
