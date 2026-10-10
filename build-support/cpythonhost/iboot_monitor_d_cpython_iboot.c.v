// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

fn C.PyNumber_And(voidptr, voidptr) voidptr
fn C.PySequence_Contains(voidptr, voidptr) i32

// Keyword CALL operands retire right-to-left before the captured target.
fn ib_keywords(target voidptr, positional []voidptr, names []string, values []voidptr) voidptr {
 if target == unsafe { nil } || positional.any(it == unsafe { nil }) || values.any(it == unsafe { nil }) {
  for i:=values.len-1;i>=0;i-- { drop(values[i]) };for i:=positional.len-1;i>=0;i-- { drop(positional[i]) };drop(target);return unsafe { nil }
 }
 args:=C.PyTuple_New(positional.len)
 if args==unsafe { nil } { for i:=values.len-1;i>=0;i-- { drop(values[i]) };for i:=positional.len-1;i>=0;i-- { drop(positional[i]) };drop(target);return args }
 for i,value in positional { C.PyTuple_SetItem(args,i,own(value)) }
 keywords:=C.PyDict_New();mut result:=voidptr(0)
 if keywords!=unsafe { nil } {
  for i,value in values {
   key:=ib_text(names[i]);if key==unsafe { nil } { break }
   status:=C.PyDict_SetItem(keywords,key,value);drop(key);if status!=0 { break }
  }
  if !pending_error() { result=C.PyObject_Call(target,args,keywords) }
 }
 drop(keywords);drop(args);for i:=values.len-1;i>=0;i-- { drop(values[i]) };for i:=positional.len-1;i>=0;i-- { drop(positional[i]) };drop(target);return result
}
fn ib_slice(receiver voidptr, start voidptr, end voidptr) voidptr {
 if receiver==unsafe { nil } || start==unsafe { nil } || end==unsafe { nil } { drop(end);drop(start);drop(receiver);return unsafe { nil } }
 key:=C.PySlice_New(start,end,unsafe { nil });drop(start);drop(end)
 if key==unsafe { nil } { drop(receiver);return key }
 result:=C.PyObject_GetItem(receiver,key);drop(receiver);drop(key);return result
}
fn ib_compare(left voidptr,right voidptr,operator_ i32) i32 {
 if left==unsafe { nil } || right==unsafe { nil } { drop(left);drop(right);return -1 }
 result:=C.PyObject_RichCompare(left,right,operator_);drop(left);drop(right);if result==unsafe { nil } { return -1 }
 answer:=C.PyObject_IsTrue(result);drop(result);return answer
}
fn ib_truth(value voidptr) i32 { if value==unsafe { nil } { return -1 };result:=C.PyObject_IsTrue(value);drop(value);return result }
fn ib_none(value voidptr) i32 { if value==unsafe { nil } { return -1 };none_value:=py_none();answer:=if value==none_value { i32(1) } else { i32(0) };drop(value);drop(none_value);return answer }
fn ib_contains(container voidptr,member voidptr) i32 {
 if container==unsafe { nil } || member==unsafe { nil } { drop(member);drop(container);return -1 }
 result:=C.PySequence_Contains(container,member);drop(member);drop(container);return result
}
struct IbootRun {
 codec &IbootCodec
 mut:
 fields [33]voidptr
}
fn (r &IbootRun) at(index int) voidptr { return own(r.fields[index]) }
fn (mut r IbootRun) put(index int,value voidptr) bool { if value==unsafe { nil } { return false };old:=r.fields[index];r.fields[index]=value;drop(old);return true }
fn (r &IbootRun) retire() {
 r.codec.pin(['initramfs','image','image_base','adt_base','with_aic','provisional_adt','args_base','top_of_kernel_data','segment','adt','args','files','aic','stub','loaders','name','address','data','serial','sock','command','qemu','passed','deadline','failures','dumps','qmp','length','scratch','words','masks','log','failure'],r.fields[..])
 for value in r.fields { drop(value) }
}
fn (mut r IbootRun) finish(status voidptr,error_value voidptr) voidptr {
 result:=C.PyTuple_New(35);if result==unsafe { nil } { drop(error_value);drop(status);return result }
 for i,value in r.fields { r.fields[i]=unsafe { nil };C.PyTuple_SetItem(result,i,if value==unsafe { nil } { py_none() } else { value }) }
 C.PyTuple_SetItem(result,33,status);C.PyTuple_SetItem(result,34,error_value);return result
}
fn (r &IbootRun) append(message string) bool { value:=ib_invoke(ib_attr(r.fields[24],'append'),[ib_text(message)]);if value==unsafe { nil } { return false };drop(value);return true }
fn (r &IbootRun) real(arguments voidptr) i32 { return ib_truth(ib_attr(arguments,'real_adt')) }
fn (mut r IbootRun) monitor(work voidptr,arguments voidptr) voidptr {
 s:=r.codec
 print_target:=s.global('print');if print_target==unsafe { nil } { return print_target }
 join_receiver:=ib_text(' ');if join_receiver==unsafe { nil } { drop(print_target);return join_receiver };join_target:=ib_attr(join_receiver,'join');drop(join_receiver);if join_target==unsafe { nil } { drop(print_target);return join_target }
 joined:=ib_invoke(join_target,[ib_slice(r.at(20),py_none(),ib_int(12))])
 line:=ib_binary('add',ib_binary('add',ib_text('==> '),joined),ib_text(' ...'))
 printed:=ib_keywords(print_target,[line],['flush'],[C.PyBool_FromLong(1)]);if printed==unsafe { nil } { return printed };drop(printed)
 if !r.put(21,ib_invoke(s.member('subprocess','Popen'),[r.at(20)])) { return unsafe { nil } }
 if !r.put(22,C.PyBool_FromLong(0)) { return unsafe { nil } }
 now:=ib_invoke(s.member('time','monotonic'),[]);if now==unsafe { nil } { return now }
 if !r.put(23,ib_binary('add',now,ib_attr(arguments,'timeout'))) { return unsafe { nil } }
 for {
  within:=ib_compare(ib_invoke(s.member('time','monotonic'),[]),r.at(23),0);if within<0 { return unsafe { nil } };if within==0 { break }
  running:=ib_none(ib_invoke(ib_attr(r.fields[21],'poll'),[]));if running<0 { return unsafe { nil } };if running==0 { break }
  exists:=ib_truth(ib_invoke(ib_attr(r.fields[18],'exists'),[]));if exists<0 { return unsafe { nil } }
  if exists>0 {
   marker:=s.global('MARKER');if marker==unsafe { nil } { return marker }
   detected:=ib_contains(ib_invoke(ib_attr(r.fields[18],'read_bytes'),[]),marker);if detected<0 { return unsafe { nil } }
   if detected>0 { r.put(22,C.PyBool_FromLong(1));break }
  }
  sleep:=ib_invoke(s.member('time','sleep'),[ib_int(1)]);if sleep==unsafe { nil } { return sleep };drop(sleep)
 }
 if !r.put(24,C.PyList_New(0)) { return unsafe { nil } }
 passed:=ib_truth(r.at(22));if passed<0 { return unsafe { nil } }
 if passed==0 && !r.append('PID 1 never printed its marker') { return unsafe { nil } }
 running:=ib_none(ib_invoke(ib_attr(r.fields[21],'poll'),[]));if running<0 { return unsafe { nil } }
 if running>0 {
  mut dumps:=C.PyDict_New();if dumps==unsafe { nil } { return dumps };defer { drop(dumps) }
  if !ib_dict_put(dumps,'scratch',ib_sequence([s.global('SCRATCH'),ib_int(0x400)],true)) || !ib_dict_put(dumps,'segment',ib_sequence([r.at(8),s.global('SEGMENT_BYTES')],true)) { return unsafe { nil } }
  if !r.put(25,dumps) { return unsafe { nil } };dumps=unsafe { nil }
  aic:=ib_truth(r.at(4));if aic<0 { return unsafe { nil } }
  if aic>0 && !ib_dict_put(r.fields[25],'aic',ib_sequence([s.global('FAKE_AIC'),s.global('AIC_SIZE')],true)) { return unsafe { nil } }
  screenshot:=ib_truth(ib_attr(arguments,'screenshot'));if screenshot<0 { return unsafe { nil } }
  if screenshot>0 {
   base:=s.global('FB_BASE');if base==unsafe { nil } { return base }
   stride:=s.global('FB_STRIDE');if stride==unsafe { nil } { drop(base);return stride }
   size:=ib_binary('mul',stride,s.global('FB_HEIGHT'))
   if !ib_dict_put(r.fields[25],'framebuffer',ib_sequence([base,size],true)) { return unsafe { nil } }
  }
  target:=s.global('Qmp');if target==unsafe { nil } { return target }
  if !r.put(26,ib_invoke(target,[r.at(19)])) { return unsafe { nil } }
  items:=ib_invoke(ib_attr(r.fields[25],'items'),[]);if items==unsafe { nil } { return items }
  iterator:=C.PyObject_GetIter(items);drop(items);if iterator==unsafe { nil } { return iterator }
  for {
   next:=C.PyIter_Next(iterator);if next==unsafe { nil } { break }
   pair:=ib_invoke(own(s.pair),[next]);if pair==unsafe { nil } { break }
   name:=own(C.PyTuple_GetItem(pair,0));nested:=own(C.PyTuple_GetItem(pair,1));drop(pair);r.put(15,name)
   values:=ib_invoke(own(s.pair),[nested]);if values==unsafe { nil } { break }
   address:=own(C.PyTuple_GetItem(values,0));length:=own(C.PyTuple_GetItem(values,1));drop(values);r.put(16,address);r.put(27,length)
   execute:=ib_attr(r.fields[26],'execute');if execute==unsafe { nil } { break }
   address_arg:=r.at(16);size_arg:=r.at(27);path_target:=s.global('str')
   if path_target==unsafe { nil } { drop(size_arg);drop(address_arg);drop(execute);break }
   filename:=ib_invoke(path_target,[ib_path(own(work),ib_binary('add',r.at(15),ib_text('.dump')))])
   result:=ib_keywords(execute,[ib_text('pmemsave')],['val','size','filename'],[address_arg,size_arg,filename]);if result==unsafe { nil } { break };drop(result)
  }
  drop(iterator);if pending_error() { return unsafe { nil } }
  quit:=ib_invoke(ib_attr(r.fields[26],'execute'),[ib_text('quit')]);if quit==unsafe { nil } { return quit };drop(quit)
  waited:=ib_keywords(ib_attr(r.fields[21],'wait'),[],['timeout'],[ib_int(30)]);if waited==unsafe { nil } { return waited };drop(waited)
  if !r.put(28,ib_temporary_method(ib_path(own(work),ib_text('scratch.dump')),'read_bytes',[])) { return unsafe { nil } }
  real:=r.real(arguments);if real<0 { return unsafe { nil } }
  if real==0 {
   scratch_receiver:=r.at(28)
   start:=s.global('WDT_CONTROL');if start==unsafe { nil } { drop(scratch_receiver);return start }
   endbase:=s.global('WDT_CONTROL');if endbase==unsafe { nil } { drop(start);drop(scratch_receiver);return endbase }
   left:=ib_slice(scratch_receiver,start,ib_binary('add',endbase,ib_int(4)));if left==unsafe { nil } { return left }
   right_target:=s.global('bytes');if right_target==unsafe { nil } { drop(left);return right_target }
   different:=ib_compare(left,ib_invoke(right_target,[ib_int(4)]),3);if different<0 { return unsafe { nil } }
   if different>0 && !r.append("the watchdog's control register was not cleared") { return unsafe { nil } }
  }
  real2:=r.real(arguments);if real2<0 { return unsafe { nil } }
  if real2==0 {
   left:=ib_slice(r.at(28),ib_int(0x100),ib_int(0x104));if left==unsafe { nil } { return left }
   right_target:=s.global('bytes');if right_target==unsafe { nil } { drop(left);return right_target }
   different:=ib_compare(left,ib_invoke(right_target,[ib_int(4)]),3);if different<0 { return unsafe { nil } }
   if different>0 && !r.append("the watchdog's second control word was not cleared") { return unsafe { nil } }
  }
  real3:=r.real(arguments);if real3<0 { return unsafe { nil } }
  if real3==0 {
   left:=ib_temporary_method(ib_path(own(work),ib_text('segment.dump')),'read_bytes',[]);if left==unsafe { nil } { return left }
   right_target:=s.global('bytes');if right_target==unsafe { nil } { drop(left);return right_target }
   right:=ib_binary('mul',ib_invoke(right_target,[ib_sequence([s.global('SEGMENT_FILL')],false)]),s.global('SEGMENT_BYTES'))
   different:=ib_compare(left,right,3);if different<0 { return unsafe { nil } }
   if different>0 && !r.append('the reserved firmware segment was overwritten') { return unsafe { nil } }
  }
  aic2:=ib_truth(r.at(4));if aic2<0 { return unsafe { nil } }
  if aic2>0 {
   if !r.put(12,ib_temporary_method(ib_path(own(work),ib_text('aic.dump')),'read_bytes',[])) { return unsafe { nil } }
   if !r.put(29,ib_binary('div',ib_binary('add',s.global('AIC_NR_IRQ'),ib_int(31)),ib_int(32))) { return unsafe { nil } }
   aic_receiver:=r.at(12)
   start:=s.global('AIC_MASK_SET');if start==unsafe { nil } { drop(aic_receiver);return start }
   endbase:=s.global('AIC_MASK_SET');if endbase==unsafe { nil } { drop(start);drop(aic_receiver);return endbase }
   end:=ib_binary('add',endbase,ib_binary('mul',ib_int(4),r.at(29)))
   if !r.put(30,ib_slice(aic_receiver,start,end)) { return unsafe { nil } }
   different:=ib_compare(r.at(30),ib_binary('mul',ib_bytes('\xff'),s.len(r.fields[30])),3);if different<0 { return unsafe { nil } }
   if different>0 && !r.append('the kernel did not mask every AIC IRQ') { return unsafe { nil } }
   config_receiver:=r.at(12)
   key:=s.global('AIC_GLOBAL_CONFIG');if key==unsafe { nil } { drop(config_receiver);return key }
   at:=C.PyObject_GetItem(config_receiver,key);drop(config_receiver);drop(key);if at==unsafe { nil } { return at }
   one:=ib_int(1);bit:=C.PyNumber_And(at,one);drop(at);drop(one);enabled:=ib_truth(bit);if enabled<0 { return unsafe { nil } }
   if enabled==0 && !r.append('the kernel did not enable the AIC') { return unsafe { nil } }
   aic_marker:=ib_bytes('aic: masked');if aic_marker==unsafe { nil } { return aic_marker };has_marker:=ib_contains(ib_invoke(ib_attr(r.fields[18],'read_bytes'),[]),aic_marker);if has_marker<0 { return unsafe { nil } }
   if has_marker==0 && !r.append('the kernel did not take the AICv3 path') { return unsafe { nil } }
  }
  screenshot2:=ib_truth(ib_attr(arguments,'screenshot'));if screenshot2<0 { return unsafe { nil } }
  if screenshot2>0 {
   png_target:=s.global('write_png');if png_target==unsafe { nil } { return png_target }
   path:=ib_attr(arguments,'screenshot');if path==unsafe { nil } { drop(png_target);return path }
   pixels:=ib_temporary_method(ib_path(own(work),ib_text('framebuffer.dump')),'read_bytes',[])
   result:=ib_invoke(png_target,[path,pixels]);if result==unsafe { nil } { return result };drop(result)
   printer:=s.global('print');if printer==unsafe { nil } { return printer }
   text:=ib_build_string([ib_text('framebuffer: '),ib_format(ib_attr(arguments,'screenshot'),'')])
   printed2:=ib_invoke(printer,[text]);if printed2==unsafe { nil } { return printed2 };drop(printed2)
  }
 } else {
  appender:=ib_attr(r.fields[24],'append');if appender==unsafe { nil } { return appender }
  message:=ib_build_string([ib_text('QEMU exited with status '),ib_format(ib_attr(r.fields[21],'returncode'),'')])
  added:=ib_invoke(appender,[message]);if added==unsafe { nil } { return added };drop(added)
 }
 unlink:=ib_keywords(ib_attr(r.fields[19],'unlink'),[],['missing_ok'],[C.PyBool_FromLong(1)]);if unlink==unsafe { nil } { return unlink };drop(unlink)
 exists:=ib_truth(ib_invoke(ib_attr(r.fields[18],'exists'),[]));if exists<0 { return unsafe { nil } }
 if exists>0 {
  raw:=ib_invoke(ib_attr(r.fields[18],'read_bytes'),[]);if raw==unsafe { nil } { return raw }
  decoder:=ib_attr(raw,'decode');drop(raw);if decoder==unsafe { nil } { return decoder }
  if !r.put(31,ib_keywords(decoder,[],['errors'],[ib_text('replace')])) { return unsafe { nil } }
 } else { r.put(31,ib_text('')) }
 header:=ib_invoke(s.global('print'),[ib_text('---- serial (last 60 lines) ----')]);if header==unsafe { nil } { return header };drop(header)
 printer:=s.global('print');if printer==unsafe { nil } { return printer }
 join_receiver2:=ib_text('\n');if join_receiver2==unsafe { nil } { drop(printer);return join_receiver2 };join_target2:=ib_attr(join_receiver2,'join');drop(join_receiver2);if join_target2==unsafe { nil } { drop(printer);return join_target2 }
 lines:=ib_invoke(ib_attr(r.fields[31],'splitlines'),[])
 tail:=ib_slice(lines,ib_int(-60),py_none())
 output:=ib_invoke(join_target2,[tail]);output_print:=ib_invoke(printer,[output]);if output_print==unsafe { nil } { return output_print };drop(output_print)
 footer:=ib_invoke(s.global('print'),[ib_text('--------------------------------')]);if footer==unsafe { nil } { return footer };drop(footer)
 iterator:=C.PyObject_GetIter(r.fields[24]);if iterator==unsafe { nil } { return iterator }
 for {
  next:=C.PyIter_Next(iterator);if next==unsafe { nil } { break };r.put(32,next)
  printer2:=s.global('print');if printer2==unsafe { nil } { break }
  message:=ib_build_string([ib_text('FAIL: '),ib_format(r.at(32),'')])
  printed3:=ib_invoke(printer2,[message]);if printed3==unsafe { nil } { break };drop(printed3)
 }
 drop(iterator);if pending_error() { return unsafe { nil } }
 failed:=ib_truth(r.at(24));if failed<0 { return unsafe { nil } }
 if failed==0 { printed4:=ib_invoke(s.global('print'),[ib_text('PASS: iBoot-style hand-off reached user space')]);if printed4==unsafe { nil } { return printed4 };drop(printed4) }
 failed2:=ib_truth(r.at(24));if failed2<0 { return unsafe { nil } }
 return ib_int(if failed2>0 { 1 } else { 0 })
}
fn (s &IbootCodec) run_iboot(work voidptr,arguments voidptr) voidptr {
 mut r:=IbootRun{codec:s};defer { r.retire() }
 mut preparation:=IbootPreparation{codec:s}
 prepared:=preparation.body(work,arguments)
 for i,value in preparation.fields { preparation.fields[i]=unsafe { nil };r.fields[i]=value }
 mut result:=prepared
 if result!=unsafe { nil } { drop(result);result=r.monitor(work,arguments) }
 if result!=unsafe { nil } { return r.finish(result,py_none()) }
 error:=caught();tuple:=r.finish(py_none(),own(error.value));if tuple==unsafe { nil } { error.restore() };error.discard();return tuple
}
