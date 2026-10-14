// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore
import desktop.ptycore
import tools.packages.pkgprotocol

fn media_command(id string, argv []string, documents []string) Ran {
	mut arguments := ['/usr/bin/vinix-package', 'run-args', id]
	for document in documents { arguments << ['--file', document] }
	arguments << '--'
	arguments << argv
	return run(arguments, '', none, none)
}

fn media_probe(path string, grant bool) Ran {
	return media_command(pkgcore.ffprobe_application_id, ['-v', 'error', '-select_streams', 'v:0',
		'-show_entries', 'stream=codec_name,width,height,nb_frames', '-of', 'csv=p=0', path], if grant { [path] } else { []string{} })
}

fn qualify_package_ffmpeg(mut t Test) ! {
	t.make_accounts()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	roots := '/usr/share/ffmpeg-fixtures'
	t.say('PACKAGE FFMPEG inventory started')
	profile := json2.decode[pkgcore.FfmpegProfileInfo](package_success(['ffmpeg-catalog', '1.0.0', roots, '/tmp/ffmpeg-lock'])!)!
	assert profile.profile == 'ffmpeg-cli' && profile.architectures == ['aarch64', 'x86_64']
	second := json2.decode[pkgcore.FfmpegProfileInfo](package_success(['ffmpeg-catalog', '1.0.0', roots, '/tmp/ffmpeg-lock-again'])!)!
	assert profile.catalog_sha256 == second.catalog_sha256
	t.say('PACKAGE FFMPEG canonical inventory PASS')
	workspace := '/tmp/ffmpeg-workspace'
	catalog := json2.decode[pkgcore.CatalogInfo](package_success(['pack-catalog', profile.catalog, roots, workspace])!)!
	assert catalog.package_count == 6
	os.mkdir_all('/tmp/package-publisher', mode: 0o700)!
	key := package_success(['keygen', '/tmp/package-publisher/ffmpeg-seed'])!.trim_space()
	release := json2.decode[pkgcore.ReleaseInfo](package_success(['publish-release', workspace, 'ffmpeg-fixture',
		'/tmp/package-publisher/ffmpeg-seed', '1', (time.now().unix() + 3600).str(), '/tmp/ffmpeg-release'])!)!
	assert release.public_key == key && release.package_count == 6
	t.say('PACKAGE FFMPEG signed release PASS')
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{
		architecture: architecture, launch_user: 'alex', policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 }
	}))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	package_success(['--offline', 'repo-enroll', 'ffmpeg-fixture', 'file:///tmp/ffmpeg-release', key])!
	package_success(['--offline', 'update'])!
	package_success(['--offline', 'install', pkgcore.ffmpeg_application_id, pkgcore.ffprobe_application_id])!
	installed := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	assert installed.packages.len == 3 && installed.requested.len == 2
	t.say('PACKAGE FFMPEG offline install PASS')
	for id in [pkgcore.ffmpeg_application_id, pkgcore.ffprobe_application_id] {
		banner := media_command(id, ['-version'], [])
		assert banner.status == 0 && banner.output.contains('version 8.0.1'), banner.output
	}
	t.say('PACKAGE FFMPEG ordinary argument banners PASS')
	terminal := ptycore.spawn(['/usr/bin/vinix-package', 'run-terminal-args', pkgcore.ffmpeg_application_id, '--', '-version'],
		['PATH=/usr/bin:/usr/sbin', 'HOME=/root', 'TERM=linux'], '/', 24, 80, 640, 384)!
	defer { C.close(terminal.terminal) }
	assert sqlite_terminal_read(terminal.terminal, 'ffmpeg version 8.0.1')!.contains('ffmpeg version 8.0.1')
	mut terminal_status := i32(0)
	mut terminal_finished := false
	mut terminal_bytes := [4096]u8{}
	for _ in 0 .. 5000 {
		// -version keeps writing configuration/library details after its first
		// line. Drain them while reaping; a full PTY can otherwise block exit.
		C.read(terminal.terminal, &terminal_bytes[0], usize(terminal_bytes.len))
		if C.waitpid(terminal.pid, &terminal_status, C.WNOHANG) == terminal.pid { terminal_finished = true; break }
		time.sleep(10 * time.millisecond)
	}
	assert terminal_finished && terminal_status == 0
	t.say('PACKAGE FFMPEG terminal argument banner PASS')
	data := '/home/alex/.local/share/vinix-apps/' + pkgcore.ffmpeg_application_id
	mut relative_words := pkgprotocol.command_words('-v error -f lavfi -i testsrc2=size=64x48:duration=0.1 -c:v mpeg4 -threads 2 -y "relative output; $literal.avi"')!
	defer { pkgprotocol.free_command_values(mut relative_words) }
	mut relative_vector := pkgprotocol.command_vector(pkgcore.ffmpeg_application_id, relative_words, [], true, false)!
	defer { pkgprotocol.free_command_values(mut relative_vector) }
	relative_reply := run(['/usr/bin/vinix-package', ...relative_vector], '', none, none)
	assert relative_reply.status == 0, relative_reply.output
	relative_path := data + '/relative output; $literal.avi'
	assert os.file_size(relative_path) > 0 && os.stat(relative_path)!.uid == 1000
	assert media_probe(relative_path, true).status == 0
	assert media_probe(relative_path, false).status != 0
	installed_folder := '/var/lib/vinix-packages/generations/' + installed.generation.str() + '/apps/' + pkgcore.ffmpeg_application_id
	assert !os.exists(installed_folder + '/relative output; $literal.avi')
	t.say('PACKAGE COMMAND private-working-folder quoted-arguments relative-output ordinary-owner explicit-grants PASS')
	video := data + '/a space; $literal.avi'
	encoded := media_command(pkgcore.ffmpeg_application_id, ['-hide_banner', '-loglevel', 'error',
		'-f', 'lavfi', '-i', 'testsrc2=size=64x48:rate=10:duration=1', '-c:v', 'mpeg4', '-threads', '2', '-y', video], [])
	assert encoded.status == 0 && os.file_size(video) > 0, encoded.output
	assert os.stat(video)!.uid == 1000 && os.stat(data)!.mode & 0o777 == 0o700
	denied := media_probe(video, false)
	assert denied.status != 0, denied.output
	probe := media_probe(video, true)
	assert probe.status == 0 && probe.output.trim_space() == 'mpeg4,64,48,10', probe.output
	decoded := media_command(pkgcore.ffmpeg_application_id, ['-v', 'error', '-threads', '2', '-i', video, '-c:v', 'rawvideo', '-f', 'null', '-'], [])
	assert decoded.status == 0, decoded.output
	audio := data + '/tone.wav'
	sound := media_command(pkgcore.ffmpeg_application_id, ['-v', 'error', '-f', 'lavfi', '-i',
		'sine=frequency=1000:duration=0.1', '-c:a', 'pcm_s16le', '-threads', '2', '-y', audio], [])
	assert sound.status == 0 && os.file_size(audio) > 8000 && os.stat(audio)!.uid == 1000, sound.output
	audio_probe := media_command(pkgcore.ffprobe_application_id, ['-v', 'error', '-select_streams', 'a:0',
		'-show_entries', 'stream=codec_name,sample_rate,channels', '-of', 'csv=p=0', audio], [audio])
	assert audio_probe.status == 0 && audio_probe.output.trim_space() == 'pcm_s16le,44100,1', audio_probe.output
	outside := '/home/alex/ungranted-media.avi'
	refused := media_command(pkgcore.ffmpeg_application_id, ['-v', 'error', '-f', 'lavfi', '-i',
		'testsrc2=size=64x48:duration=0.1', '-c:v', 'mpeg4', '-threads', '2', '-y', outside], [])
	assert refused.status != 0 && !os.exists(outside), refused.output
	assert run(['/usr/bin/vinix-package', 'run-terminal-args', pkgcore.ffmpeg_application_id, '--', '-version'], '', none, none).status != 0
	t.say('PACKAGE FFMPEG real-video-encode decode probe audio-pcm literal-arguments terminal-arguments ordinary-owner explicit-file-grant outside-path-refusal PASS')
	package_success(['verify'])!
	package_success(['--offline', 'remove', pkgcore.ffmpeg_application_id])!
	partial := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	assert partial.packages.len == 2 && partial.packages.any(it.package.id == pkgcore.ffmpeg_runtime_id)
	assert media_probe(video, true).status == 0
	assert !os.exists('/var/lib/vinix-packages/current/share/applications/' + pkgcore.ffmpeg_application_id + '.desktop')
	package_success(['--offline', 'remove', pkgcore.ffprobe_application_id])!
	assert pkgcore.read_state('/var/lib/vinix-packages', architecture)!.packages.len == 0 && os.is_file(video) && os.is_file(audio)
	package_success(['rollback'])!
	assert media_probe(video, true).status == 0
	package_success(['--offline', 'remove', pkgcore.ffprobe_application_id])!
	os.rename('/tmp/ffmpeg-release', '/tmp/ffmpeg-hidden')!
	package_success(['--offline', 'install', pkgcore.ffmpeg_application_id, pkgcore.ffprobe_application_id])!
	assert media_probe(video, true).status == 0 && os.stat(video)!.uid == 1000
	package_success(['--offline', 'remove', pkgcore.ffmpeg_application_id, pkgcore.ffprobe_application_id])!
	assert pkgcore.read_state('/var/lib/vinix-packages', architecture)!.packages.len == 0 && os.is_file(video)
	assert os.is_file(relative_path) && os.stat(relative_path)!.uid == 1000
	t.say('PACKAGE FFMPEG signed-canonical-catalog shared-runtime removal rollback offline-cache-reinstall retained-media PASS')
}

fn scenario_packages_ffmpeg(mut t Test) { qualify_package_ffmpeg(mut t) or { t.check(false, err.msg()) } }
