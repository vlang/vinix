// SPDX-License-Identifier: GPL-2.0-or-later
module kernelvinixcore

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
fn selected_path(state string,name string) !string {
 factory := global('Path')!
 which := global('shutil.which') or {release([factory])!;return err}
 value := arg(state,name) or {release([which,factory])!;return err}
 found := invoke_owned(which,[o(value)],{},[value]) or {release([factory])!;return err}
 mut selected := found
 if !truth(found)! {release([found])!;selected=arg(state,name)!}
 result := invoke_owned(factory,[o(selected)],{},[selected])!
 return temporary_method(result,'resolve',[],{})!
}
fn prepare(state string) !string {
 put(state,'kernel',temporary_method(arg(state,'kernel')!,'resolve',[],{})!)!
 root := global('ROOT')!
 source := path(root,'kernel/heapbench/core.v') or {release([root])!;return err}
 release([root])!
 put(state,'source',source)!
 put(state,'qemu',selected_path(state,'qemu')!)!
 put(state,'cc',selected_path(state,'cc')!)!
 supplied := arg(state,'firmware')!
 mut firmware := supplied
 if !truth(supplied)! {
  release([supplied])!
  qemu := get(state,'qemu')!
  first := member(qemu,'parent') or {release([qemu])!;return err}
  release([qemu])!
  second := member(first,'parent') or {release([first])!;return err}
  release([first])!
  firmware=path(second,'share/qemu/edk2-x86_64-code.fd') or {release([second])!;return err}
  release([second])!
 }
 put(state,'firmware',temporary_method(firmware,'resolve',[],{})!)!
 mut required := []string{}
 for name in ['kernel','source','qemu','cc','firmware'] {required<<get(state,name)!}
 list_ := list_owned(required)!
 iterator := call('_ITER',o(list_)) or {release([list_])!;return err}
 release([list_])!
 for {
  row := callback('next',{'owner':ah.Value(iterator)})!.object()
  if ah.field(row,'done') as bool {break}
  put(state,'path',ah.field(row,'value').text())!
  if !tested(state_method(state,'path','is_file',[],{})!)! {
   parser_error(state,'required input missing: ',get(state,'path')!) or {release([iterator])!;return err}
  }
 }
 release([iterator])!
 runner := global('subprocess.check_output')!
 executable := string_state(state,'cc') or {release([runner])!;return err}
 argv := list_owned([executable,literal(ah.Value('--version'))!]) or {release([runner])!;return err}
 put(state,'compiler',invoke_owned(runner,[o(argv)],{'text':v(ah.Value(true))!},[argv])!)!
 lower := state_method(state,'compiler','lower',[],{})!
 clang := call('operator.contains',o(lower),v(ah.Value('clang'))!) or {release([lower])!;return err}
 release([lower])!
 mut wrong := tested(clang)!
 if !wrong {
  lowered := state_method(state,'compiler','lower',[],{})!
  gcc := call('operator.contains',o(lowered),v(ah.Value('gcc'))!) or {release([lowered])!;return err}
  release([lowered])!
  wrong = !tested(gcc)!
 }
 if wrong {
  parser := get(state,'parser')!
  target := member(parser,'error') or {release([parser])!;return err}
  release([parser])!
  release([invoke(target,[v(ah.Value('--cc must be genuine GNU GCC'))!],{})!])!
 }
 put(state,'state',temporary_method(arg(state,'state_dir')!,'resolve',[],{})!)!
 perform_state_method(state,'state','mkdir',[],{'parents':v(ah.Value(true))!,'exist_ok':v(ah.Value(false))!})!
 put(state,'generated',named_path(state,'state','heap_benchmark.c')!)!
 generator := global('subprocess.run')!
 mut args := []string{}
 args<<literal(ah.Value('python3'))!
 converter := global('str')!
 root_ := global('ROOT')!
 script := path(root_,'tests/alloc-bench/compile-v-sampler.py') or {release([root_,converter,generator])!;return err}
 release([root_])!
 args<<invoke_owned(converter,[o(script)],{},[script])!
 args<<string_state(state,'generated')!
 command := list_owned(args)!
 release([invoke_owned(generator,[o(command)],{'check':v(ah.Value(true))!},[command])!])!
 put(state,'rootfs',named_path(state,'state','rootfs')!)!
 for name in ['sbin','dev','tmp','proc'] {
  put(state,'name',literal(ah.Value(name))!)!
  directory := named_path(state,'rootfs',name)!
  release([temporary_method(directory,'mkdir',[],{'parents':v(ah.Value(true))!,'exist_ok':v(ah.Value(true))!})!])!
 }
 put(state,'init_source',named_path(state,'state','init.c')!)!
 writer := state_method_target(state,'init_source','write_text')!
 value := call('_init_text') or {release([writer])!;return err}
 release([invoke_owned(writer,[o(value)],{},[value])!])!
 builder := global('subprocess.run')!
 mut compiler_args := []string{}
 compiler_args<<string_state(state,'cc')!
 for value_ in ['-std=c11','-O2','-static','-Wall','-Wextra','-Werror'] {compiler_args<<literal(ah.Value(value_))!}
 compiler_args<<string_state(state,'init_source')!
 compiler_args<<literal(ah.Value('-o'))!
 output_converter := global('str')!
 destination := named_path(state,'rootfs','sbin/init') or {release([output_converter,builder])!;return err}
 compiler_args<<invoke_owned(output_converter,[o(destination)],{},[destination])!
 build_argv := list_owned(compiler_args)!
 release([invoke_owned(builder,[o(build_argv)],{'check':v(ah.Value(true))!},[build_argv])!])!
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
 mut pending := true
 defer {
  if pending {
   retire_parts(consumed) or {}
   release([environ,factory]) or {}
  }
 }
 for pair in [['VINIX_AMD64_ISO_BUILD_DIR','iso-build'],['VINIX_AMD64_KERNEL',''],['VINIX_AMD64_INITRAMFS',''],['VINIX_AMD64_ISO','']] {
  converter := global('str')!
  value := if pair[0]=='VINIX_AMD64_ISO_BUILD_DIR' {
   named_path(state,'state',pair[1]) or {release([converter])!;return err}
  }else{
   get(state,match pair[0]{'VINIX_AMD64_KERNEL'{'kernel'}'VINIX_AMD64_INITRAMFS'{'initramfs'}else{'iso'}}) or {release([converter])!;return err}
  }
  text_ := invoke_owned(converter,[o(value)],{},[value])!
  options[pair[0]]=o(text_);consumed<<text_
 }
 mut cleanup := consumed.reverse();cleanup<<environ
 environment := invoke_owned(factory,[o(environ)],options,cleanup) or {pending=false;consumed.clear();return err}
 pending=false;consumed.clear()
 put(state,'env',environment)!
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
fn setitem(id string,key string,value string) ! { put(id,key,value)! }
fn raise_value(target string,message string) !string {
 error_id := invoke_owned(target,[o(message)],{},[message])!
 release([invoke_owned(global('_raise_value')!,[o(error_id)],{},[error_id])!])!
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

fn config(state string) !string {
 put(state,'kernel_hash',hash_state(state,'boot_kernel')!)!
 actual := get(state,'kernel_hash')!
 expected := hash_state(state,'kernel') or {release([actual])!;return err}
 unequal := call('operator.ne',o(actual),o(expected)) or {release([actual,expected])!;return err}
 release([actual,expected])!
 if tested(unequal)! {return raise_value(global('RuntimeError')!,literal(ah.Value('kernel embedded in completed ISO differs from supplied kernel'))!)!}
 put(state,'serial',named_path(state,'state','serial.log')!)!
 put(state,'machine',literal(ah.Value('q35,vmport=off'))!)!
 put(state,'accelerator',literal(ah.Value('tcg,thread=single,tb-size=1024'))!)!
 put(state,'cpu',literal(ah.Value('Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt'))!)!
 mut parts := []string{}
 parts<<formatted_temporary(arg(state,'cpus')!,false)!
 parts<<literal(ah.Value(',sockets=1,cores='))!
 parts<<formatted_temporary(arg(state,'cpus')!,false)!
 parts<<literal(ah.Value(',threads=1'))!
 put(state,'smp',concatenate(parts)!)!
 mut values := []string{}
 values<<string_state(state,'qemu')!
 for pair in [['-machine','machine'],['-accel','accelerator'],['-cpu','cpu'],['-smp','smp']] {values<<literal(ah.Value(pair[0]))!;values<<get(state,pair[1])!}
 for value in ['-m','4096','-display','none','-monitor','none','-drive'] {values<<literal(ah.Value(value))!}
 values<<concatenate([literal(ah.Value('if=pflash,format=raw,readonly=on,file='))!,formatted_temporary(get(state,'firmware')!,false)!])!
 values<<literal(ah.Value('-cdrom'))!;values<<string_state(state,'iso')!
 values<<literal(ah.Value('-serial'))!;values<<concatenate([literal(ah.Value('file:'))!,formatted_temporary(get(state,'serial')!,false)!])!
 values<<literal(ah.Value('-no-reboot'))!
 put(state,'command',list_owned(values)!)!
 mut fields := []string{}
 mut field_values := []string{}
 // A dictionary display evaluates all RHS values before BUILD_MAP. Preserve
 // that stack and its reverse failure retirement until construction finishes.
 defer { retire_parts(field_values) or {} }
 version_target := global('subprocess.check_output')!
 executable := string_state(state,'qemu')!
 version_argv := list_owned([executable,literal(ah.Value('--version'))!])!
 version := invoke_owned(version_target,[o(version_argv)],{'text':v(ah.Value(true))!},[version_argv])!
 split := temporary_method(version,'splitlines',[],{})!
 first := item(split,v(ah.Value(0))!) or {release([split])!;return err}
 release([split])!
 fields<<'qemu_version';field_values<<first
 for name in ['machine','accelerator','cpu','smp'] {fields<<name;field_values<<get(state,name)!}
 fields<<'memory_mb';field_values<<literal(ah.Value(4096))!
 fields<<'source_sha256';field_values<<hash_state(state,'generated')!
 hasher := global('hashlib.sha256')!
 root := global('ROOT')!
 header := path(root,'kernel/c/heap_benchmark_v.h') or {release([root,hasher])!;return err}
 release([root])!
 fields<<'sampler_header_sha256';field_values<<hash_file(hasher,header)!
 fields<<'sampler_language';field_values<<literal(ah.Value('V'))!
 fields<<'kernel_sha256';field_values<<get(state,'kernel_hash')!
 fields<<'kernel_verification';field_values<<literal(ah.Value('extracted from completed ISO and matched supplied kernel'))!
 fields<<'compile_flags';field_values<<global('FLAGS')!
 fields<<'platform_compile_flags';field_values<<list_owned([literal(ah.Value('-fno-PIC'))!,literal(ah.Value('-mcmodel=kernel'))!])!
 fields<<'sampler_build_provenance';field_values<<literal(ah.Value('caller must verify supplied kernel used the recorded source and flags'))!
 fields<<'execution_context';field_values<<literal(ah.Value('pre-scheduler'))!
 fields<<'argv';field_values<<get(state,'command')!
 mut pairs := []string{}
 defer { retire_parts(pairs) or {} }
 for i,name in fields {pairs<<call('_tuple',v(ah.Value(name))!,o(field_values[i]))!}
 dict_target := global('_named')!
 dict_ := invoke_owned(dict_target,pairs.map(o(it)),{},pairs.reverse())!
 pairs.clear()
 retire_parts(field_values)!
 field_values.clear()
 put(state,'config',dict_)!
 dest := named_path(state,'state','config.json')!
 writer := member(dest,'write_text') or {release([dest])!;return err}
 release([dest])!
 serializer := global('json.dumps')!
 cfg := get(state,'config')!
 encoded := invoke_owned(serializer,[o(cfg)],{'indent':v(ah.Value(2))!},[cfg])!
 line := added(encoded,v(ah.Value('\n'))!)!
 release([invoke_owned(writer,[o(line)],{},[line])!])!
 printer := global('print')!
 message := concatenate([literal(ah.Value('Booting kernel sampler; output: '))!,formatted_temporary(get(state,'serial')!,false)!])!
 print_owned(printer,message,true)!
 return literal(none_())!
}
fn capture(state string,snapshot string,failed string,lines string) !string {
 clock := call('time.monotonic')!
 timeout := arg(state,'timeout')!
 deadline := call('operator.add',o(clock),o(timeout)) or {release([clock,timeout])!;return err}
 release([clock,timeout])!
 put(state,'deadline',deadline)!
 for {
  now := call('time.monotonic')!;until := get(state,'deadline')!
  comparison := call('operator.lt',o(now),o(until)) or {release([now,until])!;return err}
  release([now,until])!
  if !tested(comparison)! {break}
  value := if tested(state_method(state,'serial','exists',[],{})!)! {state_method(state,'serial','read_text',[],{'errors':v(ah.Value('replace'))!})!}else{literal(ah.Value(''))!}
  // Publish the actual closure cell before retiring the prior named output.
  release([callback('function',{'target':ah.Value(snapshot),'call':ah.Value(true),'args':ah.Value([o(value)]),'kwargs':ah.Value(map[string]ah.Value{})})!.text()])!
  put(state,'output',value)!
  any_ := global('any')!
  candidates := generator_call(failed) or {release([any_])!;return err}
  if tested(invoke_owned(any_,[o(candidates)],{},[candidates])!)! {return failure(state,'guest failed; see ','serial')!}
  if contains(state,'KALLOC-DONE')! {
   runner := global('subprocess.run')!
   mut args := []string{}
   converter := global('str')!
   path_factory := global('Path')!
   file := global('__file__')!
   path_ := invoke_owned(path_factory,[o(file)],{},[file])!
   validator := temporary_method(path_,'with_name',[v(ah.Value('validate-kernel'))!],{})!
   args<<invoke_owned(converter,[o(validator)],{},[validator])!
   args<<literal(ah.Value('--stdin'))!;args<<literal(ah.Value('vinix'))!
   command := list_owned(args)!
   output := get(state,'output')!
   release([invoke_owned(runner,[o(command)],{'input':o(output),'text':v(ah.Value(true))!,'check':v(ah.Value(true))!,'capture_output':v(ah.Value(true))!},[output,command])!])!
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
  perform('time.sleep',v(ah.Value(ah.Number{'0.1'}))!)!
 }
 return failure(state,'kernel sampler timed out; see ','serial')!
}
fn failure(state string,prefix string,key string) !string {
 target := global('RuntimeError')!
 value := if key=='qemu.log'{named_path(state,'state',key)!}else{get(state,key)!}
 line := concatenate([literal(ah.Value(prefix))!,formatted_temporary(value,false)!])!
 return raise_value(target,line)!
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
  'capture' {capture(ids[2],ids[3],ids[4],ids[5])!}
  else {return error('unknown alloc-bench kernel Vinix controller operation')}
 }
}
