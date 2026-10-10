// SPDX-License-Identifier: GPL-2.0-or-later
module vinixcore

import androidhost as ah

fn put(state string, name string, value string) ! {
 target := global('operator.setitem') or { release([value])!; return err }
 returned := invoke(target,[o(state),v(ah.Value(name))!,o(value)],{}) or { release([value])!; return err }
 release([returned,value])!
}
fn path(parent string, name string) !string { return call('operator.truediv',o(parent),v(ah.Value(name))!)! }
fn named_path(state string, parent string, name string) !string {
 base := get(state,parent)!
 result := path(base,name) or { release([base])!; return err }
 release([base])!
 return result
}
fn arg(state string, name string) !string {
 args := get(state,'args')!
 result := member(args,name) or { release([args])!; return err }
 release([args])!
 return result
}
fn string_state(state string,name string) !string {
 target := global('str')!
 id := get(state,name) or {release([target])!;return err}
 return invoke_owned(target,[o(id)],{},[id])!
}
fn state_method(state string,name string,method_ string,arguments []ah.Value,options map[string]ah.Value) !string {
 receiver := get(state,name)!
 target := member(receiver,method_) or { release([receiver])!; return err }
 release([receiver])!
 return invoke(target,arguments,options)!
}
fn perform_state_method(state string,name string,method_ string,arguments []ah.Value,options map[string]ah.Value) ! {
 release([state_method(state,name,method_,arguments,options)!])!
}
fn list_owned(values []string) !string {
 target := global('_list') or { retire_parts(values)!; return err }
 return invoke_owned(target,values.map(o(it)),{},values.reverse())!
}
fn print_owned(target string,line string,flush_ bool) ! {
 release([invoke_owned(target,[o(line)],if flush_ { {'flush':v(ah.Value(true))!} }else{map[string]ah.Value{}},[line])!])!
}
fn parser_error(state string,prefix string,value string) ! {
 parser := get(state,'parser')!
 target := member(parser,'error') or { release([parser,value])!;return err }
 release([parser])!
 line := concatenate([literal(ah.Value(prefix))!,formatted_temporary(value,false)!]) or { release([target])!;return err }
 release([invoke_owned(target,[o(line)],{},[line])!])!
}
fn prepare(state string) !string {
 kernel := temporary_method(arg(state,'kernel')!,'resolve',[],{})!
 sysroot := temporary_method(arg(state,'sysroot')!,'resolve',[],{}) or { release([kernel])!;return err }
 put(state,'kernel',kernel)!
 put(state,'sysroot',sysroot)!
 path_factory := global('Path')!
 which := global('shutil.which') or { release([path_factory])!;return err }
 name := arg(state,'qemu') or { release([which,path_factory])!;return err }
 found := invoke_owned(which,[o(name)],{},[name]) or { release([path_factory])!;return err }
 mut selected := found
 if !truth(found)! { release([found])!;selected=arg(state,'qemu')! }
 qpath := invoke_owned(path_factory,[o(selected)],{},[selected])!
 put(state,'qemu',temporary_method(qpath,'resolve',[],{})!)!
 supplied := arg(state,'firmware')!
 mut firmware := supplied
 if !truth(supplied)! {
  release([supplied])!
  qemu := get(state,'qemu')!
  first := member(qemu,'parent') or { release([qemu])!;return err }
  release([qemu])!
  second := member(first,'parent') or { release([first])!;return err }
  release([first])!
  firmware=path(second,'share/qemu/edk2-x86_64-code.fd') or { release([second])!;return err }
  release([second])!
 }
 put(state,'firmware',temporary_method(firmware,'resolve',[],{})!)!
 root := global('ROOT')!
 source := path(root,'tests/alloc-bench/benchcore/core.v') or { release([root])!;return err }
 release([root])!
 put(state,'source',source)!
 mut values := []string{}
 values << get(state,'kernel')!
 values << get(state,'firmware')!
 values << get(state,'source')!
 source_id := get(state,'source')!
 parent := member(source_id,'parent') or { release([source_id])!;return err }
 release([source_id])!
 values << path(parent,'bench-native-abi.h') or { release([parent])!;return err }
 release([parent])!
 for name_ in ['usr/bin/gcc','bin/busybox','lib/ld-musl-x86_64.so.1','usr/lib/libc.a'] { values << named_path(state,'sysroot',name_)! }
 put(state,'inputs',list_owned(values)!)!
 requested := arg(state,'allocator_check')!
 if truth(requested)! {
  release([requested])!
  appender := state_method_target(state,'inputs','append')!
  resolved := temporary_method(arg(state,'allocator_check')!,'resolve',[],{}) or { release([appender])!;return err }
  release([invoke_owned(appender,[o(resolved)],{},[resolved])!])!
 } else { release([requested])! }
 inputs := get(state,'inputs')!
 iterator := call('_ITER',o(inputs)) or { release([inputs])!;return err }
 release([inputs])!
 for {
  row := callback('next',{'owner':ah.Value(iterator)})!.object()
  if ah.field(row,'done') as bool { break }
  item_ := ah.field(row,'value').text()
  put(state,'path',item_)!
  if !tested(state_method(state,'path','is_file',[],{})!)! {
   parser_error(state,'required input missing: ',get(state,'path')!) or { release([iterator])!;return err }
  }
 }
 release([iterator])!
 put(state,'state',temporary_method(arg(state,'state_dir')!,'resolve',[],{})!)!
 perform_state_method(state,'state','mkdir',[],{'parents':v(ah.Value(true))!,'exist_ok':v(ah.Value(false))!})!
 put(state,'rootfs',named_path(state,'state','rootfs')!)!
 copier := global('shutil.copytree')!
 from := get(state,'sysroot') or { release([copier])!;return err }
 dest := get(state,'rootfs') or { release([from,copier])!;return err }
 release([invoke_owned(copier,[o(from),o(dest)],{'symlinks':v(ah.Value(true))!},[dest,from])!])!
 for name_ in ['dev','proc','sys','tmp','root','sbin'] {
  put(state,'name',literal(ah.Value(name_))!)!
  dir := named_path(state,'rootfs',name_)!
  release([temporary_method(dir,'mkdir',[],{'exist_ok':v(ah.Value(true))!})!])!
 }
 release([temporary_method(named_path(state,'rootfs','tmp')!,'chmod',[v(ah.Value(0o1777))!],{})!])!
 put(state,'guest_source',named_path(state,'rootfs','root/alloc-bench.c')!)!
 runner := global('runpy.run_path')!
 converter := global('str') or { release([runner])!;return err }
 root_ := global('ROOT') or { release([converter,runner])!;return err }
 generator_path := path(root_,'tests/alloc-bench/compile-v-bench.py') or { release([root_,converter,runner])!;return err }
 release([root_])!
 generator_name := invoke_owned(converter,[o(generator_path)],{},[generator_path]) or { release([runner])!;return err }
 module_ := invoke_owned(runner,[o(generator_name)],{},[generator_name])!
 generator := get(module_,'generate') or { release([module_])!;return err }
 release([module_])!
 destination := get(state,'guest_source') or { release([generator])!;return err }
 put(state,'generation',invoke_owned(generator,[o(destination)],{},[destination])!)!
 generation := get(state,'generation')!
 hash_ := get(generation,'source_sha256') or { release([generation])!;return err }
 release([generation])!
 put(state,'source_hash',hash_)!
 put(state,'allocator_check',literal(ah.Value(''))!)!
 requested_ := arg(state,'allocator_check')!
 if truth(requested_)! {
  release([requested_])!
  put(state,'check_source',named_path(state,'rootfs','root/allocator-check.c')!)!
  writer := state_method_target(state,'check_source','write_bytes')!
  resolved_ := temporary_method(arg(state,'allocator_check')!,'resolve',[],{}) or { release([writer])!;return err }
  data := temporary_method(resolved_,'read_bytes',[],{}) or { release([writer])!;return err }
  release([invoke_owned(writer,[o(data)],{},[data])!])!
  put(state,'allocator_check',call('_allocator_script')!)!
 } else { release([requested_])! }
 put(state,'init',named_path(state,'rootfs','sbin/init')!)!
 perform_state_method(state,'init','unlink',[],{'missing_ok':v(ah.Value(true))!})!
 writer := state_method_target(state,'init','write_text')!
 script_target := global('_init_script') or { release([writer])!;return err }
 allocator := get(state,'allocator_check') or { release([script_target,writer])!;return err }
 args := get(state,'args') or { release([allocator,script_target,writer])!;return err }
 script := invoke_owned(script_target,[o(allocator),o(args)],{},[args,allocator]) or { release([writer])!;return err }
 release([invoke_owned(writer,[o(script)],{},[script])!])!
 perform_state_method(state,'init','chmod',[v(ah.Value(0o755))!],{})!
 put(state,'initramfs',named_path(state,'state','initramfs.tar')!)!
 return literal(none_())!
}
fn state_method_target(state string,name string,method_ string) !string {
 receiver := get(state,name)!
 target := member(receiver,method_) or { release([receiver])!;return err }
 release([receiver])!
 return target
}
fn image_paths(state string) !string {
 put(state,'iso',named_path(state,'state','vinix.iso')!)!
 factory := global('dict')!
 environ := global('os.environ') or { release([factory])!;return err }
 mut options := map[string]ah.Value{}
 mut consumed := []string{}
 for pair in [['VINIX_AMD64_ISO_BUILD_DIR','iso-build'],['VINIX_AMD64_KERNEL',''],['VINIX_AMD64_INITRAMFS',''],['VINIX_AMD64_ISO','']] {
  converter := global('str')!
  value := if pair[0]=='VINIX_AMD64_ISO_BUILD_DIR' { named_path(state,'state',pair[1])! }else { get(state,match pair[0]{'VINIX_AMD64_KERNEL'{'kernel'}'VINIX_AMD64_INITRAMFS'{'initramfs'}else{'iso'}})! }
  text_ := invoke_owned(converter,[o(value)],{},[value])!
  options[pair[0]]=o(text_);consumed<<text_
 }
 consumed.reverse_in_place();consumed<<environ
 put(state,'env',invoke_owned(factory,[o(environ)],options,consumed)!)!
 put(state,'boot_kernel',named_path(state,'state','boot-kernel')!)!
 return literal(none_())!
}
fn image(state string) !string {
 runner := global('subprocess.run')!
 converter := global('str')!
 root := global('ROOT')!
 script := path(root,'build-support/build-amd64-iso.sh') or { release([root,converter,runner])!;return err }
 release([root])!
 text_ := invoke_owned(converter,[o(script)],{},[script])!
 command := list_owned([text_])!
 env := get(state,'env')!;log := get(state,'log')!
 release([invoke_owned(runner,[o(command)],{'env':o(env),'check':v(ah.Value(true))!,'stdout':o(log),'stderr':o(log)},[log,env,command])!])!
 extraction := global('subprocess.run')!
 mut args := []string{}
 for value in ['xorriso','-osirrox','on','-indev'] { args<<literal(ah.Value(value))! }
 args<<string_state(state,'iso')!
 args<<literal(ah.Value('-extract'))!;args<<literal(ah.Value('/boot/vinix'))!
 args<<string_state(state,'boot_kernel')!
 argv := list_owned(args)!
 log_ := get(state,'log')!
 release([invoke_owned(extraction,[o(argv)],{'check':v(ah.Value(true))!,'stdout':o(log_),'stderr':o(log_)},[log_,argv])!])!
 return literal(none_())!
}
fn hash_file(factory string,id string) !string {
 data := temporary_method(id,'read_bytes',[],{}) or { release([factory])!;return err }
 hash_ := invoke_owned(factory,[o(data)],{},[data])!
 return temporary_method(hash_,'hexdigest',[],{})!
}
fn hash_state(state string,name string) !string {
 factory := global('hashlib.sha256')!
 id := get(state,name) or {release([factory])!;return err}
 return hash_file(factory,id)!
}
fn hash_path(state string,parent string,name string) !string {
 factory := global('hashlib.sha256')!
 id := named_path(state,parent,name) or {release([factory])!;return err}
 return hash_file(factory,id)!
}
fn setitem(id string,key string,value string) ! { put(id,key,value)! }
fn raise_value(target string,message string) !string {
 error_id := invoke_owned(target,[o(message)],{},[message])!
 release([invoke_owned(global('_raise_value')!,[o(error_id)],{},[error_id])!])!
 return literal(none_())!
}
fn config(state string) !string {
 put(state,'kernel_hash',hash_state(state,'boot_kernel')!)!
 actual := get(state,'kernel_hash')!
 expected := hash_state(state,'kernel') or {release([actual])!;return err}
 unequal := call('operator.ne',o(actual),o(expected)) or { release([actual,expected])!;return err }
 release([actual,expected])!
 if tested(unequal)! { error_factory := global('RuntimeError')!;return raise_value(error_factory,literal(ah.Value('kernel embedded in completed ISO differs from supplied kernel'))!)! }
 put(state,'serial',named_path(state,'state','serial.log')!)!
 mut values := []string{}
 values<<string_state(state,'qemu')!
 for pair in [['-machine','MACHINE'],['-accel','ACCELERATOR'],['-cpu','CPU'],['-smp','SMP']] {values<<literal(ah.Value(pair[0]))!;values<<global(pair[1])!}
 for value in ['-m','4096','-display','none','-monitor','none','-drive'] {values<<literal(ah.Value(value))!}
 values<<concatenate([literal(ah.Value('if=pflash,format=raw,readonly=on,file='))!,formatted_temporary(get(state,'firmware')!,false)!])!
 values<<literal(ah.Value('-cdrom'))!;values<<string_state(state,'iso')!
 values<<literal(ah.Value('-serial'))!;values<<concatenate([literal(ah.Value('file:'))!,formatted_temporary(get(state,'serial')!,false)!])!
 values<<literal(ah.Value('-no-reboot'))!
 put(state,'command',list_owned(values)!)!
 dict_ := call('_named')!
 target := global('subprocess.check_output')!
 executable := string_state(state,'qemu')!
 version_args := list_owned([executable,literal(ah.Value('--version'))!])!
 version := invoke_owned(target,[o(version_args)],{'text':v(ah.Value(true))!},[version_args])!
 split := temporary_method(version,'splitlines',[],{})!
 first := item(split,v(ah.Value(0))!) or { release([split])!;return err }
 release([split])!
 setitem(dict_,'qemu_version',first)!
 for pair in [['machine','MACHINE'],['accelerator','ACCELERATOR'],['cpu','CPU'],['smp','SMP']] {setitem(dict_,pair[0],global(pair[1])!)!}
 setitem(dict_,'memory_mb',literal(ah.Value(4096))!)!
 setitem(dict_,'source_sha256',get(state,'source_hash')!)!
 setitem(dict_,'v_generation',get(state,'generation')!)!
 generation := get(state,'generation')!
 native_hash := get(generation,'native_header_sha256') or {release([generation])!;return err}
 release([generation])!
 setitem(dict_,'native_header_sha256',native_hash)!
 setitem(dict_,'kernel_sha256',get(state,'kernel_hash')!)!
 setitem(dict_,'kernel_verification',literal(ah.Value('extracted from completed ISO and matched supplied kernel'))!)!
 setitem(dict_,'compile_flags',global('FLAGS')!)!
 setitem(dict_,'iterations',arg(state,'iterations')!)!
 setitem(dict_,'samples',arg(state,'samples')!)!
 setitem(dict_,'argv',get(state,'command')!)!
 put(state,'config',dict_)!
 put(state,'loader',named_path(state,'rootfs','lib/ld-musl-x86_64.so.1')!)!
 config_ := get(state,'config')!
 setitem(config_,'libc_sha256',hash_state(state,'loader')!)!
 setitem(config_,'libc_a_sha256',hash_path(state,'rootfs','usr/lib/libc.a')!)!
 put(state,'libc_manifest',named_path(state,'rootfs','usr/share/vinix/musl-build.json')!)!
 if tested(state_method(state,'libc_manifest','is_file',[],{})!)! {
  factory := global('json.loads')!
  text_ := state_method(state,'libc_manifest','read_text',[],{})!
  setitem(config_,'libc_build',invoke_owned(factory,[o(text_)],{},[text_])!)!
  pairs := call('_manifest_pairs',o(config_))!
  iterator := call('_ITER',o(pairs)) or {release([pairs])!;return err}
  release([pairs])!
  for {
   row := callback('next',{'owner':ah.Value(iterator)})!.object()
   if ah.field(row,'done') as bool {break}
   members := pair(ah.field(row,'value').text())!
   put(state,'field',members[0])!
   put(state,'actual',members[1])!
   build := get(config_,'libc_build')!
   getter := member(build,'get') or {release([build])!;return err}
   release([build])!
   field := get(state,'field')!
   value := invoke_owned(getter,[o(field)],{},[field])!
   actual_ := get(state,'actual')!
   compared_ := call('operator.ne',o(value),o(actual_)) or {release([value,actual_])!;return err}
   release([value,actual_])!
   if tested(compared_)! { error_factory := global('RuntimeError')!;return raise_value(error_factory,concatenate([literal(ah.Value('staged libc does not match build manifest: '))!,formatted_temporary(get(state,'field')!,false)!])!)! }
  }
  release([iterator])!
 }
 check := arg(state,'allocator_check')!
 if truth(check)! {release([check])!;setitem(config_,'allocator_check_sha256',hash_state(state,'check_source')!)!}else{release([check])!}
 release([config_])!
 dest := named_path(state,'state','config.json')!
 writer := member(dest,'write_text') or {release([dest])!;return err}
 release([dest])!
 serializer := global('json.dumps')!
 cfg := get(state,'config')!
 encoded := invoke_owned(serializer,[o(cfg)],{'indent':v(ah.Value(2))!},[cfg])!
 line := added(encoded,v(ah.Value('\n'))!)!
 release([invoke_owned(writer,[o(line)],{},[line])!])!
 printer := global('print')!
 message := concatenate([literal(ah.Value('Booting benchmark; output: '))!,formatted_temporary(get(state,'serial')!,false)!])!
 print_owned(printer,message,true)!
 return literal(none_())!
}
fn launch(state string) !string {
 target := global('subprocess.Popen')!
 command := get(state,'command')!;log := get(state,'log')!
 put(state,'process',invoke_owned(target,[o(command)],{'stdout':o(log),'stderr':o(log)},[log,command])!)!
 return literal(none_())!
}
fn contains(state string,marker string) !bool {
 output := get(state,'output')!
 result := call('operator.contains',o(output),v(ah.Value(marker))!) or {release([output])!;return err}
 release([output])!
 return tested(result)!
}
fn generator_call(id string) !string {return callback('function',{'target':ah.Value(id),'call':ah.Value(true),'args':ah.Value([]ah.Value{}),'kwargs':ah.Value(map[string]ah.Value{})})!.text()}
fn capture(state string,snapshot string,latest string,failed string,verified string,lines string) !string {
 clock := call('time.monotonic')!
 timeout := arg(state,'timeout')!
 deadline := call('operator.add',o(clock),o(timeout)) or {release([clock,timeout])!;return err}
 release([clock,timeout])!
 put(state,'deadline',deadline)!
 put(state,'last_stage',literal(ah.Value(''))!)!
 for {
  now := call('time.monotonic')!;until := get(state,'deadline')!
  comparison := call('operator.lt',o(now),o(until)) or {release([now,until])!;return err}
  release([now,until])!
  if !tested(comparison)! {break}
  value := if tested(state_method(state,'serial','exists',[],{})!)! {state_method(state,'serial','read_text',[],{'errors':v(ah.Value('replace'))!})!}else{literal(ah.Value(''))!}
  put(state,'output',value)!
  output := get(state,'output')!
  release([callback('function',{'target':ah.Value(snapshot),'call':ah.Value(true),'args':ah.Value([o(output)]),'kwargs':ah.Value(map[string]ah.Value{})})!.text()])!
  release([output])!
  for marker in ['heap-bench: done','ALLOC-COMPILE-BEGIN','ALLOC-COMPILE-DONE'] {
   put(state,'marker',literal(ah.Value(marker))!)!
   if contains(state,marker)! {
    previous := get(state,'last_stage')!
    equal := call('operator.ne',v(ah.Value(marker))!,o(previous)) or {release([previous])!;return err}
    release([previous])!
    if tested(equal)! {
     next_ := global('next')!
     iterator := generator_call(latest) or {release([next_])!;return err}
     stage := invoke_owned(next_,[o(iterator),v(ah.Value(''))!],{},[iterator])!
     put(state,'stage',stage)!
     current := get(state,'stage')!;old := get(state,'last_stage')!
     changed := call('operator.ne',o(current),o(old)) or {release([current,old])!;return err}
     release([current,old])!
     if tested(changed)! {
      printer := global('print')!
      stage_ := get(state,'stage')!
      print_owned(printer,stage_,true)!
      put(state,'last_stage',get(state,'stage')!)!
     }
    }
   }
  }
  any_ := global('any')!
  candidates := generator_call(failed) or {release([any_])!;return err}
  if tested(invoke_owned(any_,[o(candidates)],{},[candidates])!)! {return failure(state,'guest failed; see ','serial')!}
  if contains(state,'ALLOC-GUEST-DONE')! {
   if !contains(state,'ALLOC-DONE')! {return failure(state,'benchmark did not finish; see ','serial')!}
   check := arg(state,'allocator_check')!
   if truth(check)! {
    release([check])!
    mut incomplete := !contains(state,'UALLOC-VERIFY-COMPLETE')!
    if !incomplete {
     sum_ := global('sum')!
     counts := generator_call(verified) or {release([sum_])!;return err}
     count := invoke_owned(sum_,[o(counts)],{},[counts])!
     incomplete=compared('ne',count,v(ah.Value(2))!)!
    }
    if incomplete {return failure(state,'allocator verification incomplete; see ','serial')!}
   }else{release([check])!}
   printer := global('print')!
   newline := literal(ah.Value('\n'))!
   joiner := member(newline,'join') or {release([newline,printer])!;return err}
   release([newline])!
   rows := generator_call(lines) or {release([joiner,printer])!;return err}
   report := invoke_owned(joiner,[o(rows)],{},[rows]) or {release([printer])!;return err}
   print_owned(printer,report,true)!
   return literal(ah.Value(0))!
  }
  status := state_method(state,'process','poll',[],{})!
  if !is_none(status)! {release([status])!;return failure(state,'QEMU exited; see ','qemu.log')!}
  release([status])!
  perform('time.sleep',v(ah.Value(ah.Number{'0.25'}))!)!
 }
 return failure(state,'guest timed out; see ','serial')!
}
fn failure(state string,prefix string,key string) !string {
 target := global('RuntimeError')!
 value := if key=='qemu.log'{named_path(state,'state',key)!}else{get(state,key)!}
 line := concatenate([literal(ah.Value(prefix))!,formatted_temporary(value,false)!])!
 cause := invoke_owned(target,[o(line)],{},[line])!
 release([invoke_owned(global('_raise_value')!,[o(cause)],{},[cause])!])!
 return literal(none_())!
}
pub fn dispatch(row map[string]ah.Value) !ah.Value {
 ids := ah.field(row,'arguments').items().map(it.text());current_builtins=ids[1]
 operation := ah.field(row,'operation').text();start := checkpoint()!
 result := execute(operation,ids) or {
  cause := err
  target := global('operator.setitem')!
  release([invoke(target,[o(ids[0]),v(ah.Value('_state'))!,o(ids[2])],{})!])!
  clean_since(start,[])!
  return cause
 }
 clean_since(start,[result])!
 return ah.Value(result)
}
fn execute(operation string,ids []string) !string {
 return match operation {
  'prepare' {prepare(ids[2])!}
  'image_paths' {image_paths(ids[2])!}
  'image' {image(ids[2])!}
  'config' {config(ids[2])!}
  'launch' {launch(ids[2])!}
  'capture' {capture(ids[2],ids[3],ids[4],ids[5],ids[6],ids[7])!}
  else {return error('unknown alloc-bench Vinix controller operation')}
 }
}
