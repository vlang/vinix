// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

fn methods(source string) map[string]string {
	mut result := map[string]string{}
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		assert name !in result, name
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn transform(name string, source string) !string {
	return match name {
		'android/content/BroadcastReceiver' { androidtools.framework_broadcast_receiver(source)! }
		'android/content/BroadcastReceiver$PendingResult' { androidtools.framework_broadcast_pending(source)! }
		'android/atl/VinixBroadcast' { androidtools.framework_broadcast_run(source)! }
		else { androidtools.framework_broadcast_loaded_app(source)! }
	}
}

fn main() {
	assert os.args.len == 2 || os.args.len == 4, 'BASE_SMALI [TOOLS JAVA]'
	work := os.temp_dir() + '/vinix-broadcast-result-' + os.getpid().str()
	defer { os.rmdir_all(work) or {} }
	result_apis := ['setResultCode(I)V', 'getResultCode()I', 'setResultData(Ljava/lang/String;)V',
		'getResultData()Ljava/lang/String;', 'setResultExtras(Landroid/os/Bundle;)V',
		'getResultExtras(Z)Landroid/os/Bundle;', 'setResult(ILjava/lang/String;Landroid/os/Bundle;)V',
		'getAbortBroadcast()Z', 'abortBroadcast()V', 'clearAbortBroadcast()V']
	for name in ['android/content/BroadcastReceiver', 'android/content/BroadcastReceiver$PendingResult',
		'android/atl/ATLLoadedApp', 'android/atl/VinixBroadcast'] {
		old := os.read_file(os.args[1] + '/' + name + '.smali')!
		new := transform(name, old)!
		before, after := methods(old), methods(new)
		mut changed := []string{}
		for signature, body in before {
			assert signature in after, name + signature
			if after[signature] != body { changed << signature }
		}
		expected_changed := match name {
			'android/content/BroadcastReceiver' { ['goAsync()Landroid/content/BroadcastReceiver$PendingResult;', 'isOrderedBroadcast()Z'] }
			'android/content/BroadcastReceiver$PendingResult' { ['finish()V', 'setResultCode(I)V'] }
			'android/atl/ATLLoadedApp' { ['receiveBroadcast(Landroid/content/Context;Landroid/content/Intent;)V'] }
			else { ['run()V'] }
		}
		changed.sort()
		mut expected := expected_changed.clone()
		expected.sort()
		assert changed == expected, name
		added := match name {
			'android/content/BroadcastReceiver' { 14 }
			'android/content/BroadcastReceiver$PendingResult' { 11 }
			else { 0 }
		}
		assert after.len == before.len + added, name
		if name.starts_with('android/content/BroadcastReceiver') {
			for signature in result_apis { assert signature in after, signature }
		}
		if name == 'android/content/BroadcastReceiver' {
			assert after['goAsync()Landroid/content/BroadcastReceiver$PendingResult;'].contains('iput-object v1, p0')
			dispatch := after['vinixDispatch(Landroid/content/Context;Landroid/content/Intent;Z)V']
			assert dispatch.count('->vinixFinish()V') == 2 && dispatch.contains('.catchall')
			assert !after['goAsync()Landroid/content/BroadcastReceiver$PendingResult;'].contains('new-instance')
			assert !after['getResultExtras(Z)Landroid/os/Bundle;'].contains('new-instance')
			assert new.count('.field ') == 1
		} else if name.ends_with('$PendingResult') {
			assert new.count('.field ') == 6
			assert after['<init>(Z)V'].contains('const/4 v0, -0x1\n    iput v0, p0, Landroid/content/BroadcastReceiver$PendingResult;->vinixCode:I')
			assert after['finish()V'].contains('if-nez v0, :done')
			assert after['finish()V'].contains('monitor-enter p0')
			assert after['finish()V'].count('monitor-exit p0') == 2
			assert after['setResultCode(I)V'].contains('->vinixWarnUnordered()V')
			assert after['getResultExtras(Z)Landroid/os/Bundle;'].contains('if-eqz p1, :done')
		} else if name.ends_with('VinixBroadcast') {
			assert after['run()V'] == androidtools.framework_broadcast_run_method().trim_space()
		} else {
			assert new.contains('const/4 v4, 0x0\n    invoke-virtual {v1, p1, p2, v4}')
		}
		if _ := transform(name, new) { panic('accepted already extended broadcast source: ' + name) }
		if _ := transform(name, old.replace('.method public ', '.method private ')) {
			panic('accepted missing public broadcast entry: ' + name)
		}
		if name == 'android/atl/ATLLoadedApp' {
			if _ := transform(name, old.replace('->onReceive(', '->wrongReceive(')) {
				panic('accepted wrong manifest target')
			}
		}
		if os.args.len == 4 {
			path := work + '/smali/' + name + '.smali'
			os.mkdir_all(os.dir(path))!
			os.write_file(path, new)!
		}
	}
	println('ANDROID-BROADCAST-RESULT-TRANSFORM-PASS four exact classes, 25 added methods, seven fields, pending ownership, exception cleanup, manifest and Handler bridge')
	if os.args.len == 4 {
		androidtools.framework_assemble(work + '/smali', work + '/classes.dex', os.real_path(os.args[2]), os.args[3])!
		assert os.file_size(work + '/classes.dex') > 112
		println('ANDROID-BROADCAST-RESULT-ASSEMBLY-PASS four classes produce DEX; ART not executed')
	}
}
