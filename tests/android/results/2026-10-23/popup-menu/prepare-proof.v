import os

fn checked(args []string) string {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
	return r.output
}

fn main() {
	b := 'build/android-maps/'
	task := b + 'popup243/'
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	for mode in ['baseline', 'fixed'] {
		jar := if mode == 'baseline' { 'framework242-canvas-save' } else { 'framework243-popup-menus' }
		checked([java, '-cp', 'build/android-framework/tools/*', 'org.jf.baksmali.Main',
			'disassemble', '--classes',
			'Landroid/widget/PopupMenu;,Landroid/widget/PopupMenu$MenuImpl;,Landroid/view/VinixMenu;,Landroid/view/VinixMenuItem;,Landroid/widget/VinixPopupMenuClick;,Landroid/widget/VinixPopupMenuDismiss;,Landroid/view/MenuInflater;',
			'-o', task + 'verify-' + mode + '-smali', b + jar + '/api-impl.jar'])
	}
	checked([java, '-cp', 'build/android-framework/tools/*', 'org.jf.baksmali.Main',
		'disassemble', '--classes',
		'Lorg/vinix/bootstrap/Main;,Lorg/vinix/bootstrap/PopupProbe;,Lorg/vinix/bootstrap/PopupContext;,Lorg/vinix/bootstrap/ItemListener;',
		'-o', task + 'verify-apk-smali', b + 'popup243-apk/probe.apk'])
	os.write_file(task + 'menu-resource-dump.txt', checked(['build/android-native-ws/aapt2',
		'dump', 'xmltree', b + 'popup243-apk/probe.apk', '--file', 'res/menu/popup.xml']))!
	println('POPUP-MENU PROOF PREPARED exact signed APK/framework DEX and compiled menu XML')
}
