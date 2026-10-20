// SPDX-License-Identifier: GPL-2.0-or-later
// Isolated application investigation, not a full runtime release/staging tool.
import crypto.sha256
import json2
import os

fn checked(command []string) ! {
 result := os.exec(command)
 if result.exit_code != 0 { return error(command.str() + '\n' + result.output) }
}
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn main() {
 if os.args.len != 5 { panic('usage: stage-overlay BASE_OVERLAY WORK_DIR FRAMEWORK.so API-IMPL.jar') }
 base := os.real_path(os.args[1])
 work := os.abs_path(os.args[2])
 if work == base || base.starts_with(work + '/') || work.starts_with(base + '/') { panic('use a separate work directory') }
 if !os.is_file(base + '/opt/android-test/config.sh') { panic('base must be a prepared Android test overlay') }
 overlay := work + '/overlay'
 os.mkdir_all(overlay)!
 checked(['rsync', '-aH', '--delete', base + '/', overlay + '/'])!
 runtime := overlay + '/opt/vinix-android-aarch64'
 os.cp(os.args[3], runtime + '/usr/lib/art/libvinix-android-framework.so')!
 os.cp(os.args[4], runtime + '/usr/lib/java/dex/android_translation_layer/api-impl.jar')!
 launch := overlay + '/usr/bin/run-android'
 original := os.read_file(launch)!
 old := 'guest_preload="$runtime/usr/lib/libvinix-android-compat.so"'
 if original.count(old) != 1 { panic('expected original launcher in prepared base') }
 os.write_file(launch, original.replace(old, 'guest_preload="$runtime/usr/lib/libvinix-android-compat.so:$runtime/usr/lib/art/libvinix-android-framework.so"'))!
 config := overlay + '/opt/android-test/config.sh'
 os.write_file(config, os.read_file(config)!.replace('TEST_OBSERVATION_SECONDS=30', 'TEST_OBSERVATION_SECONDS=600'))!
 os.write_file(work + '/framework-test-overlay.json', json2.encode({
  'scope': 'application checks only; preserved runtime plus V framework extension'
  'base_overlay': base
  'framework_sha256': digest(os.args[3])!
  'dex_jar_sha256': digest(os.args[4])!
 }) + '\n')!
 checked(['tar', '--format=ustar', '-cf', work + '/initramfs.tar', '-C', overlay, '.'])!
}
