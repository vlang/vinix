// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// The inherited ATL implementation prints the supplied password and userdata
// before returning false. Until an authenticator and account store exist,
// reject insertion without inspecting any caller-supplied account data.
pub fn framework_account_addition(source string) !string {
 return framework_replace_method(source, 'addAccountExplicitly(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)Z',
  '.method public addAccountExplicitly(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)Z\n.locals 2\n' +
  'new-instance v0, Ljava/lang/UnsupportedOperationException;\n' +
  'const-string v1, "Android account storage and authenticators are unavailable"\n' +
  'invoke-direct {v0, v1}, Ljava/lang/UnsupportedOperationException;-><init>(Ljava/lang/String;)V\n' +
  'throw v0\n.end method')!
}

// No account authenticator is registered in the native backend. Preserve the
// Android asynchronous API contract: return a failed future and dispatch its
// callback through a Handler, without reading credentials or inventing accounts.
pub fn framework_account_async_addition(source string) !string {
 signature := 'addAccount(Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;'
 return framework_replace_method(source, signature, '.method public ' + signature + '\n.locals 2\n' +
  'if-nez p1, :valid\nnew-instance v0, Ljava/lang/IllegalArgumentException;\n' +
  'const-string v1, "accountType is null"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n:valid\n' +
  'new-instance v0, Landroid/atl/VinixAccountFuture;\n' +
  'invoke-direct {v0, p6, p7}, Landroid/atl/VinixAccountFuture;-><init>(Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)V\n' +
  'return-object v0\n.end method')!
}

pub fn framework_account_async_classes() map[string]string {
 mut classes := {
  'android/accounts/AccountManagerCallback': interface_class('android/accounts/AccountManagerCallback', ['run(Landroid/accounts/AccountManagerFuture;)V'])
  'android/accounts/AccountManagerFuture': interface_class('android/accounts/AccountManagerFuture', ['cancel(Z)Z', 'isCancelled()Z', 'isDone()Z', 'getResult()Ljava/lang/Object;', 'getResult(JLjava/util/concurrent/TimeUnit;)Ljava/lang/Object;'])
 }
 for name in ['AccountsException', 'AuthenticatorException', 'OperationCanceledException', 'NetworkErrorException'] {
  parent := if name == 'AccountsException' { 'Ljava/lang/Exception;' } else { 'Landroid/accounts/AccountsException;' }
  mut text := '.class public Landroid/accounts/' + name + ';\n.super ' + parent + '\n'
  for signature in ['', 'Ljava/lang/String;', 'Ljava/lang/Throwable;', 'Ljava/lang/String;Ljava/lang/Throwable;'] {
   registers := if signature == '' { 'p0' } else if signature == 'Ljava/lang/String;Ljava/lang/Throwable;' { 'p0, p1, p2' } else { 'p0, p1' }
   text += '.method public constructor <init>(' + signature + ')V\n.locals 0\n' +
    'invoke-direct {' + registers + '}, ' + parent + '-><init>(' + signature + ')V\nreturn-void\n.end method\n'
  }
  classes['android/accounts/' + name] = text
 }
 classes['android/atl/VinixAccountFailure'] = '.class public final Landroid/atl/VinixAccountFailure;\n.super Ljava/lang/Object;\n.implements Ljava/util/concurrent/Callable;\n' +
  '.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
  '.method public call()Ljava/lang/Object;\n.locals 2\nnew-instance v0, Landroid/accounts/AuthenticatorException;\n' +
  'const-string v1, "No account authenticator is available"\n' +
  'invoke-direct {v0, v1}, Landroid/accounts/AuthenticatorException;-><init>(Ljava/lang/String;)V\nthrow v0\n.end method\n'
 classes['android/atl/VinixAccountCallback'] = '.class public final Landroid/atl/VinixAccountCallback;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
  '.field private callback:Landroid/accounts/AccountManagerCallback;\n.field private future:Landroid/accounts/AccountManagerFuture;\n' +
  '.method public constructor <init>(Landroid/accounts/AccountManagerCallback;Landroid/accounts/AccountManagerFuture;)V\n.locals 0\n' +
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, Landroid/atl/VinixAccountCallback;->callback:Landroid/accounts/AccountManagerCallback;\n' +
  'iput-object p2, p0, Landroid/atl/VinixAccountCallback;->future:Landroid/accounts/AccountManagerFuture;\nreturn-void\n.end method\n' +
  '.method public run()V\n.locals 2\niget-object v0, p0, Landroid/atl/VinixAccountCallback;->callback:Landroid/accounts/AccountManagerCallback;\n' +
  'iget-object v1, p0, Landroid/atl/VinixAccountCallback;->future:Landroid/accounts/AccountManagerFuture;\n' +
  'invoke-interface {v0, v1}, Landroid/accounts/AccountManagerCallback;->run(Landroid/accounts/AccountManagerFuture;)V\nreturn-void\n.end method\n'
 mut future := '.class public final Landroid/atl/VinixAccountFuture;\n.super Ljava/util/concurrent/FutureTask;\n.implements Landroid/accounts/AccountManagerFuture;\n' +
  '.field private callback:Landroid/accounts/AccountManagerCallback;\n.field private handler:Landroid/os/Handler;\n' +
  '.method public constructor <init>(Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)V\n.locals 2\n' +
  'new-instance v0, Landroid/atl/VinixAccountFailure;\ninvoke-direct {v0}, Landroid/atl/VinixAccountFailure;-><init>()V\n' +
  'invoke-direct {p0, v0}, Ljava/util/concurrent/FutureTask;-><init>(Ljava/util/concurrent/Callable;)V\n' +
  'iput-object p1, p0, Landroid/atl/VinixAccountFuture;->callback:Landroid/accounts/AccountManagerCallback;\n' +
  'if-nez p2, :handler\ninvoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;\nmove-result-object v1\n' +
  'new-instance p2, Landroid/os/Handler;\ninvoke-direct {p2, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V\n:handler\n' +
  'iput-object p2, p0, Landroid/atl/VinixAccountFuture;->handler:Landroid/os/Handler;\n' +
  // The known missing authenticator completes immediately. FutureTask owns all
  // completion/cancellation state, and done() still posts the callback.
  'invoke-virtual {p0}, Ljava/util/concurrent/FutureTask;->run()V\nreturn-void\n.end method\n' +
  '.method protected done()V\n.locals 3\niget-object v0, p0, Landroid/atl/VinixAccountFuture;->callback:Landroid/accounts/AccountManagerCallback;\n' +
  'if-eqz v0, :done\nnew-instance v1, Landroid/atl/VinixAccountCallback;\n' +
  'invoke-direct {v1, v0, p0}, Landroid/atl/VinixAccountCallback;-><init>(Landroid/accounts/AccountManagerCallback;Landroid/accounts/AccountManagerFuture;)V\n' +
  'iget-object v2, p0, Landroid/atl/VinixAccountFuture;->handler:Landroid/os/Handler;\n' +
  'invoke-virtual {v2, v1}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z\n:done\nreturn-void\n.end method\n'
 for timed in [false, true] {
  signature := if timed { 'JLjava/util/concurrent/TimeUnit;' } else { '' }
  registers := if timed { 'p0, p1, p2, p3' } else { 'p0' }
  future += '.method public getResult(' + signature + ')Ljava/lang/Object;\n.locals 2\n:result_start\n' +
   'invoke-virtual {' + registers + '}, Ljava/util/concurrent/FutureTask;->get(' + signature + ')Ljava/lang/Object;\n' +
   'move-result-object v0\n:result_end\nreturn-object v0\n' +
   '.catch Ljava/util/concurrent/ExecutionException; {:result_start .. :result_end} :failed\n' +
   '.catch Ljava/lang/InterruptedException; {:result_start .. :result_end} :cancelled\n' +
   '.catch Ljava/util/concurrent/CancellationException; {:result_start .. :result_end} :cancelled\n'
  if timed { future += '.catch Ljava/util/concurrent/TimeoutException; {:result_start .. :result_end} :cancelled\n' }
  // Preserve the authenticator failure, including repeated reads. FutureTask
  // also captures unexpected runtime failures, which must retain their type.
  future += ':failed\nmove-exception v0\ninvoke-virtual {v0}, Ljava/lang/Throwable;->getCause()Ljava/lang/Throwable;\n' +
   'move-result-object v0\ninstance-of v1, v0, Landroid/accounts/AuthenticatorException;\nif-nez v1, :cause\n' +
   'instance-of v1, v0, Ljava/io/IOException;\nif-nez v1, :cause\n' +
   'instance-of v1, v0, Ljava/lang/UnsupportedOperationException;\nif-eqz v1, :runtime\n' +
   'new-instance v1, Landroid/accounts/AuthenticatorException;\n' +
   'invoke-direct {v1, v0}, Landroid/accounts/AuthenticatorException;-><init>(Ljava/lang/Throwable;)V\nthrow v1\n:runtime\n' +
   'instance-of v1, v0, Ljava/lang/RuntimeException;\nif-nez v1, :cause\n' +
   'instance-of v1, v0, Ljava/lang/Error;\nif-nez v1, :cause\n' +
   'new-instance v1, Ljava/lang/IllegalStateException;\n' +
   'invoke-direct {v1, v0}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/Throwable;)V\nthrow v1\n:cause\nthrow v0\n' +
   ':cancelled\nmove-exception v0\nnew-instance v1, Landroid/accounts/OperationCanceledException;\n' +
   'invoke-direct {v1, v0}, Landroid/accounts/OperationCanceledException;-><init>(Ljava/lang/Throwable;)V\nthrow v1\n.end method\n'
 }
 classes['android/atl/VinixAccountFuture'] = future
 return classes
}

fn framework_account_listeners(smali string) ! {
 for name, source in framework_account_client_classes() {
  os.write_file(smali + '/' + name + '.smali', source)!
 }
 os.write_file(smali + '/android/accounts/OnAccountsUpdateListener.smali',
  interface_class('android/accounts/OnAccountsUpdateListener', ['onAccountsUpdated([Landroid/accounts/Account;)V']))!
 path := smali + '/android/accounts/AccountManager.smali'
 mut text := framework_account_client_addition(framework_account_addition(os.read_file(path)!)!)! + '\n.field private static vinixInstance:Landroid/accounts/AccountManager;\n' +
  '.field private vinixListeners:Ljava/util/HashMap;\n'
 text = framework_replace_method(text, '<init>()V',
  '.method public constructor <init>()V\n.locals 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
  'new-instance v0, Ljava/util/HashMap;\ninvoke-direct {v0}, Ljava/util/HashMap;-><init>()V\n' +
  'iput-object v0, p0, Landroid/accounts/AccountManager;->vinixListeners:Ljava/util/HashMap;\nreturn-void\n.end method')!
 text = framework_replace_method(text, 'get(Landroid/content/Context;)Landroid/accounts/AccountManager;',
  '.method public static synchronized get(Landroid/content/Context;)Landroid/accounts/AccountManager;\n.locals 1\n' +
  'if-nez p0, :context\nnew-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string p0, "context is null"\n' +
  'invoke-direct {v0, p0}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n:context\n' +
  'sget-object v0, Landroid/accounts/AccountManager;->vinixInstance:Landroid/accounts/AccountManager;\nif-nez v0, :ready\n' +
  'new-instance v0, Landroid/accounts/AccountManager;\ninvoke-direct {v0}, Landroid/accounts/AccountManager;-><init>()V\n' +
  'sput-object v0, Landroid/accounts/AccountManager;->vinixInstance:Landroid/accounts/AccountManager;\n:ready\nreturn-object v0\n.end method')!
 for suffix in ['', '[Ljava/lang/String;'] {
  text += '\n.method public synchronized native addOnAccountsUpdatedListener(Landroid/accounts/OnAccountsUpdateListener;Landroid/os/Handler;Z' + suffix + ')V\n.end method\n'
 }
 text += '\n.method public synchronized native removeOnAccountsUpdatedListener(Landroid/accounts/OnAccountsUpdateListener;)V\n.end method\n'
 // The native backend has neither an authenticator nor stored accounts.
 // Package visibility cannot expose any accounts in that empty store. Use
 // the same fresh snapshot as the existing typed query, including null type.
 text += '\n.method public getAccountsByTypeForPackage(Ljava/lang/String;Ljava/lang/String;)[Landroid/accounts/Account;\n.locals 1\n' +
  'invoke-virtual {p0, p1}, Landroid/accounts/AccountManager;->getAccountsByType(Ljava/lang/String;)[Landroid/accounts/Account;\n' +
  'move-result-object v0\nreturn-object v0\n.end method\n'
 text = framework_account_store(text)!
 os.write_file(path, text)!
 os.write_file(smali + '/android/atl/VinixAccountUpdate.smali',
  '.class public final Landroid/atl/VinixAccountUpdate;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
  '.field public listener:Landroid/accounts/OnAccountsUpdateListener;\n' +
  '.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
  '.method public native run()V\n.end method\n')!
}

fn framework_storage_queries(smali string) ! {
 path := smali + '/android/os/Environment.smali'
 mut text := os.read_file(path)!
 // The runtime's external directory is a non-removable ordinary filesystem.
 // Reject paths outside it instead of silently describing an unrelated volume.
 text += '\n.method private static vinixCheckExternalStorage(Ljava/io/File;)V\n.locals 3\n' +
  'invoke-virtual {p0}, Ljava/io/File;->getAbsoluteFile()Ljava/io/File;\nmove-result-object v0\n' +
  'invoke-virtual {v0}, Ljava/io/File;->toPath()Ljava/nio/file/Path;\nmove-result-object v0\n' +
  'invoke-interface {v0}, Ljava/nio/file/Path;->normalize()Ljava/nio/file/Path;\nmove-result-object v0\n' +
  'invoke-static {}, Landroid/os/Environment;->getExternalStorageDirectory()Ljava/io/File;\nmove-result-object v1\n' +
  'invoke-virtual {v1}, Ljava/io/File;->getAbsoluteFile()Ljava/io/File;\nmove-result-object v1\n' +
  'invoke-virtual {v1}, Ljava/io/File;->toPath()Ljava/nio/file/Path;\nmove-result-object v1\n' +
  'invoke-interface {v1}, Ljava/nio/file/Path;->normalize()Ljava/nio/file/Path;\nmove-result-object v1\n' +
  'invoke-interface {v0, v1}, Ljava/nio/file/Path;->startsWith(Ljava/nio/file/Path;)Z\nmove-result v0\nif-nez v0, :valid\n' +
  'new-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "path is not on external storage"\n' +
  'invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n:valid\nreturn-void\n.end method\n'
 for name in ['isExternalStorageEmulated', 'isExternalStorageRemovable'] {
  signature := name + '(Ljava/io/File;)Z'
  text = framework_replace_method(text, signature, '.method public static ' + signature + '\n.locals 1\n' +
   'invoke-static {p0}, Landroid/os/Environment;->vinixCheckExternalStorage(Ljava/io/File;)V\nconst/4 v0, 0\nreturn v0\n.end method')!
 }
 os.write_file(path, text)!
}
