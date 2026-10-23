import os
import crypto.sha256
import json2
import compress.gzip

struct Receipt {
	artifacts map[string]string
	inputs    map[string]string
	scope     string
}

fn read_gzip(path string) !string { return gzip.decompress(os.read_bytes(path)!)!.bytestr() }

fn digest(source string) string { return sha256.sum(source.bytes()).hex() }

fn main() {
	out := os.dir(@FILE)
	r := json2.decode[Receipt](os.read_file(out + '/receipt.json')!)!
	for name, hash in r.artifacts {
		assert sha256.sum(os.read_bytes(out + '/' + name)!).hex() == hash, name
	}
	assert r.inputs['build/android-maps/popup243-apk/probe.apk'] == 'f1956192a8e340d7c53c196a6082eb8f8c7df413a1e7360f9906e9b74a233969'
	assert r.inputs['build/android-maps/framework242-canvas-save/api-impl.jar'] == '8e6eb74104871e7b3391a75bd5160c0b74bb1951a45ab9b6626a26e46c965f74'
	assert r.inputs['build/android-maps/framework243-popup-menus/api-impl.jar'] == '0eb5f294900d7ef1683c7444c97ebd59d96d6dc7e2c372731e358ce9c6bde0cc'
	assert r.inputs['build/android-maps/libnative235.so'] == '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9'
	assert r.inputs['build/android-maps/libnative236.so'] == '78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d'
	base := read_gzip(out + '/baseline-serial.log.gz')!
	fixed := read_gzip(out + '/fixed-serial.log.gz')!
	assert base.contains('java.lang.UnsatisfiedLinkError: No implementation found for long android.widget.PopupMenu.native_init()')
	assert base.contains('ANDROID-WS-FAIL start activity') && !base.contains('POPUP-MENU-PROGRAMMATIC-PASS')
	for marker in ['POPUP-MENU-ACTIVITY-OWNER-PASS', 'POPUP-MENU-PROGRAMMATIC-PASS',
		'POPUP-MENU-GUEST-CLICK-READY', 'POPUP-MENU-GUEST-ITEM-CLICK',
		'POPUP-MENU-PASS resources submenus listeners hidden disabled repeated reentrant stale guest-click',
		'ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent'] {
		assert fixed.contains(marker), marker
	}
	assert !fixed.contains('ANDROID-WS-FAIL') && !fixed.contains('java.lang.AssertionError')
	assert !fixed.contains('APK-SUITE-EXIT id=bootstrap-fixture') && !fixed.contains('AbstractMethodError')
	mut framework := map[string]map[string]string{}
	mut natives := map[string]map[string]string{}
	for mode, serial in {
		'baseline': base
		'fixed':    fixed
	} {
		row := json2.decode[[]json2.Any](os.read_file(out + '/' + mode + '-results.json')!)![0].as_map()
		assert row['serial_sha256']!.str() == digest(serial)
		assert row['metadata']!.as_map()['apk_sha256']!.str() == r.inputs['build/android-maps/popup243-apk/probe.apk']
		assert row['launcher_entered']!.bool() && row['native_maps_observed']!.bool()
		assert row['startup_seconds']!.int() == 180
		if mode == 'baseline' {
			assert row['outcome']!.str() == 'startup_failed' && row['process_exited']!.bool()
		} else {
			assert row['backend_ready']!.bool() && !row['process_exited']!.bool()
			assert row['outcome']!.str() == 'startup_failed' && row['failure_markers']!.as_array().len == 2
			for marker in row['failure_markers']!.as_array() {
				line := marker.str()
				assert (line.contains('NoSuchFieldError:') && line.contains('Lnge;') && line.contains('Lorg/vinix/bootstrap/Main;')) || line == 'Caused by: java.lang.ClassNotFoundException: nge', line
			}
		}
		staged := json2.decode[map[string]string](os.read_file(out + '/' + mode + '-staged-runtime-sha256.json')!)!
		assert staged.len == 6
		for name, hash in staged {
			assert hash == r.inputs[mode + '/staged/' + name], name
			if !name.ends_with('api-impl.jar') && !name.ends_with('libvinix-android-native.so') {
				assert hash == r.inputs['baseline/staged/' + name], name
			}
		}
		jar := if mode == 'baseline' {
			'framework242-canvas-save'
		} else {
			'framework243-popup-menus'
		}
		native := if mode == 'baseline' { '235' } else { '236' }
		assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'] == r.inputs['build/android-maps/' + jar + '/api-impl.jar']
		assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'] == r.inputs['build/android-maps/libnative' + native + '.so']
		manifest := json2.decode[map[string]json2.Any](os.read_file(out + '/' + mode + '-framework-manifest.json')!)!
		assert manifest['output_sha256']!.str() == r.inputs['build/android-maps/' + jar + '/api-impl.jar']
		sources := json2.decode[map[string]string](read_gzip(out + '/' + mode + '-framework-sources.json.gz')!)!
		assert sources.len == manifest['sources']!.as_map().len
		for name, source in sources {
			assert digest(source) == manifest['sources']!.as_map()[name]!.str(), name
		}
		framework[mode] = sources
		native_sources := json2.decode[map[string]string](read_gzip(out + '/' + mode + '-native-sources.json.gz')!)!
		hashes := json2.decode[map[string]string](os.read_file(out + '/' + mode + '-native-sources-sha256.json')!)!
		assert native_sources.len == 83 && native_sources.len == hashes.len
		for name, source in native_sources {
			assert digest(source) == hashes[name], name
		}
		natives[mode] = native_sources
	}
	assert framework['baseline'].len == 111 && framework['fixed'].len == 112
	mut changes := []string{}
	for name, source in framework['fixed'] {
		if source != framework['baseline'][name] { changes << os.base(name) }
	}
	changes.sort()
	assert changes == ['framework_classes.v', 'framework_popup_menus.v', 'menus.v'], changes.str()
	for name in framework['baseline'].keys() {
		assert name in framework['fixed'], name
	}
	mut native_changes := []string{}
	for name, source in natives['fixed'] {
		if source != natives['baseline'][name] { native_changes << name }
	}
	assert native_changes == ['menus.v'], native_changes.str()
	for name in natives['baseline'].keys() {
		assert name in natives['fixed'], name
	}
	assert digest(natives['fixed']['menus.v']) == '073c19f8f2106af02a4f32525c4bd9f62435ef943dff436d54cc918301f0343a'
	assert digest(os.read_file(out + '/fixture.v')!) == r.inputs['fixture.v']
	probe := read_gzip(out + '/PopupProbe.smali.gz')!
	for part in ['->setIcon(I)', '->setTitle(I)', '->addSubMenu(IIII)', '->performClick()Z',
		'->postDelayed(Ljava/lang/Runnable;J)Z', '->vinixGetDialog()',
		'->getDeclaredField(Ljava/lang/String;)', 'native menu resource icon storage', '-0xedcbaa'] {
		assert probe.contains(part), part
	}
	assert !probe.contains('->getIcon()')
	assert read_gzip(out + '/Main.smali.gz')!.contains('onCreateOptionsMenu(Landroid/view/Menu;)Z')
	assert read_gzip(out + '/baseline-PopupMenu.smali.gz')!.contains('.method protected native native_init()J')
	api := read_gzip(out + '/fixed-PopupMenu.smali.gz')!
	assert !api.contains('native_init()') && api.contains('vinixGetDialog()Landroid/app/Dialog;')
	assert read_gzip(out + '/fixed-VinixMenu.smali.gz')!.contains('vinixContext:Landroid/content/Context;')
	assert read_gzip(out + '/fixed-VinixPopupMenuClick.smali.gz')!.contains('dialog:Landroid/app/Dialog;')
	assert read_gzip(out + '/fixed-VinixPopupMenuDismiss.smali.gz')!.contains('notified:Z')
	xml := os.read_file(out + '/menu-resource-dump.txt')!
	assert xml.contains('android:visible') && xml.contains('android:enabled') && xml.contains('android:checked')
	interaction := os.read_file(out + '/interaction.log')!
	assert interaction.contains('actual QMP input click') && interaction.contains('real guest item callback and eighth delayed dismissal PASS')
	assert r.inputs['rejected-get-icon/apk'] == 'c4cac4d1522e646b01122013fa40930df39b85371e76f9264bae5d872f74d336'
	rejected := read_gzip(out + '/rejected-get-icon/fixed-serial.log.gz')!
	assert rejected.contains('java.lang.AbstractMethodError: abstract method "android.graphics.drawable.Drawable android.view.MenuItem.getIcon()"')
	assert rejected.contains('ANDROID-WS-FAIL start activity') && !rejected.contains('POPUP-MENU-PROGRAMMATIC-PASS')
	assert digest(os.read_file(out + '/rejected-get-icon/fixture.v')!) == 'db2d6f498f5232e7cf599b3c3902d136cc5373a1d1c6c09980f466d8266d92ea'
	println('POPUP-MENU VALIDATION PASS same signed APK; exact native_init baseline; resources/Activity fallback, listener precedence, nested menus, visibility/enabled/checked, reentry/stale events, eight dismissals and actual guest click +READY. Raw fixed startup_failed limited to two inherited nge diagnostics; initial unsupported getIcon fixture failure retained.')
}
