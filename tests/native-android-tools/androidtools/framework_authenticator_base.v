// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// API/dispatch contract from AOSP android-13.0.0_r1 AbstractAccountAuthenticator.
// https://android.googlesource.com/platform/frameworks/base/+/android-13.0.0_r1/core/java/android/accounts/AbstractAccountAuthenticator.java
// No authenticator discovery, account store, permission grant or broker lives
// here. Context permission checks are not package isolation in the shared VM.
const auth_base = 'Landroid/accounts/AbstractAccountAuthenticator;'
const auth_transport = 'Landroid/accounts/AbstractAccountAuthenticator$Transport;'
const auth_default = 'Landroid/accounts/AbstractAccountAuthenticator$DefaultResponse;'
const auth_wrapper = 'Landroid/accounts/AccountAuthenticatorResponse;'
const auth_raw_response = 'Landroid/accounts/IAccountAuthenticatorResponse;'
const auth_token_key = 'android.accounts.AbstractAccountAuthenticato.KEY_AUTH_TOKEN_TYPE'
const auth_features_key = 'android.accounts.AbstractAccountAuthenticator.KEY_REQUIRED_FEATURES'
const auth_options_key = 'android.accounts.AbstractAccountAuthenticator.KEY_OPTIONS'
const auth_account_key = 'android.accounts.AbstractAccountAuthenticator.KEY_ACCOUNT'

fn auth_base_method(signature string, locals int, body string) string {
 return '\n.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

pub fn framework_authenticator_base_class_names() []string {
 return ['android/accounts/AbstractAccountAuthenticator',
  'android/accounts/AbstractAccountAuthenticator$Transport',
  'android/accounts/AbstractAccountAuthenticator$DefaultResponse']
}

// Apply only the diagnostic handler to an existing canonical class. Retain
// unrelated methods and disassembler formatting byte-for-byte.
pub fn framework_authenticator_private_exception(original string) !string {
 signature := 'vinixHandleException(${auth_raw_response}Ljava/lang/String;Ljava/lang/Exception;)V'
 if original.count('.class public abstract ${auth_base}\n') != 1 {
  return error('authenticator base class required')
 }
 mut matches := 0
 for block in original.split('.method ') {
  if block.all_before('\n').ends_with(' ' + signature) { matches++ }
 }
 if matches != 1 { return error('one existing authenticator exception handler required') }
 generated := framework_authenticator_base_classes()['android/accounts/AbstractAccountAuthenticator'] or {
  return error('generated authenticator base absent')
 }
 for block in generated.split('.method ') {
  if !block.all_before('\n').ends_with(' ' + signature) { continue }
  end := block.index('.end method') or { return error('unterminated generated handler') }
  return framework_replace_method(original, signature, '.method ' + block[..end + '.end method'.len])!
 }
 return error('generated authenticator exception handler absent')
}

fn auth_base_signature(method AuthenticatorRequestMethod) string {
 if method.name == 'getAuthTokenLabel' { return 'getAuthTokenLabel(Ljava/lang/String;)Ljava/lang/String;' }
 return method.name + '(${auth_wrapper}' + method.arguments.join('') + ')Landroid/os/Bundle;'
}

fn auth_base_boolean(value int) string {
 return 'new-instance v0, Landroid/os/Bundle;\ninvoke-direct {v0}, Landroid/os/Bundle;-><init>()V\n' +
  'const-string v1, "booleanResult"\nconst/4 v2, ${value}\n' +
  'invoke-virtual {v0, v1, v2}, Landroid/os/Bundle;->putBoolean(Ljava/lang/String;Z)V\nreturn-object v0'
}

fn auth_base_async(kind int, args []string) string {
 // The runnable retains inputs and constructs the result on its new thread,
 // matching the default asynchronous cloning and session APIs.
 mut body := 'new-instance v0, ${auth_default}\nmove-object v1, p1\nconst/4 v2, ${kind}\n'
 for i, arg in args { body += if arg == 'null' { 'const/4 v${i + 3}, 0x0\n' } else { 'move-object v${i + 3}, ${arg}\n' } }
 return body + 'invoke-direct/range {v0 .. v6}, ${auth_default}-><init>(${auth_wrapper}ILjava/lang/String;[Ljava/lang/String;Landroid/accounts/Account;Landroid/os/Bundle;)V\n' +
  'new-instance v1, Ljava/lang/Thread;\ninvoke-direct {v1, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V\n' +
  'invoke-virtual {v1}, Ljava/lang/Thread;->start()V\nconst/4 v0, 0x0\nreturn-object v0'
}

fn auth_base_finish() string {
 return 'if-eqz p2, :bad_type\ninvoke-virtual {p2}, Ljava/lang/String;->length()I\nmove-result v0\nif-eqz v0, :bad_type\n' +
  'if-eqz p3, :bad_bundle\nconst-string v0, "${auth_token_key}"\n' +
  'invoke-virtual {p3, v0}, Landroid/os/Bundle;->containsKey(Ljava/lang/String;)Z\nmove-result v1\nif-eqz v1, :unsupported\n' +
  'invoke-virtual {p3, v0}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v3\n' +
  'const-string v0, "${auth_options_key}"\ninvoke-virtual {p3, v0}, Landroid/os/Bundle;->getBundle(Ljava/lang/String;)Landroid/os/Bundle;\nmove-result-object v6\n' +
  'const-string v0, "${auth_features_key}"\ninvoke-virtual {p3, v0}, Landroid/os/Bundle;->getStringArray(Ljava/lang/String;)[Ljava/lang/String;\nmove-result-object v4\n' +
  'const-string v0, "${auth_account_key}"\ninvoke-virtual {p3, v0}, Landroid/os/Bundle;->getParcelable(Ljava/lang/String;)Landroid/os/Parcelable;\nmove-result-object v7\ncheck-cast v7, Landroid/accounts/Account;\n' +
  'invoke-virtual {p3, v0}, Landroid/os/Bundle;->containsKey(Ljava/lang/String;)Z\nmove-result v8\n' +
  'new-instance v5, Landroid/os/Bundle;\ninvoke-direct {v5, p3}, Landroid/os/Bundle;-><init>(Landroid/os/Bundle;)V\n' +
  ['${auth_token_key}', '${auth_features_key}', '${auth_options_key}', '${auth_account_key}'].map(
   'const-string v0, "${it}"\ninvoke-virtual {v5, v0}, Landroid/os/Bundle;->remove(Ljava/lang/String;)V\n').join('') +
  'if-eqz v6, :options_ready\ninvoke-virtual {v6, v5}, Landroid/os/Bundle;->putAll(Landroid/os/Bundle;)V\nmove-object v5, v6\n:options_ready\n' +
  'move-object v0, p0\nmove-object v1, p1\nif-eqz v8, :add\nmove-object v2, v7\nmove-object v4, v6\n' +
  'invoke-virtual/range {v0 .. v4}, ${auth_base}->updateCredentials(${auth_wrapper}Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;\nmove-result-object v0\nreturn-object v0\n' +
  ':add\nmove-object v2, p2\ninvoke-virtual/range {v0 .. v5}, ${auth_base}->addAccount(${auth_wrapper}Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;\nmove-result-object v0\nreturn-object v0\n' +
  ':bad_type\nconst/4 v0, 0x7\nconst-string v1, "accountType cannot be empty."\ngoto :error\n' +
  ':bad_bundle\nconst/4 v0, 0x7\nconst-string v1, "sessionBundle cannot be null."\ngoto :error\n' +
  ':unsupported\nconst/4 v0, 0x6\nconst-string v1, "Authenticator must override finishSession if startAddAccountSession or startUpdateCredentialsSession is overridden."\n' +
  'invoke-static {v0, v1}, ${auth_base}->vinixErrorBundle(ILjava/lang/String;)Landroid/os/Bundle;\nmove-result-object v0\n' +
  'invoke-virtual {p1, v0}, ${auth_wrapper}->onResult(Landroid/os/Bundle;)V\nreturn-object v0\n' +
  ':error\ninvoke-static {v0, v1}, ${auth_base}->vinixErrorBundle(ILjava/lang/String;)Landroid/os/Bundle;\nmove-result-object v0\nreturn-object v0'
}

pub fn framework_authenticator_base_classes() map[string]string {
 names := framework_authenticator_base_class_names()
 methods := authenticator_request_methods()
 mut classes := map[string]string{}
 mut text := '.class public abstract ${auth_base}\n.super Ljava/lang/Object;\n' +
  '.field public static final KEY_CUSTOM_TOKEN_EXPIRY:Ljava/lang/String; = "android.accounts.expiry"\n' +
  '.field private final context:Landroid/content/Context;\n.field private final transport:${auth_transport}\n'
 text += auth_base_method('public constructor <init>(Landroid/content/Context;)V', 1,
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${auth_base}->context:Landroid/content/Context;\n' +
  'new-instance v0, ${auth_transport}\ninvoke-direct {v0, p0}, ${auth_transport}-><init>(${auth_base})V\niput-object v0, p0, ${auth_base}->transport:${auth_transport}\nreturn-void')
 text += auth_base_method('public final getIBinder()Landroid/os/IBinder;', 1,
  'iget-object v0, p0, ${auth_base}->transport:${auth_transport}\nreturn-object v0')
 for method in methods[..7] { text += '\n.method public abstract ' + auth_base_signature(method) + '\n.end method\n' }
 text += auth_base_method('final vinixCheckBinderPermission()V', 3,
  'invoke-static {}, Landroid/os/Binder;->getCallingUid()I\nmove-result v2\n' +
  'iget-object v0, p0, ${auth_base}->context:Landroid/content/Context;\nconst-string v1, "android.permission.ACCOUNT_MANAGER"\n' +
  'invoke-virtual {v0, v1}, Landroid/content/Context;->checkCallingOrSelfPermission(Ljava/lang/String;)I\nmove-result v0\nif-eqz v0, :allowed\n' +
  'new-instance v0, Ljava/lang/StringBuilder;\ninvoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V\nconst-string v1, "caller uid "\n' +
  'invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' +
  'invoke-virtual {v0, v2}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;\nconst-string v1, " lacks android.permission.ACCOUNT_MANAGER"\n' +
  'invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' +
  'invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\nmove-result-object v1\nnew-instance v0, Ljava/lang/SecurityException;\n' +
  'invoke-direct {v0, v1}, Ljava/lang/SecurityException;-><init>(Ljava/lang/String;)V\nthrow v0\n:allowed\nreturn-void')
 text += auth_base_method('final vinixHandleException(${auth_raw_response}Ljava/lang/String;Ljava/lang/Exception;)V', 3,
  // The broker keeps stderr private; the public result retains only the
  // original Android error mapping. A failed diagnostic must not mask it.
  ':trace_start\nsget-object v0, Ljava/lang/System;->err:Ljava/io/PrintStream;\n' +
  'const-string v1, "ANDROID-AUTHENTICATOR-EXCEPTION"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n' +
  'invoke-virtual {p3}, Ljava/lang/Throwable;->printStackTrace()V\n:trace_end\ngoto :trace_done\n' +
  '.catchall {:trace_start .. :trace_end} :trace_failed\n:trace_failed\nmove-exception v0\n:trace_done\n' +
  'instance-of v0, p3, Landroid/accounts/NetworkErrorException;\nif-eqz v0, :unsupported\nconst/4 v0, 0x3\n' +
  'invoke-virtual {p3}, Ljava/lang/Exception;->getMessage()Ljava/lang/String;\nmove-result-object v1\ngoto :send\n' +
  ':unsupported\ninstance-of v0, p3, Ljava/lang/UnsupportedOperationException;\nif-eqz v0, :arguments\nconst/4 v0, 0x6\ngoto :not_supported\n' +
  ':arguments\ninstance-of v0, p3, Ljava/lang/IllegalArgumentException;\nif-eqz v0, :other\nconst/4 v0, 0x7\n' +
  ':not_supported\nconst-string v1, " not supported"\ngoto :message\n:other\nconst/4 v0, 0x1\nconst-string v1, " failed"\n' +
  ':message\ninvoke-virtual {p2, v1}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v1\n' +
  ':send\ninvoke-interface {p1, v0, v1}, ${auth_raw_response}->onError(ILjava/lang/String;)V\nreturn-void')
 text += auth_base_method('private static vinixErrorBundle(ILjava/lang/String;)Landroid/os/Bundle;', 2,
  'new-instance v0, Landroid/os/Bundle;\ninvoke-direct {v0}, Landroid/os/Bundle;-><init>()V\nconst-string v1, "errorCode"\n' +
  'invoke-virtual {v0, v1, p0}, Landroid/os/Bundle;->putInt(Ljava/lang/String;I)V\nconst-string v1, "errorMessage"\n' +
  'invoke-virtual {v0, v1, p1}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V\nreturn-object v0')
 text += auth_base_method('public ' + auth_base_signature(methods[7]), 3, auth_base_boolean(1))
 for i in [8, 9] { text += auth_base_method('public ' + auth_base_signature(methods[i]), 7,
  auth_base_async(0, ['null', 'null', 'null', 'null'])) }
 text += auth_base_method('public ' + auth_base_signature(methods[10]), 7,
  auth_base_async(1, ['p3', 'p4', 'null', 'p5']))
 text += auth_base_method('public ' + auth_base_signature(methods[11]), 7,
  auth_base_async(2, ['p3', 'null', 'p2', 'p4']))
 text += auth_base_method('public ' + auth_base_signature(methods[12]), 9, auth_base_finish())
 text += auth_base_method('public ' + auth_base_signature(methods[13]), 3, auth_base_boolean(0))
 classes[names[0]] = text

 text = '.class public final ${auth_transport}\n.super Landroid/accounts/IAccountAuthenticator$Stub;\n.field private final owner:${auth_base}\n'
 text += auth_base_method('public constructor <init>(${auth_base})V', 0,
  'invoke-direct {p0}, Landroid/accounts/IAccountAuthenticator$Stub;-><init>()V\niput-object p1, p0, ${auth_transport}->owner:${auth_base}\nreturn-void')
 for method in methods {
  mut body := 'iget-object v0, p0, ${auth_transport}->owner:${auth_base}\ninvoke-virtual {v0}, ${auth_base}->vinixCheckBinderPermission()V\n:begin\n'
  if method.name == 'getAuthTokenLabel' {
   body += 'invoke-virtual {v0, p2}, ${auth_base}->getAuthTokenLabel(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v2\n' +
    'new-instance v0, Landroid/os/Bundle;\ninvoke-direct {v0}, Landroid/os/Bundle;-><init>()V\nconst-string v1, "authTokenLabelKey"\n' +
    'invoke-virtual {v0, v1, v2}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V\n'
  } else {
   body += 'new-instance v1, ${auth_wrapper}\ninvoke-direct {v1, p1}, ${auth_wrapper}-><init>(${auth_raw_response})V\n'
   for i, _ in method.arguments { body += 'move-object v${i + 2}, p${i + 2}\n' }
   body += 'invoke-virtual/range {v0 .. v${method.arguments.len + 1}}, ${auth_base}->' + auth_base_signature(method) + '\nmove-result-object v0\n'
  }
  body += 'if-eqz v0, :null_result\ninvoke-interface {p1, v0}, ${auth_raw_response}->onResult(Landroid/os/Bundle;)V\ngoto :end\n:null_result\n'
  if method.name == 'addAccount' {
   body += 'const/4 v0, 0x5\nconst-string v1, "null bundle returned"\ninvoke-interface {p1, v0, v1}, ${auth_raw_response}->onError(ILjava/lang/String;)V\n'
  }
  body += ':end\nreturn-void\n.catch Ljava/lang/Exception; {:begin .. :end} :failed\n:failed\nmove-exception v3\n' +
   'iget-object v0, p0, ${auth_transport}->owner:${auth_base}\nconst-string v2, "${method.name}"\n' +
   'invoke-virtual {v0, p1, v2, v3}, ${auth_base}->vinixHandleException(${auth_raw_response}Ljava/lang/String;Ljava/lang/Exception;)V\nreturn-void'
  text += auth_base_method('public ' + authenticator_request_signature(method), 6, body)
 }
 classes[names[1]] = text

 text = '.class public final ${auth_default}\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
  '.field private final response:${auth_wrapper}\n.field private final kind:I\n.field private final token:Ljava/lang/String;\n' +
  '.field private final features:[Ljava/lang/String;\n.field private final account:Landroid/accounts/Account;\n.field private final options:Landroid/os/Bundle;\n'
 mut body := 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n'
 for i, field in ['response:${auth_wrapper}', 'kind:I', 'token:Ljava/lang/String;', 'features:[Ljava/lang/String;',
  'account:Landroid/accounts/Account;', 'options:Landroid/os/Bundle;'] {
  body += 'iput' + if i == 1 { '' } else { '-object' } + ' p${i + 1}, p0, ${auth_default}->${field}\n'
 }
 text += auth_base_method('public constructor <init>(${auth_wrapper}ILjava/lang/String;[Ljava/lang/String;Landroid/accounts/Account;Landroid/os/Bundle;)V', 0, body + 'return-void')
 body = 'new-instance v0, Landroid/os/Bundle;\ninvoke-direct {v0}, Landroid/os/Bundle;-><init>()V\niget v1, p0, ${auth_default}->kind:I\nif-nez v1, :session\n' +
  'const-string v1, "booleanResult"\nconst/4 v2, 0x0\ninvoke-virtual {v0, v1, v2}, Landroid/os/Bundle;->putBoolean(Ljava/lang/String;Z)V\ngoto :send\n' +
  ':session\nnew-instance v3, Landroid/os/Bundle;\ninvoke-direct {v3}, Landroid/os/Bundle;-><init>()V\nconst-string v1, "${auth_token_key}"\n' +
  'iget-object v2, p0, ${auth_default}->token:Ljava/lang/String;\ninvoke-virtual {v3, v1, v2}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V\n' +
  'const-string v1, "${auth_options_key}"\niget-object v2, p0, ${auth_default}->options:Landroid/os/Bundle;\ninvoke-virtual {v3, v1, v2}, Landroid/os/Bundle;->putBundle(Ljava/lang/String;Landroid/os/Bundle;)V\n' +
  'iget v1, p0, ${auth_default}->kind:I\nconst/4 v2, 0x1\nif-ne v1, v2, :update\nconst-string v1, "${auth_features_key}"\n' +
  'iget-object v2, p0, ${auth_default}->features:[Ljava/lang/String;\ninvoke-virtual {v3, v1, v2}, Landroid/os/Bundle;->putStringArray(Ljava/lang/String;[Ljava/lang/String;)V\ngoto :wrapped\n' +
  ':update\nconst-string v1, "${auth_account_key}"\niget-object v2, p0, ${auth_default}->account:Landroid/accounts/Account;\n' +
  'invoke-virtual {v3, v1, v2}, Landroid/os/Bundle;->putParcelable(Ljava/lang/String;Landroid/os/Parcelable;)V\n' +
  ':wrapped\nconst-string v1, "accountSessionBundle"\ninvoke-virtual {v0, v1, v3}, Landroid/os/Bundle;->putBundle(Ljava/lang/String;Landroid/os/Bundle;)V\n' +
  ':send\niget-object v1, p0, ${auth_default}->response:${auth_wrapper}\ninvoke-virtual {v1, v0}, ${auth_wrapper}->onResult(Landroid/os/Bundle;)V\nreturn-void'
 text += auth_base_method('public run()V', 4, body)
 classes[names[2]] = text
 return classes
}

fn framework_account_authenticator_base(smali string) ! {
 classes := framework_authenticator_base_classes()
 for name, _ in classes {
  if os.exists(smali + '/' + name + '.smali') { return error('authenticator base class already exists: ' + name) }
 }
 for name, source in classes { os.write_file(smali + '/' + name + '.smali', source)! }
}
