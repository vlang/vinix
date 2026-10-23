import os

fn checked(args []string) {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
}

fn main() {
	b := 'build/android-maps/'
	task := b + 'insets238/'
	for mode in ['baseline', 'fixed'] {
		jar := if mode == 'baseline' { 'framework236-texture' } else { 'framework238-insets' }
		checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*',
			'org.jf.baksmali.Main', 'disassemble', '--classes',
			'Landroid/view/WindowInsets;,Landroid/view/WindowInsets$Builder;', '-o',
			task + 'verify-' + mode + '-smali', b + jar + '/api-impl.jar'])
	}
	checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*',
		'org.jf.baksmali.Main', 'disassemble', '--classes',
		'Lorg/vinix/bootstrap/WindowInsetsProbe;,Lorg/vinix/bootstrap/StartupProbe;',
		'-o', task + 'verify-apk-smali', b + 'insets238-apk/bootstrap.apk'])
	println('INSETS238-PROOF PREPARED actual signed APK and WindowInsets DEX')
}
