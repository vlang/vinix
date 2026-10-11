// SPDX-License-Identifier: GPL-2.0-or-later
import bundlehost as bh
import json2
import minecraftnative as mc
import os

fn parsed(text string) !json2.Any { return json2.decode[json2.Any](text)! }

fn reject(operation fn () !, expected string) ! {
	mut rejected := false
	operation() or {
		if !err.msg().contains(expected) { return err }
		rejected = true
	}
	assert rejected
}

fn versions() ! {
	java25 := '{"id":"26.2","type":"release","javaVersion":{"majorVersion":25}}'.bytes()
	java21 := '{"id":"1.21.5","type":"release","javaVersion":{"majorVersion":21}}'.bytes()
	manifest := ('{"latest":{"release":"26.2","snapshot":"26.3-snapshot-1"},"versions":[{"id":"26.2","type":"release","url":"https://fixture/25","sha1":"' + mc.digest(java25) + '"},{"id":"1.21.5","type":"release","url":"https://fixture/21","sha1":"' + mc.digest(java21) + '"}]}').bytes()
	source := mc.Source{
		fixture:   true
		responses: {
			mc.manifest_url:      manifest
			'https://fixture/25': java25
			'https://fixture/21': java21
		}
	}
	id, version := source.resolve_version('release', 21)!
	assert id == '1.21.5' && mc.field(mc.field(version, 'javaVersion')!, 'majorVersion')!.int() == 21
	latest, _ := source.resolve_version('release', none)!
	assert latest == '26.2'
	reject(fn [source] () ! { source.resolve_version('26.2', 21)! }, 'needs Java 25')!
	reject(fn [source] () ! { source.resolve_version('release', 7)! }, 'no Minecraft release supports Java 7')!
	reject(fn [source] () ! { source.resolve_version('missing', none)! }, 'unknown Minecraft version')!
	reject(fn [source] () ! {
		source.fetch_version(parsed('{"id":"bad","url":"https://fixture/21","sha1":"bad"}')!)!
	}, 'checksum mismatch')!
	println('PASS version selection, Java bounds, latest, unknown version and independent SHA1')
}

fn policy(work string) ! {
	for row in [
		['[]', 'true'],
		['[{"action":"allow","os":{"name":"linux","arch":"arm64"}}]', 'true'],
		['[{"action":"allow","os":{"name":"windows"}}]', 'false'],
		['[{"action":"disallow","os":{"name":"windows"}}]', 'true'],
		['[{"action":"allow"},{"action":"disallow","os":{"name":"linux"}}]', 'false'],
		['[{"action":"disallow"},{"action":"allow","os":{"name":"linux"}}]', 'true'],
		['[{"action":"allow","os":{"version":".*"}}]', 'false'],
		['[{"action":"allow","os":{"versionRange":".*"}}]', 'false'],
		['[{"action":"allow","features":{"unknown":false}}]', 'true'],
		['[{"action":"allow","features":{"unknown":true}}]', 'false'],
	] {
		assert mc.rule_allows(parsed(row[0])!, map[string]bool{})! == (row[1] == 'true')
	}
	assert mc.rule_allows(json2.Any(json2.Null{}), map[string]bool{})!
	assert mc.maven_path('org.lwjgl:lwjgl:3.3.3:natives-linux-arm64')! == 'org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-linux-arm64.jar'
	reject(fn () ! { mc.maven_path('../bad:a:1')! }, 'Invalid Maven')!
	for path in ['/outside', '../outside', 'a/../outside', 'a\\outside', 'a//outside'] {
		reject(fn [path] () ! { mc.safe_relative(path)! }, 'Unsafe download path')!
	}
	version := parsed(r'{"type":"release","mainClass":"net.minecraft.client.main.Main","javaVersion":{"majorVersion":21},"arguments":{"jvm":["-Xmx2G","-cp","${classpath}","-Dsample=1"],"game":["--username","${auth_player_name}",{"rules":[{"action":"allow","features":{"is_demo_user":true}}],"value":"--demo"},{"rules":[{"action":"allow","features":{"has_custom_resolution":true}}],"value":["--width","${resolution_width}","--height","${resolution_height}"]}]}}')!
	mc.write_launch_env(work + '/launch.env', "version'quoted", version, ['lib a.jar', 'client.jar'], '17', '/usr/share/game')!
	content := os.read_file(work + '/launch.env')!
	assert content.contains(r'--width ${resolution_width} --height ${resolution_height}')
	assert content.contains("MC_VERSION='version'\\''quoted'")
	assert content.contains("MC_JVM_ARGS='-Xmx2G -Dsample=1'")
	assert content.contains("MC_CLASSPATH='/usr/share/game/lib a.jar:/usr/share/game/client.jar'")
	assert content.split_into_lines().filter(it.starts_with('MC_GAME_ARGS_DEMO='))[0].contains('--demo')
	assert !content.split_into_lines().filter(it.starts_with('MC_GAME_ARGS_FULL='))[0].contains('--demo')
	// An independent POSIX shell evaluates quoting and literal substitutions.
	result := os.exec(['/bin/sh', '-c', '. "$1"; printf "%s\n%s\n" "$MC_VERSION" "$MC_GAME_ARGS_FULL"',
		'env-check', work + '/launch.env'])
	assert result.exit_code == 0 && result.output.starts_with("version'quoted\n") && result.output.contains(r'${resolution_width}')
	println('PASS target rules, last match, Maven paths, shell quoting and custom resolution for demo/full profiles')
}

fn downloads(work string) ! {
	data := 'native download fixture\x00\xff'.bytes()
	checksum := mc.digest(data)
	source := mc.Source{
		fixture:   true
		responses: {
			'https://fixture/good': data
		}
	}
	assert source.download_to('https://fixture/good', work + '/download', checksum)!
	assert !source.download_to('https://fixture/missing', work + '/download', checksum)!
	assert !source.download_to('https://fixture/missing', work + '/download', none)!
	before := os.read_bytes(work + '/download')!
	reject(fn [source, work] () ! {
		source.download_to('https://fixture/good', work + '/download', 'bad')!
	}, 'checksum mismatch')!
	assert os.read_bytes(work + '/download')! == before
	mut entries := []mc.Download{}
	for i in 0 .. 40 { entries << mc.Download{'many/' + i.str(), 'https://fixture/good', checksum} }
	source.download_all(entries, work, 'libraries', 8)!
	source.download_all(entries, work, 'libraries', 8)!
	for entry in entries {
		assert os.read_bytes(work + '/' + entry.path)! == data
	}
	bad := [mc.Download{'bad', 'https://fixture/missing', checksum},
		mc.Download{'other', 'https://fixture/good', checksum}]
	reject(fn [source, bad, work] () ! { source.download_all(bad, work, 'failure', 2)! }, 'No fixture response')!
	assert os.read_bytes(work + '/other')! == data
	for path in os.walk_ext(work, '') {
		assert !path.contains('.minecraft-download-')
	}
	index := ('{"objects":{"one":{"hash":"' + checksum + '"},"two":{"hash":"' + checksum + '"}}}').bytes()
	assets := mc.Source{
		fixture:   true
		responses: {
			'https://fixture/index':                              index
			mc.assets_url + '/' + checksum[..2] + '/' + checksum: data
		}
	}
	version := parsed('{"assetIndex":{"id":"17","url":"https://fixture/index","sha1":"' + mc.digest(index) + '"}}')!
	assert assets.download_assets(version, work + '/assets-root', 4, false)! == '17'
	assert os.read_bytes(work + '/assets-root/assets/objects/' + checksum[..2] + '/' + checksum)! == data
	assert (os.walk_ext(work + '/assets-root/assets/objects', '')).len == 1
	println('PASS cached/fresh download integrity, failed publication, joined worker failure and asset deduplication')
}

fn libraries() ! {
	version := parsed('{"libraries":[{"name":"org.lwjgl:lwjgl-glfw:3.3.3","downloads":{"artifact":{"path":"glfw.jar","url":"https://fixture/glfw","sha1":"glfw"}}},{"name":"org.lwjgl:lwjgl:3.3.3:unsafe","downloads":{"artifact":{"path":"core.jar","url":"https://fixture/core","sha1":"core"}}},{"name":"org.lwjgl:lwjgl:3.3.3:natives-linux","downloads":{"artifact":{"path":"foreign.jar","url":"https://fixture/foreign","sha1":"foreign"}}},{"name":"org.lwjgl:lwjgl-openal:3.3.3:natives-windows"},{"name":"other:filtered:1","rules":[{"action":"allow","os":{"name":"windows"}}],"downloads":{"artifact":{"path":"filtered.jar","url":"https://fixture/filtered","sha1":"filtered"}}}]}')!
	source := mc.Source{
		fixture:   true
		responses: {
			mc.maven_url + '/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-linux-arm64.jar.sha1':           'core-hash\n'.bytes()
			mc.maven_url + '/org/lwjgl/lwjgl-glfw/3.3.3/lwjgl-glfw-3.3.3-natives-linux-arm64.jar.sha1': 'glfw-hash  file\n'.bytes()
		}
	}
	mojang, natives := source.select_libraries(version)!
	assert mojang.map(it.path) == ['glfw.jar', 'core.jar']
	assert natives.map(it.path) == [
		'org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-linux-arm64.jar',
		'org/lwjgl/lwjgl-glfw/3.3.3/lwjgl-glfw-3.3.3-natives-linux-arm64.jar',
	]
	println('PASS LWJGL core unsafe classifier, foreign native filtering, ordered ARM substitution and missing native')
}

fn main() {
	work := bh.temporary(os.temp_dir(), 'vinix-minecraft-fetch-tests-') or { panic(err) }
	defer { bh.retire(work) }
	versions() or { panic(err) }
	policy(work) or { panic(err) }
	downloads(work) or { panic(err) }
	libraries() or { panic(err) }
	println('MINECRAFT FETCH NATIVE PASS')
}
