import os
import json2

fn main() {
 assert os.args.len == 2
 variant := os.args[1]
 assert variant in ['baseline', 'fixed']
 base := 'build/android-maps/'
 native := base + 'native-provider218'
 os.cp(base + if variant == 'baseline' { 'framework217-observer2/api-impl.jar' } else { 'framework-attachment221/api-impl.jar' }, native + '/api-impl.jar')!
 os.cp(base + 'libnative204.so', native + '/libvinix-android-native.so')!
 mut config := os.read_file(base + 'services31.json')!.replace(base + 'service-apk/', base + 'attachment221-apk/')
 config = config.replace('build/android-native-ws/vm/boot.img', base + 'provider218-boot.img').replace('build/android-native-ws/vm/efivars.fd', base + 'provider218-efivars.fd')
 config = config.replace('"' + base + 'native"', '"' + native + '"').replace(base + 'services31', base + 'attachment221-' + variant)
 settings := json2.decode[map[string]json2.Any](config)!
 println('ATTACHMENT221 ' + variant + ' native=' + settings['native_dir']!.str())
 path := base + 'attachment221-' + variant + '.json'
 os.write_file(path, config)!
 r := os.exec([base + 'suite159', path])
 print(r.output)
 exit(r.exit_code)
}
