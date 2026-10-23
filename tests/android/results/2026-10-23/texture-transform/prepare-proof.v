import os

fn checked(args []string) {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
}

fn main() {
	b := 'build/android-maps/'
	task := b + 'texture236/'
	for mode in ['baseline', 'fixed'] {
		jar := if mode == 'baseline' {
			'framework235-accessibility'
		} else {
			'framework236-texture'
		}
		checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*',
			'org.jf.baksmali.Main', 'disassemble', '--classes', 'Landroid/view/TextureView;', '-o',
			task + 'verify-' + mode + '-smali', b + jar + '/api-impl.jar'])
	}
	checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*',
		'org.jf.baksmali.Main', 'disassemble', '--classes',
		'Lorg/vinix/bootstrap/TextureViewTransformProbe;,Lorg/vinix/bootstrap/TransformTextureView;,Lorg/vinix/bootstrap/StartupProbe;',
		'-o', task + 'verify-apk-smali', b + 'texture236-apk/bootstrap.apk'])
	println('TEXTURE236-PROOF PREPARED actual signed APK + framework TextureView DEX')
}
