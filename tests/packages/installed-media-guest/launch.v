// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

const hello_app = 'org.vinix.package-hello'
const editor_app = 'org.neovim.editor'
const sqlite_app = 'org.sqlite.cli'
const ffmpeg_app = 'org.ffmpeg.cli'
const ffprobe_app = 'org.ffmpeg.probe'
const app_data = home + '/.local/share/vinix-apps/'
const database = app_data + sqlite_app + '/database.sqlite3'
const wave_name = 'offline release; \$literal.wav'
const wave_path = app_data + ffmpeg_app + '/' + wave_name
const launch_document = home + '/offline document.txt'
const data_checkpoint = home + '/offline application data.json'

fn launch_output(args []string, input string) !string {
	code, output := package_exchange(args, input)
	require(code == 0, '${args[1]} launch exited ${code}: ${output}')!
	return output
}

fn application_data_hashes(device u64) !map[string]string {
	mut values := map[string]string{}
	for path in [database, wave_path] {
		info := os.lstat(path)!
		require(u64(info.dev) == device && info.uid == 1000 && info.gid == 1000 && info.nlink == 1
			&& info.mode & 0o170000 == 0o100000 && info.size > 0,
			'expected ordinary-owned application data on the installed root: ' + path)!
		values[path] = sha256.hexhash(os.read_file(path)!)
	}
	return values
}

fn run_offline_workload(first_boot bool, device u64) ! {
	require(os.getuid() == 1000 && os.geteuid() == 1000 && os.setenv('HOME', home, true) == 0,
		'expected the ordinary application session')!
	document_text := 'Receipt-bound offline native document'
	if first_boot {
		os.write_file(launch_document, document_text + '\n')!
	} else {
		retained := json2.decode[map[string]string](os.read_file(data_checkpoint)!)!
		require(application_data_hashes(device)! == retained, 'application data changed across cold boot')!
	}
	hello := launch_output(['run', hello_app, launch_document], '')!
	require(hello.contains('Application: ' + hello_app) && hello.contains(document_text),
		'Hello did not read its granted document')!
	editor := launch_output(['run-args', editor_app, '--data-cwd', '--', '--headless', '-u', 'NONE',
		'-i', 'NONE', '-n', '-c', "lua assert(vim.uv.getuid()==1000); print('OFFLINE_NEOVIM_UID_OK')",
		'-c', 'qa!'], '')!
	require(editor.contains('OFFLINE_NEOVIM_UID_OK'), 'Neovim did not run with ordinary credentials')!
	sqlite := ['run', sqlite_app]
	if first_boot {
		creation := launch_output(sqlite, '.bail on\nPRAGMA journal_mode=WAL; CREATE TABLE saved(value); INSERT INTO saved VALUES(42);\n')!
		require(creation.trim_space() == 'wal', 'SQLite did not create a private WAL database')!
		launch_output(['run-args', ffmpeg_app, '--data-cwd', '--', '-v', 'error', '-f', 'lavfi',
			'-i', 'sine=frequency=440:duration=0.1', '-c:a', 'pcm_s16le', wave_name], '')!
	}
	saved := launch_output(sqlite, '.bail on\nSELECT sum(value) FROM saved; PRAGMA integrity_check;\n')!
	require(saved.trim_space() == '42\nok', 'SQLite did not reopen an intact private database')!
	probe := ['--', '-v', 'error', '-select_streams', 'a:0', '-show_entries',
		'stream=codec_name,sample_rate,channels', '-of', 'csv=p=0', wave_path]
	code, _ := package_exchange(['run-args', ffprobe_app, ...probe], '')
	require(code != 0, 'FFprobe opened private audio without an explicit file grant')!
	audio := launch_output(['run-args', ffprobe_app, '--file', wave_path, ...probe], '')!
	require(audio.trim_space() == 'pcm_s16le,44100,1', 'FFprobe did not identify the granted audio')!
	if first_boot { os.write_file(data_checkpoint, json2.encode(application_data_hashes(device)!))! }
}

fn launch_installed_apps(first_boot bool, device u64) ! {
	as_ordinary(fn [first_boot, device] () ! {
		run_offline_workload(first_boot, device)!
	})!
	println(if first_boot { 'HWTEST PASS five offline-installed applications ran as UID 1000' }
		else { 'HWTEST PASS offline-installed applications reopened unchanged private data after cold boot' })
}
