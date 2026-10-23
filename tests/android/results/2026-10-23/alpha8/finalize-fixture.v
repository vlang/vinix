import os
import startupfixture

fn checked(args []string) ! {
 r := os.exec(args)
 if r.exit_code != 0 { return error(r.output) }
}

fn main() {
 output := os.abs_path('build/android-maps/alpha224-apk')
 java := '/opt/homebrew/opt/openjdk@25/bin/java'
 resources := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
 startupfixture.install(output, resources)!
 if os.is_file(output + '/classes.dex') { os.rm(output + '/classes.dex')! }
 checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main', 'assemble', output + '/smali', '-o', output + '/classes.dex'])!
 assert os.is_file(output + '/classes.dex'), 'smali did not produce DEX'
 checked(['zip', '-q', '-j', output + '/unsigned.apk', output + '/classes.dex'])!
 mut zip := os.new_process('zip')
 zip.set_work_folder(output)
 zip.set_args(['-q', 'unsigned.apk', 'lib/arm64-v8a/libfixture.so', 'lib/arm64-v8a/libfixture-dependency.so', 'lib/arm64-v8a/libfixture-broken.so', 'lib/arm64-v8a/libfixture-tls.so'])
 zip.run()
 zip.wait()
 assert zip.code == 0
 key := output + '/fixture.p12'
 if !os.is_file(key) {
  checked(['/opt/homebrew/opt/openjdk@25/bin/keytool', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname', 'CN=Vinix Runtime Fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])!
 }
 checked([java, '-jar', os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar'), 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', output + '/bootstrap.apk', output + '/unsigned.apk'])!
 println(output + '/bootstrap.apk')
}
