import os
import crypto.sha256
import json2
import compress.gzip

struct Receipt {
	artifacts map[string]string
	inputs    map[string]string
	scope     string
}

fn unpack(path string) !string { return gzip.decompress(os.read_bytes(path)!)!.bytestr() }

fn main() {
	out := os.dir(@FILE)
	r := json2.decode[Receipt](os.read_file(out + '/receipt.json')!)!
	for name, digest in r.artifacts {
		assert sha256.sum(os.read_bytes(out + '/' + name)!).hex() == digest, name
	}
	assert r.inputs['build/android-maps/action244-apk/probe.apk'] == '30f17fa850ebbe1faa76ad0ff1d0841a1922ae791414a31519657bb483923dd7'
	assert r.inputs['fixture.v'] == 'a96059e0098fd1727ac5110f43361515edf36b55bbca7fa42f65413f87e72564'
	assert sha256.sum(os.read_bytes(out + '/fixture.v')!).hex() == r.inputs['fixture.v']
	assert r.inputs['build/android-maps/framework243-popup-menus/api-impl.jar'] == '0eb5f294900d7ef1683c7444c97ebd59d96d6dc7e2c372731e358ce9c6bde0cc'
	assert r.inputs['build/android-maps/framework244-action-provider/api-impl.jar'] == '933fc7db4267d123a33bb1e4e064ea3b69450fd065bb4d8e4f5898b91cf842b8'
	assert r.inputs['build/android-maps/libnative236.so'] == '78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d'
	base := unpack(out + '/baseline-serial.log.gz')!
	fixed := unpack(out + '/fixed-serial.log.gz')!
	assert base.contains('java.lang.NoClassDefFoundError: Failed resolution of: Landroid/view/ActionProvider;')
	assert base.contains('ProviderProbe.run') && base.contains('APK-SUITE-EXIT id=bootstrap-fixture code=1')
	assert !base.contains('BOOTSTRAP-ACTION-PROVIDER-PASS')
	assert fixed.contains('BOOTSTRAP-ACTION-PROVIDER-PASS\r\ndefaults virtual factories visibility listeners reset and popup callback order')
	assert fixed.contains('BOOTSTRAP-READY') && fixed.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
	assert !fixed.contains('ANDROID-WS-FAIL') && !fixed.contains('java.lang.AssertionError') && !fixed.contains('APK-SUITE-EXIT id=bootstrap-fixture')
	mut framework := map[string]map[string]string{}
	for mode, serial in {
		'baseline': base
		'fixed':    fixed
	} {
		row := json2.decode[[]json2.Any](os.read_file(out + '/' + mode + '-results.json')!)![0].as_map()
		assert row['serial_sha256']!.str() == sha256.sum(serial.bytes()).hex()
		assert row['screenshot_sha256']!.str() == sha256.sum(os.read_bytes(out + '/' + mode + '-application.png')!).hex()
		assert row['metadata']!.as_map()['apk_sha256']!.str() == r.inputs['build/android-maps/action244-apk/probe.apk']
		assert row['launcher_entered']!.bool() && row['native_maps_observed']!.bool()
		if mode == 'baseline' {
			assert row['outcome']!.str() == 'startup_failed' && row['process_exited']!.bool()
		} else {
			assert row['backend_ready']!.bool() && !row['process_exited']!.bool()
			assert row['startup_seconds']!.int() == 120 && row['startup_timeout_seconds']!.int() == 120
			assert row['outcome']!.str() == 'startup_failed' && row['failure_markers']!.as_array().len == 2
			for marker in row['failure_markers']!.as_array() {
				line := marker.str()
				assert (line.contains('NoSuchFieldError:') && line.contains('Lnge;') && line.contains('Lorg/vinix/bootstrap/Main;')) || line == 'Caused by: java.lang.ClassNotFoundException: nge', line
			}
		}
		config := json2.decode[map[string]json2.Any](os.read_file(out + '/' + mode + '-configuration.json')!)!
		assert config['applications']!.as_array()[0].as_map()['startup_seconds']!.int() == 120
		staged := json2.decode[map[string]string](os.read_file(out + '/' + mode + '-staged-runtime-sha256.json')!)!
		assert staged.len == 6
		for name, digest in staged {
			assert digest == r.inputs[mode + '/staged/' + name], name
			if !name.ends_with('api-impl.jar') {
				assert digest == r.inputs['baseline/staged/' + name], name
			}
		}
		jar := if mode == 'baseline' {
			'framework243-popup-menus'
		} else {
			'framework244-action-provider'
		}
		assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'] == r.inputs['build/android-maps/' + jar + '/api-impl.jar']
		assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'] == r.inputs['build/android-maps/libnative236.so']
		manifest := json2.decode[map[string]json2.Any](os.read_file(out + '/' + mode + '-framework-manifest.json')!)!
		assert manifest['output_sha256']!.str() == r.inputs['build/android-maps/' + jar + '/api-impl.jar']
		sources := json2.decode[map[string]string](unpack(out + '/' + mode + '-framework-sources.json.gz')!)!
		hashes := manifest['sources']!.as_map()
		assert sources.len == hashes.len
		for name, source in sources {
			assert sha256.sum(source.bytes()).hex() == hashes[name]!.str(), name
		}
		framework[mode] = sources
	}
	assert framework['baseline'].len == 112 && framework['fixed'].len == 113
	mut changed := []string{}
	for name, source in framework['fixed'] {
		if source != framework['baseline'][name] { changed << os.base(name) }
	}
	changed.sort()
	assert changed == ['framework_action_provider.v', 'framework_classes.v'], changed.str()
	for name in framework['baseline'].keys() {
		assert name in framework['fixed'], name
	}
	old_hook := framework['baseline']['tests/native-android-tools/androidtools/framework_classes.v']
	new_hook := framework['fixed']['tests/native-android-tools/androidtools/framework_classes.v']
	assert new_hook.count(' framework_action_provider(smali)!\n') == 1
	assert new_hook.replace(' framework_action_provider(smali)!\n', '') == old_hook
	for name in ['native-sources.json.gz'] {
		sources := json2.decode[map[string]string](unpack(out + '/' + name)!)!
		hashes := json2.decode[map[string]string](os.read_file(out + '/native-sources-sha256.json')!)!
		assert sources.len == 83 && sources.len == hashes.len
		for file, source in sources {
			assert sha256.sum(source.bytes()).hex() == hashes[file], file
		}
	}
	assert !(unpack(out + '/baseline-MenuItem.smali.gz')!).contains('getActionProvider')
	provider := unpack(out + '/fixed-ActionProvider.smali.gz')!
	for method in ['public abstract onCreateActionView()',
		'public onCreateActionView(Landroid/view/MenuItem;)', 'public overridesItemVisibility()',
		'public isVisible()', 'public refreshVisibility()', 'public onPerformDefaultAction()',
		'public hasSubMenu()', 'public onPrepareSubMenu(', 'public subUiVisibilityChanged(',
		'public setSubUiVisibilityListener(', 'public setVisibilityListener(', 'public reset()'] {
		assert provider.contains(method), method
	}
	assert provider.contains('invoke-virtual {p0}, Landroid/view/ActionProvider;->overridesItemVisibility()Z')
	item := unpack(out + '/fixed-VinixMenuItem.smali.gz')!
	assert item.contains('->reset()V') && item.contains('->vinixActionProvider:Landroid/view/ActionProvider;')
	popup := unpack(out + '/fixed-PopupMenu.smali.gz')!
	item_call := popup.index('->vinixInvokeClick()Z') or { panic('missing item callback') }
	popup_call := popup.index('->onMenuItemClick(Landroid/view/MenuItem;)Z') or { panic('missing popup callback') }
	provider_call := popup.index('->onPerformDefaultAction()Z') or { panic('missing provider callback') }
	assert item_call < popup_call && popup_call < provider_call
	assert unpack(out + '/ProviderProbe.smali.gz')!.contains('->performClick()Z')
	for label in ['same provider replacement resets old provider', 'null removes visibility listener',
		'null removes subUI listener', 'provider clears old direct action view',
		'popup callback order case 0', 'popup callback order case 3',
		'no provider leaves callback chain unhandled'] {
		assert unpack(out + '/ProviderProbe.smali.gz')!.contains(label), label
	}
	println('ACTION-PROVIDER VALIDATION PASS same signed APK/native236; exact missing class baseline; defaults/virtual factories, visibility/subUI gates and replacement/reset, provider retention/clear, real popup callback order +READY. Raw fixed startup_failed limited to inherited nge diagnostics; bounded menu integration only.')
}
