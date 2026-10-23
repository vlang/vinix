import os

fn checked(args []string) string {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
	return r.output
}

fn main() {
	b := 'build/android-maps/'
	task := b + 'accessibility235/'
	for mode in ['baseline', 'fixed'] {
		jar := if mode == 'baseline' { 'framework234-interpolators' } else { 'framework235-accessibility' }
		checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*', 'org.jf.baksmali.Main', 'disassemble', '--classes', 'Landroid/view/View;', '-o', task + 'verify-' + mode + '-smali', b + jar + '/api-impl.jar'])
	}
	checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*', 'org.jf.baksmali.Main', 'disassemble', '--classes', 'Lorg/vinix/bootstrap/StartupProbe;', '-o', task + 'verify-apk-smali', b + 'accessibility235-apk/bootstrap.apk'])
	os.write_file(task + 'compiled-xml.txt', checked(['build/android-native-ws/aapt2', 'dump', 'xmltree', b + 'accessibility235-apk/bootstrap.apk', '--file', 'res/layout/accessibility_traversal.xml']))!
	println('ACCESSIBILITY235-PROOF PREPARED actual signed APK + framework View DEX + compiled XML')
}
