import os

fn checked(args []string) {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
}

fn main() {
	b := 'build/android-maps/'
	task := b + 'canvas242/'
	for mode in ['baseline', 'fixed'] {
		jar := if mode == 'baseline' { 'framework241-blur-styles' } else { 'framework242-canvas-save' }
		checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*',
			'org.jf.baksmali.Main', 'disassemble', '--classes',
			'Landroid/graphics/Canvas;,Landroid/graphics/VinixPictureCanvas;,Landroid/graphics/VinixPictureCommand;,Landroid/graphics/VinixPictureCommand54;,Landroid/graphics/RecordingCanvas;', '-o',
			task + 'verify-' + mode + '-smali', b + jar + '/api-impl.jar'])
	}
	checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*',
		'org.jf.baksmali.Main', 'disassemble', '--classes',
		'Lorg/vinix/bootstrap/CanvasSaveFlagsProbe;,Lorg/vinix/bootstrap/SaveLayerForwardCanvas;,Lorg/vinix/bootstrap/StartupProbe;',
		'-o', task + 'verify-apk-smali', b + 'canvas242-apk/bootstrap.apk'])
	println('CANVAS-SAVE-FLAGS PROOF PREPARED actual signed APK and Canvas DEX')
}
