// SPDX-License-Identifier: GPL-2.0-or-later
// Exact four-class source delta and focused DEX assembly; lifecycle needs ART.
module main

import androidtools
import crypto.sha256
import json2
import os

fn methods(source string) map[string]string {
	mut result := map[string]string{}
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		assert name !in result && block.contains('.end method'), name
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn norm(source string) string {
	return source.split_into_lines().map(it.trim_space()).filter(it != '').join('\n')
}

fn metadata(source string) string {
	mut result := source
	for _, method in methods(source) { result = result.replace(method, '') }
	return norm(result)
}

fn transformed(name string, source string) !string {
	return match name {
		'Activity' { androidtools.framework_platform_fragments_activity(source)! }
		'Fragment' { androidtools.framework_platform_fragments_fragment(source)! }
		'FragmentManager' { androidtools.framework_platform_fragments_manager(source)! }
		'FragmentTransaction' { androidtools.framework_platform_fragments_transaction(source)! }
		else { return error('unexpected class') }
	}
}

fn changed_methods(name string) []string {
	return match name {
		'Activity' {
			mut names := ['getFragmentManager()Landroid/app/FragmentManager;']
			for prefix in ['vinixLifecycleOn', 'vinixPerform'] {
				for event in ['Create', 'Start', 'Resume', 'Pause', 'Stop', 'Destroy'] {
					names << prefix + event + if event == 'Create' { '(Landroid/os/Bundle;)V' } else { '()V' }
				}
			}
			names
		}
		'Fragment' { []string{} }
		'FragmentManager' { ['<init>(Landroid/app/Activity;)V', 'beginTransaction()Landroid/app/FragmentTransaction;', 'executePendingTransactions()Z', 'findFragmentByTag(Ljava/lang/String;)Landroid/app/Fragment;'] }
		else { ['<init>(Landroid/app/Activity;)V', 'add(Landroid/app/Fragment;Ljava/lang/String;)Landroid/app/FragmentTransaction;', 'commit()I'] }
	}
}

fn added_fields(name string) []string {
	return match name {
		'Activity' { ['.field private vinixPlatformFragments:Landroid/app/FragmentManager;'] }
		'Fragment' { ['.field vinixManager:Landroid/app/FragmentManager;', '.field vinixTag:Ljava/lang/String;', '.field vinixState:I', '.field vinixAdded:Z'] }
		'FragmentManager' { ['.field private vinixPending:Ljava/util/ArrayList;', '.field private vinixHandler:Landroid/os/Handler;', '.field private vinixRunner:Ljava/lang/Runnable;', '.field private vinixState:I', '.field private vinixExecuting:Z', '.field private vinixDestroyed:Z'] }
		else { ['.field vinixManager:Landroid/app/FragmentManager;', '.field private vinixAdds:Ljava/util/ArrayList;', '.field private vinixCommitted:Z'] }
	}
}

fn added_methods(name string) []string {
	return match name {
		'Activity' { []string{} }
		'Fragment' { ['getTag()Ljava/lang/String;', 'onAttach(Landroid/app/Activity;)V', 'onAttach(Landroid/content/Context;)V', 'onActivityCreated(Landroid/os/Bundle;)V', 'onDetach()V'] }
		'FragmentManager' { ['vinixCheckHost()V', 'vinixEnqueue(Landroid/app/FragmentTransaction;)V', 'vinixAdd(Landroid/app/Fragment;)V', 'vinixCancelPosted()V', 'vinixSynchronize()V', 'vinixMoveToState(I)V', 'vinixMoveFragment(Landroid/app/Fragment;)V', 'vinixTerminalCleanup()V'] }
		else { ['vinixExecute()V', 'vinixCancel()V'] }
	}
}

fn digest(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn inventory(root string, relative string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		if os.is_link(path) { return error('unexpected result symlink') }
		if os.is_dir(path) { inventory(root, key, mut pins)! } else if os.is_file(path) { pins[key] = digest(path) } else { return error('unexpected result file type') }
	}
}

fn main() {
	$if prod { eprintln('requires assertions; compile without -prod'); exit(2) }
	assert os.args.len == 5, 'BASE_SMALI TOOLS JAVA FRESH_EXTERNAL_OUTPUT'
	base, tools, java, out := os.real_path(os.args[1]), os.real_path(os.args[2]), os.real_path(os.args[3]), os.abs_path(os.args[4])
	repo := os.real_path(os.dir(@FILE) + '/../..')
	assert !os.exists(out) && !os.is_link(out) && out != repo && !out.starts_with(repo + '/')
	os.mkdir_all(out + '/smali/android/app')!
	mut changes, additions, fields, rejected := 0, 0, 0, 0
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), repo + '/tests/native-android-tools/androidtools/framework_platform_fragments.v', repo + '/tests/native-android-tools/androidtools/framework.v', java] { inputs[os.real_path(path)] = digest(path) }
	for name in os.ls(tools)! { if name.ends_with('.jar') { inputs[tools + '/' + name] = digest(tools + '/' + name) } }
	for name in ['Activity', 'Fragment', 'FragmentManager', 'FragmentTransaction'] {
		path := base + '/android/app/' + name + '.smali'
		inputs[path] = digest(path)
		old := os.read_file(path)!
		new := transformed(name, old)!
		before, after := methods(old), methods(new)
		allowed, added := changed_methods(name), added_methods(name)
		assert after.len == before.len + added.len, name
		for signature, method in before {
			assert signature in after, signature
			if signature in allowed {
				assert after[signature] != method, signature
				assert after[signature].all_before('\n') == method.all_before('\n'), signature
				changes++
			} else { assert after[signature] == method, signature }
		}
		for signature in added { assert signature !in before && signature in after, signature; additions++ }
		mut retained := new
		for field in added_fields(name) { assert retained.count(field + '\n') == 1, field; retained = retained.replace(field + '\n', ''); fields++ }
		for signature in added { retained = retained.replace(after[signature], '') }
		assert metadata(retained) == metadata(old), name
		for bad in [new, old.replace('Landroid/app/' + name + ';', 'Lwrong/' + name + ';'), old + '\n' + before.values()[0] + '\n'] {
			if _ := transformed(name, bad) { panic('accepted invalid or repeated ' + name) }
			rejected++
		}
		if name == 'Activity' {
			drift := old.replace('iget-object v0, p0, Landroid/app/Activity;->fragments:Ljava/util/List;', 'iget-object v0, p0, Landroid/app/Activity;->fragments:Ljava/util/List;\nconst-string v0, "unexpected side effect"')
			if _ := transformed(name, drift) { panic('accepted drift inside removed fragment loop') }
			rejected++
			assert new.count('Landroid/app/Fragment;->on') == 0, 'old direct lifecycle loops remain'
			for event in ['Create', 'Start', 'Resume', 'Pause', 'Stop', 'Destroy'] {
				suffix := if event == 'Create' { '(Landroid/os/Bundle;)V' } else { '()V' }
				body := after['vinixPerform' + event + suffix]
				call := body.index('Landroid/app/Activity;->on' + event + suffix) or { panic('missing host callback') }
				move := body.index('Landroid/app/FragmentManager;->vinixMoveToState(I)V') or { panic('missing fragment state transition') }
				assert (move > call) == (event in ['Create', 'Start', 'Resume']), event
				if event == 'Destroy' {
					flag := body.index('iput-boolean v0, p0, Landroid/app/Activity;->destroyed:Z') or { panic('missing host destroyed flag') }
					assert flag < move
				}
			}
		}
		os.write_file(out + '/smali/android/app/' + name + '.smali', new)!
	}
	assert changes == 20 && additions == 15 && fields == 14 && rejected == 13
	extra := androidtools.framework_platform_fragments_classes()
	assert extra.len == 1 && 'android/app/VinixFragmentCommit' in extra
	for name, source in extra { os.write_file(out + '/smali/' + name + '.smali', source)! }
	androidtools.framework_assemble(out + '/smali', out + '/classes.dex', tools, java)!
	assert os.file_size(out + '/classes.dex') > 112
	r := os.exec([java, '-Xmx512m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', out + '/classes.dex', '-o', out + '/roundtrip'])
	os.write_file(out + '/roundtrip-command.json', json2.encode({'exit_code': json2.Any(r.exit_code), 'output': json2.Any(r.output)}, prettify: true) + '\n')!
	assert r.exit_code == 0
	for name in ['Activity', 'Fragment', 'FragmentManager', 'FragmentTransaction', 'VinixFragmentCommit'] {
		decoded := os.read_file(out + '/roundtrip/android/app/' + name + '.smali')!
		assert methods(decoded).len == methods(os.read_file(out + '/smali/android/app/' + name + '.smali')!).len, name
	}
	for path, pin in inputs { assert digest(path) == pin, path }
	os.write_file(out + '/result.json', json2.encode({'changed_methods': json2.Any(changes), 'added_methods': json2.Any(additions), 'added_fields': json2.Any(fields), 'rejected_mutations': json2.Any(rejected), 'inputs_sha256': json2.decode[json2.Any](json2.encode(inputs))!, 'scope': json2.Any('Exact source delta, invalid-input rejection, five-class DEX assembly and roundtrip; lifecycle execution requires ART.')}, prettify: true) + '\n')!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	os.write_file(out + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
	println('ANDROID-PLATFORM-FRAGMENTS-PASS changed=20 added=15 fields=14 rejected=13 five-class DEX roundtrip; ART pending')
}
