import os
import crypto.sha256
import json2
fn checked(args []string) { r:=os.exec(args); assert r.exit_code==0,r.output }
fn main() {
 b := 'build/android-maps/'
 out := b+'native221'
 os.mkdir_all(out)!
 if !os.is_dir(out+'/atlframework') { os.cp_all(b+'native218/atlframework',out+'/atlframework',false)! }
 for header in ['androidfw_c_api.h','sqlite3.h','stb_image.h','stb_truetype.h'] { os.cp(b+'native218/'+header,out+'/'+header)! }
 os.write_file(out+'/atlframework/diagnostic_objects.v','@[translated]\nmodule atlframework\n__global ws_object_samples i32\nfn ws_trace_objects(e voidptr) {\n unsafe {\n if C.getenv(c\'VINIX_ANDROID_TRACE_OBJECT_CLASS\') == nil || ws_object_samples >= 12 || pending(e) { return }\n ws_object_samples++\n ws_maps_queue_snapshot(e)\n }\n}\n')!
 mut probe:=os.read_file(b+'queue220.v')!
 probe=probe.all_before("  looper :=")+' }\n}\n'
 probe=probe.replace("Check(slot(e,16))(e) }", "Check(slot(e,16))(e); ExceptionClear(slot(e,17))(e) }")
 os.write_file(out+'/atlframework/queue219.v',probe)!
 mut sources:=map[string]string{}
 for path in os.walk_ext(out+'/atlframework','.v') { sources[os.base(path)]=sha256.sum(os.read_bytes(path)!).hex() }
 os.write_file(b+'native221-sources.json',json2.encode(sources,prettify:true)+'\n')!
 checked(['build-support/compile-v-module',out+'/atlframework',out+'/android-native.c','--arch','arm64'])
 runtime:='build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
 checked(['aarch64-linux-musl-gcc','-D_GNU_SOURCE','-O2','-Wall','-Wextra','-Werror','-Wno-unused-function','-Wno-unused-label','-Wno-unused-parameter','-fvisibility=hidden','-shared','-fPIC','-I'+out,'-Wl,-z,max-page-size=65536','-Wl,--allow-shlib-undefined',out+'/android-native.c',runtime+'/usr/lib/art/libandroidfw.so','-Wl,--no-as-needed',runtime+'/usr/lib/libpng16.so.16',runtime+'/usr/lib/libsqlite3.so.0','-ldl','-lm','-o',b+'libnative221.so'])
 println('NATIVE221 '+sha256.sum(os.read_bytes(b+'libnative221.so')!).hex())
}
