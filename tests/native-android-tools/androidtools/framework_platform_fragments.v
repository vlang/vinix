// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Nonvisual platform fragments share the host lifecycle and main queue. Only
// the retained add/commit/query surface is extended; no UI or back stack API.
fn platform_fragment_method(signature string, locals int, body string) string {
	return '.method ' + signature + '\n.locals ' + locals.str() + '\n' + body + '\n.end method'
}

fn platform_fragment_get(source string, signature string) !string {
	mut result := ''
	for block in source.split('.method ')[1..] {
		if !block.all_before('\n').ends_with(' ' + signature) { continue }
		if result != '' { return error('duplicate platform fragment method: ' + signature) }
		end := block.index('.end method') or { return error('unterminated platform fragment method') }
		result = '.method ' + block[..end + '.end method'.len]
	}
	if result == '' { return error('missing platform fragment method: ' + signature) }
	return result
}

fn platform_fragment_unique_methods(source string) ! {
	mut seen := map[string]bool{}
	if source.count('.method ') != source.count('.end method') { return error('unbalanced platform fragment methods') }
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		if name in seen || !block.contains('.end method') { return error('duplicate or unterminated platform fragment method') }
		seen[name] = true
	}
}

fn platform_fragment_class(source string, owner string, fields []string, methods []string) ! {
	if source.split_into_lines().filter(it.starts_with('.class ')) != ['.class public Landroid/app/' + owner + ';']
		|| source.split_into_lines().filter(it.starts_with('.super ')) != ['.super Ljava/lang/Object;']
		|| source.split_into_lines().filter(it.starts_with('.field ')) != fields
		|| source.count('.method ') != methods.len || source.count('.end method') != methods.len {
		return error('unexpected or already extended platform ' + owner)
	}
	for signature in methods { platform_fragment_get(source, signature)! }
}

fn platform_fragment_replace(source string, signature string, locals int, body string) !string {
	return framework_replace_method(source, signature, platform_fragment_method('public ' + signature, locals, body))
}

fn platform_fragment_failure(kind string, message string) string {
	return 'new-instance v0, Ljava/lang/' + kind + ';\nconst-string v1, "' + message + '"\ninvoke-direct {v0, v1}, Ljava/lang/' + kind + ';-><init>(Ljava/lang/String;)V\nthrow v0\n'
}

pub fn framework_platform_fragments_fragment(original string) !string {
	platform_fragment_class(original, 'Fragment', ['.field activity:Landroid/app/Activity;'],
		['<init>()V', 'getActivity()Landroid/app/Activity;', 'onCreate(Landroid/os/Bundle;)V', 'onDestroy()V', 'onPause()V', 'onResume()V', 'onStart()V', 'onStop()V'])!
	mut source := original + '\n.field vinixManager:Landroid/app/FragmentManager;\n.field vinixTag:Ljava/lang/String;\n.field vinixState:I\n.field vinixAdded:Z\n'
	source += '\n' + platform_fragment_method('public getTag()Ljava/lang/String;', 1,
		'iget-object v0, p0, Landroid/app/Fragment;->vinixTag:Ljava/lang/String;\nreturn-object v0')
	for signature in ['onAttach(Landroid/app/Activity;)V', 'onActivityCreated(Landroid/os/Bundle;)V', 'onDetach()V'] {
		source += '\n' + platform_fragment_method('public ' + signature, 0, 'return-void')
	}
	source += '\n' + platform_fragment_method('public onAttach(Landroid/content/Context;)V', 1,
		'instance-of v0, p1, Landroid/app/Activity;\nif-eqz v0, :done\ncheck-cast p1, Landroid/app/Activity;\ninvoke-virtual {p0, p1}, Landroid/app/Fragment;->onAttach(Landroid/app/Activity;)V\n:done\nreturn-void') + '\n'
	return source
}

pub fn framework_platform_fragments_transaction(original string) !string {
	platform_fragment_class(original, 'FragmentTransaction', ['.field private activity:Landroid/app/Activity;'],
		['<init>(Landroid/app/Activity;)V', 'add(Landroid/app/Fragment;Ljava/lang/String;)Landroid/app/FragmentTransaction;', 'commit()I'])!
	mut source := original + '\n.field vinixManager:Landroid/app/FragmentManager;\n.field private vinixAdds:Ljava/util/ArrayList;\n.field private vinixCommitted:Z\n'
	source = framework_replace_method(source, '<init>(Landroid/app/Activity;)V', platform_fragment_method('public constructor <init>(Landroid/app/Activity;)V', 1,
		'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, Landroid/app/FragmentTransaction;->activity:Landroid/app/Activity;\ninvoke-virtual {p1}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;\nmove-result-object v0\niput-object v0, p0, Landroid/app/FragmentTransaction;->vinixManager:Landroid/app/FragmentManager;\nnew-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\niput-object v0, p0, Landroid/app/FragmentTransaction;->vinixAdds:Ljava/util/ArrayList;\nreturn-void'))!
	source = platform_fragment_replace(source, 'add(Landroid/app/Fragment;Ljava/lang/String;)Landroid/app/FragmentTransaction;', 3, '
iget-boolean v0, p0, Landroid/app/FragmentTransaction;->vinixCommitted:Z
if-nez v0, :committed
if-eqz p1, :invalid
iget-object v2, p0, Landroid/app/FragmentTransaction;->vinixManager:Landroid/app/FragmentManager;
invoke-virtual {v2}, Landroid/app/FragmentManager;->vinixCheckHost()V
iget-object v0, p1, Landroid/app/Fragment;->vinixManager:Landroid/app/FragmentManager;
if-eqz v0, :owner_ok
if-ne v0, v2, :owner
:owner_ok
iget-object v0, p1, Landroid/app/Fragment;->vinixTag:Ljava/lang/String;
if-eqz p2, :tag_ok
if-eqz v0, :tag_ok
invoke-virtual {v0, p2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :tag
:tag_ok
iget-object v0, p0, Landroid/app/FragmentTransaction;->vinixAdds:Ljava/util/ArrayList;
invoke-virtual {v0, p1}, Ljava/util/ArrayList;->contains(Ljava/lang/Object;)Z
move-result v1
if-nez v1, :duplicate
iget-boolean v1, p1, Landroid/app/Fragment;->vinixAdded:Z
if-nez v1, :duplicate
iput-object v2, p1, Landroid/app/Fragment;->vinixManager:Landroid/app/FragmentManager;
if-eqz p2, :keep_tag
iput-object p2, p1, Landroid/app/Fragment;->vinixTag:Ljava/lang/String;
:keep_tag
invoke-virtual {v0, p1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
return-object p0
:committed
' + platform_fragment_failure('IllegalStateException', 'transaction already committed') + ':invalid\n' + platform_fragment_failure('IllegalArgumentException', 'fragment required') + ':owner\n' + platform_fragment_failure('IllegalStateException', 'fragment belongs to another manager') + ':tag\n' + platform_fragment_failure('IllegalStateException', 'cannot change fragment tag') + ':duplicate\n' + platform_fragment_failure('IllegalStateException', 'fragment already added'))!
	source = platform_fragment_replace(source, 'commit()I', 2, '
iget-boolean v0, p0, Landroid/app/FragmentTransaction;->vinixCommitted:Z
if-nez v0, :committed
const/4 v0, 1
iput-boolean v0, p0, Landroid/app/FragmentTransaction;->vinixCommitted:Z
iget-object v0, p0, Landroid/app/FragmentTransaction;->vinixManager:Landroid/app/FragmentManager;
invoke-virtual {v0, p0}, Landroid/app/FragmentManager;->vinixEnqueue(Landroid/app/FragmentTransaction;)V
const/4 v0, -1
return v0
:committed
' + platform_fragment_failure('IllegalStateException', 'transaction already committed'))!
	source += '\n' + platform_fragment_method('public vinixExecute()V', 4, '
iget-object v0, p0, Landroid/app/FragmentTransaction;->vinixAdds:Ljava/util/ArrayList;
const/4 v1, 0
:try_start
:loop
invoke-virtual {v0}, Ljava/util/ArrayList;->size()I
move-result v2
if-ge v1, v2, :done
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v2
check-cast v2, Landroid/app/Fragment;
iget-object v3, p0, Landroid/app/FragmentTransaction;->vinixManager:Landroid/app/FragmentManager;
invoke-virtual {v3, v2}, Landroid/app/FragmentManager;->vinixAdd(Landroid/app/Fragment;)V
add-int/lit8 v1, v1, 1
goto :loop
:done
:try_end
invoke-virtual {p0}, Landroid/app/FragmentTransaction;->vinixCancel()V
return-void
:failed
move-exception v3
:cancel_start
invoke-virtual {p0}, Landroid/app/FragmentTransaction;->vinixCancel()V
:cancel_end
goto :rethrow
:cancel_failed
move-exception v2
:rethrow
throw v3
.catchall {:cancel_start .. :cancel_end} :cancel_failed
.catchall {:try_start .. :try_end} :failed')
	source += '\n' + platform_fragment_method('public vinixCancel()V', 5, '
iget-object v0, p0, Landroid/app/FragmentTransaction;->vinixAdds:Ljava/util/ArrayList;
const/4 v1, 0
:loop
invoke-virtual {v0}, Ljava/util/ArrayList;->size()I
move-result v2
if-ge v1, v2, :done
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v2
check-cast v2, Landroid/app/Fragment;
add-int/lit8 v1, v1, 1
iget-boolean v3, v2, Landroid/app/Fragment;->vinixAdded:Z
if-nez v3, :loop
iget-object v3, v2, Landroid/app/Fragment;->vinixManager:Landroid/app/FragmentManager;
iget-object v4, p0, Landroid/app/FragmentTransaction;->vinixManager:Landroid/app/FragmentManager;
if-ne v3, v4, :loop
const/4 v3, 0
iput-object v3, v2, Landroid/app/Fragment;->vinixManager:Landroid/app/FragmentManager;
goto :loop
:done
return-void') + '\n'
	return source
}

pub fn framework_platform_fragments_runner() string {
	return '.class public final Landroid/app/VinixFragmentCommit;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n.field private manager:Landroid/app/FragmentManager;\n' +
		platform_fragment_method('public constructor <init>(Landroid/app/FragmentManager;)V', 0, 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, Landroid/app/VinixFragmentCommit;->manager:Landroid/app/FragmentManager;\nreturn-void') + '\n' +
		platform_fragment_method('public run()V', 1, 'iget-object v0, p0, Landroid/app/VinixFragmentCommit;->manager:Landroid/app/FragmentManager;\ninvoke-virtual {v0}, Landroid/app/FragmentManager;->executePendingTransactions()Z\nreturn-void') + '\n'
}

pub fn framework_platform_fragments_classes() map[string]string {
	return {'android/app/VinixFragmentCommit': framework_platform_fragments_runner()}
}

pub fn framework_platform_fragments_manager(original string) !string {
	platform_fragment_class(original, 'FragmentManager', ['.field private activity:Landroid/app/Activity;'],
		['<init>(Landroid/app/Activity;)V', 'beginTransaction()Landroid/app/FragmentTransaction;', 'executePendingTransactions()Z', 'findFragmentByTag(Ljava/lang/String;)Landroid/app/Fragment;'])!
	mut source := original + '\n.field private vinixPending:Ljava/util/ArrayList;\n.field private vinixHandler:Landroid/os/Handler;\n.field private vinixRunner:Ljava/lang/Runnable;\n.field private vinixState:I\n.field private vinixExecuting:Z\n.field private vinixDestroyed:Z\n'
	source = framework_replace_method(source, '<init>(Landroid/app/Activity;)V', platform_fragment_method('public constructor <init>(Landroid/app/Activity;)V', 2, '
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Landroid/app/FragmentManager;->activity:Landroid/app/Activity;
new-instance v0, Ljava/util/ArrayList;
invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V
iput-object v0, p0, Landroid/app/FragmentManager;->vinixPending:Ljava/util/ArrayList;
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
iput-object v0, p0, Landroid/app/FragmentManager;->vinixHandler:Landroid/os/Handler;
new-instance v0, Landroid/app/VinixFragmentCommit;
invoke-direct {v0, p0}, Landroid/app/VinixFragmentCommit;-><init>(Landroid/app/FragmentManager;)V
iput-object v0, p0, Landroid/app/FragmentManager;->vinixRunner:Ljava/lang/Runnable;
return-void'))!
	source = platform_fragment_replace(source, 'beginTransaction()Landroid/app/FragmentTransaction;', 2, '
new-instance v0, Landroid/app/FragmentTransaction;
iget-object v1, p0, Landroid/app/FragmentManager;->activity:Landroid/app/Activity;
invoke-direct {v0, v1}, Landroid/app/FragmentTransaction;-><init>(Landroid/app/Activity;)V
iput-object p0, v0, Landroid/app/FragmentTransaction;->vinixManager:Landroid/app/FragmentManager;
return-object v0')!
	source = platform_fragment_replace(source, 'findFragmentByTag(Ljava/lang/String;)Landroid/app/Fragment;', 3, '
if-eqz p1, :missing
iget-object v0, p0, Landroid/app/FragmentManager;->activity:Landroid/app/Activity;
iget-object v0, v0, Landroid/app/Activity;->fragments:Ljava/util/List;
invoke-interface {v0}, Ljava/util/List;->size()I
move-result v1
add-int/lit8 v1, v1, -1
:loop
if-ltz v1, :missing
invoke-interface {v0, v1}, Ljava/util/List;->get(I)Ljava/lang/Object;
move-result-object v2
check-cast v2, Landroid/app/Fragment;
iget-object v2, v2, Landroid/app/Fragment;->vinixTag:Ljava/lang/String;
invoke-virtual {p1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-nez v2, :found
add-int/lit8 v1, v1, -1
goto :loop
:found
invoke-interface {v0, v1}, Ljava/util/List;->get(I)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/app/Fragment;
return-object v0
:missing
const/4 v0, 0
return-object v0')!
	source += '\n' + platform_fragment_method('public vinixCheckHost()V', 2, '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-ne v0, v1, :thread
iget-boolean v0, p0, Landroid/app/FragmentManager;->vinixDestroyed:Z
if-nez v0, :destroyed
return-void
:thread
' + platform_fragment_failure('IllegalStateException', 'fragment operations require the main thread') + ':destroyed\n' + platform_fragment_failure('IllegalStateException', 'fragment host destroyed'))
	source += '\n' + platform_fragment_method('public vinixEnqueue(Landroid/app/FragmentTransaction;)V', 2, '
invoke-virtual {p0}, Landroid/app/FragmentManager;->vinixCheckHost()V
iget-object v0, p0, Landroid/app/FragmentManager;->vinixPending:Ljava/util/ArrayList;
invoke-virtual {v0, p1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
iget-object v0, p0, Landroid/app/FragmentManager;->vinixHandler:Landroid/os/Handler;
iget-object v1, p0, Landroid/app/FragmentManager;->vinixRunner:Ljava/lang/Runnable;
invoke-virtual {v0, v1}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
move-result v0
if-eqz v0, :failed
return-void
:failed
' + platform_fragment_failure('IllegalStateException', 'fragment main queue rejected commit'))
	source += '\n' + platform_fragment_method('public vinixAdd(Landroid/app/Fragment;)V', 2, '
iget-boolean v0, p0, Landroid/app/FragmentManager;->vinixDestroyed:Z
if-nez v0, :done
iget-boolean v0, p1, Landroid/app/Fragment;->vinixAdded:Z
if-nez v0, :duplicate
const/4 v0, 1
iput-boolean v0, p1, Landroid/app/Fragment;->vinixAdded:Z
iget-object v0, p0, Landroid/app/FragmentManager;->activity:Landroid/app/Activity;
iget-object v0, v0, Landroid/app/Activity;->fragments:Ljava/util/List;
invoke-interface {v0, p1}, Ljava/util/List;->add(Ljava/lang/Object;)Z
invoke-direct {p0, p1}, Landroid/app/FragmentManager;->vinixMoveFragment(Landroid/app/Fragment;)V
:done
return-void
:duplicate
' + platform_fragment_failure('IllegalStateException', 'fragment already added'))
	source += '\n' + platform_fragment_method('private vinixCancelPosted()V', 2,
		'iget-object v0, p0, Landroid/app/FragmentManager;->vinixHandler:Landroid/os/Handler;\niget-object v1, p0, Landroid/app/FragmentManager;->vinixRunner:Ljava/lang/Runnable;\ninvoke-virtual {v0, v1}, Landroid/os/Handler;->removeCallbacks(Ljava/lang/Runnable;)V\nreturn-void')
	source += '\n' + platform_fragment_method('private vinixSynchronize()V', 5, '
:snapshot
iget v4, p0, Landroid/app/FragmentManager;->vinixState:I
iget-object v0, p0, Landroid/app/FragmentManager;->activity:Landroid/app/Activity;
iget-object v0, v0, Landroid/app/Activity;->fragments:Ljava/util/List;
invoke-interface {v0}, Ljava/util/List;->toArray()[Ljava/lang/Object;
move-result-object v0
const/4 v1, 0
:loop
array-length v2, v0
if-ge v1, v2, :finish
aget-object v3, v0, v1
check-cast v3, Landroid/app/Fragment;
invoke-direct {p0, v3}, Landroid/app/FragmentManager;->vinixMoveFragment(Landroid/app/Fragment;)V
add-int/lit8 v1, v1, 1
goto :loop
:finish
iget v2, p0, Landroid/app/FragmentManager;->vinixState:I
if-ne v2, v4, :snapshot
iget-boolean v0, p0, Landroid/app/FragmentManager;->vinixDestroyed:Z
if-eqz v0, :done
invoke-direct {p0}, Landroid/app/FragmentManager;->vinixTerminalCleanup()V
:done
return-void')
	source = platform_fragment_replace(source, 'executePendingTransactions()Z', 3, '
iget-boolean v0, p0, Landroid/app/FragmentManager;->vinixDestroyed:Z
if-nez v0, :empty
invoke-virtual {p0}, Landroid/app/FragmentManager;->vinixCheckHost()V
iget-boolean v0, p0, Landroid/app/FragmentManager;->vinixExecuting:Z
if-nez v0, :reentrant
iget-object v0, p0, Landroid/app/FragmentManager;->vinixPending:Ljava/util/ArrayList;
invoke-virtual {v0}, Ljava/util/ArrayList;->isEmpty()Z
move-result v1
if-nez v1, :empty
const/4 v1, 1
iput-boolean v1, p0, Landroid/app/FragmentManager;->vinixExecuting:Z
:try_start
invoke-direct {p0}, Landroid/app/FragmentManager;->vinixCancelPosted()V
:loop
invoke-virtual {v0}, Ljava/util/ArrayList;->isEmpty()Z
move-result v1
if-nez v1, :sync
iget-boolean v1, p0, Landroid/app/FragmentManager;->vinixDestroyed:Z
if-nez v1, :sync
const/4 v1, 0
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->remove(I)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/app/FragmentTransaction;
invoke-virtual {v1}, Landroid/app/FragmentTransaction;->vinixExecute()V
goto :loop
:sync
invoke-direct {p0}, Landroid/app/FragmentManager;->vinixSynchronize()V
invoke-virtual {v0}, Ljava/util/ArrayList;->isEmpty()Z
move-result v1
if-eqz v1, :loop
invoke-direct {p0}, Landroid/app/FragmentManager;->vinixCancelPosted()V
:try_end
const/4 v0, 0
iput-boolean v0, p0, Landroid/app/FragmentManager;->vinixExecuting:Z
const/4 v0, 1
return v0
:cleanup
move-exception v2
const/4 v0, 0
iput-boolean v0, p0, Landroid/app/FragmentManager;->vinixExecuting:Z
iget-boolean v0, p0, Landroid/app/FragmentManager;->vinixDestroyed:Z
if-eqz v0, :rethrow
:terminal_start
invoke-direct {p0}, Landroid/app/FragmentManager;->vinixTerminalCleanup()V
:terminal_end
goto :rethrow
:terminal_failed
move-exception v0
:rethrow
throw v2
.catchall {:terminal_start .. :terminal_end} :terminal_failed
.catchall {:try_start .. :try_end} :cleanup
:empty
const/4 v0, 0
return v0
:reentrant
' + platform_fragment_failure('IllegalStateException', 'fragment manager already executing'))!
	source += '\n' + platform_fragment_method('public vinixMoveToState(I)V', 2, '
iget-boolean v0, p0, Landroid/app/FragmentManager;->vinixDestroyed:Z
if-nez v0, :done
invoke-virtual {p0}, Landroid/app/FragmentManager;->vinixCheckHost()V
:try_start
iget-boolean v0, p0, Landroid/app/FragmentManager;->vinixExecuting:Z
if-nez v0, :set_state
if-nez p1, :set_state
invoke-virtual {p0}, Landroid/app/FragmentManager;->executePendingTransactions()Z
iget-boolean v1, p0, Landroid/app/FragmentManager;->vinixDestroyed:Z
if-nez v1, :done
:set_state
iput p1, p0, Landroid/app/FragmentManager;->vinixState:I
if-nez p1, :not_destroyed
const/4 v1, 1
iput-boolean v1, p0, Landroid/app/FragmentManager;->vinixDestroyed:Z
:not_destroyed
if-nez v0, :done
const/4 v0, 1
iput-boolean v0, p0, Landroid/app/FragmentManager;->vinixExecuting:Z
invoke-direct {p0}, Landroid/app/FragmentManager;->vinixSynchronize()V
:try_end
const/4 v0, 0
iput-boolean v0, p0, Landroid/app/FragmentManager;->vinixExecuting:Z
invoke-virtual {p0}, Landroid/app/FragmentManager;->executePendingTransactions()Z
:done
return-void
:cleanup
move-exception v1
if-nez p1, :preserve_host
const/4 v0, 0
iput v0, p0, Landroid/app/FragmentManager;->vinixState:I
const/4 v0, 1
iput-boolean v0, p0, Landroid/app/FragmentManager;->vinixDestroyed:Z
:preserve_host
const/4 v0, 0
iput-boolean v0, p0, Landroid/app/FragmentManager;->vinixExecuting:Z
iget-boolean v0, p0, Landroid/app/FragmentManager;->vinixDestroyed:Z
if-eqz v0, :rethrow
:terminal_start
invoke-direct {p0}, Landroid/app/FragmentManager;->vinixTerminalCleanup()V
:terminal_end
goto :rethrow
:terminal_failed
move-exception v0
:rethrow
throw v1
.catchall {:terminal_start .. :terminal_end} :terminal_failed
.catchall {:try_start .. :try_end} :cleanup')
	source += '\n' + platform_fragment_method('private vinixTerminalCleanup()V', 4, '
iget-object v0, p0, Landroid/app/FragmentManager;->vinixPending:Ljava/util/ArrayList;
const/4 v1, 0
:pending
invoke-virtual {v0}, Ljava/util/ArrayList;->size()I
move-result v3
if-ge v1, v3, :pending_done
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v2
check-cast v2, Landroid/app/FragmentTransaction;
invoke-virtual {v2}, Landroid/app/FragmentTransaction;->vinixCancel()V
add-int/lit8 v1, v1, 1
goto :pending
:pending_done
invoke-virtual {v0}, Ljava/util/ArrayList;->clear()V
iget-object v0, p0, Landroid/app/FragmentManager;->activity:Landroid/app/Activity;
iget-object v0, v0, Landroid/app/Activity;->fragments:Ljava/util/List;
const/4 v1, 0
:added
invoke-interface {v0}, Ljava/util/List;->size()I
move-result v3
if-ge v1, v3, :added_done
invoke-interface {v0, v1}, Ljava/util/List;->get(I)Ljava/lang/Object;
move-result-object v2
check-cast v2, Landroid/app/Fragment;
const/4 v3, 0
iput-object v3, v2, Landroid/app/Fragment;->activity:Landroid/app/Activity;
iput-object v3, v2, Landroid/app/Fragment;->vinixManager:Landroid/app/FragmentManager;
iput-boolean v3, v2, Landroid/app/Fragment;->vinixAdded:Z
iput v3, v2, Landroid/app/Fragment;->vinixState:I
add-int/lit8 v1, v1, 1
goto :added
:added_done
invoke-interface {v0}, Ljava/util/List;->clear()V
invoke-direct {p0}, Landroid/app/FragmentManager;->vinixCancelPosted()V
return-void')
	source += '\n' + platform_fragment_method('private vinixMoveFragment(Landroid/app/Fragment;)V', 3, platform_fragment_move_body()) + '\n'
	return source
}

fn platform_fragment_move_body() string {
	// Each completed boundary is stored before calling app code. Reentrant host
	// teardown requests change the target; the outer driver completes them once.
	mut body := ':loop\niget v0, p1, Landroid/app/Fragment;->vinixState:I\niget v1, p0, Landroid/app/FragmentManager;->vinixState:I\nif-eq v0, v1, :done\nif-gt v0, v1, :down\npacked-switch v0, :up_states\ngoto :done\n'
	for i, name in ['Attach', 'Create', 'ActivityCreated', 'Start', 'Resume'] {
		body += ':up_' + i.str() + '\nconst/4 v0, ' + (i + 1).str() + '\niput v0, p1, Landroid/app/Fragment;->vinixState:I\n'
		if i == 0 {
			body += 'iget-object v0, p0, Landroid/app/FragmentManager;->activity:Landroid/app/Activity;\niput-object v0, p1, Landroid/app/Fragment;->activity:Landroid/app/Activity;\ninvoke-virtual {p1, v0}, Landroid/app/Fragment;->onAttach(Landroid/content/Context;)V\n'
		} else if i in [1, 2] {
			body += 'const/4 v0, 0\ninvoke-virtual {p1, v0}, Landroid/app/Fragment;->on' + name + '(Landroid/os/Bundle;)V\n'
		} else { body += 'invoke-virtual {p1}, Landroid/app/Fragment;->on' + name + '()V\n' }
		body += 'goto :loop\n'
	}
	body += ':down\npacked-switch v0, :down_states\ngoto :done\n'
	for i, name in ['Detach', 'Destroy', '', 'Stop', 'Pause'] {
		body += ':down_' + (i + 1).str() + '\nconst/4 v0, ' + i.str() + '\niput v0, p1, Landroid/app/Fragment;->vinixState:I\n'
		if name == 'Detach' {
			body += ':detach_start\ninvoke-virtual {p1}, Landroid/app/Fragment;->onDetach()V\n:detach_end\nconst/4 v0, 0\niput-object v0, p1, Landroid/app/Fragment;->activity:Landroid/app/Activity;\niput-object v0, p1, Landroid/app/Fragment;->vinixManager:Landroid/app/FragmentManager;\niput-boolean v0, p1, Landroid/app/Fragment;->vinixAdded:Z\ngoto :loop\n:detach_failed\nmove-exception v2\nconst/4 v0, 0\niput-object v0, p1, Landroid/app/Fragment;->activity:Landroid/app/Activity;\niput-object v0, p1, Landroid/app/Fragment;->vinixManager:Landroid/app/FragmentManager;\niput-boolean v0, p1, Landroid/app/Fragment;->vinixAdded:Z\nthrow v2\n.catchall {:detach_start .. :detach_end} :detach_failed\n'
		} else {
			if name != '' { body += 'invoke-virtual {p1}, Landroid/app/Fragment;->on' + name + '()V\n' }
			body += 'goto :loop\n'
		}
	}
	body += ':done\nreturn-void\n:up_states\n.packed-switch 0\n:up_0\n:up_1\n:up_2\n:up_3\n:up_4\n.end packed-switch\n:down_states\n.packed-switch 1\n:down_1\n:down_2\n:down_3\n:down_4\n:down_5\n.end packed-switch'
	return body
}

fn platform_fragment_remove_loop(source string, signature string, callback string, replacement string) !string {
	original := platform_fragment_get(source, signature)!
	mut lines := original.split_into_lines().map(it.trim_space()).filter(it != '').join('\n')
	start := lines.index('iget-object v0, p0, Landroid/app/Activity;->fragments:Ljava/util/List;\n') or { return error('missing old fragment lifecycle loop') }
	rest := lines[start..]
	if rest.count('Landroid/app/Fragment;->' + callback) != 1 { return error('unexpected old fragment callback') }
	label := rest.all_after('if-eqz v0, :').all_before('\n')
	if label == '' { return error('missing fragment loop exit') }
	end_marker := '\n:' + label + '\n'
	end := rest.index(end_marker) or { return error('missing fragment loop target') }
	loop_label := if callback == 'onStart()V' { 'goto_25' } else { 'goto_d' }
	exit_label := if callback == 'onStart()V' { 'cond_35' } else { 'cond_1d' }
	args := if callback == 'onCreate(Landroid/os/Bundle;)V' { 'v0, p1' } else { 'v0' }
	expected := 'iget-object v0, p0, Landroid/app/Activity;->fragments:Ljava/util/List;\n' +
		'invoke-interface {v0}, Ljava/util/List;->iterator()Ljava/util/Iterator;\nmove-result-object v1\n:' + loop_label + '\n' +
		'invoke-interface {v1}, Ljava/util/Iterator;->hasNext()Z\nmove-result v0\nif-eqz v0, :' + exit_label + '\n' +
		'invoke-interface {v1}, Ljava/util/Iterator;->next()Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, Landroid/app/Fragment;\n' +
		'invoke-virtual {' + args + '}, Landroid/app/Fragment;->' + callback + '\ngoto :' + loop_label + '\n:' + exit_label + '\n'
	if rest[..end + end_marker.len] != expected { return error('unexpected instructions inside old fragment lifecycle loop') }
	lines = lines[..start] + replacement + rest[end + end_marker.len..]
	if lines.contains('Landroid/app/Fragment;->') || lines.contains('->fragments:') { return error('fragment loop was not fully removed') }
	return source.replace(original, lines)
}

fn platform_fragment_host_move(state int) string {
	return 'invoke-virtual {p0}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;\nmove-result-object v0\nconst/4 v1, ' + state.str() + '\ninvoke-virtual {v0, v1}, Landroid/app/FragmentManager;->vinixMoveToState(I)V\nconst/4 v1, 0\n'
}

pub fn framework_platform_fragments_activity(original string) !string {
	platform_fragment_unique_methods(original)!
	if original.split_into_lines().filter(it.starts_with('.class ')) != ['.class public Landroid/app/Activity;']
		|| original.split_into_lines().filter(it.starts_with('.super ')) != ['.super Landroid/view/ContextThemeWrapper;']
		|| original.contains('vinixPlatformFragments') || original.count('.field fragments:Ljava/util/List;') != 1 {
		return error('canonical Activity fragment list required')
	}
	getter := platform_fragment_get(original, 'getFragmentManager()Landroid/app/FragmentManager;')!
	if getter.count('new-instance v0, Landroid/app/FragmentManager;') != 1 || getter.contains('iget-object') {
		return error('unexpected Activity fragment manager getter')
	}
	mut source := original + '\n.field private vinixPlatformFragments:Landroid/app/FragmentManager;\n'
	source = platform_fragment_replace(source, 'getFragmentManager()Landroid/app/FragmentManager;', 1,
		'iget-object v0, p0, Landroid/app/Activity;->vinixPlatformFragments:Landroid/app/FragmentManager;\nif-nez v0, :done\nnew-instance v0, Landroid/app/FragmentManager;\ninvoke-direct {v0, p0}, Landroid/app/FragmentManager;-><init>(Landroid/app/Activity;)V\niput-object v0, p0, Landroid/app/Activity;->vinixPlatformFragments:Landroid/app/FragmentManager;\n:done\nreturn-object v0')!
	for name in ['Create', 'Start', 'Resume', 'Pause', 'Stop', 'Destroy'] {
		suffix := if name == 'Create' { '(Landroid/os/Bundle;)V' } else { '()V' }
		source = platform_fragment_remove_loop(source, 'vinixLifecycleOn' + name + suffix, 'on' + name + suffix,
			if name == 'Create' { platform_fragment_host_move(2) } else { '' })!
		signature := 'vinixPerform' + name + suffix
		method := platform_fragment_get(source, signature)!
		needle := 'invoke-virtual {' + (if name == 'Create' { 'p0, p1' } else { 'p0' }) + '}, Landroid/app/Activity;->on' + name + suffix
		if method.count(needle) != 1 { return error('unique Activity callback boundary required') }
		state := match name { 'Create' { 3 } 'Start' { 4 } 'Resume' { 5 } 'Pause' { 4 } 'Stop' { 3 } else { 0 } }
		move := platform_fragment_host_move(state)
		mut replacement := if name in ['Pause', 'Stop', 'Destroy'] { move + needle } else { needle + '\n' + move }
		if name == 'Destroy' { replacement = 'const/4 v0, 1\niput-boolean v0, p0, Landroid/app/Activity;->destroyed:Z\n' + replacement }
		if name in ['Start', 'Resume'] {
			replacement = 'invoke-virtual {p0}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;\nmove-result-object v0\ninvoke-virtual {v0}, Landroid/app/FragmentManager;->executePendingTransactions()Z\n' + replacement
		}
		source = source.replace(method, method.replace(needle, replacement))
	}
	return source
}

pub fn framework_platform_fragments(smali string) ! {
	for name in ['Activity', 'Fragment', 'FragmentManager', 'FragmentTransaction'] {
		path := smali + '/android/app/' + name + '.smali'
		old := os.read_file(path)!
		patched := match name {
			'Activity' { framework_platform_fragments_activity(old)! }
			'Fragment' { framework_platform_fragments_fragment(old)! }
			'FragmentManager' { framework_platform_fragments_manager(old)! }
			else { framework_platform_fragments_transaction(old)! }
		}
		os.write_file(path, patched)!
	}
	for name, source in framework_platform_fragments_classes() { os.write_file(smali + '/' + name + '.smali', source)! }
}
