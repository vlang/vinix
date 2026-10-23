import os

fn checked(args []string) !string {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
	return r.output
}

fn main() {
	b := 'build/android-maps/'
	task := b + 'interpolators234/'
	for mode in ['baseline', 'fixed'] {
		jar := if mode == 'baseline' {
			'framework228-outline'
		} else {
			'framework234-interpolators'
		}
		checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*',
			'org.jf.baksmali.Main', 'disassemble', '--classes',
			'Landroid/view/animation/AnimationUtils;,Landroid/view/animation/PathInterpolator;',
			'-o', task + 'verify-' + mode + '-smali', b + jar + '/api-impl.jar'])!
	}
	checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*',
		'org.jf.baksmali.Main', 'disassemble', '--classes',
		'Lorg/vinix/bootstrap/InterpolatorProbe;,Lorg/vinix/bootstrap/InterpolatorResources;,Lorg/vinix/bootstrap/InterpolatorContext;,Lorg/vinix/bootstrap/InterpolatorParser;,Lorg/vinix/bootstrap/StartupProbe;',
		'-o', task + 'verify-apk-smali', b + 'interpolators234-apk/bootstrap.apk'])!
	mut dumps := ''
	for path in os.walk_ext(b + 'interpolators234-apk/res/anim', '.xml') {
		dumps += os.base(path) + '\n' + checked([b + '../android-native-ws/aapt2', 'dump', 'xmltree',
			b + 'interpolators234-apk/bootstrap.apk', '--file', 'res/anim/' + os.base(path)])! + '\n'
	}
	os.write_file(task + 'compiled-xml.txt', dumps)!
	println('INTERPOLATORS-PROOF-PREPARED actual APK/framework DEX and aapt-compiled XML')
}
