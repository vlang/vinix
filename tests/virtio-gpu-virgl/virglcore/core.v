// SPDX-License-Identifier: GPL-2.0-or-later
module virglcore

import androidhost as ah

fn path_join(root string, path string) !string { return call('operator.truediv', o(root), v(ah.Value(path))!)! }
fn path_text(root string, path string) !string {
 target := global('str')!
 joined := path_join(root, path) or { release([target])!; return err }
 value := invoke_owned(target, [o(joined)], {}, [joined])!
 return value
}
fn printed(target string, value string, error_ bool) ! {
 mut options := map[string]ah.Value{}
 mut consumed := []string{}
 if error_ {
  output := global('sys.stderr')!
  options['file'] = o(output)
  consumed << output
 }
 release([invoke_owned(target, [o(value)], options, consumed)!])!
}
fn log(message_ string, error_ bool) ! {
 target := global('print')!
 printed(target, literal(ah.Value(message_))!, error_)!
}
fn exit_code(status string) !string {
 if tested(call('os.WIFEXITED', o(status))!)! { return call('os.WEXITSTATUS', o(status))! }
 if tested(call('os.WIFSIGNALED', o(status))!)! { return call('operator.add', v(ah.Value(128))!, o(call('os.WTERMSIG', o(status))!))! }
 return literal(ah.Value(1))!
}
fn signal_child(pid string, sig string) ! {
 perform('os.killpg', o(pid), o(sig)) or {
  cause := err
  active(cause)!
  if !matches(cause, ['ProcessLookupError', 'PermissionError'])! { active(none)!; return cause }
  perform('os.kill', o(pid), o(sig)) or {
   nested := err
   active(nested)!
   if !matches(nested, ['ProcessLookupError'])! { active(none)!; return nested }
   active(cause)!
   discard(nested)!
  }
  active(none)!
  discard(cause)!
 }
}
fn wait_phase(pid string, seconds int, catch_child bool, mut f Frame) !bool {
 deadline := f.named('deadline', added(call('time.monotonic')!, v(ah.Value(seconds))!)!)!
 f.clean()!
 for compared('lt', call('time.monotonic')!, o(deadline))! {
  target := global('os.waitpid')!
  flags := global('os.WNOHANG') or { release([target])!; return err }
  returned := invoke_owned(target, [o(pid), o(flags)], {}, [flags]) or {
   cause := err
   if !catch_child { return cause }
   active(cause)!
   if !matches(cause, ['ChildProcessError'])! { active(none)!; return cause }
   active(none)!
   discard(cause)!
   return true
  }
  values := pair(returned)!
  waited := f.named('waited', values[0])!
  f.named('_status', values[1])!
  if compare('eq', waited, o(pid))! { return true }
  perform('time.sleep', v(ah.Value(ah.Number{'0.05'}))!)!
  f.clean()!
 }
 return false
}
fn stop_child(pid string, master string, mut f Frame) ! {
 perform('os.write', o(master), o(bytes_('0178')!)) or {
  cause := err
  active(cause)!
  if !matches(cause, ['OSError'])! { active(none)!; return cause }
  active(none)!
  discard(cause)!
 }
 if wait_phase(pid, 5, false, mut f)! { return }
 target := global('signal_child')!
 sig := global('signal.SIGTERM') or { release([target])!; return err }
 release([invoke(target, [o(pid), o(sig)], {})!])!
 if wait_phase(pid, 2, false, mut f)! { return }
 target_kill := global('signal_child')!
 kill := global('signal.SIGKILL') or { release([target_kill])!; return err }
 release([invoke(target_kill, [o(pid), o(kill)], {})!])!
 wait_phase(pid, 2, true, mut f)!
}
fn qemu_path(root string, mut f Frame) !string {
 target := global('os.environ.get')!
 override := f.named('override', invoke(target, [v(ah.Value('VINIX_VIRGL_QEMU'))!], {})!)!
 if truth(override)! {
  path := call('Path', o(override))!
  expand := member(path, 'expanduser') or { release([path])!; return err }
  release([path])!
  expanded := invoke(expand, [], {})!
  resolve_ := member(expanded, 'resolve') or { release([expanded])!; return err }
  release([expanded])!
  return invoke(resolve_, [], {})!
 }
 parent := member(root, 'parent')!
 result := path_join(parent, 'kekvm/.tools/qemu-virgl/bin/kekvm-qemu-system-aarch64') or { release([parent])!; return err }
 release([parent])!
 return result
}
fn check_host(root string, mut f Frame) !string {
 if compared('ne', call('platform.system')!, v(ah.Value('Darwin'))!)! || compared('ne', call('platform.machine')!, v(ah.Value('arm64'))!)! {
  return tuple_([o(call('Path')!), v(ah.Value('this test requires an Apple-silicon macOS host'))!])!
 }
 qemu := f.named('qemu', call('qemu_path', o(root))!)!
 if !tested(method(qemu, 'is_file', [], {})!)! || !tested(call('os.access', o(qemu), o(global('os.X_OK')!))!)! {
  message_ := message("KekVM's VirGL QEMU is missing: ", qemu, "\nRun `make setup-gpu` in ~/code/kekvm first.")!
  return tuple_([o(qemu), o(message_)])!
 }
 runner := global('subprocess.run')!
 command := list_([o(qemu), v(ah.Value('-device'))!, v(ah.Value('help'))!])!
 devices := f.named('devices', invoke_owned(runner, [o(command)], {'capture_output': v(ah.Value(true))!, 'check': v(ah.Value(false))!}, [command])!)!
 if compared('ne', member(devices, 'returncode')!, v(ah.Value(0))!)! || !compared('contains', member(devices, 'stdout')!, o(bytes_('76697274696f2d6770752d676c2d646576696365')!))! {
  return tuple_([o(qemu), v(ah.Value('KekVM QEMU has no MMIO virtio-gpu-gl-device'))!])!
 }
 return tuple_([o(qemu), v(none_())!])!
}
fn prepare(root string, desktop string, mut f Frame) !string {
 checked := call('check_host', o(root))!
 values := pair(checked)!
 qemu := f.named('qemu', values[0])!
 host_error := f.named('host_error', values[1])!
 if truth(host_error)! {
  printer := global('print')!
  printed(printer, message('ERROR: ', host_error, '')!, true)!
  return literal(none_())!
 }
 kernel := f.named('kernel', path_join(root, 'kernel/bin/vinix')!)!
 desktop_ := truth(desktop)!
 source := f.named('source_image', path_join(root, if desktop_ { 'build-support/init-aarch64/initramfs-desktop.tar' } else { 'build-support/init-aarch64/initramfs.tar' })!)!
 guest := f.named('guest_init', path_join(root, if desktop_ { 'tests/virtio-gpu-virgl/desktop-guest-init.sh' } else { 'tests/virtio-gpu-virgl/guest-init.sh' })!)!
 passed := f.named('pass_line', global(if desktop_ { 'DESKTOP_PASS_LINE' } else { 'SMOKE_PASS_LINE' })!)!
 failed := f.named('fail_line', global(if desktop_ { 'DESKTOP_FAIL_LINE' } else { 'SMOKE_FAIL_LINE' })!)!
 for i,name in ['kernel','initramfs'] {
  label := f.named('label', literal(ah.Value(name))!)!
  path := f.named('path', if i == 0 { kernel } else { source })!
  if !tested(method(path, 'is_file', [], {})!)! {
   printer := global('print')!
   printed(printer, concatenate([literal(ah.Value('ERROR: Vinix '))!, formatted(label, false)!, literal(ah.Value(' is missing: '))!, formatted(path, false)!])!, true)!
   return literal(none_())!
  }
 }
 printer := global('print')!
 printed(printer, message('Host transport: ', qemu, '')!, false)!
 log('Path: Vinix VirtIO-GPU -> VirGL -> virglrenderer -> host Apple GPU', false)!
 log('Boundary: this does not emulate native AGX RTKit/UAT/firmware', false)!
 if truth(desktop)! { log('Workload: full vinix-desktop-gpu startup through its first frame', false)! }
 return tuple_([o(qemu), o(source), o(guest), o(passed), o(failed), o(named_values(f)!)])!
}
fn command(root string, qemu string, source string, guest string, desktop string, scratch string, mut f Frame) !string {
 env := f.named('environment', temporary_method(global('os.environ')!, 'copy', [], {})!)!
 stringer := global('str')!
 qemu_text := invoke(stringer, [o(qemu)], {})!
 perform('operator.setitem', o(env), v(ah.Value('VINIX_VIRGL_QEMU'))!, o(qemu_text))!
 release([qemu_text])!
 perform('operator.setitem', o(env), v(ah.Value('TMPDIR'))!, o(scratch))!
 for name in ['QEMU_DISPLAY_BACKEND','VINIX_QEMU_PERSIST','VINIX_QEMU_PERSIST_DISK','VINIX_QEMU_PERSIST_SEED','VINIX_QEMU_PERSIST_SIZE_MB','VINIX_QEMU_ROOT_DISK','VINIX_QEMU_ROOT_IMAGE','VINIX_BOOT_DISK','VINIX_EFIVARS','VINIX_QEMU_PACKAGE_STORE'] {
  perform_method(env, 'pop', [v(ah.Value(name))!, v(none_())!], {})!
 }
 setter := member(env, 'setdefault')!
 size := if truth(desktop)! { '12288' } else { '8192' }
 release([invoke(setter, [v(ah.Value('VINIX_QEMU_MEM'))!, v(ah.Value(size))!], {})!])!
 mut values := []ah.Value{}
 if truth(desktop)! {
  script := path_text(root, 'scripts/run-desktop-aarch64.sh')!
  values = [o(script), v(ah.Value('--no-build'))!, v(ah.Value('--no-disk-root'))!, v(ah.Value('--ephemeral'))!, v(ah.Value('gpuvm'))!]
 } else {
  image := text(source)!
  perform('operator.setitem', o(env), v(ah.Value('VINIX_INITRAMFS'))!, o(image))!
  release([image])!
  script := path_text(root, 'scripts/run-aarch64.sh')!
  values = [o(script), v(ah.Value('--no-build'))!, v(ah.Value('--no-persist'))!, v(ah.Value('--ephemeral'))!, v(ah.Value('--virgl'))!]
 }
 values << o(message('--guest-init=', guest, '')!)
 argv := f.named('command', list_(values)!)!
 return tuple_([o(env), o(argv)])!
}
fn state_put(mut f Frame, state string, name string, value string) !string {
 perform('operator.setitem', o(state), v(ah.Value(name))!, o(value))!
 return f.named(name, value)!
}
fn read_error(cause IError) !bool {
 active(cause)!
 if !matches(cause, ['OSError'])! { active(none)!; return false }
 object := callback('error_object', {'error': detail(cause)})!.text()
 number := member(object, 'errno')!
 code := global('errno.EIO')!
 equal := compare('eq', number, o(code))!
 release([code, number, object])!
 active(none)!
 if equal { discard(cause)! }
 return equal
}
fn capture_step(state string, pid string, master string, passed string, failed string, mut f Frame) !bool {
 deadline := get(state, 'deadline')!
 if !compared('lt', call('time.monotonic')!, o(deadline))! { return true }
 waiter := global('os.waitpid')!
 flag := global('os.WNOHANG') or { release([waiter])!; return err }
 values := pair(invoke_owned(waiter, [o(pid), o(flag)], {}, [flag])!)!
 waited := state_put(mut f, state, 'waited', values[0])!
 child_status := state_put(mut f, state, 'child_status', values[1])!
 if compare('eq', waited, o(pid))! { state_put(mut f, state, 'status', child_status)!; return true }
 selector := global('select.select')!
 ready := invoke(selector, [o(list_([o(master)])!), o(list_([])!), o(list_([])!), v(ah.Value(ah.Number{'0.25'}))!], {})!
 selection := triple(ready)!
 readable := state_put(mut f, state, 'readable', selection[0])!
 state_put(mut f, state, '_', selection[1])!
 state_put(mut f, state, '_', selection[2])!
 if !truth(readable)! { return false }
 chunk := call('os.read', o(master), v(ah.Value(65536))!) or {
  cause := err
  if read_error(cause)! { return false }
  return cause
 }
 state_put(mut f, state, 'chunk', chunk)!
 if !truth(chunk)! { return false }
 transcript := get(state, 'transcript')!
 perform_method(transcript, 'extend', [o(chunk)], {})!
 perform_temporary_method(global('sys.stdout.buffer')!, 'write', [o(chunk)], {})!
 perform_temporary_method(global('sys.stdout.buffer')!, 'flush', [], {})!
 byter := global('bytes')!
 cut := call('slice', v(ah.Value(-131072))!, v(none_())!)!
 sliced := item(transcript, o(cut)) or { release([byter, cut])!; return err }
 release([cut])!
 recent := invoke(byter, [o(sliced)], {}) or { release([sliced])!; return err }
 release([sliced])!
 state_put(mut f, state, 'recent', recent)!
 seen := get(state, 'pass_seen')!
 match_ := method(passed, 'search', [o(recent)], {})!
 compared := call('operator.is_not', o(match_), v(none_())!)!
 release([match_])!
 updated := call('operator.ior', o(seen), o(compared))!
 release([seen, compared])!
 state_put(mut f, state, 'pass_seen', updated)!
 seen_fail := get(state, 'fail_seen')!
 match_fail := method(failed, 'search', [o(recent)], {})!
 compared_fail := call('operator.is_not', o(match_fail), v(none_())!)!
 release([match_fail])!
 updated_fail := call('operator.ior', o(seen_fail), o(compared_fail))!
 release([seen_fail, compared_fail])!
 state_put(mut f, state, 'fail_seen', updated_fail)!
 if (truth(updated)! || truth(updated_fail)!) && !truth(get(state, 'shutdown_sent')!)! {
  perform('os.write', o(master), o(bytes_('0178')!))!
  state_put(mut f, state, 'shutdown_sent', literal(ah.Value(true))!)!
  minimum := global('min')!
  old := get(state, 'deadline')!
  new := added(call('time.monotonic')!, v(ah.Value(10))!)!
  state_put(mut f, state, 'deadline', invoke_owned(minimum, [o(old), o(new)], {}, [new, old])!)!
 }
 return false
}
fn capture(state string, pid string, master string, passed string, failed string, mut f Frame) !string {
 for {
  done := capture_step(state, pid, master, passed, failed, mut f) or { f.clean()!; return err }
  f.clean()!
  if done { break }
 }
 if is_none(get(state, 'status')!)! {
  waiter := global('os.waitpid')!
  flag := global('os.WNOHANG') or { release([waiter])!; return err }
  values := pair(invoke_owned(waiter, [o(pid), o(flag)], {}, [flag])!)!
  waited := state_put(mut f, state, 'waited', values[0])!
  child_status := state_put(mut f, state, 'child_status', values[1])!
  if compare('eq', waited, o(pid))! { state_put(mut f, state, 'status', child_status)! }
 }
 return literal(none_())!
}
fn append(missing string, value string) ! { perform_method(missing, 'append', [o(value)], {})! }
fn report(state string, forced string, desktop string, mut f Frame) !string {
 output := state_put(mut f, state, 'output', call('bytes', o(get(state, 'transcript')!))!)!
 missing := state_put(mut f, state, 'missing', list_([])!)!
 if compared('ne', method(output, 'count', [o(global('FOUR_CPUS_ONLINE')!)], {})!, v(ah.Value(1))!)! { append(missing, literal(ah.Value('exactly four QEMU CPUs online'))!)! }
 if truth(desktop)! {
  if !tested(temporary_method(global('DESKTOP_RENDERER')!, 'search', [o(output)], {})!)! { append(missing, literal(ah.Value('desktop VirGL renderer backed by an Apple host GPU'))!)! }
  iterable := global('DESKTOP_REQUIRED_STAGES')!
  iterator := call('_ITER', o(iterable))!
  f.names['iterator'] = iterator
  release([iterable])!
  for {
   next := callback('next', {'owner': ah.Value(iterator)})!.object()
   if ah.field(next, 'done') as bool { break }
   stage := state_put(mut f, state, 'stage', ah.field(next, 'value').text())!
   marker := state_put(mut f, state, 'marker', call('operator.add', o(bytes_('76696e69782d6465736b746f703a2047505520696e69743a20')!), o(stage))!)!
   if !compare('contains', output, o(marker))! {
    appender := member(missing, 'append')!
    decoded := method(stage, 'decode', [], {})!
    value := concatenate([literal(ah.Value('desktop stage '))!, formatted_temporary(decoded, true)!])!
    release([invoke(appender, [o(value)], {})!])!
   }
   f.clean()!
  }
  release([iterator])!
  f.names.delete('iterator')
  if !compare('contains', output, o(global('DESKTOP_READY')!))! { append(missing, literal(ah.Value('desktop ready marker'))!)! }
 } else {
  if compared('ne', method(output, 'count', [o(global('NETWORK_PASS')!)], {})!, v(ah.Value(1))!)! { append(missing, literal(ah.Value('DHCP and package server connectivity'))!)! }
  if !tested(temporary_method(global('RENDERER')!, 'search', [o(output)], {})!)! { append(missing, literal(ah.Value('VirGL renderer backed by an Apple host GPU'))!)! }
  if compared('ne', method(output, 'count', [o(global('PIXELS')!)], {})!, v(ah.Value(1))!)! { append(missing, literal(ah.Value('validated rendered pixels'))!)! }
  if compared('ne', method(output, 'count', [o(global('VIRGL_PASS')!)], {})!, v(ah.Value(1))!)! { append(missing, literal(ah.Value('in-guest VirGL PASS marker'))!)! }
 }
 if compare('contains', output, o(global('M1_HARDWARE_PASS')!))! { append(missing, literal(ah.Value('VM incorrectly claimed a native M1 AGX pass'))!)! }
 if !truth(get(state, 'pass_seen')!)! { append(missing, literal(ah.Value('guest test-init PASS marker'))!)! }
 if truth(get(state, 'fail_seen')!)! { append(missing, literal(ah.Value('guest test-init reported failure'))!)! }
 if truth(forced)! { append(missing, literal(ah.Value('VM did not exit after the result'))!)! }
 status := get(state, 'status')!
 if !is_none(status)! && compared('ne', call('child_exit_code', o(status))!, v(ah.Value(0))!)! {
  appender := member(missing, 'append')!
  code := call('child_exit_code', o(status))!
  msg := concatenate([literal(ah.Value('VM exit status '))!, formatted_temporary(code, false)!])!
  release([invoke(appender, [o(msg)], {})!])!
 }
 if truth(missing)! {
  label := state_put(mut f, state, 'label', literal(ah.Value(if truth(desktop)! { 'GPU desktop startup' } else { 'VirGL smoke test' }))!)!
  stages := state_put(mut f, state, 'stages', temporary_method(global('DESKTOP_STAGE')!, 'findall', [o(output)], {})!)!
  if truth(desktop)! && truth(stages)! {
   appender := member(missing, 'append')!
   last := item(stages, v(ah.Value(-1))!)!
   decoder := member(last, 'decode') or { release([last, appender])!; return err }
   release([last])!
   decoded := invoke(decoder, [], {'errors': v(ah.Value('replace'))!})!
   msg := concatenate([literal(ah.Value('last desktop stage '))!, formatted_temporary(decoded, true)!])!
   release([invoke(appender, [o(msg)], {})!])!
  }
  printer := global('print')!
  first := concatenate([literal(ah.Value('\nFAIL KekVM '))!, formatted(label, false)!, literal(ah.Value(': '))!])!
  comma := literal(ah.Value(', '))!
  joiner := member(comma, 'join')!
  release([comma])!
  joined := invoke(joiner, [o(missing)], {})!
  result := call('operator.add', o(first), o(joined))!
  release([first, joined])!
  printed(printer, result, true)!
  return literal(ah.Value(1))!
 }
 return literal(ah.Value(0))!
}
fn success(desktop string) !string {
 if truth(desktop)! { log('\nPASS Vinix GPU desktop reached its first presented frame in KekVM', false)! } else { log('\nPASS Vinix rendered validated pixels through KekVM and the host Apple GPU', false)! }
 log('NOTE native Apple AGX firmware execution remains a physical-hardware test', false)!
 return literal(none_())!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
 ids := ah.field(row, 'arguments').items().map(it.text())
 operation := ah.field(row, 'operation').text()
 mut f := Frame{ start: checkpoint()!, pins: ids[0], order: ['root','timeout','desktop_startup','qemu','host_error','kernel','source_image','guest_init','pass_line','fail_line','label','path','scratch','environment','command','pid','master','transcript','pass_seen','fail_seen','shutdown_sent','forced_stop','status','deadline','waited','child_status','readable','_','chunk','recent','output','missing','stage','marker','stages','override','devices','sig','_status'] }
 for i in 1 .. ids.len { f.names['argument-' + i.str()] = ids[i] }
 result := execute(operation, ids, mut f) or { f.failed(err)!; return err }
 clean_since(f.start, [result])!
 return ah.Value(result)
}

fn execute(operation string, ids []string, mut f Frame) !string {
 return match operation {
  'child_exit_code' { exit_code(ids[1])! }
  'signal_child' { signal_child(ids[1], ids[2])!; literal(none_())! }
  'stop_child' { stop_child(ids[1], ids[2], mut f)!; literal(none_())! }
  'qemu_path' { qemu_path(ids[1], mut f)! }
  'check_host' { check_host(ids[1], mut f)! }
  'prepare' { prepare(ids[1], ids[2], mut f)! }
  'command' { command(ids[1], ids[2], ids[3], ids[4], ids[5], ids[6], mut f)! }
  'capture' { capture(ids[1], ids[2], ids[3], ids[4], ids[5], mut f)! }
  'report' { report(ids[1], ids[2], ids[3], mut f)! }
  'success' { success(ids[1])! }
  else { return error('unknown VirGL controller operation') }
 }
}
