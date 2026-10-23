import os

fn checked(args []string) {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
}

fn main() {
	b := 'build/android-maps/'
	task := b + 'outline228/'
	config := task + 'fixed.json'
	os.write_file(config, os.read_file(config)!.replace('"startup_seconds": 40', '"startup_seconds": 120'))!
	for variant, jar in {
		'baseline': 'framework227-canvas-z/api-impl.jar'
		'fixed':    'framework228-outline/api-impl.jar'
	} {
		checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*',
			'org.jf.baksmali.Main', 'disassemble', '--classes',
			'Landroid/graphics/RenderNode;,Landroid/graphics/Canvas;,Landroid/atl/GskCanvas;',
			'-o', task + 'verify-' + variant + '-smali', b + jar])
	}
	checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*',
		'org.jf.baksmali.Main', 'disassemble', '--classes',
		'Lorg/vinix/bootstrap/RenderNodeOutlineProbe;,Lorg/vinix/bootstrap/StartupProbe;', '-o',
		task + 'verify-apk-smali', b + 'outline228-apk/bootstrap.apk'])
	println('OUTLINE-PROOF-PREPARED actual framework and APK DEX disassembled; fixed startup120s')
}
