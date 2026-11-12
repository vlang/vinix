// SPDX-License-Identifier: GPL-2.0-or-later
// Stage a fresh diagnostic VM from available media and current build outputs.
module main
import json2
import os
import crypto.sha256
import mapsaccountstage as media

#include <sys/clonefile.h>
fn C.clonefile(&char, &char, int) int

fn command(args []string) ! {
	if os.system_args(args) != 0 { return error('command failed: ' + args.join(' ')) }
}

fn app_data_disk(root string) ! {
	probe := os.getenv_opt('VINIX_CURRENT_DATA_VOLUME_PROBE') or { return error('app-data disk requires volume probe') }
	path := root + '/app-data.ext2'
	os.write_file(path, '')!
	os.chmod(path, 0o600)!
	os.truncate(path, u64(8) << 30)!
	format := ['/opt/homebrew/opt/e2fsprogs/sbin/mke2fs', '-q', '-F', '-t', 'ext2',
		'-b', '4096', '-I', '128', '-m', '0', '-E', 'root_owner=0:0', '-L', 'vinix-maps-data', '-O',
		'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum', path]
	command(format)!
	mut disk := os.open(path)!
	defer { disk.close() }
	mut bytes := []u8{len: 512}
	read := disk.read_bytes_into(1024, mut bytes)!
	if read != 512 || bytes[56] != 0x53 || bytes[57] != 0xef {
		return error('formatted app-data ext2 superblock missing')
	}
	metadata := json2.encode({
		'mountpoint': json2.Any('/var/lib/vinix/apps')
		'uuid_hex': json2.Any(bytes[104..120].hex())
		'image_bytes': json2.Any(u64(8) << 30)
		'initial_sha256': json2.Any(media.hash(path)!)
		'format_tool_sha256': json2.Any(media.hash(format[0])!)
		'stage_tool_sha256': json2.Any(media.hash(os.executable())!)
		'volume_probe_sha256': json2.Any(media.hash(probe)!)
		'volume_probe_input': json2.Any(os.real_path(probe))
		'format_command': json2.Any(format.map(json2.Any(it)))
	}, prettify: true)
	os.write_file(root + '/data-image.json', metadata)!
	os.mkdir_all(root + '/payload/opt/current-api')!
	os.write_file(root + '/payload/opt/current-api/data-image.json', metadata)!
	os.cp(probe, root + '/payload/opt/current-api/data-volume')!
	os.chmod(root + '/payload/opt/current-api/data-volume', 0o755)!
}

fn stage(parent string, framework string, native string, root string) ! {
	data_disk := os.getenv_opt('VINIX_CURRENT_APP_DATA_DISK') or { '0' }
	if data_disk !in ['0', '1'] { return error('VINIX_CURRENT_APP_DATA_DISK must be 0 or1') }
	if os.exists(root) { return error('fresh output required') }
	os.mkdir_all(root)!
	for name in ['boot.img', 'efivars.fd'] {
		if C.clonefile((parent + '/' + name).str, (root + '/' + name).str, 0) != 0 { return error('media clone failed') }
	}
	runtime := root + '/payload/opt/vinix-android-aarch64/usr/lib/'
	java := runtime + 'java/dex/android_translation_layer/'
	os.mkdir_all(java)!
	os.mkdir_all(runtime + 'art')!
	for name in ['api-impl.jar', 'classes.dex'] { os.cp(framework + '/' + name, java + name)! }
	os.cp(native + '/native/libvinix-android-native.so', runtime + 'art/libvinix-android-native.so')!
	os.chmod(runtime + 'art/libvinix-android-native.so', 0o755)!
	// Describe the files actually selected for this deployment, rather than
	// requiring artifacts from a historical build to still exist.
	mut deployment := json2.decode[map[string]json2.Any](os.read_file(parent + '/payload/opt/vinix-maps-account/build.json')!)!
	mut inputs := deployment['inputs_sha256']!.as_map()
	for relative in ['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/classes.dex'] {
		inputs['/' + relative] = json2.Any(sha256.sum(os.read_bytes(root + '/payload/' + relative)!).hex())
	}
	deployment['inputs_sha256'] = json2.Any(inputs)
	if protocol := os.getenv_opt('VINIX_CURRENT_ACCOUNT_PROTOCOL') {
		// Cancellation acknowledgements require the broker and service-side
		// transport together. One build directory selects both, never one half.
		for relative, name in {
			'/opt/vinix-android-aarch64/usr/bin/native-account-broker': 'native-account-broker'
			'/opt/vinix-android-aarch64/usr/lib/libvinix-android-account.so': 'libvinix-android-account.so'
		} {
			os.mkdir_all(os.dir(root + '/payload' + relative))!
			os.cp(protocol + '/' + name, root + '/payload' + relative)!
			os.chmod(root + '/payload' + relative, 0o755)!
			inputs[relative] = json2.Any(media.hash(root + '/payload' + relative)!)
		}
		deployment['inputs_sha256'] = json2.Any(inputs)
	}
	if controller := os.getenv_opt('VINIX_CURRENT_ACCOUNT_CONTROLLER') {
		for relative in ['/opt/vinix-maps-account/bin/maps-account-guest', '/usr/bin/run-android-calculator'] {
			os.mkdir_all(os.dir(root + '/payload' + relative))!
			os.cp(controller, root + '/payload' + relative)!
			os.chmod(root + '/payload' + relative, 0o755)!
			inputs[relative] = json2.Any(media.hash(root + '/payload' + relative)!)
		}
		deployment['inputs_sha256'] = json2.Any(inputs)
	}
	if boot := os.getenv_opt('VINIX_CURRENT_CORE_LIBART') {
		relative := '/opt/vinix-android-aarch64/usr/lib/java/dex/art/core-libart-hostdex.jar'
		os.mkdir_all(os.dir(root + '/payload' + relative))!
		os.cp(boot, root + '/payload' + relative)!
		inputs[relative] = json2.Any(sha256.sum(os.read_bytes(boot)!).hex())
		deployment['inputs_sha256'] = json2.Any(inputs)
	}
	if boot := os.getenv_opt('VINIX_CURRENT_WOLFSSL') {
		relative := '/opt/vinix-android-aarch64/usr/lib/java/dex/art/wolfssljni-hostdex.jar'
		os.mkdir_all(os.dir(root + '/payload' + relative))!
		os.cp(boot, root + '/payload' + relative)!
		inputs[relative] = json2.Any(sha256.sum(os.read_bytes(boot)!).hex())
		deployment['inputs_sha256'] = json2.Any(inputs)
	}
	os.mkdir_all(root + '/payload/opt/vinix-maps-account')!
	os.write_file(root + '/payload/opt/vinix-maps-account/build.json', json2.encode(deployment))!
	if fixture := os.getenv_opt('VINIX_CURRENT_API_FIXTURE') {
		runner := os.getenv_opt('VINIX_CURRENT_API_RUNNER') or { return error('fixture requires VINIX_CURRENT_API_RUNNER') }
		os.mkdir_all(root + '/payload/opt/current-api')!
		os.cp(fixture, root + '/payload/opt/current-api/probe.apk')!
		os.cp(runner, root + '/payload/opt/current-api/run')!
		os.chmod(root + '/payload/opt/current-api/run', 0o755)!
	}
	if fixture := os.getenv_opt('VINIX_CURRENT_LOADER_FIXTURE') {
		os.mkdir_all(root + '/payload/opt/current-api')!
		os.cp(fixture, root + '/payload/opt/current-api/loader.apk')!
	}
	if probe := os.getenv_opt('VINIX_CURRENT_STORAGE_WATCH') {
		os.mkdir_all(root + '/payload/opt/current-api')!
		os.cp(probe, root + '/payload/opt/current-api/storage-watch')!
		os.chmod(root + '/payload/opt/current-api/storage-watch', 0o755)!
	}
	if data_disk == '1' { app_data_disk(root)! }
	os.setenv('COPYFILE_DISABLE', '1', true)
	mut archive := ['/usr/bin/tar', '-cf', root + '/maps-current.tar', '-C', root + '/payload', 'opt']
	if os.is_dir(root + '/payload/usr') { archive << 'usr' }
	command(archive)!
	config := os.read_file(parent + '/limine-after.conf')! + '    module_path: boot():/boot/maps-current.tar\n'
	os.write_file(root + '/limine-after.conf', config)!
	command(['/opt/homebrew/bin/mcopy', '-i', root + '/boot.img', root + '/maps-current.tar', '::/boot/maps-current.tar'])!
	command(['/opt/homebrew/bin/mcopy', '-o', '-i', root + '/boot.img', root + '/limine-after.conf', '::/boot/limine.conf'])!
	launch := json2.decode[map[string]json2.Any](os.read_file(parent + '/launch.json')!)!
	mut args := launch['argv']!.as_array().map(it.str().replace(parent, root))
	if data_disk == '1' {
		args << ['-drive', 'if=none,id=mapsdata,format=raw,file=' + root + '/app-data.ext2',
			'-device', 'virtio-blk-device,drive=mapsdata']
	}
	os.write_file(root + '/launch-argv.json', json2.encode(args))!
	os.write_file(root + '/build.json', json2.encode({'parent': parent, 'framework': framework, 'native': native}))!
	println('MAPS-CURRENT-STAGED ' + root)
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--hash' {
		println(media.hash(os.abs_path(os.args[2]))!)
		return
	}
	if os.args.len == 3 && os.args[1] == '--start' {
		root := os.abs_path(os.args[2])
		if os.exists(root + '/qemu.pid') { eprintln('VM already launched'); exit(1) }
		if os.exists(root + '/data-image.json') {
			metadata := json2.decode[map[string]json2.Any](os.read_file(root + '/data-image.json')!)!
			if media.hash(root + '/app-data.ext2')! != metadata['initial_sha256']!.str() {
				panic('fresh app-data image changed before launch')
			}
		}
		args := json2.decode[[]string](os.read_file(root + '/launch-argv.json')!)!
		command(args) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 5 { eprintln('usage: maps-current-guest PARENT_VM FRAMEWORK NATIVE FRESH_ROOT'); exit(2) }
	stage(os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3]), os.abs_path(os.args[4])) or { eprintln(err); exit(1) }
}
