// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

fn C.PyObject_RichCompare(voidptr, voidptr, i32) voidptr
fn C.PyNumber_TrueDivide(voidptr, voidptr) voidptr
fn C.PyNumber_Rshift(voidptr, voidptr) voidptr
fn C.PyList_SetSlice(voidptr, isize, isize, voidptr) i32
@[c_extern]
__global C.PyExc_AssertionError voidptr

fn ib_sequence(values []voidptr, tuple bool) voidptr {
 if values.any(it == unsafe { nil }) { for i := values.len - 1; i >= 0; i-- { drop(values[i]) }; return unsafe { nil } }
 result := if tuple { C.PyTuple_New(values.len) } else { C.PyList_New(values.len) }
 if result == unsafe { nil } { for i := values.len - 1; i >= 0; i-- { drop(values[i]) }; return result }
 for i, value in values {
  if tuple { C.PyTuple_SetItem(result, i, value) } else { C.PyList_SetItem(result, i, value) }
 }
 return result
}
fn ib_path(left voidptr, right voidptr) voidptr {
 if left == unsafe { nil } || right == unsafe { nil } { drop(left);drop(right);return unsafe { nil } }
 result := C.PyNumber_TrueDivide(left,right);drop(left);drop(right);return result
}
fn ib_format(value voidptr, spec string) voidptr {
 if value == unsafe { nil } { return value }
 format := ib_text(spec);if format == unsafe { nil } { drop(value);return format }
 result := C.PyObject_Format(value,format);drop(value);drop(format);return result
}
fn ib_build_string(values []voidptr) voidptr {
 if values.any(it == unsafe { nil }) { for i := values.len - 1; i >= 0; i-- { drop(values[i]) };return unsafe { nil } }
 parts := C.PyTuple_New(values.len)
 if parts == unsafe { nil } { for i := values.len - 1; i >= 0; i-- { drop(values[i]) };return parts }
 for i,value in values { C.PyTuple_SetItem(parts,i,own(value)) }
 empty := ib_text('');mut result := voidptr(0)
 if empty != unsafe { nil } { result=C.PyUnicode_Join(empty,parts) }
 drop(empty);drop(parts);for i := values.len - 1; i >= 0; i-- { drop(values[i]) };return result
}
fn ib_dict_put(dictionary voidptr, name string, value voidptr) bool {
 if value == unsafe { nil } { return false }
 key := ib_text(name);if key == unsafe { nil } { drop(value);return false }
 status := C.PyDict_SetItem(dictionary,key,value);drop(key);drop(value);return status==0
}
struct IbootPreparation {
 codec &IbootCodec
 mut:
 fields [21]voidptr
}
fn (p &IbootPreparation) at(index int) voidptr { return own(p.fields[index]) }
fn (mut p IbootPreparation) put(index int, value voidptr) bool {
 if value == unsafe { nil } { return false }
 old := p.fields[index];p.fields[index]=value;drop(old);return true
}
fn (mut p IbootPreparation) finish(error_value voidptr) voidptr {
 result := C.PyTuple_New(22)
 if result == unsafe { nil } { drop(error_value);return result }
 for i,value in p.fields { p.fields[i]=unsafe { nil };C.PyTuple_SetItem(result,i,if value == unsafe { nil } { py_none() } else { value }) }
 C.PyTuple_SetItem(result,21,error_value)
 return result
}
fn (p &IbootPreparation) retire() {
 p.codec.pin(['initramfs','image','image_base','adt_base','with_aic','provisional_adt','args_base','top_of_kernel_data','segment','adt','args','files','aic','stub','loaders','name','address','data','serial','sock','command'],p.fields[..])
 for value in p.fields { drop(value) }
}
fn (mut p IbootPreparation) body(work voidptr, arguments voidptr) voidptr {
 s := p.codec
 initial := ib_attr(arguments,'initramfs');if initial == unsafe { nil } { return initial }
 include := C.PyObject_IsTrue(initial);if include<0 { drop(initial);return unsafe { nil } }
 initramfs := if include>0 { initial } else { drop(initial);ib_invoke(s.member('build','build_initramfs'),[own(work)]) }
 if !p.put(0,initramfs) { return unsafe { nil } }
 pack_target := s.member('pack','pack');if pack_target == unsafe { nil } { return pack_target }
 loader := ib_temporary_method(ib_path(s.global('APPLE_BOOT'),ib_text('build/vinix-apple-loader.bin')),'read_bytes',[])
 if loader == unsafe { nil } { drop(pack_target);return loader }
 symbol_target := s.member('pack','elf_symbol');if symbol_target == unsafe { nil } { drop(loader);drop(pack_target);return symbol_target }
 symbol := ib_invoke(symbol_target,[ib_path(s.global('APPLE_BOOT'),ib_text('build/vinix-apple-loader.elf')),ib_text('loader_end')])
 if symbol == unsafe { nil } { drop(loader);drop(pack_target);return symbol }
 kernel := ib_temporary_method(ib_attr(arguments,'kernel'),'read_bytes',[])
 if kernel == unsafe { nil } { drop(symbol);drop(loader);drop(pack_target);return kernel }
 ramdisk := ib_temporary_method(p.at(0),'read_bytes',[])
 if ramdisk == unsafe { nil } { drop(kernel);drop(symbol);drop(loader);drop(pack_target);return ramdisk }
 cmdline := ib_attr(arguments,'cmdline')
 if cmdline == unsafe { nil } { drop(ramdisk);drop(kernel);drop(symbol);drop(loader);drop(pack_target);return cmdline }
 flag := s.member('pack','FLAG_MAP_LOW_4G')
 if flag == unsafe { nil } { drop(cmdline);drop(ramdisk);drop(kernel);drop(symbol);drop(loader);drop(pack_target);return flag }
 int_target := s.global('int')
 if int_target == unsafe { nil } { drop(flag);drop(cmdline);drop(ramdisk);drop(kernel);drop(symbol);drop(loader);drop(pack_target);return int_target }
 timestamp := ib_invoke(int_target,[ib_invoke(s.member('time','time'),[])])
 if timestamp == unsafe { nil } { drop(flag);drop(cmdline);drop(ramdisk);drop(kernel);drop(symbol);drop(loader);drop(pack_target);return timestamp }
 if !p.put(1,ib_invoke(pack_target,[loader,symbol,kernel,ramdisk,cmdline,flag,timestamp])) { return unsafe { nil } }
 if !p.put(2,s.global('PHYS_BASE')) { return unsafe { nil } }
 align_target := s.global('align');if align_target == unsafe { nil } { return align_target }
 if !p.put(3,ib_invoke(align_target,[ib_binary('add',p.at(2),s.len(p.fields[1])),ib_int(0x4000)])) { return unsafe { nil } }
 no_aic := ib_attr(arguments,'no_aic');if no_aic == unsafe { nil } { return no_aic };no_aic_truth:=C.PyObject_IsTrue(no_aic);drop(no_aic);if no_aic_truth<0 { return unsafe { nil } }
 mut with_aic := no_aic_truth==0
 if with_aic { real:=ib_attr(arguments,'real_adt');if real==unsafe { nil } { return real };truth:=C.PyObject_IsTrue(real);drop(real);if truth<0 { return unsafe { nil } };with_aic=truth==0 }
 if !p.put(4,C.PyBool_FromLong(if with_aic { 1 } else { 0 })) { return unsafe { nil } }
 real:=ib_attr(arguments,'real_adt');if real==unsafe { nil } { return real };real_truth:=C.PyObject_IsTrue(real);drop(real);if real_truth<0 { return unsafe { nil } }
 provisional:=if real_truth>0 { ib_invoke(s.global('real_adt'),[]) } else { ib_invoke(s.global('build_adt'),[ib_int(0),p.at(4)]) }
 if !p.put(5,provisional) { return unsafe { nil } }
 align_args:=s.global('align');if align_args==unsafe { nil } { return align_args }
 if !p.put(6,ib_invoke(align_args,[ib_binary('add',p.at(3),s.len(p.fields[5])),ib_int(0x4000)])) { return unsafe { nil } }
 if !p.put(7,ib_binary('add',p.at(6),ib_int(0x4000))) { return unsafe { nil } }
 if !p.put(8,ib_binary('add',ib_invoke(s.global('align'),[p.at(7),ib_int(0x200000)]),ib_int(0x100000))) { return unsafe { nil } }
 real2:=ib_attr(arguments,'real_adt');if real2==unsafe { nil } { return real2 };real_truth2:=C.PyObject_IsTrue(real2);drop(real2);if real_truth2<0 { return unsafe { nil } }
 tree:=if real_truth2>0 { p.at(5) } else { ib_invoke(s.global('build_adt'),[p.at(8),p.at(4)]) }
 if !p.put(9,tree) { return unsafe { nil } }
 left:=s.len(p.fields[9]);if left==unsafe { nil } { return left };right:=s.len(p.fields[5]);if right==unsafe { nil } { drop(left);return right }
 compared:=C.PyObject_RichCompare(left,right,2);drop(left);drop(right);if compared==unsafe { nil } { return compared };equal:=C.PyObject_IsTrue(compared);drop(compared);if equal<0 { return unsafe { nil } }
 if equal==0 { no_value:=py_none();C.PyErr_SetObject(unsafe { voidptr(C.PyExc_AssertionError) },no_value);drop(no_value);return unsafe { nil } }
 boot_target:=s.global('boot_args');if boot_target==unsafe { nil } { return boot_target }
 if !p.put(10,ib_invoke(boot_target,[p.at(3),s.len(p.fields[9]),p.at(7)])) { return unsafe { nil } }
 mut files:=C.PyDict_New();if files==unsafe { nil } { return files };defer { drop(files) }
 if !ib_dict_put(files,'image.bin',ib_sequence([p.at(2),p.at(1)],true)) || !ib_dict_put(files,'adt.bin',ib_sequence([p.at(3),p.at(9)],true)) || !ib_dict_put(files,'boot_args.bin',ib_sequence([p.at(6),p.at(10)],true)) { return unsafe { nil } }
 scratch:=s.global('SCRATCH');if scratch==unsafe { nil } { return scratch }
 scratch_bytes:=ib_binary('mul',ib_bytes('\xff'),ib_int(0x400));if !ib_dict_put(files,'scratch.bin',ib_sequence([scratch,scratch_bytes],true)) { return unsafe { nil } }
 segment_address:=p.at(8)
 segment_target:=s.global('bytes');if segment_target==unsafe { nil } { drop(segment_address);return segment_target }
 segment_bytes:=ib_invoke(segment_target,[ib_sequence([s.global('SEGMENT_FILL')],false)])
 if segment_bytes==unsafe { nil } { drop(segment_address);return segment_bytes }
 segment_fill:=ib_binary('mul',segment_bytes,s.global('SEGMENT_BYTES'))
 if !ib_dict_put(files,'segment.bin',ib_sequence([segment_address,segment_fill],true)) { return unsafe { nil } }
 if !p.put(11,files) { return unsafe { nil } };files=unsafe { nil }
 if with_aic {
  if !p.put(12,ib_invoke(s.global('bytearray'),[s.global('AIC_SIZE')])) { return unsafe { nil } }
  first_target:=s.member('struct','pack_into');if first_target==unsafe { nil } { return first_target }
  first:=ib_invoke(first_target,[ib_text('<I'),p.at(12),ib_int(4),s.global('AIC_NR_IRQ')]);if first==unsafe { nil } { return first };drop(first)
  second_target:=s.member('struct','pack_into');if second_target==unsafe { nil } { return second_target }
  second:=ib_invoke(second_target,[ib_text('<I'),p.at(12),ib_int(0xc),s.global('AIC_MAX_IRQ')]);if second==unsafe { nil } { return second };drop(second)
  aic_address:=s.global('FAKE_AIC');if aic_address==unsafe { nil } { return aic_address }
  aic_target:=s.global('bytes');if aic_target==unsafe { nil } { drop(aic_address);return aic_target }
  aic_bytes:=ib_invoke(aic_target,[p.at(12)])
  if !ib_dict_put(p.fields[11],'aic.bin',ib_sequence([aic_address,aic_bytes],true)) { return unsafe { nil } }
 }
 stub_target:=s.global('build_stub');if stub_target==unsafe { nil } { return stub_target }
 if !p.put(13,ib_invoke(stub_target,[own(work),p.at(6),ib_binary('add',p.at(2),ib_int(0x800))])) { return unsafe { nil } }
 stub_text:=ib_format(p.at(13),'');if stub_text==unsafe { nil } { return stub_text }
 address_text:=ib_format(s.global('STUB'),'#x')
 loader_text:=ib_build_string([ib_text('loader,file='),stub_text,ib_text(',addr='),address_text,ib_text(',cpu-num=0,force-raw=on')])
 if !p.put(14,ib_sequence([ib_text('-device'),loader_text],false)) { return unsafe { nil } }
 items:=ib_invoke(ib_attr(p.fields[11],'items'),[]);if items==unsafe { nil } { return items };iterator:=C.PyObject_GetIter(items);drop(items);if iterator==unsafe { nil } { return iterator }
 for {
  next:=C.PyIter_Next(iterator);if next==unsafe { nil } { break }
  pair:=ib_invoke(own(s.pair),[next]);if pair==unsafe { nil } { break }
  next_name:=own(C.PyTuple_GetItem(pair,0));nested:=own(C.PyTuple_GetItem(pair,1));drop(pair);p.put(15,next_name)
  values:=ib_invoke(own(s.pair),[nested]);if values==unsafe { nil } { break }
  next_address:=own(C.PyTuple_GetItem(values,0));next_data:=own(C.PyTuple_GetItem(values,1));drop(values);p.put(16,next_address);p.put(17,next_data)
  wrote:=ib_temporary_method(ib_path(own(work),p.at(15)),'write_bytes',[p.at(17)]);if wrote==unsafe { nil } { break };drop(wrote)
  file_text:=ib_format(ib_path(own(work),p.at(15)),'');if file_text==unsafe { nil } { break }
  address:=ib_format(p.at(16),'#x')
  text:=ib_build_string([ib_text('loader,file='),file_text,ib_text(',addr='),address,ib_text(',force-raw=on')])
  if !p.put(14,ib_binary('iadd',p.at(14),ib_sequence([ib_text('-device'),text],false))) { break }
 }
 drop(iterator);if pending_error() { return unsafe { nil } }
 if !p.put(18,ib_path(own(work),ib_text('serial.log'))) { return unsafe { nil } }
 path_target:=s.global('Path');if path_target==unsafe { nil } { return path_target }
 temp_path:=ib_invoke(path_target,[ib_invoke(s.member('tempfile','gettempdir'),[])])
 if temp_path==unsafe { nil } { return temp_path }
 pid_text:=ib_format(ib_invoke(s.member('os','getpid'),[]),'')
 sock_text:=ib_build_string([ib_text('vinix-apple-boot-'),pid_text,ib_text('.sock')])
 if !p.put(19,ib_path(temp_path,sock_text)) { return unsafe { nil } }
 accel:=ib_attr(arguments,'accel');if accel==unsafe { nil } { return accel }
 ram:=s.global('RAM_BYTES');if ram==unsafe { nil } { drop(accel);return ram };shift:=ib_int(20);if shift==unsafe { nil } { drop(ram);drop(accel);return shift };megabytes:=C.PyNumber_Rshift(ram,shift);drop(ram);drop(shift)
 memory_text:=ib_build_string([ib_format(megabytes,''),ib_text('M')]);if memory_text==unsafe { nil } { drop(accel);return memory_text }
 serial_text:=ib_build_string([ib_text('file:'),ib_format(p.at(18),'')]);if serial_text==unsafe { nil } { drop(memory_text);drop(accel);return serial_text }
 socket_text:=ib_build_string([ib_text('unix:'),ib_format(p.at(19),''),ib_text(',server=on,wait=off')]);if socket_text==unsafe { nil } { drop(serial_text);drop(memory_text);drop(accel);return socket_text }
 command:=ib_sequence([ib_text('qemu-system-aarch64'),ib_text('-machine'),ib_text('virt,gic-version=3,virtualization=on'),ib_text('-cpu'),ib_text('max'),ib_text('-accel'),accel,ib_text('-smp'),ib_text('1'),ib_text('-m'),memory_text,ib_text('-display'),ib_text('none'),ib_text('-nodefaults'),ib_text('-serial'),serial_text,ib_text('-qmp'),socket_text,ib_text('-device'),ib_text('virtio-keyboard-device')],false)
 if command==unsafe { nil } { return command }
 if C.PyList_SetSlice(command,C.PyList_Size(command),C.PyList_Size(command),p.fields[14])!=0 { drop(command);return unsafe { nil } }
 if !p.put(20,command) { return unsafe { nil } }
 return py_none()
}

// Transfer named locals and the actual error to the original main frame. A body
// failure must not acquire private PyDLL carrier frames that retain work after
// later fast locals. The caller raises the same object and clears its leaf.
fn (s &IbootCodec) prepare(work voidptr, arguments voidptr) voidptr {
 mut p:=IbootPreparation{codec:s};defer { p.retire() }
 result:=p.body(work,arguments)
 if result!=unsafe { nil } { drop(result);return p.finish(py_none()) }
 cause:=caught()
 tuple:=p.finish(own(cause.value))
 if tuple==unsafe { nil } { cause.restore() }
 cause.discard()
 return tuple
}
