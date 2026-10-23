import os

fn checked(args []string) {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
}

fn main() {
	b := 'build/android-maps/'
	task := b + 'blur241/'
	for mode in ['baseline', 'fixed'] {
		jar := if mode == 'baseline' { 'framework240-date-ranges' } else { 'framework241-blur-styles' }
		checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*',
			'org.jf.baksmali.Main', 'disassemble', '--classes',
			'Landroid/graphics/BlurMaskFilter;,Landroid/graphics/BlurMaskFilter$Blur;', '-o',
			task + 'verify-' + mode + '-smali', b + jar + '/api-impl.jar'])
	}
	checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*',
		'org.jf.baksmali.Main', 'disassemble', '--classes',
		'Lorg/vinix/bootstrap/BlurStylesProbe;,Lorg/vinix/bootstrap/StartupProbe;',
		'-o', task + 'verify-apk-smali', b + 'blur241-apk/bootstrap.apk'])
	println('BLUR-STYLES PROOF PREPARED actual signed APK and BlurMaskFilter DEX')
}
