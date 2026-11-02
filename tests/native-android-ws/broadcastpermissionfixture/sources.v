// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const context_type = 'Landroid/content/Context;'
const intent_type = 'Landroid/content/Intent;'
const receiver_type = 'Landroid/content/BroadcastReceiver;'
const dynamic_type = 'Lorg/vinix/bootstrap/DynamicReceiver;'
const state_type = 'Lorg/vinix/bootstrap/MetadataState;'
const package_type = 'Landroid/content/pm/PackageParser$Package;'
const info_type = 'Landroid/content/pm/PermissionInfo;'
const item_type = 'Landroid/content/pm/PackageItemInfo;'
const handler_type = 'Landroid/os/Handler;'
const broadcast_action = 'org.vinix.bootstrap.BROADCAST_PERMISSION'
const signature_permission = 'org.vinix.bootstrap.permission.SIGNATURE'
const unrequested_permission = 'org.vinix.bootstrap.permission.UNREQUESTED'
const normal_permission = 'org.vinix.bootstrap.permission.NORMAL'
const dangerous_permission = 'org.vinix.bootstrap.permission.DANGEROUS'
const tree_permission = 'org.vinix.bootstrap.permission.TREE'
const unknown_permission = 'org.vinix.bootstrap.permission.UNKNOWN'
const pass_marker = 'BROADCAST-PERMISSION-PASS actual-delivery signature-owned null-legacy denied-permissions fake-grants immutable-authority metadata-restored async-barriers'
const fail_marker = 'BROADCAST-PERMISSION-FAIL'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn fail(message string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "${message}"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0\n'
}

fn checks_source() string {
	return method('private static equal(IILjava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('public static merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;', 0, '
if-eqz p0, :new_failure
if-eq p0, p1, :done
invoke-virtual {p0, p1}, Ljava/lang/Throwable;->addSuppressed(Ljava/lang/Throwable;)V
:done
return-object p0
:new_failure
return-object p1')
}

fn record_source() string {
	return method('public static record(Landroid/content/Intent;Z)V', 4, '
invoke-virtual {p0}, ${intent_type}->getAction()Ljava/lang/String;
move-result-object v0
const-string v1, "${broadcast_action}"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
const-string v0, "sequence"
const/4 v1, -1
invoke-virtual {p0, v0, v1}, ${intent_type}->getIntExtra(Ljava/lang/String;I)I
move-result v0
sget v1, ${main_type}->sequence:I
if-ne v0, v1, :bad
if-eqz p1, :manifest
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
sget-object v1, ${main_type}->expectedLooper:Landroid/os/Looper;
if-ne v0, v1, :bad
sget v0, ${main_type}->dynamicCalls:I
add-int/lit8 v0, v0, 1
sput v0, ${main_type}->dynamicCalls:I
return-void
:manifest
sget v0, ${main_type}->manifestCalls:I
add-int/lit8 v0, v0, 1
sput v0, ${main_type}->manifestCalls:I
return-void
' + fail('real receiver callback action, sequence or dedicated-handler identity'))
}

// Every send, including denials, is observed after a queued barrier on the
// dynamic receiver's handler. One deadline bounds all barrier waits together.
fn barrier_source() string {
	return method('private static check(Landroid/os/Handler;I)V', 6, '
new-instance v0, Ljava/util/concurrent/CountDownLatch;
const/4 v1, 1
invoke-direct {v0, v1}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V
new-instance v3, Lorg/vinix/bootstrap/Barrier;
invoke-direct {v3, v0}, Lorg/vinix/bootstrap/Barrier;-><init>(Ljava/util/concurrent/CountDownLatch;)V
invoke-virtual {p0, v3}, ${handler_type}->post(Ljava/lang/Runnable;)Z
move-result v3
if-eqz v3, :bad
sget-wide v1, ${main_type}->deadline:J
invoke-static {}, Ljava/lang/System;->nanoTime()J
move-result-wide v3
sub-long/2addr v1, v3
const-wide/16 v3, 0
cmp-long v5, v1, v3
if-lez v5, :bad
sget-object v3, Ljava/util/concurrent/TimeUnit;->NANOSECONDS:Ljava/util/concurrent/TimeUnit;
invoke-virtual {v0, v1, v2, v3}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v0
if-eqz v0, :bad
sget-object v0, ${main_type}->failure:Ljava/lang/Throwable;
if-nez v0, :callback_failed
sget v0, ${main_type}->dynamicCalls:I
if-ne v0, p1, :bad
sget v0, ${main_type}->manifestCalls:I
if-ne v0, p1, :bad
return-void
:callback_failed
throw v0
' + fail('broadcast callback counts, queued barrier or shared deadline'))
}

fn delivery_source() string {
	return method('private static attempt(${context_type}${handler_type}Ljava/lang/String;II)V', 3, '
sput p4, ${main_type}->sequence:I
new-instance v0, ${intent_type}
const-string v1, "${broadcast_action}"
invoke-direct {v0, v1}, ${intent_type}-><init>(Ljava/lang/String;)V
const-string v1, "sequence"
invoke-virtual {v0, v1, p4}, ${intent_type}->putExtra(Ljava/lang/String;I)${intent_type}
invoke-virtual {p0, v0, p2}, ${context_type}->sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V
invoke-static {p1, p3}, ${main_type}->check(${handler_type}I)V
const-string v1, "sequence"
const/4 v2, -1
invoke-virtual {v0, v1, v2}, ${intent_type}->getIntExtra(Ljava/lang/String;I)I
move-result v2
if-ne v2, p4, :bad
return-void
' + fail('broadcast must preserve the caller intent payload')) + method('private static legacy(${context_type}${handler_type})V', 3, '
const/4 v2, 1
sput v2, ${main_type}->sequence:I
new-instance v0, ${intent_type}
const-string v1, "${broadcast_action}"
invoke-direct {v0, v1}, ${intent_type}-><init>(Ljava/lang/String;)V
const-string v1, "sequence"
invoke-virtual {v0, v1, v2}, ${intent_type}->putExtra(Ljava/lang/String;I)${intent_type}
invoke-virtual {p0, v0}, ${context_type}->sendBroadcast(Landroid/content/Intent;)V
invoke-static {p1, v2}, ${main_type}->check(${handler_type}I)V
return-void')
}

fn null_intents_source() string {
	mut body := ''
	for i, permission in ['', unknown_permission, signature_permission] {
		body += 'const/4 v0, 0\n' + if permission == '' { 'const/4 v1, 0\n' } else {
			'const-string v1, "${permission}"\n'
		} + ':null_start_${i}\ninvoke-virtual {p0, v0, v1}, ${context_type}->sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V\n' +
			':null_end_${i}\ngoto :bad\n.catch Ljava/lang/NullPointerException; {:null_start_${i} .. :null_end_${i}} :null_caught_${i}\n' +
			':null_caught_${i}\nmove-exception v2\n'
	}
	return method('private static nullIntents(${context_type}${handler_type}I)V', 3,
		body + 'invoke-static {p1, p2}, ${main_type}->check(${handler_type}I)V\nreturn-void\n' + fail('null Intent must fail before receiver-permission selection'))
}

fn find_permission_source() string {
	return method('public static findPermission(${package_type}Ljava/lang/String;)${info_type}', 3, '
iget-object v0, p0, ${package_type}->permissions:Ljava/util/ArrayList;
invoke-virtual {v0}, Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;
move-result-object v0
:again
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v1
if-eqz v1, :bad
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/content/pm/PackageParser$Permission;
iget-object v1, v1, Landroid/content/pm/PackageParser$Permission;->info:${info_type}
iget-object v2, v1, ${item_type}->name:Ljava/lang/String;
invoke-virtual {p1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :again
return-object v1
' + fail('actual parsed permission metadata is missing'))
}

fn cleanup_source() string {
	return method('private static restoreMetadata(${state_type}Ljava/lang/Throwable;)V', 1, '
:restore_start
invoke-virtual {p0}, ${state_type}->restore()V
:restore_end
if-eqz p1, :done
throw p1
:done
return-void
.catchall {:restore_start .. :restore_end} :restore_failed
:restore_failed
move-exception v0
invoke-static {p1, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object v0
throw v0') + method('private static cleanup(${context_type}${dynamic_type}Landroid/os/HandlerThread;ZLjava/lang/Throwable;)V', 4, '
move-object v0, p4
if-eqz p3, :quit
:unregister_start
invoke-virtual {p0, p1}, ${context_type}->unregisterReceiver(${receiver_type})V
:unregister_end
goto :quit
.catchall {:unregister_start .. :unregister_end} :unregister_failed
:unregister_failed
move-exception v1
invoke-static {v0, v1}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object v0
:quit
:quit_start
invoke-virtual {p2}, Landroid/os/HandlerThread;->quit()Z
const-wide/16 v1, 1000
invoke-virtual {p2, v1, v2}, Ljava/lang/Thread;->join(J)V
invoke-virtual {p2}, Ljava/lang/Thread;->isAlive()Z
move-result v1
if-eqz v1, :quit_end
new-instance v1, Ljava/lang/AssertionError;
const-string v3, "broadcast HandlerThread must terminate within one second"
invoke-direct {v1, v3}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v1
:quit_end
goto :done
.catchall {:quit_start .. :quit_end} :quit_failed
:quit_failed
move-exception v1
invoke-static {v0, v1}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object v0
:done
if-eqz v0, :success
throw v0
:success
return-void')
}

fn attempt(context string, permission string, expected int, sequence int) string {
	return (if permission == '' { 'const/4 v5, 0\n' } else { 'const-string v5, "${permission}"\n' }) +
		'const/16 v6, ${expected}\nconst/16 v7, ${sequence}\n' +
		'invoke-static {${context}, v2, v5, v6, v7}, ${main_type}->attempt(${context_type}${handler_type}Ljava/lang/String;II)V\n'
}

fn run_source() string {
	mut body := '
const/4 v11, 0
sput v11, ${main_type}->dynamicCalls:I
sput v11, ${main_type}->manifestCalls:I
sput-object v11, ${main_type}->failure:Ljava/lang/Throwable;
new-instance v0, Landroid/os/HandlerThread;
const-string v11, "broadcast-permission-fixture"
invoke-direct {v0, v11}, Landroid/os/HandlerThread;-><init>(Ljava/lang/String;)V
const/4 v3, 0
const/4 v4, 0
:run_start
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
invoke-virtual {v0}, Landroid/os/HandlerThread;->getLooper()Landroid/os/Looper;
move-result-object v1
sput-object v1, ${main_type}->expectedLooper:Landroid/os/Looper;
new-instance v2, ${handler_type}
invoke-direct {v2, v1}, ${handler_type}-><init>(Landroid/os/Looper;)V
new-instance v3, ${dynamic_type}
invoke-direct {v3}, ${dynamic_type}-><init>()V
new-instance v5, Landroid/content/IntentFilter;
const-string v11, "${broadcast_action}"
invoke-direct {v5, v11}, Landroid/content/IntentFilter;-><init>(Ljava/lang/String;)V
const/4 v11, 0
invoke-virtual {p0, v3, v5, v11, v2}, ${context_type}->registerReceiver(${receiver_type}Landroid/content/IntentFilter;Ljava/lang/String;${handler_type})${intent_type}
const/4 v4, 1
invoke-static {}, Ljava/lang/System;->nanoTime()J
move-result-wide v5
const-wide v7, 8000000000L
add-long/2addr v5, v7
sput-wide v5, ${main_type}->deadline:J
invoke-virtual {p0}, ${context_type}->getApplicationContext()${context_type}
move-result-object v8
invoke-static {p0, v2}, ${main_type}->legacy(${context_type}${handler_type})V
'
	body += attempt('p0', '', 2, 2) + attempt('p0', signature_permission, 3, 3) +
		attempt('v8', signature_permission, 4, 4)
	for i, permission in [unknown_permission, unrequested_permission, normal_permission,
		dangerous_permission, tree_permission] {
		body += attempt('p0', permission, 4, i + 5)
	}
	body += '
new-instance v9, Lorg/vinix/bootstrap/FakeContext;
invoke-direct {v9, p0}, Lorg/vinix/bootstrap/FakeContext;-><init>(${context_type})V
const-string v5, "${unknown_permission}"
invoke-virtual {v9, v5}, ${context_type}->checkSelfPermission(Ljava/lang/String;)I
move-result v6
const/4 v7, 0
const-string v11, "fake Context must claim its permission grant as a control"
invoke-static {v6, v7, v11}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v9}, ${context_type}->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v6
const-string v7, "${package_name}"
invoke-virtual {v6, v5, v7}, Landroid/content/pm/PackageManager;->checkPermission(Ljava/lang/String;Ljava/lang/String;)I
move-result v6
const/4 v7, 0
const-string v11, "fake PackageManager must claim its permission grant as a control"
invoke-static {v6, v7, v11}, ${main_type}->equal(IILjava/lang/String;)V
' + attempt('v9', unknown_permission, 4, 10) + '
const/4 v6, 4
invoke-static {p0, v2, v6}, ${main_type}->nullIntents(${context_type}${handler_type}I)V
invoke-static {p0, v2, v9}, ${main_type}->metadata(${context_type}${handler_type}${context_type})V
' + attempt('p0', signature_permission, 6, 15) + attempt('v8', '', 7, 16) + '
:run_end
const/4 v11, 0
invoke-static {p0, v3, v0, v4, v11}, ${main_type}->cleanup(${context_type}${dynamic_type}Landroid/os/HandlerThread;ZLjava/lang/Throwable;)V
return-void
.catchall {:run_start .. :run_end} :run_failed
:run_failed
move-exception v11
invoke-static {p0, v3, v0, v4, v11}, ${main_type}->cleanup(${context_type}${dynamic_type}Landroid/os/HandlerThread;ZLjava/lang/Throwable;)V
throw v11'
	return method('private static run(${context_type})V', 12, body)
}

// Keep the metadata finally range in its own method: DEX does not allow two
// overlapping catch-all handlers with different targets in one code item.
fn metadata_source() string {
	return method('private static metadata(${context_type}${handler_type}${context_type})V', 12, '
move-object v2, p1
move-object v9, p2
invoke-static {}, Landroid/atl/ATLLoadedApp;->getPrimaryApplication()Landroid/atl/ATLLoadedApp;
move-result-object v11
iget-object v11, v11, Landroid/atl/ATLLoadedApp;->pkg:${package_type}
new-instance v10, ${state_type}
invoke-direct {v10, v11}, ${state_type}-><init>(${package_type})V
:mutation_start
invoke-virtual {v10}, ${state_type}->mutate()V
' + attempt('p0', signature_permission, 5, 11) + attempt('p0', unrequested_permission, 5, 12) +
		attempt('p0', normal_permission, 5, 13) + attempt('v9', unknown_permission, 5, 14) + '
:mutation_end
const/4 v11, 0
invoke-static {v10, v11}, ${main_type}->restoreMetadata(${state_type}Ljava/lang/Throwable;)V
return-void
.catchall {:mutation_start .. :mutation_end} :mutation_failed
:mutation_failed
move-exception v11
invoke-static {v10, v11}, ${main_type}->restoreMetadata(${state_type}Ljava/lang/Throwable;)V
throw v11')
}

fn metadata_state_source() string {
	return '.class public final ${state_type}\n.super Ljava/lang/Object;\n' +
		'.field private final pkg:${package_type}\n.field private final requests:Ljava/util/ArrayList;\n' +
		'.field private final positive:${info_type}\n.field private final normal:${info_type}\n' +
		'.field private final oldName:Ljava/lang/String;\n.field private final oldOwner:Ljava/lang/String;\n' +
		'.field private final oldProtection:I\n.field private final oldNormalProtection:I\n' +
		method('public constructor <init>(${package_type})V', 3, '
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, ${state_type}->pkg:${package_type}
iget-object v0, p1, ${package_type}->requestedPermissions:Ljava/util/ArrayList;
new-instance v1, Ljava/util/ArrayList;
invoke-direct {v1, v0}, Ljava/util/ArrayList;-><init>(Ljava/util/Collection;)V
iput-object v1, p0, ${state_type}->requests:Ljava/util/ArrayList;
const-string v1, "${signature_permission}"
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->contains(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-static {p1, v1}, ${main_type}->findPermission(${package_type}Ljava/lang/String;)${info_type}
move-result-object v0
iput-object v0, p0, ${state_type}->positive:${info_type}
iget-object v1, v0, ${item_type}->name:Ljava/lang/String;
iput-object v1, p0, ${state_type}->oldName:Ljava/lang/String;
iget-object v1, v0, ${item_type}->packageName:Ljava/lang/String;
iput-object v1, p0, ${state_type}->oldOwner:Ljava/lang/String;
iget-object v2, p1, ${package_type}->packageName:Ljava/lang/String;
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
iget v1, v0, ${info_type}->protectionLevel:I
iput v1, p0, ${state_type}->oldProtection:I
and-int/lit8 v1, v1, 0xf
const/4 v2, 2
if-ne v1, v2, :bad
const-string v1, "${normal_permission}"
invoke-static {p1, v1}, ${main_type}->findPermission(${package_type}Ljava/lang/String;)${info_type}
move-result-object v0
iput-object v0, p0, ${state_type}->normal:${info_type}
iget v1, v0, ${info_type}->protectionLevel:I
iput v1, p0, ${state_type}->oldNormalProtection:I
and-int/lit8 v1, v1, 0xf
if-nez v1, :bad
return-void
' + fail('signed primary package must contain its actual requested owned signature permission')) +
		method('public mutate()V', 3, '
iget-object v0, p0, ${state_type}->pkg:${package_type}
iget-object v0, v0, ${package_type}->requestedPermissions:Ljava/util/ArrayList;
invoke-virtual {v0}, Ljava/util/ArrayList;->clear()V
const-string v1, "${unrequested_permission}"
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
const-string v1, "${normal_permission}"
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
const-string v1, "${unknown_permission}"
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
const-string v1, "${dangerous_permission}"
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
const-string v1, "${tree_permission}"
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
iget-object v0, p0, ${state_type}->positive:${info_type}
const-string v1, "org.vinix.bootstrap.permission.RENAMED"
iput-object v1, v0, ${item_type}->name:Ljava/lang/String;
const-string v1, "foreign.owner"
iput-object v1, v0, ${item_type}->packageName:Ljava/lang/String;
const/4 v1, 0
iput v1, v0, ${info_type}->protectionLevel:I
iget-object v0, p0, ${state_type}->normal:${info_type}
const/4 v1, 2
iput v1, v0, ${info_type}->protectionLevel:I
return-void') + method('public restore()V', 3, '
iget-object v0, p0, ${state_type}->pkg:${package_type}
iget-object v0, v0, ${package_type}->requestedPermissions:Ljava/util/ArrayList;
invoke-virtual {v0}, Ljava/util/ArrayList;->clear()V
iget-object v1, p0, ${state_type}->requests:Ljava/util/ArrayList;
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->addAll(Ljava/util/Collection;)Z
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
iget-object v0, p0, ${state_type}->positive:${info_type}
iget-object v1, p0, ${state_type}->oldName:Ljava/lang/String;
iput-object v1, v0, ${item_type}->name:Ljava/lang/String;
iget-object v2, v0, ${item_type}->name:Ljava/lang/String;
if-ne v1, v2, :bad
iget-object v1, p0, ${state_type}->oldOwner:Ljava/lang/String;
iput-object v1, v0, ${item_type}->packageName:Ljava/lang/String;
iget-object v2, v0, ${item_type}->packageName:Ljava/lang/String;
if-ne v1, v2, :bad
iget v1, p0, ${state_type}->oldProtection:I
iput v1, v0, ${info_type}->protectionLevel:I
iget v2, v0, ${info_type}->protectionLevel:I
if-ne v1, v2, :bad
iget-object v0, p0, ${state_type}->normal:${info_type}
iget v1, p0, ${state_type}->oldNormalProtection:I
iput v1, v0, ${info_type}->protectionLevel:I
iget v2, v0, ${info_type}->protectionLevel:I
if-ne v1, v2, :bad
return-void
' + fail('all public permission metadata must be restored before cleanup'))
}

fn callback_source(class_name string, dynamic bool) string {
	value := if dynamic { '1' } else { '0' }
	return '.class public final Lorg/vinix/bootstrap/${class_name};\n.super ${receiver_type}\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, ${receiver_type}-><init>()V\nreturn-void') +
		method('public onReceive(${context_type}${intent_type})V', 2, '
:callback_start
const/4 v0, ${value}
invoke-static {p2, v0}, ${main_type}->record(${intent_type}Z)V
:callback_end
return-void
.catchall {:callback_start .. :callback_end} :callback_failed
:callback_failed
move-exception v0
sget-object v1, ${main_type}->failure:Ljava/lang/Throwable;
invoke-static {v1, v0}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object v0
sput-object v0, ${main_type}->failure:Ljava/lang/Throwable;
return-void')
}

fn barrier_class() string {
	return '.class public final Lorg/vinix/bootstrap/Barrier;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
		'.field private final latch:Ljava/util/concurrent/CountDownLatch;\n' +
		method('public constructor <init>(Ljava/util/concurrent/CountDownLatch;)V', 0,
			'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, Lorg/vinix/bootstrap/Barrier;->latch:Ljava/util/concurrent/CountDownLatch;\nreturn-void') +
		method('public run()V', 1, 'iget-object v0, p0, Lorg/vinix/bootstrap/Barrier;->latch:Ljava/util/concurrent/CountDownLatch;\ninvoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V\nreturn-void')
}

fn fake_context_source() string {
	return '.class public final Lorg/vinix/bootstrap/FakeContext;\n.super Landroid/content/ContextWrapper;\n' +
		'.field private final manager:Landroid/content/pm/PackageManager;\n' +
		method('public constructor <init>(${context_type})V', 1, '
invoke-direct {p0, p1}, Landroid/content/ContextWrapper;-><init>(${context_type})V
new-instance v0, Lorg/vinix/bootstrap/GrantPM;
invoke-direct {v0}, Lorg/vinix/bootstrap/GrantPM;-><init>()V
iput-object v0, p0, Lorg/vinix/bootstrap/FakeContext;->manager:Landroid/content/pm/PackageManager;
return-void') + method('public checkSelfPermission(Ljava/lang/String;)I', 1, 'const/4 v0, 0\nreturn v0') +
		method('public getPackageManager()Landroid/content/pm/PackageManager;', 1,
			'iget-object v0, p0, Lorg/vinix/bootstrap/FakeContext;->manager:Landroid/content/pm/PackageManager;\nreturn-object v0')
}

fn main_class() string {
	return '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		'.field public static volatile sequence:I\n.field public static volatile dynamicCalls:I\n.field public static volatile manifestCalls:I\n' +
		'.field public static volatile failure:Ljava/lang/Throwable;\n.field public static expectedLooper:Landroid/os/Looper;\n.field private static deadline:J\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		checks_source() + record_source() + barrier_source() + delivery_source() + null_intents_source() +
		find_permission_source() + cleanup_source() + run_source() + metadata_source() +
		method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {p0}, ${main_type}->run(${context_type})V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(${context_type})V
const-string v1, "Receiver-permission broadcast delivery and authority checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
:try_end
return-void
.catchall {:try_start .. :try_end} :failed
:failed
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${fail_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
throw v2')
}

fn fixture_sources() map[string]string {
	return {
		'org/vinix/bootstrap/Main.smali': main_class()
		'org/vinix/bootstrap/DynamicReceiver.smali': callback_source('DynamicReceiver', true)
		'org/vinix/bootstrap/ManifestReceiver.smali': callback_source('ManifestReceiver', false)
		'org/vinix/bootstrap/Barrier.smali': barrier_class()
		'org/vinix/bootstrap/FakeContext.smali': fake_context_source()
		'org/vinix/bootstrap/GrantPM.smali': '.class public final Lorg/vinix/bootstrap/GrantPM;\n.super Landroid/content/pm/PackageManager;\n' +
			method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/content/pm/PackageManager;-><init>()V\nreturn-void') +
			method('public checkPermission(Ljava/lang/String;Ljava/lang/String;)I', 1, 'const/4 v0, 0\nreturn v0')
		'org/vinix/bootstrap/MetadataState.smali': metadata_state_source()
	}
}

fn expected_classes() []string {
	return ['org/vinix/bootstrap/Barrier.smali', 'org/vinix/bootstrap/DynamicReceiver.smali',
		'org/vinix/bootstrap/FakeContext.smali', 'org/vinix/bootstrap/GrantPM.smali',
		'org/vinix/bootstrap/Main.smali', 'org/vinix/bootstrap/ManifestReceiver.smali',
		'org/vinix/bootstrap/MetadataState.smali']
}

fn verify_source_references(name string, source string) {
	if name.ends_with('/Main.smali') {
		assert source.count('${context_type}->sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V') == 4,
			'actual two-argument delivery and all null-intent cases must remain'
		assert source.count('${context_type}->sendBroadcast(Landroid/content/Intent;)V') == 1,
			'actual legacy broadcast control required'
		assert source.count('->attempt(${context_type}${handler_type}Ljava/lang/String;II)V') == 15,
			'every positive and negative delivery case must be called'
		for reference in ['->await(JLjava/util/concurrent/TimeUnit;)Z', '->post(Ljava/lang/Runnable;)Z',
			'->join(J)V', '->checkSelfPermission(Ljava/lang/String;)I',
			'->checkPermission(Ljava/lang/String;Ljava/lang/String;)I', '${state_type}->mutate()V',
			'${state_type}->restore()V'] {
			assert source.contains(reference), 'live callback, bounded cleanup and public metadata checks required: ' + reference
		}
		assert source.count('.catch Ljava/lang/NullPointerException;') == 3
	} else if name.ends_with('/DynamicReceiver.smali') || name.ends_with('/ManifestReceiver.smali') {
		assert source.count('${main_type}->record(${intent_type}Z)V') == 1, 'real receiver callback must record delivery'
	} else if name.ends_with('/MetadataState.smali') {
		assert source.contains('${package_type}->requestedPermissions:Ljava/util/ArrayList;')
		assert source.contains('${info_type}->protectionLevel:I')
		assert source.contains('${item_type}->packageName:Ljava/lang/String;')
		assert !source.contains('vinixBroadcastPermissions') && !source.contains('getDeclaredField'),
			'fixture must not access the private authority set'
	}
}
