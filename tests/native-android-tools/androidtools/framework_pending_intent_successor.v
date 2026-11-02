// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Process-local PendingIntent controller. Weak entries do not retain abandoned
// operations; local parcel capabilities still resolve their original object.
// Registry mutation and send snapshots share the class monitor. No component
// dispatch happens while that monitor is held. Remote Binder transport remains
// outside this implementation.
pub fn framework_pending_intent_successor(smali string) ! {
	path := smali + '/android/app/PendingIntent.smali'
	os.write_file(path, framework_pending_intent_source(os.read_file(path)!)!)!
}

fn pending_method(declaration string, locals int, body string) string {
	return '.method ' + declaration + '\n.locals ' + locals.str() + '\n' + body + '\n.end method\n'
}

pub fn framework_pending_intent_source(original string) !string {
	owner := 'Landroid/app/PendingIntent;'
	intent := 'Landroid/content/Intent;'
	ctx := 'Landroid/content/Context;'
	array := '[' + intent
	get := 'vinixGet(' + ctx + 'I' + intent + array + 'II)' + owner
	if original.split_into_lines().filter(it.starts_with('.class ')) != ['.class public ' + owner]
		|| original.count('.field private vinixToken:Landroid/app/PendingIntent$VinixToken;') != 1
		|| original.count('.field private volatile vinixCanceled:Z') != 1
		|| original.count('vinixAccountActivityIntent()') != 1
		|| original.contains('vinixOperations:') || original.contains('vinixGet(') {
		return error('unmodified local-capability PendingIntent required')
	}
	if original.count('.method ') != original.count('.end method') {
		return error('balanced PendingIntent methods required')
	}
	for block in original.split('.method ')[1..] {
		if block.count('.end method') != 1 {
			return error('one end per PendingIntent method required')
		}
	}
	// Replace the deployed API; never silently add a missing overload to an
	// incompatible input. Reject collisions before changing any source text.
	for signature in ['<clinit>()V', 'getActivity(' + ctx + 'I' + intent + 'I)' + owner,
		'getService(' + ctx + 'I' + intent + 'I)' + owner,
		'getBroadcast(' + ctx + 'I' + intent + 'I)' + owner,
		'getForegroundService(' + ctx + 'I' + intent + 'I)' + owner,
		'getActivities(' + ctx + 'I' + array + 'ILandroid/os/Bundle;)' + owner,
		'getCreatorPackage()Ljava/lang/String;', 'getCreatorUid()I', 'cancel()V', 'send()V',
		'send(' + ctx + 'I' + intent + ')V', 'toString()Ljava/lang/String;'] {
		if original.split_into_lines().filter(it.starts_with('.method ') && it.ends_with(' ' + signature)).len != 1 {
			return error('exact PendingIntent method required: ' + signature)
		}
	}
	for reserved in ['vinixCreator:', 'vinixCreatorPackage:', 'vinixCreatorUid:', 'vinixFlags:',
		'vinixIntents:', 'vinixKey:', 'vinixCopyIntents(', 'vinixCreatorContext(', 'vinixCancel(',
		'vinixPrepare(', 'vinixDispatch(', 'vinixFillIn('] {
		if original.contains(reserved) {
			return error('PendingIntent successor member collision: ' + reserved)
		}
	}
	mut text := original + '\n.field private static final vinixOperations:Ljava/util/ArrayList;\n' +
		'.field private vinixCreator:Landroid/content/Context;\n' +
		'.field private vinixCreatorPackage:Ljava/lang/String;\n.field private vinixCreatorUid:I\n' +
		'.field private vinixFlags:I\n.field private vinixIntents:[Landroid/content/Intent;\n' +
		'.field private vinixKey:Landroid/content/Intent;\n'
	text = framework_replace_method(text, '<clinit>()V', pending_method('static constructor <clinit>()V', 1,
		'new-instance v0, Landroid/app/PendingIntent$VinixCreator;\n' +
			'invoke-direct {v0}, Landroid/app/PendingIntent$VinixCreator;-><init>()V\n' +
			'sput-object v0, ' + owner + '->CREATOR:Landroid/os/Parcelable$Creator;\n' +
			'new-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\n' +
			'sput-object v0, ' + owner + '->vinixOperations:Ljava/util/ArrayList;\nreturn-void'))!
	for name, kind in {
		'getActivity':          0
		'getService':           1
		'getBroadcast':         2
		'getForegroundService': 3
	} {
		signature := name + '(' + ctx + 'I' + intent + 'I)' + owner
		text = framework_replace_method(text, signature, pending_method('public static ' + signature, 6,
			'move-object v0, p0\nmove v1, p1\nmove-object v2, p2\nconst/4 v3, 0\nmove v4, p3\n' +
				'const/4 v5, ' + kind.str() + '\ninvoke-static/range {v0 .. v5}, ' + owner + '->' + get +
				'\nmove-result-object v0\nreturn-object v0'))!
	}
	activities := 'getActivities(' + ctx + 'I' + array + 'ILandroid/os/Bundle;)' + owner
	text = framework_replace_method(text, activities, pending_method('public static ' + activities, 6,
		'array-length v0, p2\nif-nez v0, :nonempty\nnew-instance v0, Ljava/lang/IllegalArgumentException;\n' +
			'const-string v1, "intents must not be empty"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n' +
			':nonempty\nadd-int/lit8 v0, v0, -1\naget-object v2, p2, v0\nmove-object v0, p0\nmove v1, p1\n' +
			'move-object v3, p2\nmove v4, p3\nconst/4 v5, 0\ninvoke-static/range {v0 .. v5}, ' + owner + '->' + get +
			'\nmove-result-object v0\nreturn-object v0'))!
	text += pending_method('private static vinixCopyIntents(' + intent + array + ')' + array, 6,
		'if-nez p1, :many\nconst/4 v0, 1\nnew-array v1, v0, ' + array + '\nconst/4 v0, 0\n' +
			'new-instance v2, ' + intent + '\ninvoke-direct {v2, p0}, ' + intent + '-><init>(' + intent + ')V\n' +
			'aput-object v2, v1, v0\nreturn-object v1\n:many\narray-length v0, p1\nnew-array v1, v0, ' + array +
			'\nconst/4 v2, 0\n:next\nif-ge v2, v0, :done\naget-object v3, p1, v2\n' +
			'new-instance v4, ' + intent + '\ninvoke-direct {v4, v3}, ' + intent + '-><init>(' + intent + ')V\n' +
			'aput-object v4, v1, v2\nadd-int/lit8 v2, v2, 1\ngoto :next\n:done\nreturn-object v1')
	// Context methods are application code. Resolve them before taking the class
	// monitor, then reuse the no-longer-needed p0 register for that monitor.
	text += pending_method('private static ' + get, 10, '
invoke-static {p0}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
invoke-static {p2}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v0
invoke-virtual {p0}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v1
iget v1, v1, Landroid/content/pm/ApplicationInfo;->uid:I
const v2, -0x38000001
and-int v2, p4, v2
invoke-static {p0}, Landroid/app/PendingIntent;->vinixCreatorContext(Landroid/content/Context;)Landroid/content/Context;
move-result-object v9
const-class p0, Landroid/app/PendingIntent;
monitor-enter p0
:locked
sget-object v3, Landroid/app/PendingIntent;->vinixOperations:Ljava/util/ArrayList;
invoke-virtual {v3}, Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;
move-result-object v3
const/4 v4, 0
:next
invoke-interface {v3}, Ljava/util/Iterator;->hasNext()Z
move-result v5
if-eqz v5, :create
invoke-interface {v3}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v5
check-cast v5, Ljava/lang/ref/WeakReference;
invoke-virtual {v5}, Ljava/lang/ref/WeakReference;->get()Ljava/lang/Object;
move-result-object v5
check-cast v5, Landroid/app/PendingIntent;
if-eqz v5, :stale
iget-boolean v6, v5, Landroid/app/PendingIntent;->vinixCanceled:Z
if-nez v6, :stale
iget v6, v5, Landroid/app/PendingIntent;->type:I
if-ne v6, p5, :next
iget v6, v5, Landroid/app/PendingIntent;->requestCode:I
if-ne v6, p1, :next
iget v6, v5, Landroid/app/PendingIntent;->vinixFlags:I
if-ne v6, v2, :next
iget v6, v5, Landroid/app/PendingIntent;->vinixCreatorUid:I
if-ne v6, v1, :next
iget-object v6, v5, Landroid/app/PendingIntent;->vinixCreatorPackage:Ljava/lang/String;
invoke-static {v0, v6}, Ljava/util/Objects;->equals(Ljava/lang/Object;Ljava/lang/Object;)Z
move-result v6
if-eqz v6, :next
iget-object v6, v5, Landroid/app/PendingIntent;->vinixKey:Landroid/content/Intent;
invoke-virtual {v6, p2}, Landroid/content/Intent;->filterEquals(Landroid/content/Intent;)Z
move-result v6
if-eqz v6, :next
move-object v4, v5
const v6, 0x10000000
and-int v6, p4, v6
if-nez v6, :cancel
const v6, 0x08000000
and-int v6, p4, v6
if-eqz v6, :return
invoke-static {p2, p3}, Landroid/app/PendingIntent;->vinixCopyIntents(Landroid/content/Intent;[Landroid/content/Intent;)[Landroid/content/Intent;
move-result-object v6
array-length v7, v6
add-int/lit8 v7, v7, -1
aget-object v8, v6, v7
invoke-virtual {v8}, Landroid/content/Intent;->getExtras()Landroid/os/Bundle;
move-result-object v8
iget-object v9, v4, Landroid/app/PendingIntent;->intent:Landroid/content/Intent;
invoke-virtual {v9, v8}, Landroid/content/Intent;->replaceExtras(Landroid/os/Bundle;)Landroid/content/Intent;
aput-object v9, v6, v7
iput-object v6, v4, Landroid/app/PendingIntent;->vinixIntents:[Landroid/content/Intent;
goto :return
:cancel
const/4 v6, 1
iput-boolean v6, v4, Landroid/app/PendingIntent;->vinixCanceled:Z
invoke-interface {v3}, Ljava/util/Iterator;->remove()V
goto :create
:stale
invoke-interface {v3}, Ljava/util/Iterator;->remove()V
goto :next
:create
const v6, 0x20000000
and-int v6, p4, v6
if-nez v6, :return
invoke-static {p2, p3}, Landroid/app/PendingIntent;->vinixCopyIntents(Landroid/content/Intent;[Landroid/content/Intent;)[Landroid/content/Intent;
move-result-object v6
array-length v7, v6
add-int/lit8 v7, v7, -1
aget-object v7, v6, v7
new-instance v4, Landroid/app/PendingIntent;
invoke-direct {v4, p1, v7, p5}, Landroid/app/PendingIntent;-><init>(ILandroid/content/Intent;I)V
iput-object v6, v4, Landroid/app/PendingIntent;->vinixIntents:[Landroid/content/Intent;
iput v2, v4, Landroid/app/PendingIntent;->vinixFlags:I
iput-object v0, v4, Landroid/app/PendingIntent;->vinixCreatorPackage:Ljava/lang/String;
iput v1, v4, Landroid/app/PendingIntent;->vinixCreatorUid:I
invoke-virtual {v7}, Landroid/content/Intent;->cloneFilter()Landroid/content/Intent;
move-result-object v7
iput-object v7, v4, Landroid/app/PendingIntent;->vinixKey:Landroid/content/Intent;
iput-object v9, v4, Landroid/app/PendingIntent;->vinixCreator:Landroid/content/Context;
new-instance v7, Ljava/lang/ref/WeakReference;
invoke-direct {v7, v4}, Ljava/lang/ref/WeakReference;-><init>(Ljava/lang/Object;)V
sget-object v6, Landroid/app/PendingIntent;->vinixOperations:Ljava/util/ArrayList;
invoke-virtual {v6, v7}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
:return
:unlock
monitor-exit p0
return-object v4
:failed
move-exception v0
monitor-exit p0
throw v0
.catchall {:locked .. :unlock} :failed')
	text += pending_method('private static vinixCreatorContext(' + ctx + ')' + ctx, 4, '
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v0
if-eqz v0, :original
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v1
invoke-virtual {v0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v2
invoke-static {v1, v2}, Ljava/util/Objects;->equals(Ljava/lang/Object;Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :original
invoke-virtual {p0}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v1
iget v1, v1, Landroid/content/pm/ApplicationInfo;->uid:I
invoke-virtual {v0}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v2
iget v2, v2, Landroid/content/pm/ApplicationInfo;->uid:I
if-ne v1, v2, :original
return-object v0
:original
return-object p0')
	text = framework_replace_method(text, 'getCreatorPackage()Ljava/lang/String;', pending_method('public getCreatorPackage()Ljava/lang/String;', 1,
		'iget-object v0, p0, ' + owner + '->vinixCreatorPackage:Ljava/lang/String;\nreturn-object v0'))!
	text = framework_replace_method(text, 'getCreatorUid()I', pending_method('public getCreatorUid()I', 1,
		'iget v0, p0, ' + owner + '->vinixCreatorUid:I\nreturn v0'))!
	// DEX only honors ACC_SYNCHRONIZED for native methods. Use explicit monitors
	// for every registry/snapshot entry point, including reentrant one-shot cancel.
	text += pending_method('private static vinixCancel(' + owner + ')V', 3, '
const-class v2, Landroid/app/PendingIntent;
monitor-enter v2
:locked
const/4 v0, 1
iput-boolean v0, p0, Landroid/app/PendingIntent;->vinixCanceled:Z
sget-object v0, Landroid/app/PendingIntent;->vinixOperations:Ljava/util/ArrayList;
invoke-virtual {v0}, Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;
move-result-object v0
:next
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v1
if-eqz v1, :done
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v1
check-cast v1, Ljava/lang/ref/WeakReference;
invoke-virtual {v1}, Ljava/lang/ref/WeakReference;->get()Ljava/lang/Object;
move-result-object v1
if-eqz v1, :remove
if-ne v1, p0, :next
:remove
invoke-interface {v0}, Ljava/util/Iterator;->remove()V
goto :next
:done
:unlock
monitor-exit v2
return-void
:failed
move-exception v1
monitor-exit v2
throw v1
.catchall {:locked .. :unlock} :failed')
	text = framework_replace_method(text, 'cancel()V', pending_method('public cancel()V', 0,
		'invoke-static {p0}, ' + owner + '->vinixCancel(' + owner + ')V\nreturn-void'))!
	text += pending_method('private static vinixPrepare(' + owner + intent + ')' + array, 6, '
const-class v5, Landroid/app/PendingIntent;
monitor-enter v5
:locked
iget-boolean v0, p0, Landroid/app/PendingIntent;->vinixCanceled:Z
if-eqz v0, :active
new-instance v0, Landroid/app/PendingIntent$CanceledException;
invoke-direct {v0}, Landroid/app/PendingIntent$CanceledException;-><init>()V
throw v0
:active
iget v0, p0, Landroid/app/PendingIntent;->vinixFlags:I
const v1, 0x40000000
and-int/2addr v1, v0
if-eqz v1, :snapshot
invoke-static {p0}, Landroid/app/PendingIntent;->vinixCancel(Landroid/app/PendingIntent;)V
:snapshot
iget-object v1, p0, Landroid/app/PendingIntent;->intent:Landroid/content/Intent;
iget-object v2, p0, Landroid/app/PendingIntent;->vinixIntents:[Landroid/content/Intent;
invoke-static {v1, v2}, Landroid/app/PendingIntent;->vinixCopyIntents(Landroid/content/Intent;[Landroid/content/Intent;)[Landroid/content/Intent;
move-result-object v1
const v2, 0x04000000
and-int/2addr v2, v0
if-nez v2, :done
if-eqz p1, :done
new-instance v2, Landroid/content/Intent;
invoke-direct {v2, p1}, Landroid/content/Intent;-><init>(Landroid/content/Intent;)V
array-length v3, v1
add-int/lit8 v3, v3, -1
aget-object v3, v1, v3
invoke-static {v3, v2, v0}, Landroid/app/PendingIntent;->vinixFillIn(Landroid/content/Intent;Landroid/content/Intent;I)V
:done
:unlock
monitor-exit v5
return-object v1
:failed
move-exception v0
monitor-exit v5
throw v0
.catchall {:locked .. :unlock} :failed')
	text += pending_method('private static vinixDispatch(' + owner + array + ')V', 6, '
iget-object v0, p0, Landroid/app/PendingIntent;->vinixCreator:Landroid/content/Context;
iget v1, p0, Landroid/app/PendingIntent;->type:I
if-nez v1, :other
array-length v2, p1
const/4 v3, 0
:activity
if-ge v3, v2, :done
aget-object v4, p1, v3
invoke-virtual {v0, v4}, Landroid/content/Context;->startActivity(Landroid/content/Intent;)V
add-int/lit8 v3, v3, 1
goto :activity
:other
const/4 v2, 0
aget-object v3, p1, v2
const/4 v2, 2
if-eq v1, v2, :broadcast
# Foreground-service factory identity is distinct. This runtime has no separate
# Context.startForegroundService API, so retain its existing service dispatch.
invoke-virtual {v0, v3}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;
goto :done
:broadcast
invoke-virtual {v0, v3}, Landroid/content/Context;->sendBroadcast(Landroid/content/Intent;)V
:done
return-void')
	text = framework_replace_method(text, 'send()V', pending_method('public send()V', 2,
		'const/4 v0, 0\ninvoke-static {p0, v0}, ' + owner + '->vinixPrepare(' + owner + intent + ')' + array +
			'\nmove-result-object v0\ninvoke-static {p0, v0}, ' + owner + '->vinixDispatch(' + owner + array + ')V\nreturn-void'))!
	text = framework_replace_method(text, 'send(' + ctx + 'I' + intent + ')V', pending_method('public send(' + ctx + 'I' + intent + ')V', 2,
		'invoke-static {p0, p3}, ' + owner + '->vinixPrepare(' + owner + intent + ')' + array +
			'\nmove-result-object v0\ninvoke-static {p0, v0}, ' + owner + '->vinixDispatch(' + owner + array + ')V\nreturn-void'))!
	text += pending_method('private static vinixFillIn(' + intent + intent + 'I)V', 6, pending_fill_in())
	text = framework_replace_method(text, 'toString()Ljava/lang/String;', pending_method('public toString()Ljava/lang/String;', 3,
		'new-instance v0, Ljava/lang/StringBuilder;\ninvoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V\n' +
			'const-string v1, "PendingIntent{"\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' +
			'iget-object v1, p0, ' + owner + '->vinixCreatorPackage:Ljava/lang/String;\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' +
			'const-string v1, ":"\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' +
			'iget v2, p0, ' + owner + '->requestCode:I\ninvoke-virtual {v0, v2}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;\n' +
			'invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' +
			'iget v2, p0, ' + owner + '->type:I\ninvoke-virtual {v0, v2}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;\n' +
			'const-string v1, "}"\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' +
			'invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\nmove-result-object v0\nreturn-object v0'))!
	return text
}

// Supported Intent fields follow Android 10 fillIn: sender extras are merged
// first, then creator extras win. Component and selector require explicit
// fill-in permission even when absent. Source bounds use the SDK's cloning
// setter, keeping the sender's Rect out of the dispatched snapshot.
fn pending_fill_in() string {
	mut body := ''
	for row in [['Action', 'Ljava/lang/String;', '1'], ['Identifier', 'Ljava/lang/String;', '256'],
		['ClipData', 'Landroid/content/ClipData;', '128']] {
		name, kind, flag := row[0], row[1], row[2]
		body += 'invoke-virtual {p1}, Landroid/content/Intent;->get' + name + '()' + kind + '\nmove-result-object v0\nif-eqz v0, :done_' + name + '\n' +
			'invoke-virtual {p0}, Landroid/content/Intent;->get' + name + '()' + kind + '\nmove-result-object v1\nif-eqz v1, :set_' + name + '\n' +
			'and-int/lit16 v1, p2, ' + flag + '\nif-eqz v1, :done_' + name + '\n:set_' + name + '\n' +
			'invoke-virtual {p0, v0}, Landroid/content/Intent;->set' + name + '(' + kind + ')' + if name == 'ClipData' {
			'V'
		} else {
			'Landroid/content/Intent;'
		} +
			'\n:done_' + name + '\n'
	}
	body += '
invoke-virtual {p1}, Landroid/content/Intent;->getSourceBounds()Landroid/graphics/Rect;
move-result-object v0
if-eqz v0, :bounds_done
invoke-virtual {p0}, Landroid/content/Intent;->getSourceBounds()Landroid/graphics/Rect;
move-result-object v1
if-eqz v1, :bounds_set
and-int/lit8 v1, p2, 32
if-eqz v1, :bounds_done
:bounds_set
invoke-virtual {p0, v0}, Landroid/content/Intent;->setSourceBounds(Landroid/graphics/Rect;)V
:bounds_done
invoke-virtual {p1}, Landroid/content/Intent;->getData()Landroid/net/Uri;
move-result-object v0
invoke-virtual {p1}, Landroid/content/Intent;->getType()Ljava/lang/String;
move-result-object v1
if-nez v0, :data_present
if-eqz v1, :data_done
:data_present
and-int/lit8 v2, p2, 2
if-nez v2, :data_set
invoke-virtual {p0}, Landroid/content/Intent;->getData()Landroid/net/Uri;
move-result-object v2
if-nez v2, :data_done
invoke-virtual {p0}, Landroid/content/Intent;->getType()Ljava/lang/String;
move-result-object v2
if-nez v2, :data_done
:data_set
invoke-virtual {p0, v0, v1}, Landroid/content/Intent;->setDataAndType(Landroid/net/Uri;Ljava/lang/String;)Landroid/content/Intent;
:data_done
invoke-virtual {p1}, Landroid/content/Intent;->getCategories()Ljava/util/Set;
move-result-object v0
if-eqz v0, :categories_done
invoke-virtual {p0}, Landroid/content/Intent;->getCategories()Ljava/util/Set;
move-result-object v1
if-eqz v1, :categories_set
and-int/lit8 v2, p2, 4
if-eqz v2, :categories_done
invoke-interface {v1}, Ljava/util/Set;->clear()V
:categories_set
invoke-interface {v0}, Ljava/util/Set;->iterator()Ljava/util/Iterator;
move-result-object v0
:category
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v1
if-eqz v1, :categories_done
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v1
check-cast v1, Ljava/lang/String;
invoke-virtual {p0, v1}, Landroid/content/Intent;->addCategory(Ljava/lang/String;)Landroid/content/Intent;
goto :category
:categories_done
invoke-virtual {p1}, Landroid/content/Intent;->getPackage()Ljava/lang/String;
move-result-object v0
if-eqz v0, :package_done
invoke-virtual {p0}, Landroid/content/Intent;->getSelector()Landroid/content/Intent;
move-result-object v1
if-nez v1, :package_done
invoke-virtual {p0}, Landroid/content/Intent;->getPackage()Ljava/lang/String;
move-result-object v1
if-eqz v1, :package_set
and-int/lit8 v1, p2, 16
if-eqz v1, :package_done
:package_set
invoke-virtual {p0, v0}, Landroid/content/Intent;->setPackage(Ljava/lang/String;)Landroid/content/Intent;
:package_done
and-int/lit8 v0, p2, 64
if-eqz v0, :selector_done
invoke-virtual {p1}, Landroid/content/Intent;->getSelector()Landroid/content/Intent;
move-result-object v0
if-eqz v0, :selector_done
invoke-virtual {p0}, Landroid/content/Intent;->getPackage()Ljava/lang/String;
move-result-object v1
if-nez v1, :selector_done
new-instance v1, Landroid/content/Intent;
invoke-direct {v1, v0}, Landroid/content/Intent;-><init>(Landroid/content/Intent;)V
invoke-virtual {p0, v1}, Landroid/content/Intent;->setSelector(Landroid/content/Intent;)V
:selector_done
and-int/lit8 v0, p2, 8
if-eqz v0, :component_done
invoke-virtual {p1}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v0
if-eqz v0, :component_done
invoke-virtual {p0, v0}, Landroid/content/Intent;->setComponent(Landroid/content/ComponentName;)Landroid/content/Intent;
:component_done
invoke-virtual {p1}, Landroid/content/Intent;->getFlags()I
move-result v0
invoke-virtual {p0, v0}, Landroid/content/Intent;->addFlags(I)Landroid/content/Intent;
invoke-virtual {p1}, Landroid/content/Intent;->getExtras()Landroid/os/Bundle;
move-result-object v0
if-eqz v0, :done
new-instance v1, Landroid/os/Bundle;
invoke-direct {v1, v0}, Landroid/os/Bundle;-><init>(Landroid/os/Bundle;)V
invoke-virtual {p0}, Landroid/content/Intent;->getExtras()Landroid/os/Bundle;
move-result-object v0
if-eqz v0, :extras_set
invoke-virtual {v1, v0}, Landroid/os/Bundle;->putAll(Landroid/os/Bundle;)V
:extras_set
invoke-virtual {p0, v1}, Landroid/content/Intent;->replaceExtras(Landroid/os/Bundle;)Landroid/content/Intent;
:done
return-void'
	return body
}
