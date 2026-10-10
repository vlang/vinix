// SPDX-License-Identifier: GPL-2.0-or-later
module soundcore

import androidhost as ah

fn binary(name string, left string, right ah.Value) !string { return call('operator.' + name, o(left), right)! }
fn calculated(name string, left string, right ah.Value) !string {
 result := binary(name, left, right) or { release([left])!; return err }
 release([left])!
 return result
}
fn assign(mapping string, key string, value string) ! { release([call('operator.setitem', o(mapping), v(ah.Value(key))!, o(value))!])! }
fn state_put(mut f Frame, state string, key string, value string) !string {
 assign(state, key, value)!
 if key == 'recent' { perform('_failure_cell', o(state), v(ah.Value(key))!, o(value))! }
 return f.named(key, value)!
}
fn path(parent string, component string) !string { return binary('truediv', parent, v(ah.Value(component))!)! }
fn path_text(parent string, component string) !string {
 target := global('str')!
 value := path(parent, component) or { release([target])!; return err }
 return invoke_owned(target, [o(value)], {}, [value])!
}
fn scope(ids []string, mut f Frame) !string {
 state := callback('literal', {'value': raw(ah.Value(map[string]ah.Value{}))})!.text()
 for key in f.order { assign(state, key, literal(none_())!)! }
 for i, name in ['root','guest_init','initramfs','state','wav','timeout','no_build'] {
  value := f.named(name, ids[i + 2])!
  assign(state, name, value)!
 }
 return state
}
fn initialize(state string, mut f Frame) !string {
 pid := get(state, 'pid')!
 master := get(state, 'master')!
 state_put(mut f, state, 'pid', pid)!
 state_put(mut f, state, 'master', master)!
 state_put(mut f, state, 'transcript', call('bytearray')!)!
 state_put(mut f, state, 'status', literal(none_())!)!
 state_put(mut f, state, 'shutdown_deadline', literal(none_())!)!
 timeout := get(state, 'timeout')!
 state_put(mut f, state, 'deadline', calculated('add', call('time.monotonic')!, o(timeout))!)!
 return literal(none_())!
}
fn retire(state string) !string {
 status := get(state, 'status')!
 if is_none(status)! { perform('stop_child', o(get(state, 'pid')!), o(get(state, 'master')!))! }
 perform('os.close', o(get(state, 'master')!))!
 return literal(none_())!
}
fn prepare(state string, mut f Frame) !string {
 root := f.named('root', get(state, 'root')!)!
 initramfs := f.named('initramfs', get(state, 'initramfs')!)!
 guest_init := f.named('guest_init', get(state, 'guest_init')!)!
 directory := f.named('state', get(state, 'state')!)!
 wav := f.named('wav', get(state, 'wav')!)!
 no_build := f.named('no_build', get(state, 'no_build')!)!
 environment := state_put(mut f, state, 'environment', temporary_method(global('os.environ')!, 'copy', [], {})!)!
 assign(environment, 'VINIX_INITRAMFS', call('str', o(initramfs))!)!
 for entry in [['VINIX_BOOT_DISK','boot.img'],['VINIX_EFIVARS','efivars.fd'],['VINIX_QEMU_PACKAGE_STORE','packages.tar'],['VINIX_QEMU_PERSIST_DISK','root.ext2']] {
  assign(environment, entry[0], path_text(directory, entry[1])!)!
 }
 assign(environment, 'VINIX_QEMU_PERSIST_SIZE_MB', literal(ah.Value('64'))!)!
 perform_method(environment, 'pop', [v(ah.Value('VINIX_QEMU_PERSIST'))!, v(none_())!], {})!
 assign(environment, 'VINIX_KEEP_TEMP_BOOT_DISK', literal(ah.Value('1'))!)!
 assign(environment, 'VINIX_QEMU_AUDIO', concatenate([literal(ah.Value('wav:'))!, formatted(wav, false)!])!)!
 target := member(environment, 'setdefault')!
 port := call('available_port')!
 release([invoke_owned(target, [v(ah.Value('VINIX_QEMU_PACKAGE_STORE_PORT'))!, o(port)], {}, [port])!])!
 if compared('ne', call('platform.system')!, v(ah.Value('Darwin'))!)! {
  perform_method(environment, 'setdefault', [v(ah.Value('USE_TCG'))!, v(ah.Value('1'))!], {})!
 }
 command := state_put(mut f, state, 'command', list_([o(path_text(root, 'scripts/run-aarch64.sh')!), v(ah.Value('--serial'))!, v(ah.Value('--mem=2048'))!, o(concatenate([literal(ah.Value('--guest-init='))!, formatted(guest_init, false)!])!)])!)!
 if truth(no_build)! { perform_method(command, 'insert', [v(ah.Value(1))!, v(ah.Value('--no-build'))!], {})! }
 return literal(none_())!
}
fn sliced(value string, start ah.Value, stop ah.Value) !string {
 bounds := invoke(resolve('_SLICE')!, [start, stop], {})!
 result := item(value, o(bounds)) or { release([bounds])!; return err }
 release([bounds])!
 return result
}
fn any_failures(state string) !string {
 target := global('any')!
 markers := global('FAIL_MARKERS') or { release([target])!; return err }
 cells := get(state, '_failure_cells') or { release([markers, target])!; return err }
 cell := get(cells, 'recent') or { release([cells, markers, target])!; return err }
 release([cells])!
 generated := call('_failure_candidates', o(cell), o(markers)) or { release([cell, markers, target])!; return err }
 release([cell, markers])!
 return invoke_owned(target, [o(generated)], {}, [generated])!
}
fn clear_error(state string, mut f Frame) ! {
 assign(state, 'error', literal(none_())!)!
 if id := f.names['error'] { f.names.delete('error'); release([id])! }
}
fn is_eio(value string) !bool {
 number := member(value, 'errno')!
 expected := global('errno.EIO') or { release([number])!; return err }
 result := binary('eq', number, o(expected)) or { release([number, expected])!; return err }
 release([number, expected])!
 return tested(result)!
}
fn capture(state string, mut f Frame) !string {
 transcript := f.named('transcript', get(state, 'transcript')!)!
 deadline := f.named('deadline', get(state, 'deadline')!)!
 pid := f.named('pid', get(state, 'pid')!)!
 master := f.named('master', get(state, 'master')!)!
 mut shutdown := f.named('shutdown_deadline', get(state, 'shutdown_deadline')!)!
 for compared('lt', call('time.monotonic')!, o(deadline))! {
  waiter := global('os.waitpid')!
  flags := global('os.WNOHANG')!
  values := pair(invoke_owned(waiter, [o(pid), o(flags)], {}, [flags])!)!
  waited := state_put(mut f, state, 'waited', values[0])!
  child_status := state_put(mut f, state, 'child_status', values[1])!
  if compare('eq', waited, o(pid))! { state_put(mut f, state, 'status', child_status)!; break }
  selector := global('select.select')!
  first := list_([o(master)])!
  second := list_([])!
  third := list_([])!
  ready := triple(invoke_owned(selector, [o(first), o(second), o(third), v(ah.Value(ah.Number{'0.25'}))!], {}, [third, second, first])!)!
  readable := state_put(mut f, state, 'readable', ready[0])!
  state_put(mut f, state, '_', ready[1])!
  state_put(mut f, state, '_', ready[2])!
  if truth(readable)! {
   chunk := call('os.read', o(master), v(ah.Value(65536))!) or {
    cause := err
    active(cause)!
    accepted := matches(cause, ['OSError']) or { active(none)!; return err }
    if !accepted { active(none)!; return cause }
    value := callback('error_object', {'error': detail(cause)})!.text()
    state_put(mut f, state, 'error', value)!
    retry := is_eio(value) or {
     active(none)!
     clear_error(state, mut f)!
     return err
    }
    active(none)!
    clear_error(state, mut f)!
    if retry { discard(cause)!; f.clean()!; continue }
    return cause
   }
   state_put(mut f, state, 'chunk', chunk)!
   perform_method(transcript, 'extend', [o(chunk)], {})!
   perform_temporary_method(global('sys.stdout.buffer')!, 'write', [o(chunk)], {})!
   perform_temporary_method(global('sys.stdout.buffer')!, 'flush', [], {})!
  }
  converter := global('bytes')!
  section := sliced(transcript, v(ah.Value(-65536))!, v(none_())!)!
  recent := state_put(mut f, state, 'recent', invoke_owned(converter, [o(section)], {}, [section])!)!
  marker := global('DONE_MARKER')!
  done_result := binary('contains', recent, o(marker)) or { release([marker])!; return err }
  release([marker])!
  done := tested(done_result)!
  finished := state_put(mut f, state, 'finished', if done { literal(ah.Value(true))! } else { any_failures(state)! })!
  if truth(finished)! && is_none(shutdown)! {
   perform('os.write', o(master), o(bytes_('0178')!))!
   shutdown = state_put(mut f, state, 'shutdown_deadline', calculated('add', call('time.monotonic')!, v(ah.Value(10))!)!)!
  }
  if !is_none(shutdown)! && compared('ge', call('time.monotonic')!, o(shutdown))! { break }
  f.clean()!
 }
 return literal(none_())!
}
fn report(state string, mut f Frame) !string {
 status := f.named('status', get(state, 'status')!)!
 transcript := f.named('transcript', get(state, 'transcript')!)!
 if !is_none(status)! && compared('ne', call('exit_code', o(status))!, v(ah.Value(0))!)! {
  printer := global('print')!
  code := call('exit_code', o(status))!
  line := concatenate([literal(ah.Value('ERROR: VM runner exited with '))!, formatted_temporary(code, false)!])!
  output := global('sys.stderr')!
  release([invoke_owned(printer, [o(line)], {'file': o(output)}, [output, line])!])!
 }
 return call('bytes', o(transcript))!
}
fn contains_marker(output string, marker string) !string { return literal(ah.Value(compare('contains', output, o(marker))!))! }

pub fn dispatch(row map[string]ah.Value) !ah.Value {
 ids := ah.field(row, 'arguments').items().map(it.text())
 operation := ah.field(row, 'operation').text()
 current_builtins = ids[1]
 order := ['root','guest_init','initramfs','state','wav','timeout','no_build','environment','command','pid','master','transcript','status','shutdown_deadline','deadline','waited','child_status','readable','_','chunk','error','finished','recent']
 mut f := Frame{start: checkpoint()!, pins: ids[0], order: order}
 for i in 1 .. ids.len { f.names['argument-' + i.str()] = ids[i] }
 if operation in ['prepare','initialize','capture','retire','report'] {
  for key in order { found := compare('contains', ids[2], v(ah.Value(key))!)!; if found { f.named(key, get(ids[2], key)!)! } }
 }
 result := execute(operation, ids, mut f) or { f.failed(err)!; return err }
 for key in f.order { if id := f.names[key] { if id != result { release([id])! } } }
 clean_since(f.start, [result])!
 return ah.Value(result)
}
fn execute(operation string, ids []string, mut f Frame) !string {
 return match operation {
  'scope' { scope(ids, mut f)! }
  'prepare' { prepare(ids[2], mut f)! }
  'initialize' { initialize(ids[2], mut f)! }
  'retire' { retire(ids[2])! }
  'capture' { capture(ids[2], mut f)! }
  'report' { report(ids[2], mut f)! }
  'contains_marker' { contains_marker(ids[2], ids[3])! }
  else { return error('Unknown sound supervisor operation') }
 }
}
