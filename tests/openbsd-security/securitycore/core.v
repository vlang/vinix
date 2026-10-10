// SPDX-License-Identifier: GPL-2.0-or-later
module securitycore

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
fn length(value string) !string { return call('len', o(value))! }
fn assign(mapping string, key string, value string) ! { release([call('operator.setitem', o(mapping), v(ah.Value(key))!, o(value))!])! }
fn state_put(mut f Frame, state string, key string, value string) !string {
 id := f.named(key, value)!
 assign(state, key, id)!
 return id
}
fn append(list string, value string) ! { perform_method(list, 'append', [o(value)], {})! }
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
fn reaped(pid string, seconds string, mut f Frame) !string {
 deadline := f.named('deadline', calculated('add', call('time.monotonic')!, o(seconds))!)!
 f.clean()!
 for {
  target := global('os.waitpid')!
  flags := global('os.WNOHANG') or { release([target])!; return err }
  result := invoke_owned(target, [o(pid), o(flags)], {}, [flags]) or {
   cause := err
   active(cause)!
   if !matches(cause, ['ChildProcessError'])! { active(none)!; return cause }
   active(none)!
   discard(cause)!
   return literal(ah.Value(true))!
  }
  values := pair(result)!
  waited := f.named('waited', values[0])!
  f.named('_', values[1])!
  if compare('eq', waited, o(pid))! { return literal(ah.Value(true))! }
  if compared('ge', call('time.monotonic')!, o(deadline))! { return literal(ah.Value(false))! }
  perform('time.sleep', v(ah.Value(ah.Number{'0.05'}))!)!
  f.clean()!
 }
 return literal(ah.Value(false))!
}
fn stop(pid string, master string, mut f Frame) !string {
 perform('os.write', o(master), o(bytes_('0178')!)) or {
  cause := err
  active(cause)!
  if !matches(cause, ['OSError'])! { active(none)!; return cause }
  active(none)!
  discard(cause)!
 }
 if tested(call('reaped', o(pid), v(ah.Value(5))!)!)! { return literal(none_())! }
 // The original tuple captures both signals before the first loop body.
 terminate := global('signal.SIGTERM')!
 kill := global('signal.SIGKILL') or { release([terminate])!; return err }
 signals := tuple_([o(terminate), o(kill)])!
 release([kill, terminate])!
 iterator := call('_ITER', o(signals))!
 release([signals])!
 f.names['iterator'] = iterator
 for {
  row := callback('next', {'owner': ah.Value(iterator)})!.object()
  if ah.field(row, 'done') as bool { break }
  sig := f.named('sig', ah.field(row, 'value').text())!
  perform('os.killpg', o(pid), o(sig)) or {
   cause := err
   active(cause)!
   if !matches(cause, ['ProcessLookupError', 'PermissionError'])! { active(none)!; return cause }
   active(none)!
   discard(cause)!
  }
  if tested(call('reaped', o(pid), v(ah.Value(3))!)!)! {
   release([iterator])!
   f.names.delete('iterator')
   return literal(none_())!
  }
  f.clean()!
 }
 release([iterator])!
 f.names.delete('iterator')
 return literal(none_())!
}
fn formatted_field(receiver string, name string) !string {
 value := member(receiver, name)!
 return formatted_temporary(value, false)!
}
fn field_text(receiver string, name string) !string {
 converter := global('str')!
 value := member(receiver, name) or { release([converter])!; return err }
 return invoke_owned(converter, [o(value)], {}, [value])!
}
fn path_text(parent string, component string) !string {
 converter := global('str')!
 path := binary('truediv', parent, v(ah.Value(component))!) or { release([converter])!; return err }
 return invoke_owned(converter, [o(path)], {}, [path])!
}
fn environment_put(env string, name string, value string) ! {
 assign(env, name, value) or { release([value])!; return err }
 release([value])!
}
fn command_for(arguments string, root string, mut f Frame) !string {
 environment := f.named('environment', temporary_method(global('os.environ')!, 'copy', [], {})!)!
 if compared('eq', member(arguments, 'arch')!, v(ah.Value('aarch64'))!)! {
  state := f.named('state', member(arguments, 'state_dir')!)!
  environment_put(environment, 'VINIX_INITRAMFS', field_text(arguments, 'initramfs')!)!
  environment_put(environment, 'VINIX_BOOT_DISK', path_text(state, 'boot.img')!)!
  environment_put(environment, 'VINIX_EFIVARS', path_text(state, 'efivars.fd')!)!
  environment_put(environment, 'VINIX_QEMU_PACKAGE_STORE', path_text(state, 'packages.tar')!)!
  environment_put(environment, 'VINIX_QEMU_PERSIST_DISK', path_text(state, 'root.ext2')!)!
  environment_put(environment, 'VINIX_QEMU_PERSIST_SIZE_MB', literal(ah.Value('64'))!)!
  perform_method(environment, 'pop', [v(ah.Value('VINIX_QEMU_PERSIST'))!, v(none_())!], {})!
  filter_dump := f.named('dump', concatenate([literal(ah.Value('-object filter-dump,id=vinixdump,netdev=net0,file='))!, formatted_field(arguments, 'capture')!])!)!
  separator := literal(ah.Value(' '))!
  joiner := member(separator, 'join')!
  release([separator])!
  filter_ := global('filter')!
  previous := method(environment, 'get', [v(ah.Value('VINIX_QEMU_EXTRA'))!], {})!
  values := tuple_([o(previous), o(filter_dump)])!
  release([previous])!
  filtered := invoke_owned(filter_, [v(none_())!, o(values)], {}, [values])!
  joined := invoke_owned(joiner, [o(filtered)], {}, [filtered])!
  environment_put(environment, 'VINIX_QEMU_EXTRA', joined)!
  setter := member(environment, 'setdefault')!
  port := call('available_port')!
  release([invoke_owned(setter, [v(ah.Value('VINIX_QEMU_PACKAGE_STORE_PORT'))!, o(port)], {}, [port])!])!
  if compared('ne', call('platform.system')!, v(ah.Value('Darwin'))!)! { perform_method(environment, 'setdefault', [v(ah.Value('USE_TCG'))!, v(ah.Value('1'))!], {})! }
  script := path_text(root, 'scripts/run-aarch64.sh')!
  init := concatenate([literal(ah.Value('--guest-init='))!, formatted_field(arguments, 'init')!])!
  values_ := [o(script), v(ah.Value('--no-build'))!, v(ah.Value('--serial'))!, v(ah.Value('--mem=2048'))!, o(init)]
  command := list_(values_)!
  return tuple_([o(command), o(environment)])!
 }
 firmware := f.named('firmware', member(arguments, 'firmware')!)!
 mut command := []ah.Value{}
 command << o(member(arguments, 'qemu')!)
 command << v(ah.Value('-machine'))!
 command << v(ah.Value('q35,smm=off'))!
 command << v(ah.Value('-accel'))!
 acceleration := temporary_method(global('os.environ')!, 'get', [v(ah.Value('VINIX_QEMU_ACCEL'))!, v(ah.Value('tcg'))!], {})!
 command << o(acceleration)
 for value in ['-cpu','max','-m','1024','-smp','2','-drive'] { command << v(ah.Value(value))! }
 command << o(concatenate([literal(ah.Value('if=pflash,format=raw,unit=0,readonly=on,file='))!, formatted(firmware, false)!])!)
 command << v(ah.Value('-cdrom'))!
 command << o(field_text(arguments, 'iso')!)
 for value in ['-netdev','user,id=net0','-device','e1000,netdev=net0,mac=52:54:00:12:34:56','-object'] { command << v(ah.Value(value))! }
 command << o(concatenate([literal(ah.Value('filter-dump,id=vinixdump,netdev=net0,file='))!, formatted_field(arguments, 'capture')!])!)
 for value in ['-display','none','-monitor','none','-serial','stdio','-no-reboot'] { command << v(ah.Value(value))! }
 return tuple_([o(list_(command)!), o(environment)])!
}
fn print_line(value string, error_ bool) ! {
 target := global('print')!
 mut consumed := []string{}
 mut options := map[string]ah.Value{}
 if error_ { output := global('sys.stderr')!; options['file'] = o(output); consumed << output }
 release([invoke_owned(target, [o(value)], options, consumed)!])!
}
fn boot_message(arguments string) !string {
 target := global('print')!
 parts := [literal(ah.Value('==> Booting the '))!, formatted_field(arguments, 'arch')!, literal(ah.Value(' '))!, formatted_temporary(global('TEST_LABEL')!, false)!, literal(ah.Value(' test'))!]
 release([invoke_owned(target, [o(concatenate(parts)!)], {}, [])!])!
 return literal(none_())!
}
fn capture(state string, pid string, master string, mut f Frame) !string {
 transcript := f.named('transcript', get(state, 'transcript')!)!
 deadline := f.named('deadline', get(state, 'deadline')!)!
 mut finished := f.named('finished_at', get(state, 'finished_at')!)!
 for compared('lt', call('time.monotonic')!, o(deadline))! {
  if tested(call('reaped', o(pid), v(ah.Value(0))!)!)! { break }
  selector := global('select.select')!
  readable_args := list_([o(master)])!
  empty_write := list_([])!
  empty_except := list_([])!
  returned := invoke_owned(selector, [o(readable_args), o(empty_write), o(empty_except), v(ah.Value(ah.Number{'0.25'}))!], {}, [empty_except, empty_write, readable_args])!
  values := triple(returned)!
  readable := state_put(mut f, state, 'readable', values[0])!
  state_put(mut f, state, '_', values[1])!
  state_put(mut f, state, '_', values[2])!
  if truth(readable)! {
   chunk := call('os.read', o(master), v(ah.Value(65536))!) or {
    cause := err
    active(cause)!
    if !matches(cause, ['OSError'])! { active(none)!; return cause }
    field := callback('error_attribute', {'error': detail(cause), 'name': ah.Value('errno')})!.text()
    interrupted := compare('eq', field, o(global('errno.EIO')!))!
    release([field])!
    active(none)!
    if interrupted { discard(cause)!; continue }
    return cause
   }
   state_put(mut f, state, 'chunk', chunk)!
   perform_method(transcript, 'extend', [o(chunk)], {})!
   perform_temporary_method(global('sys.stdout.buffer')!, 'write', [o(chunk)], {})!
   perform_temporary_method(global('sys.stdout.buffer')!, 'flush', [], {})!
  }
  converter := global('bytes')!
  section := sliced(transcript, v(ah.Value(-131072))!, v(none_())!)!
  recent := state_put(mut f, state, 'recent', invoke_owned(converter, [o(section)], {}, [section])!)!
  if is_none(finished)! {
   if compare('contains', recent, o(global('PASS_MARKER')!))! || any_failures(recent)! {
    finished = state_put(mut f, state, 'finished_at', call('time.monotonic')!)!
   }
  }
  if !is_none(finished)! && compared('gt', calculated('sub', call('time.monotonic')!, o(finished))!, v(ah.Value(2))!)! { break }
  f.clean()!
 }
 return literal(none_())!
}


fn comparison_owned(name string, left string, right string, retire []string) !bool {
 result := binary(name, left, o(right)) or { release(retire)!; return err }
 release(retire)!
 return tested(result)!
}
fn unpacked(format string, data string) !string {
 target := global('struct.unpack')!
 return invoke_owned(target, [v(ah.Value(format))!, o(data)], {}, [data])!
}
fn unpack_slice(format string, source string, start ah.Value, stop ah.Value) !string {
 target := global('struct.unpack')!
 section := sliced(source, start, stop) or { release([target])!; return err }
 return invoke_owned(target, [v(ah.Value(format))!, o(section)], {}, [section])!
}
fn unpack_first(format string, source string, start ah.Value, stop ah.Value) !string {
 tuple := unpack_slice(format, source, start, stop)!
 result := item(tuple, v(ah.Value(0))!) or { release([tuple])!; return err }
 release([tuple])!
 return result
}
fn capture_frames(path string, mut f Frame) !string {
 f.named('path', path)!
 data := f.named('data', method(path, 'read_bytes', [], {})!)!
 if compared('lt', length(data)!, v(ah.Value(24))!)! { return list_([])! }
 magic := f.named('magic', unpack_first('<I', data, v(none_())!, v(ah.Value(4))!)!)!
 choices := tuple_([v(ah.Value(ah.Number{'2712847316'}))!, v(ah.Value(ah.Number{'2712812621'}))!])!
 little := compare('contains', choices, o(magic)) or { release([choices])!; return err }
 release([choices])!
 order := f.named('order', literal(ah.Value(if little { '<' } else { '>' }))!)!
 frames := f.named('frames', list_([])!)!
 mut at := f.named('at', literal(ah.Value(24))!)!
 f.clean()!
 for {
  end := binary('add', at, v(ah.Value(16))!)!
  limit := length(data) or { release([end])!; return err }
  if !comparison_owned('le', end, limit, [end, limit])! { break }
  target := global('struct.unpack')!
  format := binary('add', order, v(ah.Value('IIII'))!)!
  stop := binary('add', at, v(ah.Value(16))!)!
  section := sliced(data, o(at), o(stop))!
  release([stop])!
  returned := invoke_owned(target, [o(format), o(section)], {}, [section, format])!
  fields := invoke(resolve('_quad')!, [o(returned)], {})!
  release([returned])!
  f.named('_', item(fields, v(ah.Value(0))!)!)!
  f.named('_', item(fields, v(ah.Value(1))!)!)!
  included := f.named('included', item(fields, v(ah.Value(2))!)!)!
  f.named('_', item(fields, v(ah.Value(3))!)!)!
  release([fields])!
  appender := member(frames, 'append')!
  begin := binary('add', at, v(ah.Value(16))!)!
  end_first := binary('add', at, v(ah.Value(16))!)!
  end_frame := calculated('add', end_first, o(included))!
  frame := sliced(data, o(begin), o(end_frame))!
  release([end_frame, begin])!
  release([invoke_owned(appender, [o(frame)], {}, [frame])!])!
  increment := binary('add', literal(ah.Value(16))!, o(included))!
  at = f.named('at', binary('iadd', at, o(increment))!)!
  release([increment])!
  f.clean()!
 }
 return frames
}
fn pair_iterator(values string) !string {
 factory := global('zip')!
 rest := sliced(values, v(ah.Value(1))!, v(none_())!) or { release([factory])!; return err }
 return invoke_owned(factory, [o(values), o(rest)], {}, [rest])!
}
fn close_pairs(values string, modulus string, within string) !string {
 target := global('sum')!
 iterator := pair_iterator(values) or { release([target])!; return err }
 generated := call('_close_candidates', o(iterator), o(modulus), o(within)) or { release([iterator, target])!; return err }
 release([iterator])!
 return invoke_owned(target, [o(generated)], {}, [generated])!
}
fn close_candidate(a string, b string, modulus string, within string) !string {
 difference := binary('sub', b, o(a))!
 distance := calculated('mod', difference, o(modulus))!
 if !compare('lt', literal(ah.Value(0))!, o(distance))! { release([distance])!; return literal(ah.Value(false))! }
 return literal(ah.Value(comparison_owned('le', distance, within, [distance])!))!
}
fn near_candidate(a string, b string) !string {
 target := global('min')!
 first := calculated('mod', binary('sub', b, o(a))!, v(ah.Value(ah.Number{'4294967296'}))!)!
 second := calculated('mod', binary('sub', a, o(b))!, v(ah.Value(ah.Number{'4294967296'}))!)!
 minimum := invoke_owned(target, [o(first), o(second)], {}, [second, first])!
 return literal(ah.Value(compared('lt', minimum, v(ah.Value(16777216))!)!))!
}
fn any_failures(recent string) !bool {
 target := global('any')!
 markers := global('FAIL_MARKERS') or { release([target])!; return err }
 generated := call('_failure_candidates', o(recent), o(markers)) or { release([markers, target])!; return err }
 release([markers])!
 return tested(invoke_owned(target, [o(generated)], {}, [generated])!)!
}
fn missing_marker(output string, marker string) !string { return literal(ah.Value(compared('ne', method(output, 'count', [o(marker)], {})!, v(ah.Value(1))!)!))! }
fn contains_marker(output string, marker string) !string { return literal(ah.Value(compare('contains', output, o(marker))!))! }
fn ephemeral(port string) !string { return literal(ah.Value(compare('lt', port, v(ah.Value(49152))!)!))! }
fn near_pairs(values string) !string {
 target := global('sum')!
 iterator := pair_iterator(values) or { release([target])!; return err }
 generated := call('_near_candidates', o(iterator)) or { release([iterator, target])!; return err }
 release([iterator])!
 return invoke_owned(target, [o(generated)], {}, [generated])!
}
fn report(state string, arguments string, mut f Frame) !string {
 transcript := f.named('transcript', get(state, 'transcript')!)!
 finished := f.named('finished_at', get(state, 'finished_at')!)!
 output := f.named('output', call('bytes', o(transcript))!)!
 markers := call('_feature_markers')!
 missing := f.named('missing', call('_missing', o(output), o(markers))!)!
 release([markers])!
 if compared('eq', member(arguments, 'arch')!, v(ah.Value('aarch64'))!)! {
  marker := global('REPORT_MARKER')!
  absent := !comparison_owned('contains', output, marker, [marker])!
  if absent {
   appender := member(missing, 'append')!
   decoded := temporary_method(global('REPORT_MARKER')!, 'decode', [], {})!
   release([invoke_owned(appender, [o(decoded)], {}, [decoded])!])!
  }
 }
 markers2 := global('FAIL_MARKERS')!
 failures := f.named('failures', call('_failures', o(output), o(markers2))!)!
 release([markers2])!
 if is_none(finished)! { perform_method(failures, 'append', [v(ah.Value('the test did not finish before the timeout'))!], {})! }
 if compare('contains', output, o(bytes_('4f50454e42534420534543555249545920574952453a2073656e74')!))! {
  extender := member(failures, 'extend')!
  target := global('check_capture')!
  path := member(arguments, 'capture')!
  problems := invoke_owned(target, [o(path)], {}, [path])!
  release([invoke_owned(extender, [o(problems)], {}, [problems])!])!
 }
 for source in [missing, failures] {
  iterator := invoke(resolve('_ITER')!, [o(source)], {})!
  f.names['iterator'] = iterator
  for {
   row := callback('next', {'owner': ah.Value(iterator)})!.object()
   if ah.field(row, 'done') as bool { break }
   item_ := f.named('item', ah.field(row, 'value').text())!
   target := global('print')!
   line := concatenate([literal(ah.Value(if source == missing { 'ERROR: missing expected result: ' } else { 'ERROR: observed failure: ' }))!, formatted(item_, false)!])!
   output_ := global('sys.stderr')!
   release([invoke_owned(target, [o(line)], {'file': o(output_)}, [output_, line])!])!
   f.clean()!
  }
  release([iterator])!
  f.names.delete('iterator')
 }
 if truth(missing)! || truth(failures)! { return literal(ah.Value(1))! }
 target := global('print')!
 line := concatenate([literal(ah.Value('==> '))!, formatted_field(arguments, 'arch')!, literal(ah.Value(' '))!, formatted_temporary(global('TEST_LABEL')!, false)!, literal(ah.Value(' test passed'))!])!
 release([invoke_owned(target, [o(line)], {}, [line])!])!
 return literal(ah.Value(0))!
}

fn fcount(value string) !string { return formatted_temporary(length(value)!, false)! }
fn fsubtract_count(value string) !string { return formatted_temporary(calculated('sub', length(value)!, v(ah.Value(1))!)!, false)! }
fn check_capture(path string, mut f Frame) !string {
 f.named('path', path)!
 if !tested(method(path, 'exists', [], {})!)! { return list_([v(ah.Value('QEMU wrote no packet capture'))!])! }
 ids := f.named('ids', list_([])!)!
 syns := f.named('syns', call('_dict')!)!
 datagram_ports := f.named('datagram_ports', list_([])!)!
 iterable := call('capture_frames', o(path))!
 iterator := invoke(resolve('_ITER')!, [o(iterable)], {})!
 release([iterable])!
 f.names['iterator'] = iterator
 f.clean()!
 for {
  row := callback('next', {'owner': ah.Value(iterator)})!.object()
  if ah.field(row, 'done') as bool { break }
  frame := f.named('frame', ah.field(row, 'value').text())!
  if compared('lt', length(frame)!, v(ah.Value(34))!)! { f.clean()!; continue }
  source_mac := sliced(frame, v(ah.Value(6))!, v(ah.Value(12))!)!
  guest_mac := global('GUEST_MAC')!
  if comparison_owned('ne', source_mac, guest_mac, [source_mac, guest_mac])! { f.clean()!; continue }
  ethernet := sliced(frame, v(ah.Value(12))!, v(ah.Value(14))!)!
  if compared('ne', ethernet, o(bytes_('0800')!))! { f.clean()!; continue }
  ip := f.named('ip', sliced(frame, v(ah.Value(14))!, v(none_())!)!)!
  first := item(ip, v(ah.Value(0))!)!
  masked := calculated('and_', first, v(ah.Value(15))!)!
  header := f.named('header', calculated('mul', masked, v(ah.Value(4))!)!)!
  appender := member(ids, 'append')!
  identification := unpack_first('>H', ip, v(ah.Value(4))!, v(ah.Value(6))!)!
  release([invoke_owned(appender, [o(identification)], {}, [identification])!])!
  transport := f.named('transport', sliced(ip, o(header), v(none_())!)!)!
  address := sliced(ip, v(ah.Value(16))!, v(ah.Value(20))!)!
  factory := global('bytes')!
  input_ := list_([v(ah.Value(10))!, v(ah.Value(0))!, v(ah.Value(2))!, v(ah.Value(2))!])!
  host := invoke_owned(factory, [o(input_)], {}, [input_])!
  if comparison_owned('ne', address, host, [address, host])! || compared('lt', length(transport)!, v(ah.Value(8))!)! { f.clean()!; continue }
  ports := pair(unpack_slice('>HH', transport, v(none_())!, v(ah.Value(4))!)!)!
  source := f.named('source', ports[0])!
  destination := f.named('destination', ports[1])!
  if compare('ne', destination, v(ah.Value(9))!)! { f.clean()!; continue }
  tcp := compared('eq', item(ip, v(ah.Value(9))!)!, v(ah.Value(6))!)!
  mut syn := false
  if tcp && compared('ge', length(transport)!, v(ah.Value(14))!)! {
   flags := calculated('and_', item(transport, v(ah.Value(13))!)!, v(ah.Value(18))!)!
   syn = compared('eq', flags, v(ah.Value(2))!)!
  }
  if syn {
   target := member(syns, 'setdefault')!
   sequence := unpack_first('>I', transport, v(ah.Value(4))!, v(ah.Value(8))!)!
   release([invoke_owned(target, [o(source), o(sequence)], {}, [sequence])!])!
  } else if compared('eq', item(ip, v(ah.Value(9))!)!, v(ah.Value(17))!)! { append(datagram_ports, source)! }
  f.clean()!
 }
 release([iterator])!
 f.names.delete('iterator')
 problems := f.named('problems', list_([])!)!
 packet_count := length(ids)!
 rounds := global('WIRE_ROUNDS')!
 threshold := calculated('mul', literal(ah.Value(2))!, o(rounds))!
 release([rounds])!
 if comparison_owned('lt', packet_count, threshold, [packet_count, threshold])! {
  return list_([o(concatenate([literal(ah.Value('the capture has only '))!, fcount(ids)!, literal(ah.Value(' packets from the guest'))!])!)])!
 }
 sequential := f.named('sequential', call('close_pairs', o(ids), v(ah.Value(65536))!, v(ah.Value(64))!)!)!
 target := global('max')!
 fraction := calculated('floordiv', length(ids)!, v(ah.Value(20))!)!
 maximum := invoke_owned(target, [v(ah.Value(2))!, o(fraction)], {}, [fraction])!
 if comparison_owned('gt', sequential, maximum, [maximum])! {
  appender := member(problems, 'append')!
  line := concatenate([formatted(sequential, false)!, literal(ah.Value(' of '))!, fsubtract_count(ids)!, literal(ah.Value(' IP IDs follow the one before'))!])!
  release([invoke_owned(appender, [o(line)], {}, [line])!])!
 }
 left := length(syns)!
 threshold2 := calculated('floordiv', global('WIRE_ROUNDS')!, v(ah.Value(2))!)!
 if comparison_owned('lt', left, threshold2, [left, threshold2])! {
  appender := member(problems, 'append')!
  line := concatenate([literal(ah.Value('only '))!, fcount(syns)!, literal(ah.Value(' SYNs reached the capture'))!])!
  release([invoke_owned(appender, [o(line)], {}, [line])!])!
 }
 factory := global('list')!
 values := method(syns, 'values', [], {})!
 isns := f.named('isns', invoke_owned(factory, [o(values)], {}, [values])!)!
 near := f.named('near', near_pairs(isns)!)!
 if compare('gt', near, v(ah.Value(1))!)! {
  appender := member(problems, 'append')!
  line := concatenate([formatted(near, false)!, literal(ah.Value(' of '))!, fsubtract_count(isns)!, literal(ah.Value(' initial sequence numbers are near the last'))!])!
  release([invoke_owned(appender, [o(line)], {}, [line])!])!
 }
 tcp_ports := tuple_([v(ah.Value('TCP'))!, o(call('list', o(syns))!)])!
 udp_ports := tuple_([v(ah.Value('UDP'))!, o(datagram_ports)])!
 entries := tuple_([o(tcp_ports), o(udp_ports)])!
 release([udp_ports, tcp_ports])!
 iterator2 := invoke(resolve('_ITER')!, [o(entries)], {})!
 release([entries])!
 f.names['iterator'] = iterator2
 for {
  row := callback('next', {'owner': ah.Value(iterator2)})!.object()
  if ah.field(row, 'done') as bool { break }
  values2 := pair(ah.field(row, 'value').text())!
  kind := f.named('kind', values2[0])!
  ports := f.named('ports', values2[1])!
  any_ := global('any')!
  generator := call('_ephemeral', o(ports))!
  if tested(invoke_owned(any_, [o(generator)], {}, [generator])!)! {
   appender := member(problems, 'append')!
   line := concatenate([literal(ah.Value('a '))!, formatted(kind, false)!, literal(ah.Value(' source port is outside the ephemeral range: '))!, formatted(ports, false)!])!
   release([invoke_owned(appender, [o(line)], {}, [line])!])!
  }
  if compared('gt', call('close_pairs', o(ports), v(ah.Value(65536))!, v(ah.Value(1))!)!, v(ah.Value(2))!)! {
   appender := member(problems, 'append')!
   line := concatenate([formatted(kind, false)!, literal(ah.Value(' source ports are handed out in sequence: '))!, formatted(ports, false)!])!
   release([invoke_owned(appender, [o(line)], {}, [line])!])!
  }
  f.clean()!
 }
 release([iterator2])!
 f.names.delete('iterator')
 printer := global('print')!
 line := concatenate([literal(ah.Value('==> capture: '))!, fcount(ids)!, literal(ah.Value(' guest packets, '))!, formatted(sequential, false)!, literal(ah.Value(' IDs in sequence, '))!, fcount(isns)!, literal(ah.Value(' SYNs, '))!, formatted(near, false)!, literal(ah.Value(' close ISNs, '))!, fcount(datagram_ports)!, literal(ah.Value(' datagrams'))!])!
 release([invoke_owned(printer, [o(line)], {}, [line])!])!
 return problems
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
 ids := ah.field(row, 'arguments').items().map(it.text())
 operation := ah.field(row, 'operation').text()
 current_builtins = ids[1]
 local_order := match operation {
  'capture_frames' { ['path','data','magic','order','frames','at','_','included'] }
  'close_pairs' { ['values','modulus','within'] }
  'check_capture' { ['path','ids','syns','datagram_ports','frame','ip','header','transport','source','destination','problems','sequential','isns','near','kind','ports'] }
  'available_port' { ['listener'] }
  'reaped' { ['pid','seconds','deadline','waited','_'] }
  'stop' { ['pid','master','sig'] }
  'command_for' { ['arguments','root','environment','state','dump','firmware'] }
  else { ['transcript','deadline','finished_at','readable','_','chunk','recent','output','missing','failures','item'] }
 }
 mut f := Frame{start: checkpoint()!, pins: ids[0], order: local_order}
 for i in 1 .. ids.len { f.names['argument-' + i.str()] = ids[i] }
 keys := match operation {
  'capture_frames', 'check_capture' { ['path'] }
  'close_pairs' { ['values','modulus','within'] }
  'command_for' { ['arguments','root'] }
  'reaped' { ['pid','seconds'] }
  'stop' { ['pid','master'] }
  'boot_message' { ['arguments'] }
  else { []string{} }
 }
 for i, key in keys { f.named(key, ids[i+2])! }
 result := execute(operation, ids, mut f) or { f.failed(err)!; return err }
 for key in f.order { if id := f.names[key] { if id != result { release([id])! } } }
 clean_since(f.start, [result])!
 return ah.Value(result)
}
fn execute(operation string, ids []string, mut f Frame) !string {
 return match operation {
  'check_capture' { check_capture(ids[2], mut f)! }
  'capture_frames' { capture_frames(ids[2], mut f)! }
  'close_pairs' { close_pairs(ids[2], ids[3], ids[4])! }
  'close_candidate' { close_candidate(ids[2], ids[3], ids[4], ids[5])! }
  'near_candidate' { near_candidate(ids[2], ids[3])! }
  'contains_marker' { contains_marker(ids[2], ids[3])! }
  'missing_marker' { missing_marker(ids[2], ids[3])! }
  'ephemeral' { ephemeral(ids[2])! }
  'report' { report(ids[2], ids[3], mut f)! }
  'available_port' { available_port(mut f)! }
  'reaped' { reaped(ids[2], ids[3], mut f)! }
  'stop' { stop(ids[2], ids[3], mut f)! }
  'command_for' { command_for(ids[2], ids[3], mut f)! }
  'boot_message' { boot_message(ids[2])! }
  'capture' { capture(ids[2], ids[3], ids[4], mut f)! }
  else { return error('OpenBSD security operation remains to be implemented') }
 }
}
