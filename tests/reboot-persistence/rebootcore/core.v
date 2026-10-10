// SPDX-License-Identifier: GPL-2.0-or-later
module rebootcore

import androidhost as ah

fn binary(name string, left string, right ah.Value) !string { return call('operator.' + name, o(left), right)! }
fn calculated(name string, left string, right ah.Value) !string {
 result := binary(name, left, right) or { release([left])!; return err }
 release([left])!
 return result
}
fn sliced(value string, start ah.Value, stop ah.Value) !string {
 bounds := invoke(resolve('_SLICE')!, [start, stop], {})!
 result := item(value, o(bounds)) or { release([bounds])!; return err }
 release([bounds])!
 return result
}
fn assign(mapping string, key string, value string) ! { release([call('operator.setitem', o(mapping), v(ah.Value(key))!, o(value))!])! }
fn state_put(mut f Frame, state string, key string, value string) !string {
 // The Python main frame retains named locals across the prepare/capture/report phases.
 assign(state, key, value)!
 if key in ['recent', 'text'] { perform('_failure_cell', o(state), v(ah.Value(key))!, o(value))! }
 return f.named(key, value)!
}
fn comparison_owned(name string, left string, right string, retire []string) !bool {
 result := binary(name, left, o(right)) or { release(retire)!; return err }
 release(retire)!
 return tested(result)!
}
fn handled(cause IError, classes []string) !bool {
 active(cause)!
 accepted := matches(cause, classes) or { active(none)!; return err }
 active(none)!
 if accepted { discard(cause)! }
 return accepted
}
fn available_port(mut f Frame) !string {
 factory := global('socket.socket')!
 family := global('socket.AF_INET') or { release([factory])!; return err }
 kind := global('socket.SOCK_STREAM') or { release([family, factory])!; return err }
 manager := invoke_owned(factory, [o(family), o(kind)], {}, [kind, family])!
 listener := f.named('listener', callback('enter', {'owner': ah.Value(manager), 'consume': ah.Value(true)})!.text())!
 release([manager])!
 result := listener_port(listener) or {
  cause := err
  suppressed := callback('exit', {'owner': ah.Value(manager), 'error': detail(cause)})!
  if suppressed as bool { discard(cause)!; return literal(none_())! }
  return cause
 }
 callback('exit', {'owner': ah.Value(manager), 'error': none_()})!
 return result
}
fn listener_port(listener string) !string {
 binder := member(listener, 'bind')!
 address := tuple_([v(ah.Value('127.0.0.1'))!, v(ah.Value(0))!])!
 release([invoke_owned(binder, [o(address)], {}, [address])!])!
 converter := global('str')!
 result := method(listener, 'getsockname', [], {}) or { release([converter])!; return err }
 port := item(result, v(ah.Value(1))!) or { release([result, converter])!; return err }
 release([result])!
 return invoke_owned(converter, [o(port)], {}, [port])!
}
fn selected(master string, seconds string) ![]string {
 target := global('select.select')!
 first := list_([o(master)])!
 second := list_([])!
 third := list_([])!
 return triple(invoke_owned(target, [o(first), o(second), o(third), o(seconds)], {}, [third, second, first])!)!
}
fn gone(pid string, master string, seconds string, mut f Frame) !string {
 deadline := f.named('deadline', calculated('add', call('time.monotonic')!, o(seconds))!)!
 f.clean()!
 for {
  target := global('os.waitpid')!
  flags := global('os.WNOHANG') or { release([target])!; return err }
  release([invoke_owned(target, [o(pid), o(flags)], {}, [flags]) or {
   if !handled(err, ['ChildProcessError'])! { return err }
   literal(none_())!
  }])!
  perform('os.killpg', o(pid), v(ah.Value(0))!) or {
   cause := err
   active(cause)!
   if matches(cause, ['ProcessLookupError'])! { active(none)!; discard(cause)!; return literal(ah.Value(true))! }
   accepted := matches(cause, ['PermissionError'])!
   active(none)!
   if !accepted { return cause }
   discard(cause)!
  }
  if compared('ge', call('time.monotonic')!, o(deadline))! { return literal(ah.Value(false))! }
  values := selected(master, literal(ah.Value(ah.Number{'0.05'}))!)!
  readable := f.named('readable', values[0])!
  f.named('_', values[1])!
  f.named('_', values[2])!
  if truth(readable)! {
   perform('os.read', o(master), v(ah.Value(65536))!) or {
    if !handled(err, ['OSError'])! { return err }
    perform('time.sleep', v(ah.Value(ah.Number{'0.05'}))!)!
   }
  }
  f.clean()!
 }
 return literal(ah.Value(false))!
}
fn stop_child(pid string, master string, mut f Frame) !string {
 perform('os.write', o(master), o(bytes_('0178')!)) or { if !handled(err, ['OSError'])! { return err } }
 if tested(call('gone', o(pid), o(master), v(ah.Value(5))!)!)! { return literal(none_())! }
 terminate := global('signal.SIGTERM')!
 kill := global('signal.SIGKILL') or { release([terminate])!; return err }
 signals := tuple_([o(terminate), o(kill)])!
 release([kill, terminate])!
 iterator := call('_ITER', o(signals))!
 release([signals])!
 f.names['iteration'] = iterator
 for {
  row := callback('next', {'owner': ah.Value(iterator)})!.object()
  if ah.field(row, 'done') as bool { break }
  sig := f.named('signal_number', ah.field(row, 'value').text())!
  perform('os.killpg', o(pid), o(sig)) or {
   cause := err
   active(cause)!
   if matches(cause, ['ProcessLookupError'])! { active(none)!; discard(cause)!; return literal(none_())! }
   accepted := matches(cause, ['PermissionError'])!
   active(none)!
   if !accepted { return cause }
   discard(cause)!
  }
  if tested(call('gone', o(pid), o(master), v(ah.Value(2))!)!)! { return literal(none_())! }
  f.clean()!
 }
 release([iterator])!
 f.names.delete('iteration')
 return literal(none_())!
}
fn field_text(receiver string, name string) !string {
 converter := global('str')!
 value := member(receiver, name) or { release([converter])!; return err }
 return invoke_owned(converter, [o(value)], {}, [value])!
}
fn formatted_field(receiver string, name string) !string { return formatted_temporary(member(receiver, name)!, false)! }
fn path(parent string, component string) !string { return binary('truediv', parent, v(ah.Value(component))!)! }
fn field_path(receiver string, field string, component string) !string {
 parent := member(receiver, field)!
 result := path(parent, component) or { release([parent])!; return err }
 release([parent])!
 return result
}
fn path_text(parent string, component string) !string {
 converter := global('str')!
 value := path(parent, component) or { release([converter])!; return err }
 return invoke_owned(converter, [o(value)], {}, [value])!
}
fn field_path_text(receiver string, field string, component string) !string {
 converter := global('str')!
 value := field_path(receiver, field, component) or { release([converter])!; return err }
 return invoke_owned(converter, [o(value)], {}, [value])!
}
fn environment_put(env string, name string, value string) ! {
 assign(env, name, value) or { release([value])!; return err }
 release([value])!
}
fn env_get(name string, default_ ah.Value) !string { return temporary_method(global('os.environ')!, 'get', [v(ah.Value(name))!, default_], {})! }
fn tar_manager(archive string, append_ bool) !string {
 target := global('tarfile.open')!
 if !append_ { return invoke(target, [o(archive)], {})! }
 format_ := global('tarfile.USTAR_FORMAT') or { release([target])!; return err }
 return invoke_owned(target, [o(archive), v(ah.Value('a'))!], {'format': o(format_)}, [format_])!
}
fn managed_action(state string, manager string, action string, arguments []ah.Value, mut f Frame) ! {
 stream := state_put(mut f, state, 'stream', callback('enter', {'owner': ah.Value(manager), 'consume': ah.Value(true)})!.text())!
 release([manager])!
 perform_method(stream, action, arguments, {}) or {
  cause := err
  suppressed := callback('exit', {'owner': ah.Value(manager), 'error': detail(cause)})!
  if suppressed as bool { discard(cause)!; return }
  return cause
 }
 callback('exit', {'owner': ah.Value(manager), 'error': none_()})!
}
fn archive_add(state string, archive string, arguments string, mut f Frame) ! {
 manager := tar_manager(archive, true)!
 stream := state_put(mut f, state, 'stream', callback('enter', {'owner': ah.Value(manager), 'consume': ah.Value(true)})!.text())!
 release([manager])!
 archive_add_body(stream, arguments) or {
  cause := err
  suppressed := callback('exit', {'owner': ah.Value(manager), 'error': detail(cause)})!
  if suppressed as bool { discard(cause)!; return }
  return cause
 }
 callback('exit', {'owner': ah.Value(manager), 'error': none_()})!
}
fn archive_add_body(stream string, arguments string) ! {
 target := member(stream, 'add')!
 init := member(arguments, 'init') or { release([target])!; return err }
 release([invoke_owned(target, [o(init), v(ah.Value('sbin/init'))!], {}, [init])!])!
}
fn digest(archive string) !string {
 factory := global('hashlib.sha256')!
 content := method(archive, 'read_bytes', [], {}) or { release([factory])!; return err }
 hasher := invoke_owned(factory, [o(content)], {}, [content])!
 target := member(hasher, 'hexdigest') or { release([hasher])!; return err }
 release([hasher])!
 return invoke(target, [], {})!
}
fn prepare(state string, mut f Frame) !string {
 arguments := f.named('arguments', get(state, 'arguments')!)!
 root := f.named('root', get(state, 'root')!)!
 environment := state_put(mut f, state, 'environment', temporary_method(global('os.environ')!, 'copy', [], {})!)!
 environment_put(environment, 'VINIX_INITRAMFS', field_text(arguments, 'initramfs')!)!
 for entry in [['VINIX_BOOT_DISK','boot.img'],['VINIX_EFIVARS','efivars.fd'],['VINIX_QEMU_PACKAGE_STORE','packages.tar'],['VINIX_QEMU_PERSIST_DISK','root.ext2']] {
  environment_put(environment, entry[0], field_path_text(arguments, 'state_dir', entry[1])!)!
 }
 environment_put(environment, 'VINIX_QEMU_PERSIST_SIZE_MB', literal(ah.Value('64'))!)!
 perform_method(environment, 'pop', [v(ah.Value('VINIX_QEMU_PERSIST'))!, v(none_())!], {})!
 environment_put(environment, 'VINIX_KEEP_TEMP_BOOT_DISK', literal(ah.Value('1'))!)!
 setter := member(environment, 'setdefault')!
 port := call('available_port')!
 release([invoke_owned(setter, [v(ah.Value('VINIX_QEMU_PACKAGE_STORE_PORT'))!, o(port)], {}, [port])!])!
 if compared('ne', call('platform.system')!, v(ah.Value('Darwin'))!)! { perform_method(environment, 'setdefault', [v(ah.Value('USE_TCG'))!, v(ah.Value('1'))!], {})! }
 if compared('eq', member(arguments, 'arch')!, v(ah.Value('aarch64'))!)! {
  script := path_text(root, 'scripts/run-aarch64.sh')!
  init := concatenate([literal(ah.Value('--guest-init='))!, formatted_field(arguments, 'init')!])!
  command := state_put(mut f, state, 'command', list_([o(script), v(ah.Value('--serial'))!, v(ah.Value('--mem=2048'))!, o(init)])!)!
  release([init, script])!
  if compared('eq', env_get('VINIX_REBOOT_PERSISTENCE_NO_BUILD', v(none_())!)!, v(ah.Value('1'))!)! { perform_method(command, 'insert', [v(ah.Value(1))!, v(ah.Value('--no-build'))!], {})! }
  return literal(none_())!
 }
 archive := state_put(mut f, state, 'archive', field_path(arguments, 'state_dir', 'initramfs.tar')!)!
 copier := global('shutil.copyfile')!
 source := member(arguments, 'initramfs')!
 release([invoke_owned(copier, [o(source), o(archive)], {}, [source])!])!
 archive_add(state, archive, arguments, mut f)!
 mapped := call('_mapping', o(environment))!
 environment_receiver := global('os.environ')!
 getter := member(environment_receiver, 'get')!
 release([environment_receiver])!
 default_kernel := path_text(root, 'kernel/bin/vinix')!
 kernel := invoke_owned(getter, [v(ah.Value('VINIX_AMD64_KERNEL'))!, o(default_kernel)], {}, [default_kernel])!
 initramfs := text(archive)!
 iso := field_path_text(arguments, 'state_dir', 'test.iso')!
 iso_dir := field_path_text(arguments, 'state_dir', 'iso')!
 for entry in [['VINIX_AMD64_KERNEL',kernel],['VINIX_AMD64_INITRAMFS',initramfs],['VINIX_AMD64_ISO',iso],['VINIX_AMD64_ISO_BUILD_DIR',iso_dir]] { assign(mapped, entry[0], entry[1])! }
 release([iso_dir, iso, initramfs, kernel])!
 isoenv := state_put(mut f, state, 'isoenv', mapped)!
 runner := global('subprocess.run')!
 builder := path_text(root, 'build-support/build-amd64-iso.sh')!
 argv := list_([o(builder)])!
 release([builder])!
 devnull := global('subprocess.DEVNULL')!
 release([invoke_owned(runner, [o(argv)], {'env': o(isoenv), 'check': v(ah.Value(true))!, 'stdout': o(devnull)}, [devnull, argv])!])!
 seed := state_put(mut f, state, 'seed', field_path(arguments, 'state_dir', 'seed')!)!
 mut name_values := []ah.Value{}
 for name in ['root','dev','proc','tmp','run'] { name_values << v(ah.Value(name))! }
 names := tuple_(name_values)!
 iterator := call('_ITER', o(names))!
 release([names])!
 f.names['iteration'] = iterator
 for {
  row := callback('next', {'owner': ah.Value(iterator)})!.object()
  if ah.field(row, 'done') as bool { break }
  name := state_put(mut f, state, 'name', ah.field(row, 'value').text())!
  directory := binary('truediv', seed, o(name))!
  target := member(directory, 'mkdir') or { release([directory])!; return err }
  release([directory])!
  release([invoke(target, [], {'parents': v(ah.Value(true))!, 'exist_ok': v(ah.Value(true))!})!])!
  f.clean()!
 }
 release([iterator])!
 f.names.delete('iteration')
 managed_action(state, tar_manager(archive, false)!, 'extractall', [o(seed)], mut f)!
 identity_path := path(seed, '.vinix-image-id')!
 writer := member(identity_path, 'write_text') or { release([identity_path])!; return err }
 release([identity_path])!
 hex := digest(archive)!
 short := sliced(hex, v(none_())!, v(ah.Value(16))!)!
 release([hex])!
 line := calculated('add', short, v(ah.Value('\n'))!)!
 release([invoke_owned(writer, [o(line)], {}, [line])!])!
 disk := state_put(mut f, state, 'disk', field_path(arguments, 'state_dir', 'root.ext2')!)!
 managed_action(state, method(disk, 'open', [v(ah.Value('wb'))!], {})!, 'truncate', [v(ah.Value(67108864))!], mut f)!
 helper_path := state_put(mut f, state, 'helper_path', path(root, 'tests/disk-no-sync/run_vm.py')!)!
 helper := global('runpy.run_path')!
 location := text(helper_path)!
 module_ := invoke_owned(helper, [o(location)], {}, [location])!
 finder := item(module_, v(ah.Value('find_debugfs'))!)!
 release([module_])!
 debugfs := state_put(mut f, state, 'debugfs', invoke(finder, [], {})!)!
 if !truth(debugfs)! { raise_('RuntimeError', 'e2fsprogs is required for the native x86 persistence disk')! }
 filesystem_runner := global('subprocess.run')!
 converter := global('str')!
 path_factory := global('Path')!
 debug_path := invoke(path_factory, [o(debugfs)], {})!
 mkfs_path := temporary_method(debug_path, 'with_name', [v(ah.Value('mke2fs'))!], {})!
 executable := invoke_owned(converter, [o(mkfs_path)], {}, [mkfs_path])!
 mut command_args := [o(executable)]
 for value in ['-q','-F','-t','ext2','-b','4096','-I','128','-O','filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum','-d'] { command_args << v(ah.Value(value))! }
 seed_arg := text(seed)!
 disk_arg := text(disk)!
 command_args << o(seed_arg)
 command_args << o(disk_arg)
 fs_argv := list_(command_args)!
 release([disk_arg, seed_arg, executable])!
 release([invoke_owned(filesystem_runner, [o(fs_argv)], {'check': v(ah.Value(true))!}, [fs_argv])!])!
 which := global('shutil.which')!
 qemu_name := env_get('VINIX_QEMU_X86_64', v(ah.Value('qemu-system-x86_64'))!)!
 qemu := state_put(mut f, state, 'qemu', invoke_owned(which, [o(qemu_name)], {}, [qemu_name])!)!
 if !truth(qemu)! { raise_('RuntimeError', 'qemu-system-x86_64 is required')! }
 firmware_environment_receiver := global('os.environ')!
 firmware_getter := member(firmware_environment_receiver, 'get')!
 release([firmware_environment_receiver])!
 firmware_converter := global('str')!
 firmware_path := call('Path', o(qemu))!
 first_parent := member(firmware_path, 'parent')!
 release([firmware_path])!
 second_parent := member(first_parent, 'parent')!
 release([first_parent])!
 firmware_default_path := path(second_parent, 'share/qemu/edk2-x86_64-code.fd')!
 release([second_parent])!
 default_firmware := invoke_owned(firmware_converter, [o(firmware_default_path)], {}, [firmware_default_path])!
 firmware := state_put(mut f, state, 'firmware', invoke_owned(firmware_getter, [v(ah.Value('VINIX_OVMF_CODE_AMD64'))!, o(default_firmware)], {}, [default_firmware])!)!
 mut command := [o(qemu)]
 for value in ['-machine','q35,smm=off','-accel'] { command << v(ah.Value(value))! }
 command << o(env_get('VINIX_QEMU_ACCEL', v(ah.Value('tcg'))!)!)
 for value in ['-cpu','max','-m','2048','-smp','2','-drive'] { command << v(ah.Value(value))! }
 command << o(concatenate([literal(ah.Value('if=pflash,format=raw,unit=0,readonly=on,file='))!, formatted(firmware, false)!])!)
 command << v(ah.Value('-cdrom'))!
 command << o(field_path_text(arguments, 'state_dir', 'test.iso')!)
 command << v(ah.Value('-drive'))!
 command << o(concatenate([literal(ah.Value('if=ide,format=raw,file='))!, formatted(disk, false)!, literal(ah.Value(',cache=writeback'))!])!)
 for value in ['-display','none','-monitor','none','-serial','stdio'] { command << v(ah.Value(value))! }
 state_put(mut f, state, 'command', list_(command)!)!
 return literal(none_())!
}
fn raise_(kind string, message_ string) ! {
 error_ := call(kind, v(ah.Value(message_))!)!
 perform('_RAISE', o(error_))!
}
fn any_failures(state string, key string) !bool {
 target := global('any')!
 markers := global('FAIL_MARKERS') or { release([target])!; return err }
 cells := get(state, '_failure_cells') or { release([markers, target])!; return err }
 cell := get(cells, key) or { release([cells, markers, target])!; return err }
 release([cells])!
 generated := call('_failure_candidates', o(cell), o(markers)) or { release([cell, markers, target])!; return err }
 release([cell])!
 release([markers])!
 return tested(invoke_owned(target, [o(generated)], {}, [generated])!)!
}
fn contains_marker(output string, marker string) !string { return literal(ah.Value(compare('contains', output, o(marker))!))! }
fn capture(state string, pid string, master string, mut f Frame) !string {
 mut transcript := f.named('transcript', get(state, 'transcript')!)!
 deadline := f.named('deadline', get(state, 'deadline')!)!
 for compared('lt', call('time.monotonic')!, o(deadline))! {
  target := global('os.waitpid')!
  flags := global('os.WNOHANG')!
  values := pair(invoke_owned(target, [o(pid), o(flags)], {}, [flags])!)!
  waited := state_put(mut f, state, 'waited', values[0])!
  state_put(mut f, state, '_', values[1])!
  if compare('eq', waited, o(pid))! { break }
  ready := selected(master, literal(ah.Value(ah.Number{'0.25'}))!)!
  readable := state_put(mut f, state, 'readable', ready[0])!
  state_put(mut f, state, '_', ready[1])!
  state_put(mut f, state, '_', ready[2])!
  if !truth(readable)! { f.clean()!; continue }
  chunk := call('os.read', o(master), v(ah.Value(65536))!) or { if !handled(err, ['OSError'])! { return err }; break }
  state_put(mut f, state, 'chunk', chunk)!
  if !truth(chunk)! { break }
  transcript = state_put(mut f, state, 'transcript', binary('iadd', transcript, o(chunk))!)!
  perform_temporary_method(global('sys.stdout.buffer')!, 'write', [o(chunk)], {})!
  perform_temporary_method(global('sys.stdout.buffer')!, 'flush', [], {})!
  converter := global('bytes')!
  section := sliced(transcript, v(ah.Value(-8192))!, v(none_())!)!
  recent := state_put(mut f, state, 'recent', invoke_owned(converter, [o(section)], {}, [section])!)!
  marker := global('PASS_MARKER')!
  passed := comparison_owned('contains', recent, marker, [marker])!
  if passed || any_failures(state, 'recent')! { state_put(mut f, state, 'finished', literal(ah.Value(true))!)!; break }
  f.clean()!
 }
 return literal(none_())!
}
fn print_line(message_ string, error_ bool) ! {
 target := global('print')!
 mut options := map[string]ah.Value{}
 mut consumed := []string{}
 if error_ { output := global('sys.stderr')!; options['file'] = o(output); consumed << output }
 release([invoke_owned(target, [v(ah.Value(message_))!], options, consumed)!])!
}
fn report(state string, mut f Frame) !string {
 arguments := f.named('arguments', get(state, 'arguments')!)!
 transcript := f.named('transcript', get(state, 'transcript')!)!
 text_ := state_put(mut f, state, 'text', call('bytes', o(transcript))!)!
 serial := field_path(arguments, 'state_dir', 'serial.log')!
 target := member(serial, 'write_bytes')!
 release([serial])!
 release([invoke(target, [o(text_)], {})!])!
 perform('print')!
 if any_failures(state, 'text')! { print_line('ERROR: guest reported a failure', true)!; return literal(ah.Value(1))! }
 for entry in [['START_MARKER','ERROR: the guest did not come back up after reboot(2)'],['WROTE_MARKER','ERROR: the guest never wrote the marker'],['SYNC_MARKER','ERROR: sync(2) did not return'],['PASS_MARKER','ERROR: the file written before reboot(2) did not survive it']] {
  mut marker := ''
  mut missing := false
  if entry[0] in ['START_MARKER','SYNC_MARKER'] {
   counter := member(text_, 'count')!
   marker = global(entry[0])!
   count := invoke_owned(counter, [o(marker)], {}, [marker])!
   missing = compared('lt', count, v(ah.Value(2))!)!
  } else { marker = global(entry[0])!; missing = !comparison_owned('contains', text_, marker, [marker])! }
  if missing { print_line(entry[1], true)!; return literal(ah.Value(1))! }
 }
 printer := global('print')!
 line := concatenate([literal(ah.Value('==> '))!, formatted_field(arguments, 'arch')!, literal(ah.Value(' reboot persistence passed'))!])!
 release([invoke_owned(printer, [o(line)], {}, [line])!])!
 return literal(ah.Value(0))!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
 ids := ah.field(row, 'arguments').items().map(it.text())
 operation := ah.field(row, 'operation').text()
 current_builtins = ids[1]
 order := match operation {
  'available_port' { ['listener'] }
  'gone' { ['pid','master','seconds','deadline','readable','_'] }
  'stop_child' { ['pid','master','signal_number'] }
  else { ['parser','arguments','root','environment','command','archive','stream','isoenv','seed','name','disk','helper_path','debugfs','qemu','firmware','pid','master','transcript','finished','deadline','waited','_','readable','chunk','recent','text'] }
 }
 mut f := Frame{start: checkpoint()!, pins: ids[0], order: order}
 for i in 1 .. ids.len { f.names['argument-' + i.str()] = ids[i] }
 if operation in ['prepare','capture','report'] {
  // Pull prior named main locals into this phase before any callbacks.
  for key in order { found := compare('contains', ids[2], v(ah.Value(key))!)!; if found { f.named(key, get(ids[2], key)!)! } }
 } else if operation == 'gone' {
  for i, key in ['pid','master','seconds'] { f.named(key, ids[i+2])! }
 } else if operation == 'stop_child' { f.named('pid', ids[2])!; f.named('master', ids[3])! }
 result := execute(operation, ids, mut f) or { f.failed(err)!; return err }
 for key in f.order { if id := f.names[key] { if id != result { release([id])! } } }
 clean_since(f.start, [result])!
 return ah.Value(result)
}

fn execute(operation string, ids []string, mut f Frame) !string {
 return match operation {
  'available_port' { available_port(mut f)! }
  'gone' { gone(ids[2], ids[3], ids[4], mut f)! }
  'stop_child' { stop_child(ids[2], ids[3], mut f)! }
  'prepare' { prepare(ids[2], mut f)! }
  'capture' { capture(ids[2], ids[3], ids[4], mut f)! }
  'report' { report(ids[2], mut f)! }
  'contains_marker' { contains_marker(ids[2], ids[3])! }
  else { return error('Unknown reboot persistence operation') }
 }
}
