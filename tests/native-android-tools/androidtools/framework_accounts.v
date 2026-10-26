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

fn framework_account_listeners(smali string) ! {
 os.write_file(smali + '/android/accounts/OnAccountsUpdateListener.smali',
  interface_class('android/accounts/OnAccountsUpdateListener', ['onAccountsUpdated([Landroid/accounts/Account;)V']))!
 path := smali + '/android/accounts/AccountManager.smali'
 mut text := framework_account_addition(os.read_file(path)!)! + '\n.field private static vinixInstance:Landroid/accounts/AccountManager;\n' +
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
