import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/procns-20261016'
const compiler = '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v'
fn command(program string,args []string,folder string,output string) !int {
 mut p:=os.new_process(program); p.set_args(args); p.set_work_folder(folder);p.set_redirect_stdio_merged();p.run();data:=p.stdout_slurp();p.wait();code:=p.code;p.close()
 os.write_file(output,data)!;os.write_file(output+'.status',code.str()+'\n')!;return code
}
fn git(folder string,args []string) string {
 mut p:=os.new_process('git');p.set_args(['-C',folder,...args]);p.set_redirect_stdio_merged();p.run();data:=p.stdout_slurp();p.wait();code:=p.code;p.close();assert code==0,data;return data.trim_space()
}
fn main(){
 for key,value in {'V':compiler,'VINIX_V_COMPILER':compiler,'VINIX_AARCH64_SYSROOT':area+'/sdk','CC':area+'/arm-cc','TMPDIR':area+'/tmp'} {os.setenv(key,value,true)}
 phase:=os.args[1]
 if phase=='auditbase' {
  base:=os.read_file(area+'/base.txt')!.trim_space();tree:=area+'/audit-base'
  git(root,['worktree','add','--detach','--no-checkout',tree,base])
  git(tree,['sparse-checkout','set','kernel','build-support','tests/linuxkpi','tests/native-generators','tests/kernel-allocs','tests/scheduler-qos','tools/sourcecommand','tools/linux-compat','docs'])
  git(tree,['checkout','--detach',base])
  for name in ['freestnd-c-hdrs','cc-runtime','cc-runtime-aarch64','cc-runtime-x86_64','c/flanterm','c/nanoprintf.h','c/lwip','c/uacpi'] {os.symlink(root+'/kernel/'+name,tree+'/kernel/'+name)!}
  return
 }
 if phase=='prepare' {
  assert !os.exists(area+'/base.txt');base:=git(root,['rev-parse','HEAD']);os.write_file(area+'/base.txt',base+'\n')!
  os.mkdir_all(area+'/states')!;os.mkdir_all(area+'/tmp')!
  os.symlink('/Users/alex/.cache/vinix-linux-compat/tidfault-20261015/sdk',area+'/sdk')!
  os.write_file(area+'/arm-cc.v',os.read_file('/Users/alex/.cache/vinix-linux-compat/clonecgshare-20261016/arm-cc.v')!.replace('clonecgshare-20261016','procns-20261016'))!
  for suffix in ['arm','x86'] {
   tree:=area+'/kernel-'+suffix
   git(root,['worktree','add','--detach','--no-checkout',tree,base])
   git(tree,['sparse-checkout','set','kernel','build-support','tests/linuxkpi','tests/native-generators','tests/kernel-allocs','tests/scheduler-qos','tools/sourcecommand','tools/linux-compat','docs'])
   git(tree,['checkout','--detach',base])
   for name in ['freestnd-c-hdrs','cc-runtime','cc-runtime-aarch64','cc-runtime-x86_64','c/flanterm','c/nanoprintf.h','c/lwip','c/uacpi'] {os.symlink(root+'/kernel/'+name,tree+'/kernel/'+name)!}
   os.mkdir_all(area+'/objects-'+suffix)!;os.symlink(area+'/objects-'+suffix,tree+'/kernel/obj')!
  }
  println('Frozen procfs base '+base);return
 }
 if phase=='build' {
  suffix:=os.args[2];version:=os.args[3];assert suffix in ['arm','x86'] && version in ['before','after','revised']
  tree:=area+'/kernel-'+suffix
  if version!='before' {for path in ['fs/procfs.v','fs/namespaces.v'] {os.cp(root+'/kernel/'+path,tree+'/kernel/'+path)!}}
  tracking:=os.args.len>4 && os.args[4]=='track'
  mp:=os.args.len>5 && os.args[5]=='mp'
  mut args:= ['ARCH='+if suffix=='arm' {'aarch64'}else{'x86_64'},'V='+compiler,'CC=clang','PROD=true','-j4','LIMINE_MP='+if mp{'1'}else{'0'},'ALLOC_TRACK='+if tracking{'1'}else{'0'}]
  if suffix=='x86' {args << 'LD_X86_64=ld.lld'}
  label:=version+'-'+suffix+if tracking{'-track'}else{'-prod'}+if mp{'-mp'}else{''}
  code:=command('make',args,tree+'/kernel',area+'/build-'+label+'.log')!;assert code==0,'build failed '+label
  os.mkdir_all(area+'/'+label+'/kernel/bin')!;os.cp(tree+'/kernel/bin/vinix',area+'/'+label+'/kernel/bin/vinix')!;os.cp(tree+'/kernel/obj/blob.c',area+'/'+label+'/blob.c')!
  println(label+' build: PASS');return
 }
 if phase=='smpbase' {
  tree:=area+'/audit-base'
  code:=command('make',['ARCH=aarch64','V='+compiler,'CC=clang','PROD=true','-j4','LIMINE_MP=1','ALLOC_TRACK=1'],tree+'/kernel',area+'/build-before-arm-track-mp.log')!;assert code==0
  os.mkdir_all(area+'/before-arm-track-mp/kernel/bin')!;os.cp(tree+'/kernel/bin/vinix',area+'/before-arm-track-mp/kernel/bin/vinix')!;os.cp(tree+'/kernel/obj/blob.c',area+'/before-arm-track-mp/blob.c')!
  return
 }
 panic('unknown phase')
}
