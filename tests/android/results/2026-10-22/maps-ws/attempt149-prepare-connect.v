import os
import json2

fn checked(args []string) string {
    r := os.exec(args)
    assert r.exit_code == 0, r.output
    return r.output
}

fn main() {
    dir := 'build/android-maps/connect148/runtimecore'
    os.mkdir_all(dir)!
    for path in os.walk_ext('build-support/android/runtimecore', '.v') {
        os.cp(path, dir + '/' + os.base(path))!
    }
    os.cp('build/android-maps/connect-trace148.v', dir+'/connect_trace.v')!
    generated := 'build/android-maps/connect148/generated.c'
    println(checked(['build-support/compile-v-module', dir, generated, '--arch', 'arm64', '--define', 'nofloat']))
    // The compatibility module has a static fork callback table. Use the
    // existing runtime generator's restoration before compiling this copy.
    source := os.read_file(generated)!
    prefix := '\tmemmove(runtimecore__fork_thunks, (runtimecore__ForkThunks[128]){'
    suffix := '}, sizeof(runtimecore__fork_thunks));\n'
    start := source.index(prefix) or { panic('fork initializer missing') }
    end := start + prefix.len + (source[start+prefix.len..].index(suffix) or { panic('fork initializer end missing') })
    values := source[start+prefix.len..end]
    fixed := source.replace('runtimecore__ForkThunks runtimecore__fork_thunks[128];',
        'static const runtimecore__ForkThunks runtimecore__fork_thunks[128] = {'+values+'};')
        .replace(source[start..end+suffix.len], '')
    os.write_file(generated, fixed)!
    os.cp('build/android-maps/native/libvinix-android-compat.so', 'build/android-maps/connect148/original-compat.so')!
    println(checked(['aarch64-linux-musl-gcc','-O2','-Wall','-Wextra','-Werror','-Wno-unused-function','-Wno-unused-label','-Wno-unused-parameter','-fvisibility=hidden','-shared','-fPIC','-Ibuild-support/android',generated,'-ldl','-o','build/android-maps/native/libvinix-android-compat.so']))
    source_launcher := os.read_file('build/android-maps/fields147-launcher.v')!
    os.write_file('build/android-maps/fields148-launcher.v', source_launcher)!
    println(checked(['/Users/alex/code/v/v','-nocache','-os','linux','-arch','arm64','-cc','aarch64-linux-musl-gcc','-gc','none','-o','build/android-maps/native/popular-launcher','-cflags','-O2','-ldflags','-static','build/android-maps/fields148-launcher.v']))
    mut cfg := json2.decode[map[string]json2.Any](os.read_file('build/android-maps/attempt147.json')!)!
    cfg['output'] = 'build/android-maps/attempt148'
    os.write_file('build/android-maps/attempt148.json', json2.encode(cfg, prettify:true))!
}
