// SPDX-License-Identifier: GPL-2.0-or-later
module desktopprep

import androidhost as ah
import json2

fn named(mut f Frame, name string, id string) !string { return f.named(name,id)! }
fn binary(name string, left string, right ah.Value) !string { return call('operator.'+name,o(left),right)! }
fn divided(left string, right ah.Value) !string {
 result := binary('truediv',left,right) or { release([left])!;return err }
 release([left])!
 return result
}
fn path(base string, part string) !string { return binary('truediv',base,v(ah.Value(part))!)! }
fn global_path(base string, part string) !string { return divided(global(base)!,v(ah.Value(part))!)! }
fn value_attributable(owner string,name string) !string {
 value := member(owner,name) or {release([owner])!;return err}
 release([owner])!
 return value
}
fn append_text(prefix string,id string,suffix string) !string {return message(prefix,id,suffix)!}
fn command(mut f Frame, label string) ! {
 target := global('subprocess.run')!
 environ := global('os.environ')!
 compiler := method(environ,'get',[v(ah.Value('CC'))!,v(ah.Value('clang'))!],{}) or {release([environ,target])!;return err}
 release([environ])!
 sysroot_flag := append_text('--sysroot=',f.names['sysroot'],'')!
 source := global('str')!
 source_path := global_path('ROOT','tests/ios/desktop-init.c')!
 source_text := invoke_owned(source,[o(source_path)],{},[source_path])!
 library_flag := append_text('-L',f.names['sysroot'],'/lib')!
 output := global('str')!
 output_path := path(f.names['work'],'init')!
 output_text := invoke_owned(output,[o(output_path)],{},[output_path])!
 argv := call('_list',o(compiler),v(ah.Value('--target=aarch64-linux-musl'))!,o(sysroot_flag),v(ah.Value('-static'))!,v(ah.Value('-O2'))!,v(ah.Value('-fno-stack-protector'))!,v(ah.Value('-Wall'))!,v(ah.Value('-Wextra'))!,v(ah.Value('-Werror'))!,v(ah.Value('-DIOS_TEST_APP="'+label+'"'))!,o(source_text),o(library_flag),v(ah.Value('-fuse-ld=lld'))!,v(ah.Value('-o'))!,o(output_text))!
 release([compiler,sysroot_flag,source_text,library_flag,output_text])!
 release([invoke_owned(target,[o(argv)],{'check':v(ah.Value(true))!},[argv])!])!
}
fn archive(mut f Frame) ! {
 target := global('subprocess.run')!
 converter := global('str')!
 archive_path := path(f.names['work'],'rootfs.tar')!
 archive_text := invoke_owned(converter,[o(archive_path)],{},[archive_path])!
 rootfs := call('str',o(f.names['rootfs']))!
 argv := call('_list',v(ah.Value('tar'))!,v(ah.Value('--format=ustar'))!,v(ah.Value('-cf'))!,o(archive_text),v(ah.Value('-C'))!,o(rootfs),v(ah.Value('.'))!)!
 release([archive_text,rootfs])!
 env := environment_snapshot()!
 assign(env,'COPYFILE_DISABLE',literal(ah.Value('1'))!)!
 release([invoke_owned(target,[o(argv)],{'env':o(env),'check':v(ah.Value(true))!},[env,argv])!])!
}
fn assign(mapping string,key string,id string) ! { release([call('operator.setitem',o(mapping),v(ah.Value(key))!,o(id))!])! }
fn environment_snapshot() !string {
 mapping := global('os.environ')!
 return invoke_owned(resolve('_environment')!,[o(mapping)],{},[mapping])!
}
fn environment_path(work string,filename string) !string {
 converter := global('str')!
 value := path(work,filename)!
 return invoke_owned(converter,[o(value)],{},[value])!
}
fn runtime_environment(mut f Frame) !string {
 environment := environment_snapshot()!
 work := f.names['work']
 mut fields := []string{}
 defer { for i := fields.len - 1; i >= 0; i-- { release([fields[i]]) or {} } }
 for file in ['rootfs.tar','boot.img','efivars.fd','packages.tar','root.ext2'] { fields << environment_path(work,file)! }
 for value in ['64','0','0','off','0','1'] { fields << literal(ah.Value(value))! }
 converter := global('str')!
 ovmf := global_path('ROOT','boot-image/edk2-aarch64-code-2048x1536.fd')!
 fields << invoke_owned(converter,[o(ovmf)],{},[ovmf])!
 fields << literal(ah.Value('2048x1536x32'))!
 fields << append_text('-qmp unix:',f.names['qmp_path'],',server,nowait')!
 key_values := ['VINIX_INITRAMFS','VINIX_BOOT_DISK','VINIX_EFIVARS','VINIX_QEMU_PACKAGE_STORE','VINIX_QEMU_PERSIST_DISK','VINIX_QEMU_PERSIST_SIZE_MB','VINIX_QEMU_HOST_SOURCE','VINIX_QEMU_NETWORK','VINIX_QEMU_AUDIO','VINIX_QEMU_CLIPBOARD','VINIX_KEEP_TEMP_BOOT_DISK','VINIX_OVMF_CODE','VINIX_QEMU_RESOLUTION','VINIX_QEMU_EXTRA'].map(v(ah.Value(it)) or {return err})
 keys := call('_tuple',...key_values)!
 mut arguments := [o(environment),o(keys)]
 arguments << fields.map(o(it))
 result := invoke_owned(resolve('_fill_environment')!,arguments,{},[keys])!
 release([environment])!
 return result
}
fn prepare(operation string, mut f Frame) !string {
 directory := f.names['directory']
 work := call('Path',o(directory))!
 rootfs := divided(call('Path',o(directory))!,v(ah.Value('rootfs'))!)!
 named(mut f,'work',work)!
 named(mut f,'rootfs',rootfs)!
 for item in ['run','root','sbin','usr/bin','usr/share/vinix/icons','dev','tmp','proc','sys'] {
  name := named(mut f,'name',literal(ah.Value(item))!)!
  receiver := binary('truediv',rootfs,o(name))!
  perform_temporary_method(receiver,'mkdir',[],{'parents':v(ah.Value(true))!,'exist_ok':v(ah.Value(true))!})!
  f.clean()!
 }
 copier := global('shutil.copy2')!
 desktop := member(f.names['args'],'desktop')!
 destination := path(rootfs,'usr/bin/vinix-desktop')!
 release([invoke_owned(copier,[o(desktop),o(destination)],{},[destination,desktop])!])!
 tree_copier := global('shutil.copytree')!
 source := path(f.names['build'],'staging/usr')!
 target := path(rootfs,'usr')!
 release([invoke_owned(tree_copier,[o(source),o(target)],{'dirs_exist_ok':v(ah.Value(true))!,'symlinks':v(ah.Value(true))!},[target,source])!])!
 path_factory := global('Path')!
 environ := global('os.environ')!
 getter := member(environ,'get')!
 release([environ])!
 key := match operation {'n64_prepare' {'VINIX_N64_TEST_SYSROOT'} 'ps2_prepare' {'VINIX_PS2_TEST_SYSROOT'} else {'VINIX_PS1_TEST_SYSROOT'}}
 default_path := global_path('ROOT','build-aarch64-userland/sysroot')!
 input := invoke_owned(getter,[v(ah.Value(key))!,o(default_path)],{},[default_path])!
 sysroot := named(mut f,'sysroot',invoke_owned(path_factory,[o(input)],{},[input])!)!
 label := match operation {'n64_prepare' {'Nintendo 64'} 'ps2_prepare' {'PlayStation 2'} else {'PlayStation'}}
 command(mut f,label)!
 archive(mut f)!
 environment := runtime_environment(mut f)!
 named(mut f,'environment',environment)!
 for item in ['VINIX_QEMU_PERSIST','VINIX_QEMU_OVERLAY','VINIX_QEMU_ROOT_DISK'] {
  name := named(mut f,'name',literal(ah.Value(item))!)!
  perform_method(environment,'pop',[o(name),v(ah.Value(json2.Null{}))!],{})!
  f.clean()!
 }
 return call('_tuple',o(work),o(rootfs),o(f.names['name']),o(sysroot),o(environment))!
}
fn forget_inputs(pins string) ! {
 for name in ['directory','args','build','qmp_path'] { release([call('operator.delitem',o(pins),v(ah.Value(name))!)!])! }
}
pub fn dispatch(row map[string]ah.Value) !ah.Value {
 ids := ah.field(row,'arguments').items().map(it.text())
 current_builtins = ids[1]
 mut f := Frame{start:checkpoint()!,pins:ids[0],order:['work','rootfs','name','sysroot','environment']}
 for key in ['directory','args','build','qmp_path'] { f.named(key,get(ids[2],key)!)! }
 result := prepare(ah.field(row,'operation').text(),mut f) or {f.pin()!;forget_inputs(f.pins)!;clean_since(f.start,[f.pins])!;return err}
 forget_inputs(f.pins)!
 clean_since(f.start,[result])!
 return ah.Value(result)
}
