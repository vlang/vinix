module runtimevm

import androidhost as ah
import runtimebuild as rb

fn input_record(args ah.Value, work ah.Value, root ah.Value, kernel ah.Value, archive_ ah.Value,
 tools ah.Value, variants ah.Value, probes []string, files ah.Value) !ah.Value {
 kernel_hash := digest_api(kernel)!
 archive_hash := digest_api(archive_)!
 arch := attr(args, 'arch')!
 runner_hash := digest_api(rb.api('Path', [o(global('__file__')!)], {}, true)!)!
 factory := attr(global('hashlib')!, 'sha256')!
 v_inputs := method(tools, 'inputs', []) or {
  cause := err
  release([factory])!
  return cause
 }
 v_hash := digest_contents(factory, v_inputs)!
 fixtures := rb.dictionary([], [])!
 for probe in probes {
  put(fixtures, literal(probe)!, digest_api(join(work, probe + '.c')!)!)!
 }
 installed := rb.dictionary([], [])!
 iterator := rb.iter_object(files)!
 for {
  name := rb.next(iterator)!
  if name == rb.null() { break }
  put(installed, name, digest_api(join_object(root, name)!)!)!
 }
 return rb.dictionary(['kernel_sha256', 'archive_sha256', 'architecture', 'variants', 'runner_sha256', 'v_inputs_sha256', 'fixture_sources', 'files'].map(v(it)),
 [o(kernel_hash), o(archive_hash), o(arch), o(variants), o(runner_hash), o(v_hash), o(fixtures), o(installed)])!
}

fn update(env ah.Value, names []string, values []ah.Value) ! {
 mut objects := map[string]ah.Value{}
 for i, name in names { objects[name] = values[i] }
 rb.callback('invoke', {'id': env, 'name': ah.Value('update'), 'keyword_objects': ah.Value(objects)})!
}

fn vm_plan(work ah.Value, kernel ah.Value, archive_ ah.Value, arm ah.Value, env ah.Value) !ah.Value {
 if flag(arm)! {
  kernel_dir := str(attr(attr(kernel, 'parent')!, 'parent')!)!
  archive_text := str(archive_)!
  boot := str(join(work, 'boot.img')!)!
  vars_ := str(join(work, 'efivars.fd')!)!
  packages := str(join(work, 'packages.tar')!)!
  qmp := literal('-qmp unix:' + text(join(work, 'qmp.sock')!)! + ',server=on,wait=off')!
  update(env, ['VINIX_KERNEL_DIR', 'VINIX_INITRAMFS', 'VINIX_INITRAMFS_COMPRESSED', 'VINIX_QEMU_ROOT_DISK', 'VINIX_BOOT_DISK', 'VINIX_EFIVARS', 'VINIX_BOOT_DISK_SIZE_MB', 'VINIX_QEMU_PACKAGE_STORE', 'VINIX_QEMU_PACKAGE_PERSIST', 'VINIX_QEMU_HOST_SOURCE', 'VINIX_QEMU_AUDIO', 'VINIX_QEMU_SMP', 'VINIX_QEMU_NETWORK', 'VINIX_QEMU_EXTRA'],
    [kernel_dir, archive_text, literal('1')!, literal('0')!, boot, vars_, literal('128')!, packages, literal('0')!, literal('0')!, literal('off')!, literal('2')!, literal('0')!, qmp])!
  for name in ['VINIX_QEMU_PERSIST_DISK', 'VINIX_QEMU_GUEST_INIT', 'VINIX_QEMU_OVERLAY', 'VINIX_QEMU_MODULE_ISO', 'VINIX_QEMU_BASE_ARCHIVE', 'VINIX_QEMU_MODULE_MANIFEST', 'VINIX_QEMU_EXTRA_MODULES', 'VINIX_BOOT_HYPRLAND', 'VINIX_UI2_SOURCE'] {
   rb.method('invoke', env, 'pop', [v(name), rb.ordinary(rb.null())], {})!
  }
  return rb.make_sequence([o(str(join(global('ROOT')!, 'scripts/run-aarch64.sh')!)!), v('--no-build'), v('--serial'), v('--no-persist'), v('--mem=1024')])!
 }
 update(env, ['VINIX_AMD64_KERNEL', 'VINIX_AMD64_INITRAMFS', 'VINIX_AMD64_ISO', 'VINIX_AMD64_ISO_BUILD_DIR'], [str(kernel)!, str(archive_)!, str(join(work, 'test.iso')!)!, str(join(work, 'iso-build')!)!])!
 cache := join(global('ROOT')!, 'build-amd64-iso/limine')!
 if flag(method(cache, 'is_dir', [])!)! {
  rb.call('invoke', 'shutil', 'copytree', [o(cache), o(join(work, 'iso-build/limine')!)], {})!
 }
 argv := rb.make_sequence([o(str(join(global('ROOT')!, 'build-support/build-amd64-iso.sh')!)!)])!
 rb.callback('invoke', {'module': ah.Value('subprocess'), 'name': ah.Value('run'), 'arguments': ah.Value([o(argv)]), 'options': ah.Value({'check': ah.Value(true)}), 'keyword_objects': ah.Value({'env': env})})!
 qemu := rb.call('acquire', 'shutil', 'which', [v('qemu-system-x86_64')], {})!
 firmware := join(attr(attr(rb.api('Path', [o(qemu)], {}, true)!, 'parent')!, 'parent')!, 'share/qemu/edk2-x86_64-code.fd')!
 return rb.make_sequence([o(qemu), v('-machine'), v('q35,smm=off'), v('-accel'), v('tcg'), v('-cpu'), v('max'), v('-m'), v('1024'), v('-smp'), v('2'), v('-drive'), v('if=pflash,format=raw,unit=0,readonly=on,file=' + text(firmware)!), v('-cdrom'), o(str(join(work, 'test.iso')!)!), v('-display'), v('none'), v('-monitor'), v('none'), v('-qmp'), v('unix:' + text(join(work, 'qmp.sock')!)! + ',server=on,wait=off'), v('-serial'), v('mon:stdio'), v('-no-reboot'), v('-nic'), v('none')])!
}
