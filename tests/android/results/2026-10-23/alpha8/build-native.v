import os
import crypto.sha256
import json2

fn checked(args []string) {
 r := os.exec(args)
 assert r.exit_code == 0, r.output
}

fn main() {
 b := 'build/android-maps/'
 out := b+'native225'
 os.mkdir_all(out)!
 assert !os.exists(out+'/atlframework')
 os.cp_all(b+'native221/atlframework',out+'/atlframework',false)!
 for name in ['bitmaps.v','graphics.v','glutils.v','ndk_surfaces.v'] {
  os.cp('build-support/android/nativews/'+name,out+'/atlframework/'+name)!
 }
 for header in ['androidfw_c_api.h','sqlite3.h','stb_image.h','stb_truetype.h'] {
  os.cp(b+'native221/'+header,out+'/'+header)!
 }
 mut sources := map[string]string{}
 for path in os.walk_ext(out+'/atlframework','.v') {
  sources[os.base(path)] = sha256.sum(os.read_bytes(path)!).hex()
 }
 os.write_file(b+'native225-sources.json',json2.encode(sources,prettify:true)+'\n')!
 checked(['build-support/compile-v-module',out+'/atlframework',out+'/android-native.c','--arch','arm64'])
 runtime := 'build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
 checked(['aarch64-linux-musl-gcc','-D_GNU_SOURCE','-O2','-Wall','-Wextra','-Werror','-Wno-unused-function','-Wno-unused-label','-Wno-unused-parameter','-fvisibility=hidden','-shared','-fPIC','-I'+out,'-Wl,-z,max-page-size=65536','-Wl,--allow-shlib-undefined',out+'/android-native.c',runtime+'/usr/lib/art/libandroidfw.so','-Wl,--no-as-needed',runtime+'/usr/lib/libpng16.so.16',runtime+'/usr/lib/libsqlite3.so.0','-ldl','-lm','-o',b+'libnative225.so'])
 println('NATIVE225 '+sha256.sum(os.read_bytes(b+'libnative225.so')!).hex())
}
