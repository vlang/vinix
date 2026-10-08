// SPDX-License-Identifier: GPL-2.0-or-later
// Check the real launcher's architecture and runtime isolation.
module main

import hosttest
import json2
import os

#include <sys/resource.h>
struct C.rlimit {
	rlim_cur u64
	rlim_max u64
}

fn C.getrlimit(i32, &C.rlimit) i32

const cases = ['translator_isolated_and_arguments_preserved', 'explicit_vulkan_selection_is_preserved',
	'assertions_can_be_enabled', 'help_describes_assertion_default_and_override',
	'explicit_empty_vulkan_selection_is_preserved', 'venus_gpu_is_selected_when_the_probe_finds_it',
	'lavapipe_is_kept_without_a_venus_gpu', 'explicit_selection_overrides_a_venus_gpu',
	'dedicated_runtime_override_takes_priority', 'missing_content_is_rejected',
	'wrong_architecture_is_rejected', 'aarch64_elf_is_rejected', 'truncated_elf_is_rejected',
	'missing_glibc_loader_is_rejected', 'missing_software_vulkan_is_rejected',
	'emulator_exit_status_is_preserved', 'runtime_compatibility_preloads_are_guest_only',
	'missing_robust_list_shim_is_rejected', 'missing_early_client_loader_is_rejected',
	'missing_freetype_library_is_rejected', 'missing_actual_steamclient_is_rejected',
	'foreign_steamclient_is_rejected', 'truncated_steamclient_is_rejected',
	'actual_client_path_override_is_guest_only', 'client_path_with_qemu_separator_is_rejected',
	'explicit_cpu_model_is_preserved']

struct Fixture {
	base      string
	runtime   string
	game_dir  string
	game_root string
	game      string
	icd       string
	client    string
	output    string
mut:
	env map[string]string
}

struct Launch {
	result hosttest.Result
	row    map[string]json2.Any
}

fn require(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn write(path string, data []u8) ! {
	os.mkdir_all(path.all_before_last('/'))!
	os.write_file(path, data.bytestr())!
}

fn create(base string) !Fixture {
	runtime := base + '/glibc runtime'
	game_dir := base + '/dota 2 beta'
	game_root := game_dir + '/game'
	game := game_root + '/bin/linuxsteamrt64/dota2'
	icd := runtime + '/usr/share/vulkan/icd.d/lvp_icd.x86_64.json'
	for relative in ['lib64/ld-linux-x86-64.so.2', 'usr/lib/x86_64-linux-gnu/libvulkan.so.1',
		'usr/lib/x86_64-linux-gnu/libvulkan_lvp.so', 'usr/lib/x86_64-linux-gnu/libvinix-steam-robust.so',
		'usr/lib/x86_64-linux-gnu/libvinix-dota2-mmap32.so',
		'usr/lib/x86_64-linux-gnu/libvinix-dota2-steam-loader.so',
		'usr/lib/x86_64-linux-gnu/libmpg123.so.0', 'usr/lib/x86_64-linux-gnu/libfreetype.so.6',
		'usr/share/vulkan/icd.d/lvp_icd.x86_64.json'] {
		write(runtime + '/' + relative, 'fixture\n'.bytes())!
	}
	for relative in ['dota/gameinfo.gi', 'dota/pak01_dir.vpk', 'core/pak01_dir.vpk'] {
		write(game_root + '/' + relative, 'fixture\n'.bytes())!
	}
	mut header := []u8{len: 64}
	copy(mut header[..7], [u8(0x7f), `E`, `L`, `F`, u8(2), u8(1), u8(1)])
	header[16] = 3
	header[18] = 62
	write(game, header)!
	os.chmod(game, 0o755)!
	home := base + '/user home'
	client := home + '/.steam/sdk64/steamclient.so'
	write(client, header)!
	output := base + '/launch.json'
	emulator := base + '/fake-qemu-x86_64'
	// The independently launched recorder is native V, keeping the same
	// argv, environment, cwd, resource-limit and exit-status contract.
	os.cp(os.executable(), emulator)!
	os.chmod(emulator, 0o755)!
	mut env := os.environ()
	for key in ['VK_DRIVER_FILES', 'VK_ICD_FILENAMES', 'VK_LOADER_DRIVERS_SELECT', 'QEMU_CPU',
		'VINIX_X86_64_PRELOAD', 'VINIX_DOTA2_LD_LIBRARY_PATH', 'VINIX_DOTA2_WIDTH', 'VINIX_DOTA2_HEIGHT',
		'VINIX_X86_64_GUEST_BASE', 'VINIX_DOTA2_ROOT', 'SDL_VIDEO_DRIVER', 'VINIX_DOTA_TEST_STATUS',
		'VINIX_DOTA2_STEAMCLIENT', 'VINIX_DOTA2_EARLY_STEAMCLIENT', 'VINIX_DOTA2_ASSERTS',
		'VINIX_DOTA2_VENUS_PROBE'] {
		env.delete(key)
	}
	for key, value in {
		'DISPLAY':                 ':73'
		'HOME':                    home
		'VINIX_DOTA2_DIR':         game_dir
		'VINIX_STEAM_ROOT':        runtime
		'VINIX_X86_64_EMULATOR':   emulator
		'VINIX_DOTA_TEST_LOG':     output
		'VINIX_DOTA2_VENUS_PROBE': base + '/no venus probe'
	} {
		env[key] = value
	}
	return Fixture{base, runtime, game_dir, game_root, game, icd, client, output, env}
}

fn (fixture Fixture) launch(arguments []string) !Launch {
	result := hosttest.capture([hosttest.root() + '/build-support/dota2/run-dota2', ...arguments],
		'', -1, fixture.env)!
	row := if result.code == 0 && os.exists(fixture.output) {
		hosttest.decode_json(os.read_file(fixture.output)!)!.as_map()
	} else {
		map[string]json2.Any{}
	}
	return Launch{result, row}
}

fn (fixture Fixture) rejected(message string) ! {
	result := fixture.launch([]string{})!
	require(result.row.len == 0, 'Rejected install returned a launch record')!
	require(result.result.code == 127, result.result.stderr)!
	require(result.result.stderr.contains(message), result.result.stderr)!
	require(!os.exists(fixture.output), 'Invalid install reached the translator')!
}

fn (fixture Fixture) venus(status int) !string {
	icd := fixture.runtime + '/usr/share/vulkan/icd.d/virtio_icd.x86_64.json'
	write(icd, 'fixture\n'.bytes())!
	write(fixture.runtime + '/usr/lib/x86_64-linux-gnu/libvulkan_virtio.so', 'fixture\n'.bytes())!
	probe := fixture.base + '/venus-available'
	os.write_file(probe, '#!/bin/sh\nexit ' + status.str() + '\n')!
	os.chmod(probe, 0o755)!
	return icd
}

fn (fixture Fixture) preloads() string {
	return ['libvinix-steam-robust.so', 'libvinix-dota2-mmap32.so', 'libmpg123.so.0', 'libfreetype.so.6',
		'libvinix-dota2-steam-loader.so'].map(fixture.runtime + '/usr/lib/x86_64-linux-gnu/' + it).join(':')
}

fn json_field(row map[string]json2.Any, key string) json2.Any {
	return row[key] or { json2.Any(json2.Null{}) }
}

fn args(launch Launch) []string { return json_field(launch.row, 'args').as_array().map(it.str()) }

fn environment(launch Launch) map[string]json2.Any { return json_field(launch.row, 'env').as_map() }

fn (fixture Fixture) launched(launch Launch) ! {
	require(launch.result.code == 0 && launch.row.len > 0, launch.result.stderr)!
}

fn run_case(name string) ! {
	work := hosttest.work_dir('', 'vinix-dota2-test-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	base := hosttest.module_resolve(work)!
	mut fixture := create(base)!
	match name {
		'translator_isolated_and_arguments_preserved' {
			for key, value in {
				'LD_LIBRARY_PATH':               '/foreign/x86/libraries'
				'LD_PRELOAD':                    '/foreign/x86/preload.so'
				'QEMU_LD_PREFIX':                '/unrelated/runtime'
				'QEMU_SET_ENV':                  'LD_LIBRARY_PATH=/unrelated/libraries'
				'VINIX_DOTA2_EARLY_STEAMCLIENT': '/foreign/unrelated/steamclient.so'
				'VINIX_X86_64_PRELOAD':          '/guest/only/preload.so'
			} {
				fixture.env[key] = value
			}
			launch := fixture.launch(['+map', 'path with spaces', '-w', '960'])!
			fixture.launched(launch)!
			libraries := fixture.game.all_before_last('/') + ':' + fixture.runtime + '/usr/lib/x86_64-linux-gnu:' + fixture.runtime + '/lib/x86_64-linux-gnu'
			require(args(launch) == ['-B', '0x100000000', '-L', fixture.runtime, '-E',
				'LD_LIBRARY_PATH=' + libraries, '-E',
				'VINIX_DOTA2_EARLY_STEAMCLIENT=' + fixture.client, '-E',
				'LD_PRELOAD=/guest/only/preload.so:' + fixture.preloads(), fixture.game, '-windowed',
				'-w', '1280', '-h', '720', '-noassert', '-vulkan_allow_cpu', '+map', 'path with spaces',
				'-w', '960'], 'Launch arguments differ')!
			require(json_field(launch.row, 'cwd').str() == fixture.game_root, 'Wrong launch cwd')!
			require(json_field(launch.row, 'nofile').u64() == 2048, 'Wrong descriptor soft limit')!
			require(json_field(launch.row, 'stack').u64() == 2048 * 1024, 'Wrong stack soft limit')!
			env := environment(launch)
			for key in ['LD_LIBRARY_PATH', 'LD_PRELOAD', 'QEMU_LD_PREFIX', 'QEMU_SET_ENV',
				'VINIX_DOTA2_EARLY_STEAMCLIENT'] {
				require(key !in env, 'Native translator inherited ' + key)!
			}
			for key, value in {
				'VINIX_I386_ROOT':     fixture.runtime
				'VINIX_X86_64_ROOT':   fixture.runtime
				'VINIX_X86_MULTIARCH': '1'
				'VINIX_ALLOW_WX':      '1'
				'QEMU_CPU':            'Haswell'
				'SteamAppId':          '570'
				'SteamGameId':         '570'
				'ENABLE_PATHMATCH':    '1'
				'SDL_VIDEO_DRIVER':    'x11'
				'FONTCONFIG_FILE':     '/etc/fonts/fonts.conf'
				'FONTCONFIG_PATH':     '/etc/fonts'
				'FONTCONFIG_SYSROOT':  fixture.runtime
				'VK_ICD_FILENAMES':    fixture.icd
			} {
				require(json_field(env, key).str() == value, 'Wrong environment ' + key)!
			}
		}
		'explicit_vulkan_selection_is_preserved' {
			os.rm(fixture.icd)!
			for key in ['VK_DRIVER_FILES', 'VK_ICD_FILENAMES', 'VK_LOADER_DRIVERS_SELECT'] {
				fixture.env[key] = '/custom/driver selection'
				launch := fixture.launch([]string{})!
				fixture.launched(launch)!
				env := environment(launch)
				require(json_field(env, key).str() == fixture.env[key], 'Explicit driver selection changed')!
				require('-vulkan_allow_cpu' !in args(launch), 'Explicit driver received CPU allowance')!
				if key != 'VK_ICD_FILENAMES' {
					require('VK_ICD_FILENAMES' !in env, 'Implicit ICD leaked into explicit selection')!
				}
				fixture.env.delete(key)
			}
		}
		'assertions_can_be_enabled' {
			fixture.env['VINIX_DOTA2_ASSERTS'] = '1'
			launch := fixture.launch(['+map', 'path with spaces'])!
			fixture.launched(launch)!
			require('-noassert' !in args(launch), 'Assertions remained disabled')!
			require(args(launch)[args(launch).len - 2..] == ['+map', 'path with spaces'], 'Arguments changed')!
		}
		'help_describes_assertion_default_and_override' {
			launch := fixture.launch(['--help'])!
			require(launch.result.code == 0, launch.result.stderr)!
			require(launch.result.stdout.contains('VINIX_DOTA2_ASSERTS=1'), 'Missing assertion override help')!
			require(launch.result.stdout.contains('default: -noassert'), 'Missing assertion default help')!
			require(!os.exists(fixture.output), 'Help launched translator')!
		}
		'explicit_empty_vulkan_selection_is_preserved' {
			os.rm(fixture.icd)!
			fixture.env['VK_DRIVER_FILES'] = ''
			launch := fixture.launch([]string{})!
			fixture.launched(launch)!
			env := environment(launch)
			require('VK_DRIVER_FILES' in env && json_field(env, 'VK_DRIVER_FILES').str() == '', 'Empty driver selection lost')!
			require('VK_ICD_FILENAMES' !in env, 'Empty driver selection gained an ICD')!
			require('-vulkan_allow_cpu' !in args(launch), 'Empty driver selection gained CPU allowance')!
		}
		'venus_gpu_is_selected_when_the_probe_finds_it', 'lavapipe_is_kept_without_a_venus_gpu',
		'explicit_selection_overrides_a_venus_gpu' {
			venus_icd := fixture.venus(if name == 'lavapipe_is_kept_without_a_venus_gpu' {
				1
			} else {
				0
			})!
			fixture.env['VINIX_DOTA2_VENUS_PROBE'] = fixture.base + '/venus-available'
			if name == 'explicit_selection_overrides_a_venus_gpu' {
				fixture.env['VK_ICD_FILENAMES'] = fixture.icd
			}
			launch := fixture.launch([]string{})!
			fixture.launched(launch)!
			expected := if name == 'venus_gpu_is_selected_when_the_probe_finds_it' {
				venus_icd
			} else {
				fixture.icd
			}
			require(json_field(environment(launch), 'VK_ICD_FILENAMES').str() == expected, 'Wrong probed driver')!
			require(('-vulkan_allow_cpu' in args(launch)) == (name == 'lavapipe_is_kept_without_a_venus_gpu'), 'Wrong CPU allowance')!
		}
		'dedicated_runtime_override_takes_priority' {
			fixture.env['VINIX_DOTA2_ROOT'] = fixture.runtime
			fixture.env['VINIX_STEAM_ROOT'] = '/missing/steam/runtime'
			launch := fixture.launch([]string{})!
			fixture.launched(launch)!
			require(json_field(environment(launch), 'VINIX_X86_64_ROOT').str() == fixture.runtime, 'Wrong runtime priority')!
		}
		'wrong_architecture_is_rejected' {
			mut header := []u8{len: 64}
			header[0] = `M`
			header[1] = `Z`
			write(fixture.game, header)!
			fixture.rejected('Linux x86-64 ELF')!
		}
		'aarch64_elf_is_rejected', 'foreign_steamclient_is_rejected' {
			path := if name == 'aarch64_elf_is_rejected' { fixture.game } else { fixture.client }
			mut header := os.read_bytes(path)!
			header[18] = 183
			header[19] = 0
			write(path, header)!
			fixture.rejected(if name == 'aarch64_elf_is_rejected' {
				'Linux x86-64 ELF'
			} else {
				"Steam's client must be a Linux x86-64 shared ELF"
			})!
		}
		'truncated_elf_is_rejected', 'truncated_steamclient_is_rejected' {
			path := if name == 'truncated_elf_is_rejected' { fixture.game } else { fixture.client }
			write(path, os.read_bytes(path)![..20])!
			fixture.rejected(if name == 'truncated_elf_is_rejected' {
				'Linux x86-64 ELF'
			} else {
				"Steam's client must be a Linux x86-64 shared ELF"
			})!
		}
		'emulator_exit_status_is_preserved' {
			fixture.env['VINIX_DOTA_TEST_STATUS'] = '42'
			launch := fixture.launch([]string{})!
			require(launch.result.code == 42, 'Translator exit status changed')!
		}
		'runtime_compatibility_preloads_are_guest_only' {
			launch := fixture.launch([]string{})!
			fixture.launched(launch)!
			require('LD_PRELOAD=' + fixture.preloads() in args(launch), 'Guest preloads changed')!
			env := environment(launch)
			require(json_field(env, 'VINIX_X86_64_PRELOAD').str() == fixture.preloads(), 'Preload marker changed')!
			require('LD_PRELOAD' !in env, 'Native translator inherited LD_PRELOAD')!
		}
		'actual_client_path_override_is_guest_only' {
			custom := fixture.base + '/custom SDK/steamclient.so'
			write(custom, os.read_bytes(fixture.client)!)!
			fixture.env['VINIX_DOTA2_STEAMCLIENT'] = fixture.base + '/custom SDK/../custom SDK/steamclient.so'
			launch := fixture.launch([]string{})!
			fixture.launched(launch)!
			require('VINIX_DOTA2_EARLY_STEAMCLIENT=' + custom in args(launch), 'Client override not canonical')!
			require('VINIX_DOTA2_EARLY_STEAMCLIENT' !in environment(launch), 'Native translator inherited client marker')!
		}
		'client_path_with_qemu_separator_is_rejected' {
			custom := fixture.base + '/steamclient, alternate.so'
			write(custom, os.read_bytes(fixture.client)!)!
			fixture.env['VINIX_DOTA2_STEAMCLIENT'] = custom
			fixture.rejected('Steam client path cannot contain a comma')!
		}
		'explicit_cpu_model_is_preserved' {
			fixture.env['QEMU_CPU'] = 'Nehalem'
			launch := fixture.launch([]string{})!
			fixture.launched(launch)!
			require(json_field(environment(launch), 'QEMU_CPU').str() == 'Nehalem', 'CPU override changed')!
		}
		else {
			missing := match name {
				'missing_content_is_rejected' { fixture.game_root + '/core/pak01_dir.vpk' }
				'missing_glibc_loader_is_rejected' {
					fixture.runtime + '/lib64/ld-linux-x86-64.so.2'
				}
				'missing_software_vulkan_is_rejected' { fixture.icd }
				'missing_robust_list_shim_is_rejected' {
					fixture.runtime + '/usr/lib/x86_64-linux-gnu/libvinix-steam-robust.so'
				}
				'missing_early_client_loader_is_rejected' {
					fixture.runtime + '/usr/lib/x86_64-linux-gnu/libvinix-dota2-steam-loader.so'
				}
				'missing_freetype_library_is_rejected' {
					fixture.runtime + '/usr/lib/x86_64-linux-gnu/libfreetype.so.6'
				}
				'missing_actual_steamclient_is_rejected' { fixture.client }
				else { return error('Unknown launcher case: ' + name) }
			}
			message := match name {
				'missing_content_is_rejected' { 'game content is missing' }
				'missing_glibc_loader_is_rejected' { 'x86-64 glibc loader is missing' }
				'missing_software_vulkan_is_rejected' { 'x86-64 Lavapipe ICD is missing' }
				'missing_robust_list_shim_is_rejected' { 'x86-64 robust-list shim is missing' }
				'missing_early_client_loader_is_rejected' { 'early Steam client loader is missing' }
				'missing_freetype_library_is_rejected' { 'runtime FreeType library is missing' }
				else { "Steam's Linux64 client is missing" }
			}
			os.rm(missing)!
			fixture.rejected(message)!
		}
	}
}

fn recorder() ! {
	mut nofile := C.rlimit{}
	mut stack := C.rlimit{}
	if C.getrlimit(C.RLIMIT_NOFILE, &nofile) != 0 || C.getrlimit(C.RLIMIT_STACK, &stack) != 0 {
		return error('Cannot read resource limits')
	}
	hosttest.write_json(os.getenv('VINIX_DOTA_TEST_LOG'), {
		'args':   json2.Any(hosttest.strings(os.args[1..]))
		'env':    json2.Any(hosttest.string_map(os.environ()))
		'cwd':    json2.Any(os.getwd())
		'nofile': json2.Any(nofile.rlim_cur)
		'stack':  json2.Any(stack.rlim_cur)
	})!
	exit(hosttest.env_default('VINIX_DOTA_TEST_STATUS', '0').int())
}

fn main() {
	if os.executable().all_after_last('/') == 'fake-qemu-x86_64' {
		recorder() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	options := hosttest.parse_arguments(os.args[1..], [hosttest.Option{'--case', true, cases}],
		0, 'Usage: launcher.v [--case CASE]', 'Check the real Dota launcher without running the game.') or {
		eprintln(err)
		exit(2)
	}
	mut selected := if '--case' in options.options {
		[options.options['--case']]
	} else {
		cases.clone()
	}
	selected.sort()
	for name in selected {
		run_case(name) or {
			eprintln(name + ': ' + err.msg())
			exit(1)
		}
	}
	println('Dota launcher: ' + selected.len.str() + ' architecture/runtime/environment/argv/resource-limit cases PASS')
}
