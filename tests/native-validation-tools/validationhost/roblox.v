// SPDX-License-Identifier: GPL-2.0-or-later
module validationhost

import cachecli
import gamehost
import hosttest
import json2
import os
import sourcecommand

struct RobloxFixture {
	directory   string
	home        string
	apk         string
	checksum    string
	record      string
	runner      string
	launcher    string
	client      string
	environment map[string]string
}

fn roblox_setup(root string, directory string) !RobloxFixture {
	home := directory + '/home'
	gamehost.mkdir(home)!
	apk := home + '/Roblox.apk'
	os.write_file(apk, 'unchanged APK fixture\x00\xff')!
	record := directory + '/arguments.json'
	runner := directory + '/run-android'
	os.write_file(runner, '#!/bin/sh\nexec ' + hosttest.shell_quote(os.executable()) + ' --record-android "$@"\n')!
	os.chmod(runner, 0o755)!
	launcher := directory + '/run-roblox'
	client := directory + '/run-roblox-client'
	os.write_file(launcher, os.read_file(root + '/build-support/roblox/run-roblox')!.replace('/usr/bin/run-android', hosttest.shell_quote(runner)))!
	os.chmod(launcher, 0o755)!
	os.write_file(client, os.read_file(root + '/build-support/roblox/run-roblox-client')!.replace('/usr/bin/run-roblox', hosttest.shell_quote(launcher)))!
	os.chmod(client, 0o755)!
	return RobloxFixture{
		directory:   directory
		home:        home
		apk:         apk
		checksum:    gamehost.digest(apk)!
		record:      record
		runner:      runner
		launcher:    launcher
		client:      client
		environment: {
			'PATH':               os.getenv('PATH')
			'HOME':               home
			'ROBLOX_TEST_RECORD': record
		}
	}
}

fn (f RobloxFixture) launch(argv []string, client bool, extra map[string]string) !sourcecommand.Output {
	mut environment := f.environment.clone()
	for name, value in extra { environment[name] = value }
	result := sourcecommand.capture(['/bin/sh', if client { f.client } else { f.launcher }, ...argv], environment, 30, 1024 * 1024, cachecli.cancelled)!
	assert gamehost.digest(f.apk)! == f.checksum
	return result
}

fn (f RobloxFixture) arguments() ![]string {
	return json2.decode[[]string](os.read_file(f.record)!)!
}

pub fn record_android(argv []string) !int {
	os.write_file(os.getenv('ROBLOX_TEST_RECORD'), json2.encode(argv))!
	return gamehost.env('ROBLOX_TEST_EXIT', '0').int()
}

pub fn roblox_launcher_cases(root string, work string, selected string) !int {
	names := ['splash_dimensions_and_caller_arguments_reach_atl',
		'help_and_missing_apk_do_not_start_runtime', 'missing_native_launcher_returns_127',
		'android_exit_status_is_preserved', 'desktop_defaults_to_home_apk',
		'desktop_apk_override_and_failure_are_preserved',
		'desktop_split_paths_are_separate_unchanged_arguments',
		'missing_directory_or_empty_split_does_not_start_runtime', 'explicit_split_option_reaches_atl']
	mut count := 0
	for index, name in names {
		if selected != '' && !('test_' + name).contains(selected) { continue }
		f := roblox_setup(root, work + '/' + index.str() + '/paths with spaces')!
		match name {
			'splash_dimensions_and_caller_arguments_reach_atl' {
				result := f.launch([f.apk, '-X', 'runtime option with spaces', '-w', '1024'], false, {})!
				assert result.status == 0 && f.arguments()! == [f.apk, '-l',
					'com/roblox/client/startup/ActivitySplash', '-w', '1280', '-h', '720', '-X',
					'runtime option with spaces', '-w', '1024']
			}
			'help_and_missing_apk_do_not_start_runtime' {
				for flag in ['-h', '--help'] {
					assert f.launch([flag], false, {})!.status == 0 && !os.exists(f.record)
				}
				assert f.launch([], false, {})!.status == 2 && f.launch([f.directory + '/absent.apk'], false, {})!.status == 2 && !os.exists(f.record)
			}
			'missing_native_launcher_returns_127' {
				os.rm(f.runner)!
				result := f.launch([f.apk], false, {})!
				assert result.status == 127 && result.stderr.contains('native Android runtime launcher is missing') && !os.exists(f.record)
			}
			'android_exit_status_is_preserved' {
				assert f.launch([f.apk], false, {
					'ROBLOX_TEST_EXIT': '37'
				})!.status == 37
			}
			'desktop_defaults_to_home_apk' {
				assert f.launch(['-X', 'caller option'], true, {})!.status == 0
				args := f.arguments()!
				assert args[0] == f.apk && args[args.len - 2..] == ['-X', 'caller option']
			}
			'desktop_apk_override_and_failure_are_preserved' {
				override := f.directory + '/other unchanged.apk'
				os.write_file(override, 'second APK fixture')!
				assert f.launch([], true, {
					'VINIX_ROBLOX_APK': override
					'ROBLOX_TEST_EXIT': '19'
				})!.status == 19
				assert f.arguments()![0] == override && os.read_file(override)! == 'second APK fixture'
			}
			'desktop_split_paths_are_separate_unchanged_arguments' {
				first := f.directory + '/config arm64.apk'
				second := f.directory + '/config locale.apk'
				os.write_file(first, 'signed native split fixture')!
				os.write_file(second, 'signed resource split fixture')!
				assert f.launch(['-X', 'caller option'], true, {
					'VINIX_ROBLOX_SPLIT_APKS': first + ':' + second
				})!.status == 0
				args := f.arguments()!
				assert args[args.len - 6..] == ['-X', 'caller option', '--split-apk', first,
					'--split-apk', second]
				assert os.read_file(first)! == 'signed native split fixture' && os.read_file(second)! == 'signed resource split fixture'
			}
			'missing_directory_or_empty_split_does_not_start_runtime' {
				split := f.directory + '/config.apk'
				os.write_file(split, 'unchanged split')!
				for value in [f.directory + '/absent.apk', f.directory, ':' + split, split + ':',
					split + '::' + split] {
					assert f.launch([], true, {
						'VINIX_ROBLOX_SPLIT_APKS': value
					})!.status == 2 && !os.exists(f.record)
				}
			}
			'explicit_split_option_reaches_atl' {
				split := f.directory + '/explicit native.apk'
				os.write_file(split, 'unchanged split')!
				assert f.launch([f.apk, '--split-apk', split], false, {})!.status == 0
				args := f.arguments()!
				assert args[args.len - 2..] == ['--split-apk', split] && os.read_file(split)! == 'unchanged split'
			}
			else { return error('unknown native Roblox launcher case: ' + name) }
		}
		println('test_' + name + ': PASS')
		count++
	}
	if count == 0 { return error('no native Roblox launcher cases matched') }
	return count
}

pub fn roblox_launcher_cli(root string, argv []string) !int {
	mut arguments := []string{}
	for argument in argv {
		if argument in ['-v', '-q'] { continue }
		arguments << if argument == '-k' { '--case' } else { argument }
	}
	args := cachecli.arguments(arguments, ['--work', '--case'], [], [], 0, 0, 'Check actual Roblox launchers using a native recorder.\nUsage: launcher-test [--work DIR --case TEXT -k TEXT -v -q]') or { return error_with_code(err.msg(), 2) }
	temporary := '--work' !in args.options
	work := args.value('--work', os.temp_dir() + '/vinix-roblox-atl-' + os.getpid().str())
	defer { if temporary { gamehost.remove(work) or {} } }
	count := roblox_launcher_cases(root, work, args.value('--case', ''))!
	os.write_file(work + '/passed', 'PASS ${count}\n')!
	return 0
}
