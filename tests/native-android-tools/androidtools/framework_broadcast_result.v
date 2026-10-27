// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn broadcast_method(signature string, locals int, body string) string {
	return '\n.method ' + signature + '\n    .locals ' + locals.str() + '\n' + body + '\n.end method\n'
}

fn broadcast_replace(source string, header string, replacement string) !string {
	if source.count(header + '\n') != 1 { return error('missing exact broadcast method: ' + header) }
	return framework_replace_method(source, header.all_after_last(' '), replacement)!
}

fn broadcast_baseline(source string, declaration string, parent string, count int) ! {
	if source.split_into_lines().filter(it.starts_with('.class ')) != [declaration]
		|| source.split_into_lines().filter(it.starts_with('.super ')) != ['.super L' + parent + ';']
		|| source.count('.method ') != count || source.count('.end method') != count
		|| source.contains('vinixPending') || source.contains('vinixDispatch(') {
		return error('unexpected or already extended broadcast class')
	}
}

pub fn framework_broadcast_receiver(source string) !string {
	broadcast_baseline(source, '.class public abstract Landroid/content/BroadcastReceiver;', 'java/lang/Object', 4)!
	if source.contains('.field ') { return error('unexpected BroadcastReceiver fields') }
	mut result := broadcast_replace(source, '.method public goAsync()Landroid/content/BroadcastReceiver$PendingResult;',
		broadcast_method('public final goAsync()Landroid/content/BroadcastReceiver$PendingResult;', 2, '
    iget-object v0, p0, Landroid/content/BroadcastReceiver;->vinixPending:Landroid/content/BroadcastReceiver$PendingResult;
    const/4 v1, 0x0
    iput-object v1, p0, Landroid/content/BroadcastReceiver;->vinixPending:Landroid/content/BroadcastReceiver$PendingResult;
    return-object v0'))!
	result = broadcast_replace(result, '.method public isOrderedBroadcast()Z',
		broadcast_method('public final isOrderedBroadcast()Z', 1, '
    const/4 v0, 0x0
    return v0'))!
	result += '\n.field private vinixPending:Landroid/content/BroadcastReceiver$PendingResult;\n'
	result += broadcast_method('private vinixRequirePending()Landroid/content/BroadcastReceiver$PendingResult;', 2, '
    iget-object v0, p0, Landroid/content/BroadcastReceiver;->vinixPending:Landroid/content/BroadcastReceiver$PendingResult;
    if-nez v0, :present
    new-instance v0, Ljava/lang/IllegalStateException;
    const-string v1, "Call while result is not pending"
    invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
    throw v0
    :present
    return-object v0')
	for spec in [
		['setResultCode', '(I)V', 'p1'],
		['setResultData', '(Ljava/lang/String;)V', 'p1'],
		['setResultExtras', '(Landroid/os/Bundle;)V', 'p1'],
		['setResult', '(ILjava/lang/String;Landroid/os/Bundle;)V', 'p1, p2, p3'],
		['abortBroadcast', '()V', ''],
	] {
		args := if spec[2] == '' { 'v0' } else { 'v0, ' + spec[2] }
		result += broadcast_method('public final ' + spec[0] + spec[1], 1,
			'    invoke-direct {p0}, Landroid/content/BroadcastReceiver;->vinixRequirePending()Landroid/content/BroadcastReceiver$PendingResult;\n' +
			'    move-result-object v0\n    invoke-virtual {' + args + '}, Landroid/content/BroadcastReceiver$PendingResult;->' + spec[0] + spec[1] + '\n    return-void')
	}
	for spec in [
		['getResultCode', '()I', 'const/4 v0, 0x0', 'move-result', 'return', 'v0'],
		['getResultData', '()Ljava/lang/String;', 'const/4 v0, 0x0', 'move-result-object', 'return-object', 'v0'],
		['getResultExtras', '(Z)Landroid/os/Bundle;', 'const/4 v0, 0x0', 'move-result-object', 'return-object', 'v0, p1'],
		['getAbortBroadcast', '()Z', 'const/4 v0, 0x0', 'move-result', 'return', 'v0'],
	] {
		result += broadcast_method('public final ' + spec[0] + spec[1], 1,
			'    iget-object v0, p0, Landroid/content/BroadcastReceiver;->vinixPending:Landroid/content/BroadcastReceiver$PendingResult;\n' +
			'    if-eqz v0, :empty\n    invoke-virtual {' + spec[5] + '}, Landroid/content/BroadcastReceiver$PendingResult;->' + spec[0] + spec[1] +
			'\n    ' + spec[3] + ' v0\n    ' + spec[4] + ' v0\n    :empty\n    ' + spec[2] + '\n    ' + spec[4] + ' v0')
	}
	result += broadcast_method('public final clearAbortBroadcast()V', 1, '
    iget-object v0, p0, Landroid/content/BroadcastReceiver;->vinixPending:Landroid/content/BroadcastReceiver$PendingResult;
    if-eqz v0, :done
    invoke-virtual {v0}, Landroid/content/BroadcastReceiver$PendingResult;->clearAbortBroadcast()V
    :done
    return-void')
	result += broadcast_method('public final isInitialStickyBroadcast()Z', 1, '
    const/4 v0, 0x0
    return v0')
	result += broadcast_method('private vinixFinish()V', 2, '
    iget-object v0, p0, Landroid/content/BroadcastReceiver;->vinixPending:Landroid/content/BroadcastReceiver$PendingResult;
    const/4 v1, 0x0
    iput-object v1, p0, Landroid/content/BroadcastReceiver;->vinixPending:Landroid/content/BroadcastReceiver$PendingResult;
    if-eqz v0, :done
    invoke-virtual {v0}, Landroid/content/BroadcastReceiver$PendingResult;->finish()V
    :done
    return-void')
	result += broadcast_method('public final vinixDispatch(Landroid/content/Context;Landroid/content/Intent;Z)V', 2, '
    iget-object v0, p0, Landroid/content/BroadcastReceiver;->vinixPending:Landroid/content/BroadcastReceiver$PendingResult;
    if-eqz v0, :available
    new-instance v0, Ljava/lang/IllegalStateException;
    const-string v1, "Receiver already handling a broadcast"
    invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
    throw v0
    :available
    new-instance v0, Landroid/content/BroadcastReceiver$PendingResult;
    invoke-direct {v0, p3}, Landroid/content/BroadcastReceiver$PendingResult;-><init>(Z)V
    iput-object v0, p0, Landroid/content/BroadcastReceiver;->vinixPending:Landroid/content/BroadcastReceiver$PendingResult;
    :start
    invoke-virtual {p0, p1, p2}, Landroid/content/BroadcastReceiver;->onReceive(Landroid/content/Context;Landroid/content/Intent;)V
    :end
    invoke-direct {p0}, Landroid/content/BroadcastReceiver;->vinixFinish()V
    return-void
    :failed
    move-exception v0
    invoke-direct {p0}, Landroid/content/BroadcastReceiver;->vinixFinish()V
    throw v0
    .catchall {:start .. :end} :failed')
	return result
}

pub fn framework_broadcast_pending(source string) !string {
	broadcast_baseline(source, '.class public Landroid/content/BroadcastReceiver$PendingResult;', 'java/lang/Object', 3)!
	if source.contains('.field ') { return error('unexpected PendingResult fields') }
	mut result := broadcast_replace(source, '.method public finish()V',
		broadcast_method('public final finish()V', 2, '
    iget-boolean v0, p0, Landroid/content/BroadcastReceiver$PendingResult;->vinixRegistered:Z
    if-nez v0, :done
    monitor-enter p0
    :start
    iget-boolean v0, p0, Landroid/content/BroadcastReceiver$PendingResult;->vinixFinished:Z
    if-eqz v0, :finish
    new-instance v0, Ljava/lang/IllegalStateException;
    const-string v1, "Broadcast already finished"
    invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
    throw v0
    :finish
    const/4 v0, 0x1
    iput-boolean v0, p0, Landroid/content/BroadcastReceiver$PendingResult;->vinixFinished:Z
    :end
    monitor-exit p0
    :done
    return-void
    :failed
    move-exception v0
    monitor-exit p0
    throw v0
    .catchall {:start .. :end} :failed'))!
	result = broadcast_replace(result, '.method public setResultCode(I)V',
		broadcast_method('public final setResultCode(I)V', 0, '
    invoke-static {}, Landroid/content/BroadcastReceiver$PendingResult;->vinixWarnUnordered()V
    iput p1, p0, Landroid/content/BroadcastReceiver$PendingResult;->vinixCode:I
    return-void'))!
	result += '
.field private final vinixRegistered:Z
.field private vinixCode:I
.field private vinixData:Ljava/lang/String;
.field private vinixExtras:Landroid/os/Bundle;
.field private vinixAbort:Z
.field private vinixFinished:Z
'
	result += broadcast_method('public constructor <init>(Z)V', 1, '
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    iput-boolean p1, p0, Landroid/content/BroadcastReceiver$PendingResult;->vinixRegistered:Z
    const/4 v0, -0x1
    iput v0, p0, Landroid/content/BroadcastReceiver$PendingResult;->vinixCode:I
    return-void')
	result += broadcast_method('private static vinixWarnUnordered()V', 2, '
    const-string v0, "BroadcastReceiver"
    const-string v1, "Returning local result during an unordered broadcast"
    invoke-static {v0, v1}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I
    return-void')
	for spec in [
		['getResultCode()I', 'iget', 'vinixCode:I', 'return'],
		['getResultData()Ljava/lang/String;', 'iget-object', 'vinixData:Ljava/lang/String;', 'return-object'],
		['getAbortBroadcast()Z', 'iget-boolean', 'vinixAbort:Z', 'return'],
	] {
		result += broadcast_method('public final ' + spec[0], 1,
			'    ' + spec[1] + ' v0, p0, Landroid/content/BroadcastReceiver$PendingResult;->' + spec[2] + '\n    ' + spec[3] + ' v0')
	}
	for spec in [
		['setResultData(Ljava/lang/String;)V', 'vinixData:Ljava/lang/String;'],
		['setResultExtras(Landroid/os/Bundle;)V', 'vinixExtras:Landroid/os/Bundle;'],
	] {
		result += broadcast_method('public final ' + spec[0], 0,
			'    invoke-static {}, Landroid/content/BroadcastReceiver$PendingResult;->vinixWarnUnordered()V\n' +
			'    iput-object p1, p0, Landroid/content/BroadcastReceiver$PendingResult;->' + spec[1] + '\n    return-void')
	}
	result += broadcast_method('public final getResultExtras(Z)Landroid/os/Bundle;', 1, '
    iget-object v0, p0, Landroid/content/BroadcastReceiver$PendingResult;->vinixExtras:Landroid/os/Bundle;
    if-nez v0, :done
    if-eqz p1, :done
    new-instance v0, Landroid/os/Bundle;
    invoke-direct {v0}, Landroid/os/Bundle;-><init>()V
    iput-object v0, p0, Landroid/content/BroadcastReceiver$PendingResult;->vinixExtras:Landroid/os/Bundle;
    :done
    return-object v0')
	result += broadcast_method('public final setResult(ILjava/lang/String;Landroid/os/Bundle;)V', 0, '
    invoke-static {}, Landroid/content/BroadcastReceiver$PendingResult;->vinixWarnUnordered()V
    iput p1, p0, Landroid/content/BroadcastReceiver$PendingResult;->vinixCode:I
    iput-object p2, p0, Landroid/content/BroadcastReceiver$PendingResult;->vinixData:Ljava/lang/String;
    iput-object p3, p0, Landroid/content/BroadcastReceiver$PendingResult;->vinixExtras:Landroid/os/Bundle;
    return-void')
	result += broadcast_method('public final abortBroadcast()V', 1, '
    invoke-static {}, Landroid/content/BroadcastReceiver$PendingResult;->vinixWarnUnordered()V
    const/4 v0, 0x1
    iput-boolean v0, p0, Landroid/content/BroadcastReceiver$PendingResult;->vinixAbort:Z
    return-void')
	result += broadcast_method('public final clearAbortBroadcast()V', 1, '
    const/4 v0, 0x0
    iput-boolean v0, p0, Landroid/content/BroadcastReceiver$PendingResult;->vinixAbort:Z
    return-void')
	return result
}

// Kept canonical so the native binding generator can prove that its historical
// lazy JNI export is unused, without weakening stale-binding validation.
pub fn framework_broadcast_run_method() string {
	return broadcast_method('public run()V', 4, '
    iget-object v0, p0, Landroid/atl/VinixBroadcast;->receiver:Landroid/content/BroadcastReceiver;
    iget-object v1, p0, Landroid/atl/VinixBroadcast;->context:Landroid/content/Context;
    iget-object v2, p0, Landroid/atl/VinixBroadcast;->intent:Landroid/content/Intent;
    const/4 v3, 0x1
    invoke-virtual {v0, v1, v2, v3}, Landroid/content/BroadcastReceiver;->vinixDispatch(Landroid/content/Context;Landroid/content/Intent;Z)V
    return-void')
}

pub fn framework_broadcast_run(source string) !string {
	broadcast_baseline(source, '.class public final Landroid/atl/VinixBroadcast;', 'java/lang/Object', 4)!
	for field in ['receiver:Landroid/content/BroadcastReceiver;', 'context:Landroid/content/Context;', 'intent:Landroid/content/Intent;'] {
		if source.count('.field public ' + field) != 1 { return error('unexpected broadcast task field') }
	}
	return broadcast_replace(source, '.method public native run()V', framework_broadcast_run_method())!
}

pub fn framework_broadcast_loaded_app(source string) !string {
	if source.contains('vinixDispatch(') { return error('already extended manifest dispatch') }
	header := '.method public receiveBroadcast(Landroid/content/Context;Landroid/content/Intent;)V'
	if source.count(header) != 1 { return error('missing manifest broadcast delivery') }
	method := header + source.all_after(header).all_before('.end method') + '.end method'
	old := '    invoke-virtual {v1, p1, p2}, Landroid/content/BroadcastReceiver;->onReceive(Landroid/content/Context;Landroid/content/Intent;)V'
	if method.count(old) != 1 || !method.contains('.registers 10') {
		return error('unexpected manifest receiver dispatch')
	}
	replacement := method.replace(old, '    const/4 v4, 0x0\n    invoke-virtual {v1, p1, p2, v4}, Landroid/content/BroadcastReceiver;->vinixDispatch(Landroid/content/Context;Landroid/content/Intent;Z)V')
	return source.replace(method, replacement)
}

fn framework_broadcast_results(smali string) ! {
	for name, source in {
		'android/content/BroadcastReceiver.smali': framework_broadcast_receiver(os.read_file(smali + '/android/content/BroadcastReceiver.smali')!)!
		'android/content/BroadcastReceiver$PendingResult.smali': framework_broadcast_pending(os.read_file(smali + '/android/content/BroadcastReceiver$PendingResult.smali')!)!
		'android/atl/ATLLoadedApp.smali': framework_broadcast_loaded_app(os.read_file(smali + '/android/atl/ATLLoadedApp.smali')!)!
		'android/atl/VinixBroadcast.smali': framework_broadcast_run(os.read_file(smali + '/android/atl/VinixBroadcast.smali')!)!
	} {
		os.write_file(smali + '/' + name, source)!
	}
}
