// SPDX-License-Identifier: GPL-2.0-or-later
// Source/ABI checks only. Real dispatch semantics belong to the ARM fixture.
module main

import androidtools
import crypto.sha256
import os

const owner = 'Landroid/app/PendingIntent;'
const context = 'Landroid/content/Context;'
const intent = 'Landroid/content/Intent;'

fn changed() []string {
	mut result := ['<clinit>()V', 'cancel()V', 'getCreatorPackage()Ljava/lang/String;',
		'getCreatorUid()I', 'send()V', 'send(' + context + 'I' + intent + ')V',
		'toString()Ljava/lang/String;',
		'getActivities(' + context + 'I[' + intent + 'ILandroid/os/Bundle;)' + owner]
	for name in ['getActivity', 'getService', 'getBroadcast', 'getForegroundService'] {
		result << name + '(' + context + 'I' + intent + 'I)' + owner
	}
	return result
}

fn methods(source string) !map[string]string {
	mut result := map[string]string{}
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		if name in result || !block.contains('.end method') {
			return error('duplicate/unterminated method')
		}
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn method(source map[string]string, name string) !string {
	return source[name] or { return error('missing method: ' + name) }
}

fn preserved(old string, patched string, raw bool) ! {
	before, after := methods(old)!, methods(patched)!
	if after.len != before.len + 7 { return error('expected exactly seven private helpers') }
	mut previous, next := old, patched
	for name, body in before {
		other := after[name] or { return error('lost original method: ' + name) }
		if name !in changed() {
			if body != other { return error('changed retained method: ' + name) }
		} else {
			if body == other { return error('target method left unchanged: ' + name) }
			previous = previous.replace(body, '<' + name + '>')
			next = next.replace(other, '<' + name + '>')
		}
	}
	for name, body in after {
		if name !in before {
			if !body.starts_with('.method private static ') { return error('new public ABI') }
			next = next.replace(body, '')
		}
	}
	old_fields := old.split_into_lines().filter(it.starts_with('.field '))
	new_fields := patched.split_into_lines().filter(it.starts_with('.field '))
	if new_fields.len != old_fields.len + 7 { return error('expected seven private fields') }
	for field in old_fields { if field !in new_fields { return error('changed original field') } }
	for field in new_fields {
		if field !in old_fields {
			if !field.starts_with('.field private ') { return error('new nonprivate field') }
			next = next.replace(field, '')
		}
	}
	// Raw production transform preserves all metadata and unmodified methods.
	// DEX canonicalization may reorder fields/helpers, so compare declarations
	// and unchanged method bodies there rather than claiming raw file identity.
	if raw && previous.split_into_lines().filter(it.trim_space() != '') != next.split_into_lines().filter(it.trim_space() != '') {
		return error('unreviewed source metadata change')
	}
}

fn safety(source string) ! {
	m := methods(source)!
	get := method(m, 'vinixGet(' + context + 'I' + intent + '[' + intent + 'II)' + owner)!
	if !get.starts_with('.method private static vinixGet(') || get.count('monitor-enter p0') != 1
		|| get.count('monitor-exit p0') != 2 || !get.contains('.catchall {:locked .. :unlock} :failed')
		|| !get.contains(':unlock\nmonitor-exit p0\nreturn-object v4')
		|| !get.contains(':failed\nmove-exception v0\nmonitor-exit p0\nthrow v0') {
		return error('unlocked registry or exceptional exit')
	}
	creator := get.index('->vinixCreatorContext(') or { return error('missing creator context') }
	lookup := get.index('->iterator()') or { return error('missing lookup') }
	monitor := get.index('monitor-enter p0') or { return error('missing lock') }
	if creator >= monitor || monitor >= lookup || get.count('->vinixCreatorContext(') != 1
		|| !get.contains('iput-object v9, v4, ' + owner + '->vinixCreator:') {
		return error('reentrant creator context after lookup')
	}
	if get[monitor..].contains('Landroid/content/Context;->') {
		return error('Context callback under registry lock')
	}
	for required in ['const v2, -0x38000001', '->vinixCreatorUid:I', '->vinixCreatorPackage:',
		'->requestCode:I', '->type:I', '->vinixFlags:I', '->filterEquals(',
		':create\nconst v6, 0x20000000\nand-int v6, p4, v6\nif-nez v6, :return',
		'Ljava/lang/ref/WeakReference;', '->replaceExtras(Landroid/os/Bundle;)'] {
		if !get.contains(required) { return error('missing registry contract: ' + required) }
	}
	for name in ['send()V', 'send(' + context + 'I' + intent + ')V'] {
		body := method(m, name)!
		if body.contains('synchronized') || !body.contains('->vinixPrepare(')
			|| !body.contains('->vinixDispatch(') {
			return error('send dispatch absent or locked')
		}
	}
	dispatch := method(m, 'vinixDispatch(' + owner + '[' + intent + ')V')!
	if dispatch.contains('synchronized') || !dispatch.contains('->vinixCreator:')
		|| !dispatch.contains('->startService(') || !dispatch.contains('->sendBroadcast(')
		|| !dispatch.contains('->startActivity(') {
		return error('creator dispatch boundary')
	}
	prepare := method(m, 'vinixPrepare(' + owner + intent + ')[' + intent)!
	if !prepare.starts_with('.method private static vinixPrepare(')
		|| prepare.count('monitor-enter v5') != 1 || prepare.count('monitor-exit v5') != 2
		|| !prepare.contains('.catchall {:locked .. :unlock} :failed')
		|| !prepare.contains('->vinixCanceled:Z') || !prepare.contains('PendingIntent$CanceledException;')
		|| !prepare.contains('const v1, 0x40000000') || !prepare.contains('const v2, 0x04000000')
		|| !prepare.contains('->vinixCopyIntents(') {
		return error('send cancellation/snapshot boundary')
	}
	cancel := method(m, 'vinixCancel(' + owner + ')V')!
	if cancel.count('monitor-enter v2') != 1 || cancel.count('monitor-exit v2') != 2
		|| !cancel.contains('const-class v2, ' + owner)
		|| !cancel.contains('.catchall {:locked .. :unlock} :failed') {
		return error('cancel monitor boundary')
	}
	fill := method(m, 'vinixFillIn(' + intent + intent + 'I)V')!
	if !fill.contains('and-int/lit8 v0, p2, 8\nif-eqz v0, :component_done')
		|| !fill.contains('and-int/lit8 v1, p2, 32\nif-eqz v1, :bounds_done')
		|| !fill.contains('->setSourceBounds(Landroid/graphics/Rect;)V')
		|| !fill.contains('invoke-virtual {v1, v0}, Landroid/os/Bundle;->putAll(Landroid/os/Bundle;)V') {
		return error('fill-in authority or extras precedence changed')
	}
}

fn refused(dir string, text string) ! {
	path := dir + '/android/app/PendingIntent.smali'
	os.mkdir_all(os.dir(path))!
	os.write_file(path, text)!
	mut rejected := false
	androidtools.framework_pending_intent_successor(dir) or { rejected = true }
	assert rejected, 'invalid input accepted'
	assert os.read_file(path)! == text, 'refusal wrote source'
	assert os.walk_ext(dir, '.smali').len == 1, 'refusal added classes'
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		before := os.read_file(work + '/baseline-roundtrip/android/app/PendingIntent.smali')!
		after := os.read_file(work + '/patched-roundtrip/android/app/PendingIntent.smali')!
		preserved(before, after, false)!
		for name in ['PendingIntent$VinixToken', 'PendingIntent$VinixCreator',
			'PendingIntent$CanceledException'] {
			assert os.read_file(work + '/baseline-roundtrip/android/app/' + name + '.smali')! == os.read_file(work + '/patched-roundtrip/android/app/' + name + '.smali')!
		}
		for name in os.walk_ext(work + '/patched-roundtrip', '.smali') {
			relative := name.all_after(work + '/patched-roundtrip/')
			assert os.read_file(name)! == os.read_file(work + '/second-roundtrip/' + relative)!, 'unstable second roundtrip'
		}
		println('PENDING-INTENT-ROUNDTRIP-PASS four-classes three-capability-neighbors unchanged-retained-methods stable-second-DEX')
		return
	}
	old := os.read_file(work + '/baseline/android/app/PendingIntent.smali')!
	patched := androidtools.framework_pending_intent_source(old)!
	preserved(old, patched, true)!
	safety(patched)!
	mut invalid := [
		old.replace('.class public Landroid/app/PendingIntent;', '.class public Lwrong/PendingIntent;'),
		old + '\n.class public Landroid/app/PendingIntent;\n',
		old.replace('.field private vinixToken:', '.field private otherToken:'),
		old.replace('.field private volatile vinixCanceled:Z', ''),
		old + '\n.field private volatile vinixCanceled:Z\n',
		patched,
	]
	for name in changed() {
		body := method(methods(old)!, name)!
		invalid << old.replace(body, '')
		invalid << old + '\n' + body + '\n'
		invalid << old.replace(body, body.replace('.end method', ''))
	}
	for collision in ['vinixCreator:', 'vinixCreatorPackage:', 'vinixCreatorUid:', 'vinixFlags:',
		'vinixIntents:', 'vinixKey:', 'vinixCopyIntents(', 'vinixCreatorContext(', 'vinixCancel(',
		'vinixPrepare(', 'vinixDispatch(', 'vinixFillIn('] {
		invalid << old + '\n# ' + collision + '\n'
	}
	for index, text in invalid { refused(work + '/refused/' + index.str(), text)! }
	// These deliberately broken outputs exercise the independent source audit.
	mut controls := 0
	for text in [patched.replace('->vinixDispatch(', '->missingDispatch('),
		patched.replace(':create\nconst v6, 0x20000000', ':create\nconst v6, 0x0'),
		patched.replace('and-int/lit8 v0, p2, 8\nif-eqz v0, :component_done', 'const/4 v0, 0'),
		patched.replace('and-int/lit8 v1, p2, 32\nif-eqz v1, :bounds_done', 'const/4 v1, 0'),
		patched.replace('monitor-enter v5', '# missing monitor'),
		patched.replace('invoke-static {p0}, ' + owner + '->vinixCreatorContext(' + context + ')' + context + '\nmove-result-object v9\n', '')] {
		mut rejected := false
		safety(text) or { rejected = true }
		assert rejected, 'broken source contract passed audit'
		controls++
	}
	os.write_file(work + '/patched/android/app/PendingIntent.smali', patched)!
	println('PENDING-INTENT-SOURCE-PASS refusals=' + invalid.len.str() + ' negative-contract-controls=' + controls.str() + ' output=' + sha256.sum(patched.bytes()).hex())
}
