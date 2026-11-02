// SPDX-License-Identifier: GPL-2.0-or-later
// Independent source and DEX oracles for an unavailable subscription backend.
module main

import androidtools
import os

const targets = ['android/app/ContextImpl.smali', 'android/telephony/SubscriptionManager.smali',
	'android/telephony/TelephonyManager.smali']
const marker = 'android/telephony/SubscriptionInfo.smali'
const typed = 'getSystemService(Ljava/lang/Class;)Ljava/lang/Object;'
const named = 'getSystemService(Ljava/lang/String;)Ljava/lang/Object;'
const helper = 'vinixSubscriptionService()Landroid/telephony/SubscriptionManager;'

fn all_targets() []string {
	mut result := targets.clone()
	result << marker
	return result
}

fn marker_source() string {
	return '.class public final Landroid/telephony/SubscriptionInfo;\n.super Ljava/lang/Object;\n'
}

fn norm(source string) string {
	return source.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

fn methods(source string) !map[string]string {
	mut result := map[string]string{}
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		if name in result || block.count('.end method') != 1 {
			return error('unique complete method required')
		}
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

// Normalize branch labels, never field descriptors or quoted message text.
fn labels(source string) string {
	mut names := map[string]string{}
	mut result := ''
	mut at := 0
	for at < source.len {
		if source[at] != `:` || (at > 0 && source[at - 1] !in [` `, `\n`, `{`]) {
			result += source[at..at + 1]
			at++
			continue
		}
		mut end := at + 1
		for end < source.len && (source[end].is_alnum() || source[end] in [`_`, `$`, `-`]) { end++ }
		name := source[at..end]
		if name !in names { names[name] = ':label_' + names.len.str() }
		result += names[name]
		at = end
	}
	return result
}

// DEX disassembly moves catch directives and may give a branch target and a
// try-end address separate alias labels. Compare their instruction positions.
fn flow(source string) !string {
	lines := norm(source).split_into_lines()
	mut positions := map[string]int{}
	mut count := 0
	for line in lines {
		if line.starts_with(':') {
			if line in positions { return error('duplicate helper label') }
			positions[line] = count
		} else if !line.starts_with('.catchall ') {
			count++
		}
	}
	mut body, catches := []string{}, []string{}
	for line in lines {
		if line.starts_with(':') { continue }
		mut rendered := ''
		mut at := 0
		for at < line.len {
			if line[at] != `:` || (at > 0 && line[at - 1] !in [` `, `{`]) {
				rendered += line[at..at + 1]
				at++
				continue
			}
			mut end := at + 1
			for end < line.len && (line[end].is_alnum() || line[end] in [`_`, `$`, `-`]) { end++ }
			label := line[at..end]
			position := positions[label] or { return error('undefined helper label') }
			rendered += ':at_' + position.str()
			at = end
		}
		if line.starts_with('.catchall ') { catches << rendered } else { body << rendered }
	}
	if catches.len != 1 { return error('exact catchall range required') }
	return body.join('\n') + '\n' + catches[0]
}

fn context_guard(signature string) string {
	if signature == typed {
		return '\nconst-class v0, Landroid/telephony/SubscriptionManager;\nif-ne p1, v0, :new_other\ninvoke-direct {p0}, Landroid/app/ContextImpl;->vinixSubscriptionService()Landroid/telephony/SubscriptionManager;\nmove-result-object v0\nreturn-object v0\n:new_other\n'
	}
	return '\nconst-string v0, "telephony_subscription_service"\ninvoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :new_other\ninvoke-direct {p0}, Landroid/app/ContextImpl;->vinixSubscriptionService()Landroid/telephony/SubscriptionManager;\nmove-result-object v0\nreturn-object v0\n:new_other\n'
}

fn context_field() string {
	return '.field private vinixSubscriptionManager:Landroid/telephony/SubscriptionManager;'
}

fn telephony_field() string { return '.field private vinixSubscriptionId:I' }

fn additions(kind int) map[string]string {
	if kind == 0 {
		return {
			helper: '.method private ' + helper + '
.registers 2
monitor-enter p0
:locked
iget-object v0, p0, Landroid/app/ContextImpl;->vinixSubscriptionManager:Landroid/telephony/SubscriptionManager;
if-nez v0, :unlock
new-instance v0, Landroid/telephony/SubscriptionManager;
invoke-direct {v0}, Landroid/telephony/SubscriptionManager;-><init>()V
iput-object v0, p0, Landroid/app/ContextImpl;->vinixSubscriptionManager:Landroid/telephony/SubscriptionManager;
:unlock
monitor-exit p0
return-object v0
:failed
move-exception v0
monitor-exit p0
throw v0
.catchall {:locked .. :unlock} :failed
.end method'
		}
	}
	if kind == 1 {
		return {
			'getActiveSubscriptionInfoList()Ljava/util/List;':                  '.method public getActiveSubscriptionInfoList()Ljava/util/List;\n.registers 2\nconst/4 v0, 0x0\nreturn-object v0\n.end method'
			'getActiveSubscriptionInfo(I)Landroid/telephony/SubscriptionInfo;': '.method public getActiveSubscriptionInfo(I)Landroid/telephony/SubscriptionInfo;\n.registers 3\nconst/4 v0, 0x0\nreturn-object v0\n.end method'
			'getPhoneNumber(I)Ljava/lang/String;':                              '.method public getPhoneNumber(I)Ljava/lang/String;\n.registers 4\nnew-instance v0, Ljava/lang/IllegalStateException;\nconst-string v1, "subscription service unavailable."\ninvoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V\nthrow v0\n.end method'
		}
	}
	return {
		'getPhoneCount()I':                                               '.method public getPhoneCount()I\n.registers 2\nconst/4 v0, 0x0\nreturn v0\n.end method'
		'getActiveModemCount()I':                                         '.method public getActiveModemCount()I\n.registers 2\nconst/4 v0, 0x0\nreturn v0\n.end method'
		'createForSubscriptionId(I)Landroid/telephony/TelephonyManager;': '.method public createForSubscriptionId(I)Landroid/telephony/TelephonyManager;\n.registers 3\nnew-instance v0, Landroid/telephony/TelephonyManager;\ninvoke-direct {v0}, Landroid/telephony/TelephonyManager;-><init>()V\niput p1, v0, Landroid/telephony/TelephonyManager;->vinixSubscriptionId:I\nreturn-object v0\n.end method'
	}
}

fn verify(old string, patched string, kind int) ! {
	before, after := methods(old)!, methods(patched)!
	extra := additions(kind)
	if after.len != before.len + extra.len { return error('exact method membership required') }
	for signature, body in before {
		mut expected := norm(body)
		if kind == 0 && signature in [typed, named] {
			directive := if expected.contains('\n.locals 1\n') {
				'.locals 1'
			} else {
				'.registers 3'
			}
			expected = expected.replace(directive, directive + context_guard(signature))
		}
		if labels(norm(after[signature])) != labels(norm(expected)) {
			return error('retained method or lookup guard differs: ' + signature)
		}
	}
	for signature, expected in extra {
		mut actual_body, expected_body := labels(norm(after[signature])), labels(norm(expected))
		if kind == 0 {
			actual_body = flow(after[signature])!
			expected_body = flow(expected)!
		}
		if signature in before || actual_body != expected_body {
			return error('added method body differs: ' + signature)
		}
	}
	mut old_metadata, new_metadata := old, patched
	for _, body in before { old_metadata = old_metadata.replace(body, '') }
	for _, body in after { new_metadata = new_metadata.replace(body, '') }
	if kind in [0, 2] {
		field := if kind == 0 { context_field() } else { telephony_field() }
		if norm(new_metadata).split_into_lines().filter(it == field).len != 1 {
			return error('exact single added instance field required')
		}
		new_metadata = new_metadata.replace(field, '')
	}
	if norm(old_metadata) != norm(new_metadata) { return error('retained class metadata changed') }
}

fn transform(source string, kind int) !string {
	return match kind {
		0 { androidtools.framework_subscription_context_source(source)! }
		1 { androidtools.framework_subscription_manager_source(source)! }
		else { androidtools.framework_subscription_telephony_source(source)! }
	}
}

fn files(root string) ![]string {
	mut result := []string{}
	for name in os.ls(root)! {
		path := root + '/' + name
		match os.lstat(path)!.get_filetype() {
			.regular { result << path }
			.directory { result << files(path)! }
			else { return error('unexpected proof file type: ' + path) }
		}
	}
	return result.sorted()
}

fn schema_controls(old string, patched string, kind int) []string {
	member := (methods(old) or { panic(err) })[if kind == 0 { typed } else { '<init>()V' }]
	public_header := if kind == 0 { '.method public ' } else { '.method public constructor ' }
	class_header := norm(old).split_into_lines().filter(it.starts_with('.class '))[0]
	super_header := norm(old).split_into_lines().filter(it.starts_with('.super '))[0]
	mut invalids := [patched, old.replace(class_header, class_header.replace('public', 'private')),
		old.replace(class_header, class_header.replace('Landroid/', 'Lwrong/')),
		old + '\n' + class_header + '\n',
		old + '\n' + class_header.replace('.class ', '.class\t') + '\n',
		old.replace(super_header, '.super Lwrong/Base;'), old + '\n' + super_header + '\n',
		old + '\n' + super_header.replace('.super ', '.super\t') + '\n', old.replace(member, ''),
		old + '\n' + member, old + '\n' + member.replace('.method ', '.method\t'),
		old + '\n.end method\n', old + '\n.end\tmethod\n',
		old.replace(member, member.replace('.end method', '')),
		old.replace(member, member.replace(public_header, public_header.replace('public', 'private'))),
		old.replace(member, member.replace(public_header, public_header.replace('public', 'public static'))),
		old.replace(member, member.replace(if kind == 0 {
			'return-object v0'
		} else {
			'return-void'
		},
			if kind == 0 { 'return-void' } else { 'return-object p0' })),
		old + '\n.field private vinixSubscriptionCollision:I\n',
		old + '\n.field\tprivate vinixSubscriptionCollision:I\n',
		old + '\n.method private vinixSubscriptionCollision()V\n.registers 1\nreturn-void\n.end method\n']
	if kind == 0 {
		for signature in [typed, named] {
			body := (methods(old) or { panic(err) })[signature]
			invalids << old.replace(body, body.replace('.method public ', '.method public static '))
			invalids << old.replace(body, body.replace('.registers 3', '.registers 4'))
			invalids << old.replace(body, body.replace('.registers 3', '.registers 3\n# .registers 3'))
			invalids << old.replace(body, body.replace('return-object v0', 'return-void'))
			for instruction in norm(body).split_into_lines().filter(!it.starts_with('.method ') && it != '.end method') {
				invalids << old.replace(body, body.replace(instruction, '# removed retained instruction'))
			}
		}
	} else if kind == 1 {
		invalids << old + '\n.field private unexpected:I\n'
		invalids << old.replace(member, member.replace('invoke-direct {p0}, Ljava/lang/Object;-><init>()V', ''))
	} else {
		invalids << old.replace(member, member.replace('invoke-direct {p0}, Ljava/lang/Object;-><init>()V', ''))
		invalids << old + '\n.field public static final UNKNOWN_CARRIER_ID:I = -0x1\n'
		for _, body in additions(kind) { invalids << old + '\n' + body + '\n' }
	}
	return invalids
}

fn semantic_controls(patched string, kind int) []string {
	mut result := [patched + '\n.field private unplanned:I\n']
	if kind == 0 {
		result << [patched.replace('monitor-enter p0', '# omitted lock'),
			patched.replace('monitor-exit p0', '# omitted unlock'),
			patched.replace('move-exception v0\nmonitor-exit p0', 'move-exception v0\n# omitted error unlock'),
			patched.replace('.. :vinix_subscription_unlock', '.. :vinix_subscription_locked'),
			patched.replace('.catchall ', '# omitted catchall '),
			patched.replace('throw v0', 'return-object v0'),
			patched.replace(context_field(), context_field().replace('private ', 'private static ')),
			patched.replace('if-ne p1, v0', 'if-eq p1, v0'),
			patched.replace('"telephony_subscription_service"', '"phone"'),
			patched.replace('iput-object v0, p0,', 'iput-object p0, p0,')]
	} else if kind == 1 {
		result << [
			patched.replace('const/4 v0, 0x0', 'new-instance v0, Ljava/util/ArrayList;'),
			patched.replace('Ljava/lang/IllegalStateException;', 'Ljava/lang/UnsupportedOperationException;'),
			patched.replace('subscription service unavailable.', 'subscription unavailable'),
			patched.replace('throw v0', 'return-object v0'),
		]
	} else {
		result << [patched.replace('const/4 v0, 0x0', 'const/4 v0, 0x1'),
			patched.replace('iput p1, v0,', 'iput p0, v0,'),
			patched.replace('iput p1, v0, Landroid/telephony/TelephonyManager;->vinixSubscriptionId:I', '# omitted requested ID'),
			patched.replace('return-object v0\n.end method', 'return-object p0\n.end method'),
			patched.replace(telephony_field(), telephony_field().replace('private ', 'private static '))]
	}
	return result
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	classes := androidtools.framework_subscription_service_classes()
	assert classes.keys() == ['android/telephony/SubscriptionInfo']
	assert classes['android/telephony/SubscriptionInfo'] == marker_source()
	locked_body := additions(0)[helper]
	canonical_body := locked_body.replace('.catchall {:locked .. :unlock} :failed\n', '')
		.replace(':unlock\nmonitor-exit', ':try_end\n.catchall {:locked .. :try_end} :failed\n:unlock\nmonitor-exit')
	assert flow(locked_body)! == flow(canonical_body)!, 'catchall placement and address aliases must normalize'
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		assert files(work + '/baseline-roundtrip')! == targets.map(work + '/baseline-roundtrip/' + it).sorted()
		for kind in ['patched-roundtrip', 'second-roundtrip'] {
			assert files(work + '/' + kind)! == all_targets().map(work + '/' + kind + '/' + it).sorted()
		}
		for index, target in targets {
			verify(os.read_file(work + '/baseline-roundtrip/' + target)!,
				os.read_file(work + '/patched-roundtrip/' + target)!, index)!
		}
		for target in all_targets() {
			assert os.read_file(work + '/patched-roundtrip/' + target)! == os.read_file(work + '/second-roundtrip/' + target)!, 'unstable second DEX'
		}
		assert norm(os.read_file(work + '/patched-roundtrip/' + marker)!) == norm(marker_source())
		println('SUBSCRIPTION-SERVICE-ROUNDTRIP-PASS classes=4 retained-original-members explicit-monitors unavailable-queries no-modem fresh-ID-wrapper stable-second-DEX')
		return
	}
	root := work + '/proof'
	assert files(root)! == targets.map(root + '/' + it).sorted(), 'isolated three-class proof required'
	mut old := []string{}
	for target in targets { old << os.read_file(root + '/' + target)! }
	assert (methods(old[1])!).len == 1 && (methods(old[2])!).len == 24
	mut patched := []string{}
	for index, source in old {
		patched << transform(source, index)!
		verify(source, patched[index], index)!
	}
	mut rejected_count, semantic_count := 0, 0
	for index, target in targets {
		for invalid in schema_controls(old[index], patched[index], index) {
			assert invalid != old[index], 'negative mutation no longer applies'
			mut pure_rejected := false
			transform(invalid, index) or { pure_rejected = true }
			assert pure_rejected, 'schema control accepted: ' + target
			os.write_file(root + '/' + target, invalid)!
			mut directory_rejected := false
			androidtools.framework_subscription_service(root) or { directory_rejected = true }
			assert directory_rejected && files(root)! == targets.map(root + '/' + it).sorted(), 'refusal must precede every write'
			for position, path in targets {
				assert os.read_file(root + '/' + path)! == if position == index {
					invalid
				} else {
					old[position]
				}, 'refusal changed an input'
			}
			os.write_file(root + '/' + target, old[index])!
			rejected_count++
		}
		for broken in semantic_controls(patched[index], index) {
			assert broken != patched[index], 'semantic mutation no longer applies'
			mut rejected := false
			verify(old[index], broken, index) or { rejected = true }
			assert rejected, 'semantic output mutation escaped independent oracle'
			semantic_count++
		}
	}
	// Reproduce the complete-builder .locals spelling and raw policy/Stats
	// labels while preserving every original fallback instruction.
	ctx_methods := methods(old[0])!
	raw_typed := ctx_methods[typed].replace(':cond_6', ':vinix_stats_unavailable_other')
		.replace(':cond_c', ':cond_6').replace(':cond_12', ':cond_c').replace(':cond_18', ':cond_12')
	raw_named := ctx_methods[named].replace('.registers 3', '.locals 1').replace(':cond_d', ':other')
	raw := old[0].replace(ctx_methods[typed], raw_typed).replace(ctx_methods[named], raw_named)
	assert raw != old[0]
	verify(raw, transform(raw, 0)!, 0)!
	// Missing second/third input must leave every surviving original untouched.
	for index in [1, 2] {
		os.rm(root + '/' + targets[index])!
		mut rejected := false
		androidtools.framework_subscription_service(root) or { rejected = true }
		assert rejected && !os.exists(root + '/' + marker)
		for position, path in targets {
			if position != index {
				assert os.read_file(root + '/' + path)! == old[position]
			}
		}
		os.write_file(root + '/' + targets[index], old[index])!
		rejected_count++
	}
	class_path := root + '/' + marker
	os.mkdir_all(os.dir(class_path))!
	sentinel := 'owned marker collision\x00\xff'
	for kind in 0 .. 3 {
		match kind {
			0 { os.write_file(class_path, sentinel)! }
			1 {
				os.mkdir(class_path)!
				os.write_file(class_path + '/sentinel', sentinel)!
			}
			else { os.symlink('absent-subscription-info-target', class_path)! }
		}
		mut rejected := false
		androidtools.framework_subscription_service(root) or { rejected = true }
		assert rejected
		for index, target in targets {
			assert os.read_file(root + '/' + target)! == old[index]
		}
		match kind {
			0 {
				assert os.read_file(class_path)! == sentinel
				os.rm(class_path)!
			}
			1 {
				assert os.ls(class_path)! == ['sentinel'] && os.read_file(class_path + '/sentinel')! == sentinel
				os.rm(class_path + '/sentinel')!
				os.rmdir(class_path)!
			}
			else {
				assert os.is_link(class_path) && os.readlink(class_path)! == 'absent-subscription-info-target'
				os.rm(class_path)!
			}
		}
		rejected_count++
	}
	androidtools.framework_subscription_service(root)!
	for index, target in targets {
		assert os.read_file(root + '/' + target)! == patched[index]
	}
	assert os.read_file(class_path)! == marker_source()
	assert files(root)! == all_targets().map(root + '/' + it).sorted()
	println('SUBSCRIPTION-SERVICE-SOURCE-PASS rejected=' + rejected_count.str() + ' semantic-controls=' + semantic_count.str() +
		' retained-original-members explicit-monitors null-info exception-number no-modem fresh-ID-wrapper validation-before-writes')
}
