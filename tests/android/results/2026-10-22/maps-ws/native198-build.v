import os
import json2
import crypto.sha256
fn checked(args []string) { r:=os.exec(args); assert r.exit_code==0,r.output }
fn main() {
 out := 'build/android-maps/native'
 for name in ['ws_attachment.v','diagnostic_views.v','runtime.v','affine.v','graphics.v','canvases.v','paths.v','bitmaps.v'] { os.cp('build-support/android/nativews/'+name,out+'/atlframework/'+name)! }
 os.cp('build/android-maps/graph189.v',out+'/atlframework/diagnostic_objects.v')!
 os.write_file(out+'/atlframework/diagnostics.v',os.read_file('build-support/android/nativews/diagnostics.v')!.replace('ws_debug_tree(e, root, 0)','ws_debug_tree(e, root, 0)\n\t\tws_trace_objects(e)'))!
 os.write_file(out+'/atlframework/ws_generated.v',os.read_file(out+'/atlframework/ws_generated.v')!.replace('draw := ws_draw_state(); draw.transform.sx *= p1; draw.transform.sy *= p2', 'ws_scale(p1,p2)'))!
 os.cp('build-support/android/atlframework/recreate.v',out+'/atlframework/recreate.v')!
 mut sources := map[string]string{}
 for path in os.walk_ext(out+'/atlframework','.v') { sources[os.base(path)] = sha256.sum(os.read_bytes(path)!).hex() }
 os.write_file('build/android-maps/native198-sources.json',json2.encode(sources,prettify:true)+'\n')!
 checked(['build-support/compile-v-module',out+'/atlframework',out+'/android-native.c','--arch','arm64'])
 runtime:='build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
 checked(['aarch64-linux-musl-gcc','-D_GNU_SOURCE','-O2','-Wall','-Wextra','-Werror','-Wno-unused-function','-Wno-unused-label','-Wno-unused-parameter','-fvisibility=hidden','-shared','-fPIC','-I'+out,'-Wl,-z,max-page-size=65536','-Wl,--allow-shlib-undefined',out+'/android-native.c',runtime+'/usr/lib/art/libandroidfw.so','-Wl,--no-as-needed',runtime+'/usr/lib/libpng16.so.16',runtime+'/usr/lib/libsqlite3.so.0','-ldl','-lm','-o','build/android-maps/libnative198.so'])
 println('NATIVE198 '+sha256.sum(os.read_bytes('build/android-maps/libnative198.so')!).hex())
}
