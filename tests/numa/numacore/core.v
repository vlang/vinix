// SPDX-License-Identifier: GPL-2.0-or-later
module numacore

import androidhost as ah

fn binary(name string, left string, right ah.Value) !string { return call('operator.'+name, o(left), right)! }
fn calculated(name string, left string, right ah.Value) !string {
 result := binary(name,left,right) or { release([left])!; return err }
 release([left])!
 return result
}
fn assign(state string, key string, value string) ! { release([call('operator.setitem', o(state), v(ah.Value(key))!, o(value))!])! }
fn state_put(mut f Frame, state string, key string, value string) !string {
 id := f.named(key,value)!
 assign(state,key,id)!
 return id
}
fn load_state(mut f Frame, state string, keys []string) ! {
 for key in keys { f.named(key,get(state,key)!)! }
}
fn path_text(parent string, name string) !string {
 converter := global('str')!
 path := binary('truediv',parent,v(ah.Value(name))!) or { release([converter])!; return err }
 return invoke_owned(converter,[o(path)],{},[path])!
}
fn put(env string, name string, value string) ! {
 assign(env,name,value) or { release([value])!; return err }
 release([value])!
}
fn print_line(value string, error_ bool) ! {
 target := global('print')!
 mut consumed := []string{}
 mut options := map[string]ah.Value{}
 if error_ { output := global('sys.stderr')!; options['file']=o(output); consumed<<output }
 release([invoke_owned(target,[o(value)],options,consumed)!])!
}
fn prepare(state string, mut f Frame) !string {
 load_state(mut f,state,['root','guest_init','initramfs','state_dir','timeout'])!
 root := f.names['root']; init := f.names['guest_init']; archive:=f.names['initramfs']; directory:=f.names['state_dir']
 env := state_put(mut f,state,'environment',temporary_method(global('os.environ')!,'copy',[],{})!)!
 put(env,'VINIX_INITRAMFS',call('str',o(archive))!)!
 for pair_ in [['VINIX_BOOT_DISK','boot.img'],['VINIX_EFIVARS','efivars.fd'],['VINIX_QEMU_PACKAGE_STORE','packages.tar'],['VINIX_QEMU_PERSIST_DISK','root.ext2']] {
  put(env,pair_[0],path_text(directory,pair_[1])!)!
 }
 put(env,'VINIX_QEMU_PERSIST_SIZE_MB',literal(ah.Value('64'))!)!
 perform_method(env,'pop',[v(ah.Value('VINIX_QEMU_PERSIST'))!,v(none_())!],{})!
 put(env,'VINIX_KEEP_TEMP_BOOT_DISK',literal(ah.Value('1'))!)!
 setter := member(env,'setdefault')!
 port := call('available_port') or { release([setter])!; return err }
 release([invoke_owned(setter,[v(ah.Value('VINIX_QEMU_PACKAGE_STORE_PORT'))!,o(port)],{},[port])!])!
 extra := state_put(mut f,state,'extra',method(env,'get',[v(ah.Value('VINIX_QEMU_EXTRA'))!,v(ah.Value(''))!],{})!)!
 formatted_extra := formatted(extra,false)!
 topology := global('NUMA_TOPOLOGY') or { release([formatted_extra])!; return err }
 formatted_topology := formatted_temporary(topology,false) or { release([formatted_extra])!; return err }
 space := literal(ah.Value(' ')) or { release([formatted_topology,formatted_extra])!; return err }
 assembled := concatenate([formatted_extra,space,formatted_topology])!
 put(env,'VINIX_QEMU_EXTRA',temporary_method(assembled,'strip',[],{})!)!
 if compared('ne',call('platform.system')!,v(ah.Value('Darwin'))!)! { perform_method(env,'setdefault',[v(ah.Value('USE_TCG'))!,v(ah.Value('1'))!],{})! }
 script:=path_text(root,'scripts/run-aarch64.sh')!
 memory:=global('GUEST_MEMORY_MB')!
 memarg:=concatenate([literal(ah.Value('--mem='))!,formatted_temporary(memory,false)!])!
 initarg:=concatenate([literal(ah.Value('--guest-init='))!,formatted(init,false)!])!
 command:=state_put(mut f,state,'command',list_([o(script),v(ah.Value('--serial'))!,o(memarg),o(initarg)])!)!
 release([initarg,memarg,script])!
 environ:=global('os.environ')!
 no_build:=temporary_method(environ,'get',[v(ah.Value('VINIX_QEMU_NUMA_NO_BUILD'))!],{})!
 if compared('eq',no_build,v(ah.Value('1'))!)! { perform_method(command,'insert',[v(ah.Value(1))!,v(ah.Value('--no-build'))!],{})! }
 line:=literal(ah.Value('==> Starting AArch64 QEMU boot with two NUMA nodes'))!
 print_line(line,false)!
 release([line])!
 return tuple_([o(env),o(command)])!
}
fn exit_code(status string) !string {
 if tested(call('os.WIFEXITED',o(status))!)! { return call('os.WEXITSTATUS',o(status))! }
 if tested(call('os.WIFSIGNALED',o(status))!)! {
  left:=literal(ah.Value(128))!
  right:=call('os.WTERMSIG',o(status)) or { release([left])!; return err }
  result:=binary('add',left,o(right)) or { release([left,right])!; return err }
  release([left,right])!
  return result
 }
 return literal(ah.Value(1))!
}
fn handled(cause IError, names []string) !bool {
 active(cause)!
 result:=matches(cause,names) or { active(none)!; return err }
 active(none)!
 if result { discard(cause)! }
 return result
}
fn wait(pid string) ![]string {
 target:=global('os.waitpid')!
 flags:=global('os.WNOHANG') or { release([target])!; return err }
 return pair(invoke_owned(target,[o(pid),o(flags)],{},[flags])!)!
}
fn stop(pid string, master string, mut f Frame) !string {
 perform('os.write',o(master),o(bytes_('0178')!)) or { if !handled(err,['OSError'])! { return err } }
 mut deadline:=f.named('deadline',calculated('add',call('time.monotonic')!,v(ah.Value(5))!)!)!
 for compared('lt',call('time.monotonic')!,o(deadline))! {
  values:=wait(pid)!
  waited:=f.named('waited',values[0])!; f.named('_',values[1])!
  if compare('eq',waited,o(pid))! { return literal(none_())! }
  perform('time.sleep',v(ah.Value(ah.Number{'0.05'}))!)!
  f.clean()!
 }
 target:=global('os.killpg')!
 sig:=global('signal.SIGTERM') or { release([target])!; return err }
 release([invoke_owned(target,[o(pid),o(sig)],{},[sig]) or { if handled(err,['ProcessLookupError'])! { return literal(none_())! }; return err }])!
 deadline=f.named('deadline',calculated('add',call('time.monotonic')!,v(ah.Value(2))!)!)!
 for compared('lt',call('time.monotonic')!,o(deadline))! {
  values:=wait(pid)!
  waited:=f.named('waited',values[0])!; f.named('_',values[1])!
  if compare('eq',waited,o(pid))! { return literal(none_())! }
  perform('time.sleep',v(ah.Value(ah.Number{'0.05'}))!)!
  f.clean()!
 }
 killer:=global('os.killpg')!
 kill_sig:=global('signal.SIGKILL') or { release([killer])!; return err }
 release([invoke_owned(killer,[o(pid),o(kill_sig)],{},[kill_sig]) or { if !handled(err,['ProcessLookupError'])! { return err }; literal(none_())! }])!
 perform('os.waitpid',o(pid),v(ah.Value(0))!) or { if !handled(err,['ChildProcessError'])! { return err } }
 return literal(none_())!
}
fn capture(state string,pid string,master string,snapshot string,generator string,mut f Frame) !string {
 load_state(mut f,state,['transcript','status','forced_stop','shutdown_deadline','deadline'])!
 transcript:=f.names['transcript']; deadline:=f.names['deadline']
 mut shutdown:=f.names['shutdown_deadline']
 for compared('lt',call('time.monotonic')!,o(deadline))! {
  values:=wait(pid)!
  waited:=state_put(mut f,state,'waited',values[0])!; child_status:=state_put(mut f,state,'child_status',values[1])!
  if compare('eq',waited,o(pid))! { state_put(mut f,state,'status',child_status)!; break }
  selector:=global('select.select')!
  masters:=list_([o(master)])!; reads:=list_([])!; errors:=list_([])!
  selected:=invoke_owned(selector,[o(masters),o(reads),o(errors),v(ah.Value(ah.Number{'0.25'}))!],{},[errors,reads,masters])!
  parts:=triple(selected)!
  readable:=state_put(mut f,state,'readable',parts[0])!
  state_put(mut f,state,'_',parts[1])!; state_put(mut f,state,'_',parts[2])!
  if truth(readable)! {
   chunk_result:=call('os.read',o(master),v(ah.Value(65536))!) or {
    cause:=err
    active(cause)!
    if !matches(cause,['OSError'])! { active(none)!; return cause }
    error_id:=callback('error_object',{'error':detail(cause)})!.text()
    f.named('error',error_id)!
    errnum:=member(error_id,'errno')!
    eio:=global('errno.EIO') or { release([errnum])!; active(none)!; return err }
    equal:=call('operator.eq',o(errnum),o(eio)) or { release([errnum,eio])!; active(none)!; return err }
    release([errnum,eio])!
    retry:=tested(equal) or { active(none)!; return err }
    active(none)!
    f.names.delete('error'); release([error_id])!
    if retry { discard(cause)!; f.clean()!; continue }
    return cause
   }
   chunk:=state_put(mut f,state,'chunk',chunk_result)!
   if truth(chunk)! {
    perform_method(transcript,'extend',[o(chunk)],{})!
    writer:=global('sys.stdout.buffer.write')!
    release([invoke(writer,[o(chunk)],{})!])!
    perform('sys.stdout.buffer.flush')!
   }
  }
  recent:=state_put(mut f,state,'recent',call('bytes',o(transcript))!)!
  release([callback('function',{'target':ah.Value(snapshot),'call':ah.Value(true),'args':ah.Value([o(recent)]),'kwargs':ah.Value(map[string]ah.Value{})})!.text()])!
  pass_marker:=global('PASS_MARKER')!
  present:=call('operator.contains',o(recent),o(pass_marker)) or { release([pass_marker])!;return err }
  release([pass_marker])!
  mut finished_result:=present
  if !truth(present)! {
   release([present])!
   any_target:=global('any')!
   candidates:=callback('function',{'target':ah.Value(generator),'call':ah.Value(true),'args':ah.Value([]ah.Value{}),'kwargs':ah.Value(map[string]ah.Value{})}) or { release([any_target])!;return err }
   candidate_id:=candidates.text()
   finished_result=invoke_owned(any_target,[o(candidate_id)],{},[candidate_id])!
  }
  finished:=state_put(mut f,state,'finished',finished_result)!
  if truth(finished)! && is_none(shutdown)! {
   perform('os.write',o(master),o(bytes_('0178')!)) or {
    cause:=err
    active(cause)!
    if !matches(cause,['OSError'])! { active(none)!; return cause }
    error_id:=callback('error_object',{'error':detail(cause)})!.text()
    f.named('error',error_id)!
    errnum:=member(error_id,'errno')!; eio:=global('errno.EIO')!
    unequal:=call('operator.ne',o(errnum),o(eio))!
    release([errnum,eio])!
    fatal:=tested(unequal)!
    active(none)!
    f.names.delete('error'); release([error_id])!
    if fatal { return cause }
    discard(cause)!
   }
   shutdown=state_put(mut f,state,'shutdown_deadline',calculated('add',call('time.monotonic')!,v(ah.Value(10))!)!)!
  }
  if !is_none(shutdown)! && compared('ge',call('time.monotonic')!,o(shutdown))! { break }
  f.clean()!
 }
 return literal(none_())!
}
fn report(state string,mut f Frame) !string {
 load_state(mut f,state,['transcript','status','forced_stop'])!
 output:=state_put(mut f,state,'output',call('bytes',o(f.names['transcript']))!)!
 missing:=state_put(mut f,state,'missing',call('_missing_features',o(output))!)!
 kernel:=call('_missing_kernel',o(output))!
 updated:=binary('iadd',missing,o(kernel)) or { release([kernel])!; return err }
 release([kernel])!
 state_put(mut f,state,'missing',updated)!
 failures:=state_put(mut f,state,'failures',call('_failures',o(output))!)!
 status:=f.names['status']
 if !is_none(status)! && compared('ne',call('exit_code',o(status))!,v(ah.Value(0))!)! {
  target:=member(failures,'append')!
  code:=call('exit_code',o(status)) or { release([target])!; return err }
  line:=concatenate([literal(ah.Value('VM runner exit status '))!,formatted_temporary(code,false)!])!
  release([invoke_owned(target,[o(line)],{},[line])!])!
 }
 if truth(f.names['forced_stop'])! { perform_method(failures,'append',[v(ah.Value('VM did not exit after the test'))!],{})! }
 if truth(f.names['missing'])! || truth(failures)! {
  for row in [[f.names['missing'],'ERROR: missing expected QEMU result: '],[failures,'ERROR: observed QEMU failure: ']] {
   iterator:=call('_ITER',o(row[0]))!
   f.names['_iterator']=iterator
   for {
    next:=callback('next',{'owner':ah.Value(iterator)})!.object()
    if ah.field(next,'done') as bool { break }
    item_:=state_put(mut f,state,'item',ah.field(next,'value').text())!
    printer:=global('print')!
    line:=concatenate([literal(ah.Value(row[1]))!,formatted(item_,false)!])!
    error_stream:=global('sys.stderr') or { release([line,printer])!; return err }
    release([invoke_owned(printer,[o(line)],{'file':o(error_stream)},[error_stream,line])!])!
    f.clean()!
   }
   release([iterator])!
   f.names.delete('_iterator')
  }
  return literal(ah.Value(1))!
 }
 line:=literal(ah.Value('==> AArch64 QEMU NUMA regression passed'))!
 print_line(line,false)!
 release([line])!
 return literal(ah.Value(0))!
}
pub fn dispatch(row map[string]ah.Value) !ah.Value {
 ids:=ah.field(row,'arguments').items().map(it.text());operation:=ah.field(row,'operation').text();current_builtins=ids[1]
 order:=match operation {
  'stop' { ['pid','master','deadline','waited','_'] }
  'exit_code' { ['status'] }
  else { ['root','guest_init','initramfs','state_dir','timeout','environment','extra','command','pid','master','transcript','status','forced_stop','shutdown_deadline','deadline','waited','child_status','readable','_','chunk','error','recent','finished','output','missing','failures','item'] }
 }
 mut f:=Frame{start:checkpoint()!,pins:ids[0],order:order}
 for i in 1..ids.len { f.names['argument-'+i.str()]=ids[i] }
 if operation=='exit_code' { f.named('status',ids[2])! }
 if operation=='stop' { f.named('pid',ids[2])!;f.named('master',ids[3])! }
 if operation=='capture' { f.named('pid',ids[3])!;f.named('master',ids[4])! }
 result:=execute(operation,ids,mut f) or { f.failed(err)!;return err }
 for key in f.order { if id:=f.names[key] { if id!=result { release([id])! } } }
 clean_since(f.start,[result])!
 return ah.Value(result)
}
fn execute(operation string,ids []string,mut f Frame) !string {
 return match operation {
  'prepare' { prepare(ids[2],mut f)! }
  'capture' { capture(ids[2],ids[3],ids[4],ids[5],ids[6],mut f)! }
  'report' { report(ids[2],mut f)! }
  'stop' { stop(ids[2],ids[3],mut f)! }
  'exit_code' { exit_code(ids[2])! }
  else { return error('unknown NUMA controller operation') }
 }
}
