// SPDX-License-Identifier: GPL-2.0-or-later
// Independent class/member/instruction oracle for the real TrafficStats helper.
module main

import androidtools
import os

const target = 'android/net/TrafficStats.smali'
const uid_field = '.field private static uids:Ljava/lang/ThreadLocal;'
const old_members = ['<clinit>()V', '<init>()V', 'clearThreadStatsTag()V', 'clearThreadStatsUid()V',
	'getThreadStatsTag()I', 'getUidRxBytes(I)J', 'getUidTxBytes(I)J', 'setThreadStatsTag(I)V']
const added_members = ['setThreadStatsUid(I)V', 'getThreadStatsUid()I']

const old_clinit = '.method static constructor <clinit>()V
.registers 1
new-instance v0, Ljava/lang/ThreadLocal;
invoke-direct {v0}, Ljava/lang/ThreadLocal;-><init>()V
sput-object v0, Landroid/net/TrafficStats;->tags:Ljava/lang/ThreadLocal;
return-void
.end method'

const new_clinit = '.method static constructor <clinit>()V
.registers 1
new-instance v0, Ljava/lang/ThreadLocal;
invoke-direct {v0}, Ljava/lang/ThreadLocal;-><init>()V
sput-object v0, Landroid/net/TrafficStats;->tags:Ljava/lang/ThreadLocal;
new-instance v0, Ljava/lang/ThreadLocal;
invoke-direct {v0}, Ljava/lang/ThreadLocal;-><init>()V
sput-object v0, Landroid/net/TrafficStats;->uids:Ljava/lang/ThreadLocal;
return-void
.end method'

const old_clear = '.method public static clearThreadStatsUid()V
.registers 0
return-void
.end method'

const new_clear = '.method public static clearThreadStatsUid()V
.registers 1
sget-object v0, Landroid/net/TrafficStats;->uids:Ljava/lang/ThreadLocal;
invoke-virtual {v0}, Ljava/lang/ThreadLocal;->remove()V
return-void
.end method'

const new_set = '.method public static setThreadStatsUid(I)V
.registers 3
sget-object v0, Landroid/net/TrafficStats;->uids:Ljava/lang/ThreadLocal;
invoke-static {p0}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/lang/ThreadLocal;->set(Ljava/lang/Object;)V
return-void
.end method'

const new_get = '.method public static getThreadStatsUid()I
.registers 1
sget-object v0, Landroid/net/TrafficStats;->uids:Ljava/lang/ThreadLocal;
invoke-virtual {v0}, Ljava/lang/ThreadLocal;->get()Ljava/lang/Object;
move-result-object v0
if-nez v0, :uid
const/4 v0, -0x1
return v0
:uid
check-cast v0, Ljava/lang/Integer;
invoke-virtual {v0}, Ljava/lang/Integer;->intValue()I
move-result v0
return v0
.end method'

struct Parts {
	metadata string
	methods map[string]string
}

fn flat(text string) string {
	return text.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

fn parts(source string) !Parts {
	mut methods := map[string]string{}
	mut metadata := source
	mut name := ''
	mut start := 0
	mut offset := 0
	for line in source.split('\n') {
		trimmed := line.trim_space()
		if trimmed.starts_with('.method ') {
			if name != '' { return error('unterminated class method') }
			name = trimmed.all_after_last(' ')
			if name in methods || !name.contains('(') { return error('unique method signature required') }
			start = offset
		} else if trimmed == '.end method' {
			if name == '' { return error('unexpected method end') }
			body := source[start..offset + line.len]
			methods[name] = body
			metadata = metadata.replace(body, '')
			name = ''
		}
		offset += line.len + 1
	}
	if name != '' { return error('unterminated class method') }
	return Parts{metadata, methods}
}

fn parameter_slots(signature string) int {
	return if signature in ['<init>()V', 'setThreadStatsTag(I)V', 'setThreadStatsUid(I)V', 'getUidRxBytes(I)J', 'getUidTxBytes(I)J'] { 1 } else { 0 }
}

// Method-local label spelling and locals/registers notation may change in a
// DEX roundtrip. Every opcode, operand, register and branch target stays exact.
fn normalized(source string, signature string) !string {
	lines := flat(source).split_into_lines()
	mut labels := map[string]string{}
	mut instruction := 0
	for line in lines {
		if line.starts_with(':') {
			if line in labels { return error('unique method labels required') }
			labels[line] = ':instruction_' + instruction.str()
		} else if !line.starts_with('.') { instruction++ }
	}
	mut output := []string{}
	for original in lines {
		if original.starts_with(':') { continue }
		mut line := if original.starts_with('.locals ') {
			'.registers ' + (original.all_after(' ').int() + parameter_slots(signature)).str()
		} else { original }
		if line.starts_with('const') && line.ends_with(', -1') { line = line[..line.len - 2] + '-0x1' }
		if line.starts_with('if-') {
			name := line.all_after_last(', ')
			label := labels[name] or { return error('undefined branch label') }
			line = line[..line.len - name.len] + label
		}
		output << line
	}
	return output.join('\n')
}

fn expected(name string) string {
	return match name {
		'<clinit>()V' { new_clinit }
		'clearThreadStatsUid()V' { new_clear }
		'setThreadStatsUid(I)V' { new_set }
		'getThreadStatsUid()I' { new_get }
		else { '' }
	}
}

fn verify(before string, after string, raw bool) ! {
	old, updated := parts(before)!, parts(after)!
	if old.methods.keys().sorted() != old_members.sorted()
		|| updated.methods.keys().sorted() != [...old_members, ...added_members].sorted() {
		return error('exact original-eight plus added-two method membership required')
	}
	if normalized(old.methods['<clinit>()V']!, '<clinit>()V')! != normalized(old_clinit, '<clinit>()V')!
		|| normalized(old.methods['clearThreadStatsUid()V']!, 'clearThreadStatsUid()V')! != normalized(old_clear, 'clearThreadStatsUid()V')! {
		return error('exact old tag-only clinit and no-op UID clear required')
	}
	if updated.metadata.count(uid_field) != 1 { return error('one exact private plain ThreadLocal UID field required') }
	if flat(old.metadata) != flat(updated.metadata.replace(uid_field, '')) {
		return error('class metadata and all original fields must remain unchanged')
	}
	for name, body in old.methods {
		if name !in ['<clinit>()V', 'clearThreadStatsUid()V'] && body != updated.methods[name]! {
			return error('unrelated original method changed: ' + name)
		}
	}
	for name in ['<clinit>()V', 'clearThreadStatsUid()V', 'setThreadStatsUid(I)V', 'getThreadStatsUid()I'] {
		if normalized(updated.methods[name]!, name)! != normalized(expected(name), name)! {
			return error('complete UID method oracle differs: ' + name)
		}
	}
	if raw {
		mut restored := after
		for name in added_members { restored = restored.replace(updated.methods[name]!, '') }
		restored = restored.replace(uid_field, '')
		for name in ['<clinit>()V', 'clearThreadStatsUid()V'] {
			restored = restored.replace(updated.methods[name]!, old.methods[name]!)
		}
		if restored.trim_right('\n') != before.trim_right('\n') {
			return error('raw source changed outside the two replaced and two added methods/one field')
		}
	}
}

fn refuse(source string, invalid string) ! {
	if source == invalid { return error('inactive helper refusal control') }
	if _ := androidtools.framework_traffic_stats_uid_source(invalid) { return error('malformed helper input accepted') }
}

fn replace_member(source string, signature string, replacement string) !string {
	body := parts(source)!.methods[signature]!
	return source.replace(body, replacement)
}

fn main() {
	$if prod { panic('live assertions required') }
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		for directory in ['baseline-roundtrip', 'patched-roundtrip', 'second-roundtrip'] {
			assert os.walk_ext(work + '/' + directory, '.smali').len == 1
		}
		before := os.read_file(work + '/baseline-roundtrip/' + target)!
		for directory in ['patched-roundtrip', 'second-roundtrip'] {
			verify(before, os.read_file(work + '/' + directory + '/' + target)!, false)!
		}
		assert os.read_file(work + '/patched-roundtrip/' + target)! == os.read_file(work + '/second-roundtrip/' + target)!
		println('TRAFFIC-STATS-UID-ROUNDTRIP-PASS exact-one-class original-six-methods unchanged-counters UID-two-added-two-replaced plain-threadlocal stable-second-DEX')
		return
	}
	before := os.read_file(work + '/baseline/' + target)!
	after := androidtools.framework_traffic_stats_uid_source(before)!
	verify(before, after, true)!
	old := parts(before)!
	clinit, clear := old.methods['<clinit>()V']!, old.methods['clearThreadStatsUid()V']!
	mut positives := 0
	for variant in [before.trim_right('\n'),
		before.replace(clinit, clinit.replace('.registers 1', '.locals 1')).replace(clear, clear.replace('.registers 0', '.locals 0')),
		before.replace('UNSUPPORTED:I = -0x1', 'UNSUPPORTED:I = -1'),
		before.replace(clinit, clinit.replace('    return-void', '    # .end method\n    return-void')),
		before.replace(clear, clear.replace('    return-void', '    # .end method\n    return-void')),
		before.replace(old.methods['<init>()V']!, old.methods['<init>()V']!.replace('    return-void', '    # preserved bystander comment\n    return-void'))] {
		assert variant != before
		verify(variant, androidtools.framework_traffic_stats_uid_source(variant)!, true)!
		positives++
	}
	mut refusals := 0
	for invalid in [after, before.replace('.class public Landroid/net/TrafficStats;', '.class private Landroid/net/TrafficStats;'),
		before + '\n.class public Landroid/net/TrafficStats;\n', before.replace('.super Ljava/lang/Object;', '.super Ljava/lang/Thread;'),
		before.replace('.field private static tags:Ljava/lang/ThreadLocal;', '.field private static tags:Ljava/lang/InheritableThreadLocal;'),
		before.replace('.field private static tags:Ljava/lang/ThreadLocal;', ''),
		before + '\n.field private static injected:I\n', before + '\n.field private static tags:Ljava/lang/ThreadLocal;\n',
		before + '\n' + clear + '\n', before.replace(clear, ''), before.replace(clear, clear.replace('.end method', '')),
		before + '\n.end method\n', before.replace(clinit, clinit.replace('.end method', '.end method\n.end method')),
		before.replace(clear, clear.replace('.method public static', '.method private static')),
		before.replace(clear, clear.replace('return-void', 'const/4 v0, -1\nreturn-void')),
		before.replace(clinit, clinit.replace('.registers 1', '.registers 2')),
		before.replace(clinit, clinit.replace('->tags:', '->uids:')),
		before.replace(clinit, clinit.replace('Ljava/lang/ThreadLocal;', 'Ljava/lang/InheritableThreadLocal;')),
		before + '\n' + new_set + '\n', before + '\n' + new_get + '\n'] {
		refuse(before, invalid)!
		refusals++
	}
	updated := parts(after)!
	mut mutations := 0
	for name in ['<clinit>()V', 'clearThreadStatsUid()V', 'setThreadStatsUid(I)V', 'getThreadStatsUid()I'] {
		body := updated.methods[name]!
		mut invalids := [replace_member(after, name, body.replace('.method public static ', '.method private static '))!]
		if name == '<clinit>()V' {
			invalids = [replace_member(after, name, body.replace('->uids:', '->tags:'))!,
				replace_member(after, name, body.replace('Ljava/lang/ThreadLocal;', 'Ljava/lang/InheritableThreadLocal;'))!,
				replace_member(after, name, body.replace('sput-object v0, Landroid/net/TrafficStats;->uids:Ljava/lang/ThreadLocal;', 'sget-object v0, Landroid/net/TrafficStats;->tags:Ljava/lang/ThreadLocal;\nsput-object v0, Landroid/net/TrafficStats;->uids:Ljava/lang/ThreadLocal;'))!]
		} else {
			invalids << replace_member(after, name, body.replace('->uids:', '->tags:'))!
		}
		if name == 'setThreadStatsUid(I)V' {
			invalids << replace_member(after, name, body.replace('{p0}', '{v0}'))!
			invalids << replace_member(after, name, body.replace('invoke-static {p0}', 'const/4 p0, 0\ninvoke-static {p0}'))!
		} else if name == 'getThreadStatsUid()I' {
			invalids << replace_member(after, name, body.replace('const/4 v0, -1', 'const/4 v0, 0').replace('const/4 v0, -0x1', 'const/4 v0, 0'))!
			invalids << replace_member(after, name, body.replace('if-nez', 'if-eqz'))!
		} else if name == 'clearThreadStatsUid()V' {
			invalids << replace_member(after, name, old_clear)!
		}
		for invalid in invalids {
			assert invalid != after, 'inactive output preservation mutation'
			if _ := verify(before, invalid, true) { panic('raw oracle accepted changed UID instructions') }
			if _ := verify(before, invalid, false) { panic('canonical oracle accepted changed UID instructions') }
			mutations++
		}
	}
	for invalid in [after + '\n.field private static injected:I\n',
		after.replace(uid_field, uid_field.replace('private', 'public')),
		after.replace(updated.methods['getUidRxBytes(I)J']!, updated.methods['getUidRxBytes(I)J']!.replace('-0x1', '0x0')),
		after.replace(updated.methods['clearThreadStatsTag()V']!, updated.methods['clearThreadStatsTag()V']!.replace('->tags:', '->uids:'))] {
		assert invalid != after
		if _ := verify(before, invalid, true) { panic('raw oracle accepted bystander metadata/method edit') }
		if _ := verify(before, invalid, false) { panic('canonical oracle accepted bystander metadata/method edit') }
		mutations++
	}
	os.write_file(work + '/proof/' + target, after)!
	println('TRAFFIC-STATS-UID-SOURCE-PASS input-refusals=' + refusals.str() + ' preservation-controls=' + mutations.str()
		+ ' format-positives=' + positives.str() + ' complete-one-class-oracle signed-int-boxing UID-tag-separation noninherited-threadlocal unsupported-counters no-kernel-accounting-claim')
}
