// SPDX-License-Identifier: GPL-2.0-or-later
// Signed generic API probe. Assembly is not ART execution or Google login proof.
module main

import crypto.sha256
import json2
import os

const owner = 'Lorg/vinix/servicequery/Main;'
const context = 'Landroid/content/Context;'
const prefs = 'Landroid/content/SharedPreferences;'
const editor = 'Landroid/content/SharedPreferences$Editor;'
const client = 'org.vinix.servicequery.client'
const disabled = 'org.vinix.servicequery.disabled'
const receiver = 'Landroid/content/BroadcastReceiver;'
const pending_result = 'Landroid/content/BroadcastReceiver$PendingResult;'
const dynamic_receiver = 'Lorg/vinix/servicequery/DynamicReceiver;'
const sibling_receiver = 'Lorg/vinix/servicequery/SiblingReceiver;'
const manifest_receiver = 'Lorg/vinix/servicequery/ManifestReceiver;'
const throw_receiver = 'Lorg/vinix/servicequery/ThrowReceiver;'
const marker = 'SERVICE-QUERY-PASS no-filter disabled-component disabled-application unexported multifilter-single missing-no-action-fallback component-package wrapper implicit-preserved metadata-preserved no-initialization direct-boot-metadata credential-context broadcast-results'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn failure(message string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "${message}"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn query_check() string {
	return method('private static check(${context}Ljava/lang/String;Ljava/lang/String;II)V', 6, '
new-instance v0, Landroid/content/Intent;
invoke-direct {v0}, Landroid/content/Intent;-><init>()V
invoke-virtual {v0, p1, p2}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
const-string v1, "org.vinix.servicequery.ACTION"
invoke-virtual {v0, v1}, Landroid/content/Intent;->setAction(Ljava/lang/String;)Landroid/content/Intent;
invoke-virtual {p0}, ${context}->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v1
invoke-virtual {v1, v0, p3}, Landroid/content/pm/PackageManager;->queryIntentServices(Landroid/content/Intent;I)Ljava/util/List;
move-result-object v1
if-eqz v1, :bad
invoke-interface {v1}, Ljava/util/List;->size()I
move-result v2
if-ne v2, p4, :bad
if-eqz p4, :done
const/4 v2, 0
invoke-interface {v1, v2}, Ljava/util/List;->get(I)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/content/pm/ResolveInfo;
iget-object v1, v1, Landroid/content/pm/ResolveInfo;->serviceInfo:Landroid/content/pm/ServiceInfo;
if-eqz v1, :bad
iget-object v2, v1, Landroid/content/pm/PackageItemInfo;->name:Ljava/lang/String;
invoke-virtual {p2, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
iget-object v2, v1, Landroid/content/pm/PackageItemInfo;->packageName:Ljava/lang/String;
invoke-virtual {p1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
const-string v2, "org.vinix.servicequery.Disabled"
invoke-virtual {p2, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :boot_metadata
iget-boolean v2, v1, Landroid/content/pm/ComponentInfo;->enabled:Z
if-nez v2, :bad
:boot_metadata
const/4 v3, 0
const-string v2, "org.vinix.servicequery.BootAware"
invoke-virtual {p2, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-nez v2, :boot_true
const-string v2, "org.vinix.servicequery.BootResource"
invoke-virtual {p2, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :boot_compare
:boot_true
const/4 v3, 1
:boot_compare
iget-boolean v2, v1, Landroid/content/pm/ServiceInfo;->directBootAware:Z
if-ne v2, v3, :bad
new-instance v4, Landroid/content/pm/ServiceInfo;
invoke-direct {v4, v1}, Landroid/content/pm/ServiceInfo;-><init>(Landroid/content/pm/ServiceInfo;)V
iget-boolean v2, v4, Landroid/content/pm/ServiceInfo;->directBootAware:Z
if-ne v2, v3, :bad
:app_metadata
const-string v2, "org.vinix.servicequery.disabled"
invoke-virtual {p1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :intent_identity
iget-object v2, v1, Landroid/content/pm/ComponentInfo;->applicationInfo:Landroid/content/pm/ApplicationInfo;
if-eqz v2, :bad
iget-boolean v2, v2, Landroid/content/pm/ApplicationInfo;->enabled:Z
if-nez v2, :bad
:intent_identity
invoke-virtual {v0}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v2
invoke-virtual {v2}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;
move-result-object v2
invoke-virtual {p2, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
:done
return-void
' + failure('explicit service query result or intent identity'))
}

fn implicit_check() string {
	return method('private static implicit(${context})V', 4, '
new-instance v0, Landroid/content/Intent;
invoke-direct {v0}, Landroid/content/Intent;-><init>()V
const-string v1, "org.vinix.servicequery.ACTION"
invoke-virtual {v0, v1}, Landroid/content/Intent;->setAction(Ljava/lang/String;)Landroid/content/Intent;
invoke-virtual {p0}, ${context}->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v1
const/4 v2, 0
invoke-virtual {v1, v0, v2}, Landroid/content/pm/PackageManager;->queryIntentServices(Landroid/content/Intent;I)Ljava/util/List;
move-result-object v1
if-eqz v1, :bad
invoke-interface {v1}, Ljava/util/List;->size()I
move-result v1
const/4 v2, 2
if-ne v1, v2, :bad
invoke-virtual {v0}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v1
if-nez v1, :bad
return-void
' + failure('implicit service query changed'))
}

fn query(package_name string, class_name string, flags int, count int) string {
	return 'const-string v1, "${package_name}"\nconst-string v2, "org.vinix.servicequery.${class_name}"\nconst v3, ${flags}\nconst/4 v4, ${count}\ninvoke-static {v0, v1, v2, v3, v4}, ${owner}->check(${context}Ljava/lang/String;Ljava/lang/String;II)V\n'
}

fn component_array_check() string {
 return method('private static component([Landroid/content/pm/ComponentInfo;Ljava/lang/String;Z)V', 5, '
if-eqz p0, :bad
const/4 v0, 0
array-length v1, p0
:scan
if-ge v0, v1, :bad
aget-object v2, p0, v0
iget-object v3, v2, Landroid/content/pm/PackageItemInfo;->name:Ljava/lang/String;
invoke-virtual {p1, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-nez v3, :found
add-int/lit8 v0, v0, 1
goto :scan
:found
iget-boolean v3, v2, Landroid/content/pm/ComponentInfo;->directBootAware:Z
if-ne v3, p2, :bad
new-instance v4, Landroid/content/pm/ComponentInfo;
invoke-direct {v4, v2}, Landroid/content/pm/ComponentInfo;-><init>(Landroid/content/pm/ComponentInfo;)V
iget-boolean v3, v4, Landroid/content/pm/ComponentInfo;->directBootAware:Z
if-ne v3, p2, :bad
return-void
' + failure('component direct boot metadata or copy'))
}

fn metadata_check() string {
 mut body := '
new-instance v0, Landroid/content/pm/ComponentInfo;
invoke-direct {v0}, Landroid/content/pm/ComponentInfo;-><init>()V
iget-boolean v1, v0, Landroid/content/pm/ComponentInfo;->directBootAware:Z
if-nez v1, :bad
const/4 v1, 1
iput-boolean v1, v0, Landroid/content/pm/ComponentInfo;->directBootAware:Z
new-instance v2, Landroid/content/pm/ComponentInfo;
invoke-direct {v2, v0}, Landroid/content/pm/ComponentInfo;-><init>(Landroid/content/pm/ComponentInfo;)V
iget-boolean v1, v2, Landroid/content/pm/ComponentInfo;->directBootAware:Z
if-eqz v1, :bad
invoke-virtual {p0}, ${context}->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v0
const-string v1, "${disabled}"
const v2, 0x20b
invoke-virtual {v0, v1, v2}, Landroid/content/pm/PackageManager;->getPackageInfo(Ljava/lang/String;I)Landroid/content/pm/PackageInfo;
move-result-object v0
if-eqz v0, :bad
'
 for spec in [['activities', 'ActivityInfo', 'BootActivity', '1'], ['activities', 'ActivityInfo', 'BootAlias', '1'],
  ['activities', 'ActivityInfo', 'DefaultActivity', '0'], ['receivers', 'ActivityInfo', 'BootReceiver', '1'],
  ['receivers', 'ActivityInfo', 'DefaultReceiver', '0'], ['providers', 'ProviderInfo', 'BootProvider', '1'],
  ['providers', 'ProviderInfo', 'DefaultProvider', '0']] {
  body += 'iget-object v1, v0, Landroid/content/pm/PackageInfo;->' + spec[0] + ':[Landroid/content/pm/' + spec[1] + ';\n' +
   'const-string v2, "org.vinix.servicequery.' + spec[2] + '"\nconst/4 v3, ' + spec[3] + '\n' +
   'invoke-static {v1, v2, v3}, ${owner}->component([Landroid/content/pm/ComponentInfo;Ljava/lang/String;Z)V\n'
 }
 return method('private static metadata(${context})V', 4, body + 'return-void\n' + failure('ComponentInfo default/copy or companion metadata'))
}

fn checks() string {
	return method('private static checkEqual(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-eq p0, p1, :ok
if-eqz p0, :bad
invoke-virtual {p0, p1}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :ok
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void') + method('private static checkDirectory(Ljava/io/File;Ljava/io/File;Ljava/lang/String;)V', 1, '
invoke-static {p0, p1, p2}, ${owner}->checkEqual(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p1}, Ljava/io/File;->isDirectory()Z
move-result v0
if-nez v0, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void')
}

fn path_checks() string {
	mut body := '
invoke-virtual {p0}, ${context}->isDeviceProtectedStorage()Z
move-result v0
if-ne v0, p2, :bad
invoke-virtual {p0}, ${context}->isCredentialProtectedStorage()Z
move-result v0
xor-int/lit8 v1, p2, 1
if-ne v0, v1, :bad
new-instance v0, Ljava/io/File;
invoke-direct {v0, p1}, Ljava/io/File;-><init>(Ljava/lang/String;)V
invoke-virtual {p0}, ${context}->getDataDir()Ljava/io/File;
move-result-object v1
const-string v2, "context data root"
invoke-static {v0, v1, v2}, ${owner}->checkDirectory(Ljava/io/File;Ljava/io/File;Ljava/lang/String;)V
'
	for signature, child in {'getFilesDir()': 'files', 'getCacheDir()': 'cache'} {
		body += 'new-instance v1, Ljava/io/File;\nconst-string v2, "${child}"\n' +
			'invoke-direct {v1, v0, v2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V\n' +
			'invoke-virtual {p0}, ${context}->${signature}Ljava/io/File;\nmove-result-object v3\n' +
			'invoke-static {v1, v3, v2}, ${owner}->checkDirectory(Ljava/io/File;Ljava/io/File;Ljava/lang/String;)V\n'
	}
	body += '
new-instance v1, Ljava/io/File;
const-string v2, "app_storage_probe"
invoke-direct {v1, v0, v2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
const-string v2, "storage_probe"
const/4 v3, 0
invoke-virtual {p0, v2, v3}, ${context}->getDir(Ljava/lang/String;I)Ljava/io/File;
move-result-object v3
invoke-static {v1, v3, v2}, ${owner}->checkDirectory(Ljava/io/File;Ljava/io/File;Ljava/lang/String;)V
new-instance v1, Ljava/io/File;
const-string v2, "databases/storage_probe.db"
invoke-direct {v1, v0, v2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
const-string v2, "storage_probe.db"
invoke-virtual {p0, v2}, ${context}->getDatabasePath(Ljava/lang/String;)Ljava/io/File;
move-result-object v3
invoke-static {v1, v3, v2}, ${owner}->checkEqual(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void
' + failure('device flag or storage path')
	return method('private static checkPaths(${context}Ljava/lang/String;Z)V', 4, body)
}

fn preferences_check() string {
	mut body := '
const-string v2, "protected_storage_probe"
const/4 v3, 0
invoke-virtual {p0, v2, v3}, ${context}->getSharedPreferences(Ljava/lang/String;I)${prefs}
move-result-object v0
invoke-virtual {p1, v2, v3}, ${context}->getSharedPreferences(Ljava/lang/String;I)${prefs}
move-result-object v1
if-eq v0, v1, :bad
'
	for register, value in {'v0': 'credential', 'v1': 'device'} {
		body += 'invoke-interface {${register}}, ${prefs}->edit()${editor}\nmove-result-object v2\n' +
			'const-string v3, "storage"\nconst-string v4, "${value}"\n' +
			'invoke-interface {v2, v3, v4}, ${editor}->putString(Ljava/lang/String;Ljava/lang/String;)${editor}\n' +
			'invoke-interface {v2}, ${editor}->commit()Z\nmove-result v2\nif-eqz v2, :bad\n'
	}
	for register, value in {'v0': 'credential', 'v1': 'device'} {
		body += 'const-string v2, "storage"\nconst/4 v3, 0\n' +
			'invoke-interface {${register}, v2, v3}, ${prefs}->getString(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v2\n' +
			'const-string v3, "${value}"\nconst-string v4, "isolated preferences"\n' +
			'invoke-static {v3, v2, v4}, ${owner}->checkEqual(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
	}
	for register in ['p0', 'p1'] {
		body += 'invoke-virtual {${register}}, ${context}->getDataDir()Ljava/io/File;\nmove-result-object v0\n' +
			'new-instance v1, Ljava/io/File;\nconst-string v2, "shared_prefs/protected_storage_probe.xml"\n' +
			'invoke-direct {v1, v0, v2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V\n' +
			'invoke-virtual {v1}, Ljava/io/File;->isFile()Z\nmove-result v0\nif-eqz v0, :bad\n'
	}
	body += 'return-void\n' + failure('CE and DE preference storage must be isolated and committed')
	return method('private static checkPreferences(${context}${context})V', 5, body)
}


fn storage_check() string {
	mut body := '
invoke-virtual {p0}, ${context}->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v0
iget-object v1, v0, Landroid/content/pm/ApplicationInfo;->credentialProtectedDataDir:Ljava/lang/String;
iget-object v2, v0, Landroid/content/pm/ApplicationInfo;->deviceProtectedDataDir:Ljava/lang/String;
if-eqz v1, :bad
if-eqz v2, :bad
invoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :bad
const/4 v7, 0
invoke-static {p0, v1, v7}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
invoke-virtual {p0}, ${context}->createCredentialProtectedStorageContext()${context}
move-result-object v4
if-eq v4, p0, :bad
invoke-static {v4, v1, v7}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
invoke-virtual {p0}, ${context}->createDeviceProtectedStorageContext()${context}
move-result-object v3
if-eq v3, p0, :bad
const/4 v7, 1
invoke-static {v3, v2, v7}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
# Both original directory caches are now primed before switching DE back to CE.
invoke-virtual {v3}, ${context}->createCredentialProtectedStorageContext()${context}
move-result-object v4
if-eq v4, v3, :bad
const/4 v7, 0
invoke-static {v4, v1, v7}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
invoke-virtual {v3}, ${context}->createCredentialProtectedStorageContext()${context}
move-result-object v5
if-eq v4, v5, :bad
invoke-static {v5, v1, v7}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
invoke-static {v4, v3}, ${owner}->checkPreferences(${context}${context})V
invoke-static {v5, v3}, ${owner}->checkPreferences(${context}${context})V
'
	for spec in [['v4', 'v1', '0'], ['v3', 'v2', '1']] {
		body += '
new-instance v5, Landroid/content/ContextWrapper;
invoke-direct {v5, ${spec[0]}}, Landroid/content/ContextWrapper;-><init>(${context})V
new-instance v6, Landroid/content/ContextWrapper;
invoke-direct {v6, v5}, Landroid/content/ContextWrapper;-><init>(${context})V
const/4 v7, ${spec[2]}
invoke-static {v6, ${spec[1]}, v7}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
invoke-virtual {v6}, ${context}->createCredentialProtectedStorageContext()${context}
move-result-object v5
const/4 v7, 0
invoke-static {v5, v1, v7}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
invoke-virtual {v6}, ${context}->createDeviceProtectedStorageContext()${context}
move-result-object v5
const/4 v7, 1
invoke-static {v5, v2, v7}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
invoke-virtual {${spec[0]}}, ${context}->getResources()Landroid/content/res/Resources;
move-result-object v5
invoke-virtual {v5}, Landroid/content/res/Resources;->getConfiguration()Landroid/content/res/Configuration;
move-result-object v5
new-instance v6, Landroid/content/res/Configuration;
invoke-direct {v6, v5}, Landroid/content/res/Configuration;-><init>(Landroid/content/res/Configuration;)V
invoke-virtual {${spec[0]}, v6}, ${context}->createConfigurationContext(Landroid/content/res/Configuration;)${context}
move-result-object v5
const/4 v7, ${spec[2]}
invoke-static {v5, ${spec[1]}, v7}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
invoke-virtual {${spec[0]}}, ${context}->getApplicationContext()${context}
move-result-object v5
invoke-virtual {p0}, ${context}->getApplicationContext()${context}
move-result-object v6
if-ne v5, v6, :bad
invoke-virtual {${spec[0]}}, ${context}->getResources()Landroid/content/res/Resources;
move-result-object v5
invoke-virtual {p0}, ${context}->getResources()Landroid/content/res/Resources;
move-result-object v6
if-ne v5, v6, :bad
'
	}
	body += '
const/4 v7, 0
invoke-static {p0, v1, v7}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
invoke-static {v4, v1, v7}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
const/4 v7, 1
invoke-static {v3, v2, v7}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
return-void
' + failure('credential factory freshness, state, namespace, wrappers, configuration or identity')
	return method('private static storage(${context})V', 8, body)
}

// These probes use the real Context.sendBroadcast routes. Only exceptional
// cleanup calls the hidden dispatcher directly, so callback failures cannot be
// mistaken for successful manifest/registered delivery.
fn broadcast_defaults(code int, name string) string {
	mut body := '
invoke-virtual {p0}, ${receiver}->getResultCode()I
move-result v0
const/4 v1, ${code}
if-ne v0, v1, :bad
invoke-virtual {p0}, ${receiver}->getResultData()Ljava/lang/String;
move-result-object v0
if-nez v0, :bad
const/4 v1, 0
invoke-virtual {p0, v1}, ${receiver}->getResultExtras(Z)Landroid/os/Bundle;
move-result-object v0
if-nez v0, :bad
invoke-virtual {p0}, ${receiver}->getAbortBroadcast()Z
move-result v0
if-nez v0, :bad
invoke-virtual {p0}, ${receiver}->isOrderedBroadcast()Z
move-result v0
if-nez v0, :bad
invoke-virtual {p0}, ${receiver}->isInitialStickyBroadcast()Z
move-result v0
if-nez v0, :bad
return-void
'
	body += failure('${name} unordered broadcast defaults')
	return method('public static ${name}(${receiver})V', 2, body)
}

fn broadcast_mutation(target string, name string) string {
	return method('public static ${name}(${target})Landroid/os/Bundle;', 4, '
const/16 v0, 17
invoke-virtual {p0, v0}, ${target}->setResultCode(I)V
invoke-virtual {p0}, ${target}->getResultCode()I
move-result v1
if-ne v0, v1, :bad
const-string v0, "first-data"
invoke-virtual {p0, v0}, ${target}->setResultData(Ljava/lang/String;)V
invoke-virtual {p0}, ${target}->getResultData()Ljava/lang/String;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
const/4 v0, 1
invoke-virtual {p0, v0}, ${target}->getResultExtras(Z)Landroid/os/Bundle;
move-result-object v1
if-eqz v1, :bad
const/4 v0, 0
invoke-virtual {p0, v0}, ${target}->getResultExtras(Z)Landroid/os/Bundle;
move-result-object v2
if-ne v1, v2, :bad
new-instance v2, Landroid/os/Bundle;
invoke-direct {v2}, Landroid/os/Bundle;-><init>()V
const-string v0, "probe"
const-string v1, "retained-extra"
invoke-virtual {v2, v0, v1}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {p0, v2}, ${target}->setResultExtras(Landroid/os/Bundle;)V
const/4 v0, 0
invoke-virtual {p0, v0}, ${target}->getResultExtras(Z)Landroid/os/Bundle;
move-result-object v1
if-ne v1, v2, :bad
const/16 v0, 41
const-string v1, "retained-data"
invoke-virtual {p0, v0, v1, v2}, ${target}->setResult(ILjava/lang/String;Landroid/os/Bundle;)V
invoke-virtual {p0}, ${target}->getResultCode()I
move-result v3
if-ne v0, v3, :bad
invoke-virtual {p0}, ${target}->getResultData()Ljava/lang/String;
move-result-object v3
invoke-virtual {v1, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
const/4 v0, 0
invoke-virtual {p0, v0}, ${target}->getResultExtras(Z)Landroid/os/Bundle;
move-result-object v1
if-ne v1, v2, :bad
invoke-virtual {p0}, ${target}->abortBroadcast()V
invoke-virtual {p0}, ${target}->getAbortBroadcast()Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p0}, ${target}->clearAbortBroadcast()V
invoke-virtual {p0}, ${target}->getAbortBroadcast()Z
move-result v0
if-nez v0, :bad
invoke-virtual {p0}, ${target}->abortBroadcast()V
return-object v2
' + failure('broadcast result mutation or extras identity'))
}

fn broadcast_outside() string {
	mut body := '
invoke-static {p0}, ${owner}->broadcastDetached(${receiver})V
const/4 v1, 1
invoke-virtual {p0, v1}, ${receiver}->getResultExtras(Z)Landroid/os/Bundle;
move-result-object v0
if-nez v0, :bad
invoke-virtual {p0}, ${receiver}->goAsync()${pending_result}
move-result-object v0
if-nez v0, :bad
invoke-virtual {p0}, ${receiver}->clearAbortBroadcast()V
const/4 v1, 0
const/4 v2, 0
const/4 v3, 0
'
	for index, spec in [
		['setResultCode(I)V', 'p0, v1'],
		['setResultData(Ljava/lang/String;)V', 'p0, v2'],
		['setResultExtras(Landroid/os/Bundle;)V', 'p0, v3'],
		['setResult(ILjava/lang/String;Landroid/os/Bundle;)V', 'p0, v1, v2, v3'],
		['abortBroadcast()V', 'p0'],
	] {
		body += ':outside_start_${index}\ninvoke-virtual {${spec[1]}}, ${receiver}->${spec[0]}\n' +
			':outside_end_${index}\ngoto :bad\n.catch Ljava/lang/IllegalStateException; {:outside_start_${index} .. :outside_end_${index}} :outside_caught_${index}\n' +
			':outside_caught_${index}\nmove-exception v0\n'
	}
	return method('public static broadcastOutside(${receiver})V', 4,
		body + 'return-void\n' + failure('detached receiver accepted a result mutation'))
}

fn broadcast_cleanup() string {
	return method('private static broadcastCleanup(${context}${dynamic_receiver}${sibling_receiver}Landroid/os/HandlerThread;I)V', 4, '
const/4 v0, 0
and-int/lit8 v1, p4, 1
if-eqz v1, :second
:first_start
invoke-virtual {p0, p1}, ${context}->unregisterReceiver(${receiver})V
:first_end
goto :second
.catchall {:first_start .. :first_end} :first_failed
:first_failed
move-exception v0
:second
and-int/lit8 v1, p4, 2
if-eqz v1, :quit
:second_start
invoke-virtual {p0, p2}, ${context}->unregisterReceiver(${receiver})V
:second_end
goto :quit
.catchall {:second_start .. :second_end} :second_failed
:second_failed
move-exception v0
:quit
invoke-virtual {p3}, Landroid/os/HandlerThread;->quit()Z
const-wide/16 v1, 1000
invoke-virtual {p3, v1, v2}, Ljava/lang/Thread;->join(J)V
invoke-virtual {p3}, Ljava/lang/Thread;->isAlive()Z
move-result v1
if-nez v1, :bad
if-eqz v0, :done
throw v0
:done
return-void
' + failure('broadcast HandlerThread did not terminate'))
}

fn broadcast_checks() string {
	mut source := broadcast_defaults(-1, 'broadcastFresh') + broadcast_defaults(0, 'broadcastDetached') +
		broadcast_mutation(receiver, 'broadcastMutate') +
		broadcast_mutation(pending_result, 'pendingMutate') + broadcast_outside() + broadcast_cleanup()
	source += method('private static broadcasts(${context})V', 10, '
new-instance v0, Landroid/os/HandlerThread;
const-string v7, "broadcast-result-fixture"
invoke-direct {v0, v7}, Landroid/os/HandlerThread;-><init>(Ljava/lang/String;)V
const/4 v3, 0
const/4 v4, 0
const/4 v6, 0
:broadcast_start
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
invoke-virtual {v0}, Landroid/os/HandlerThread;->getLooper()Landroid/os/Looper;
move-result-object v1
new-instance v2, Landroid/os/Handler;
invoke-direct {v2, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
new-instance v8, Ljava/util/concurrent/CountDownLatch;
const/4 v7, 5
invoke-direct {v8, v7}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V
new-instance v5, ${dynamic_receiver}
invoke-direct {v5, v1, v8}, ${dynamic_receiver}-><init>(Landroid/os/Looper;Ljava/util/concurrent/CountDownLatch;)V
move-object v3, v5
new-instance v5, ${sibling_receiver}
invoke-direct {v5, v1, v8}, ${sibling_receiver}-><init>(Landroid/os/Looper;Ljava/util/concurrent/CountDownLatch;)V
move-object v4, v5
invoke-static {v3}, ${owner}->broadcastOutside(${receiver})V
new-instance v5, Landroid/content/IntentFilter;
const-string v7, "org.vinix.servicequery.REGISTERED_BROADCAST"
invoke-direct {v5, v7}, Landroid/content/IntentFilter;-><init>(Ljava/lang/String;)V
const/4 v9, 0
invoke-virtual {p0, v3, v5, v9, v2}, ${context}->registerReceiver(${receiver}Landroid/content/IntentFilter;Ljava/lang/String;Landroid/os/Handler;)Landroid/content/Intent;
const/4 v6, 1
invoke-virtual {p0, v4, v5, v9, v2}, ${context}->registerReceiver(${receiver}Landroid/content/IntentFilter;Ljava/lang/String;Landroid/os/Handler;)Landroid/content/Intent;
const/4 v6, 3
new-instance v5, Landroid/content/Intent;
const-string v7, "org.vinix.servicequery.MANIFEST_BROADCAST"
invoke-direct {v5, v7}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
const-string v7, "${client}"
const-string v9, "org.vinix.servicequery.ManifestReceiver"
invoke-virtual {v5, v7, v9}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
invoke-virtual {p0, v5}, ${context}->sendBroadcast(Landroid/content/Intent;)V
sget v7, ${owner}->manifestCalls:I
const/4 v9, 1
if-ne v7, v9, :bad
new-instance v5, Landroid/content/Intent;
const-string v7, "org.vinix.servicequery.REGISTERED_BROADCAST"
invoke-direct {v5, v7}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
invoke-virtual {p0, v5}, ${context}->sendBroadcast(Landroid/content/Intent;)V
invoke-virtual {p0, v5}, ${context}->sendBroadcast(Landroid/content/Intent;)V
# The callback latch alone can wake before dispatch finally detaches the result.
# This queued barrier runs after all four receiver dispatches fully return.
new-instance v5, Lorg/vinix/servicequery/BroadcastBarrier;
invoke-direct {v5, v8}, Lorg/vinix/servicequery/BroadcastBarrier;-><init>(Ljava/util/concurrent/CountDownLatch;)V
invoke-virtual {v2, v5}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
move-result v5
if-eqz v5, :bad
const-wide/16 v7, 8
sget-object v9, Ljava/util/concurrent/TimeUnit;->SECONDS:Ljava/util/concurrent/TimeUnit;
iget-object v5, v3, ${dynamic_receiver}->latch:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v5, v7, v8, v9}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v5
if-eqz v5, :bad
iget-object v5, v3, ${dynamic_receiver}->error:Ljava/lang/Throwable;
if-nez v5, :callback_failed
iget-object v5, v4, ${sibling_receiver}->error:Ljava/lang/Throwable;
if-nez v5, :callback_failed
iget v5, v3, ${dynamic_receiver}->calls:I
const/4 v7, 2
if-ne v5, v7, :bad
iget v5, v4, ${sibling_receiver}->calls:I
if-ne v5, v7, :bad
invoke-static {v3}, ${owner}->broadcastOutside(${receiver})V
invoke-static {v4}, ${owner}->broadcastOutside(${receiver})V
new-instance v5, ${throw_receiver}
invoke-direct {v5}, ${throw_receiver}-><init>()V
new-instance v7, Landroid/content/Intent;
invoke-direct {v7}, Landroid/content/Intent;-><init>()V
const/4 v8, 0
:throw_start
invoke-virtual {v5, p0, v7, v8}, ${receiver}->vinixDispatch(${context}Landroid/content/Intent;Z)V
:throw_end
goto :bad
.catch Ljava/lang/RuntimeException; {:throw_start .. :throw_end} :throw_caught
:throw_caught
move-exception v7
iget-object v8, v5, ${throw_receiver}->failure:Ljava/lang/RuntimeException;
if-ne v7, v8, :bad
invoke-static {v5}, ${owner}->broadcastOutside(${receiver})V
goto :broadcast_end
:callback_failed
throw v5
:bad
new-instance v5, Ljava/lang/AssertionError;
const-string v7, "real broadcast dispatch, callback state or async ownership"
invoke-direct {v5, v7}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v5
:broadcast_end
goto :success
.catchall {:broadcast_start .. :broadcast_end} :broadcast_failed
:broadcast_failed
move-exception v5
invoke-static {p0, v3, v4, v0, v6}, ${owner}->broadcastCleanup(${context}${dynamic_receiver}${sibling_receiver}Landroid/os/HandlerThread;I)V
throw v5
:success
invoke-static {p0, v3, v4, v0, v6}, ${owner}->broadcastCleanup(${context}${dynamic_receiver}${sibling_receiver}Landroid/os/HandlerThread;I)V
return-void')
	return source
}

fn broadcast_classes() map[string]string {
	mut classes := map[string]string{}
	classes['ManifestReceiver'] = '.class public ${manifest_receiver}\n.super ${receiver}\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, ${receiver}-><init>()V\nreturn-void') +
		method('public onReceive(${context}Landroid/content/Intent;)V', 4, '
invoke-static {p0}, ${owner}->broadcastFresh(${receiver})V
# Reproduce the actual GMS invoke-super linkage failure.
const/16 v0, 23
invoke-super {p0, v0}, ${receiver}->setResultCode(I)V
invoke-virtual {p0}, ${receiver}->getResultCode()I
move-result v1
if-ne v0, v1, :bad
invoke-static {p0}, ${owner}->broadcastMutate(${receiver})Landroid/os/Bundle;
invoke-virtual {p0}, ${receiver}->goAsync()${pending_result}
move-result-object v0
if-eqz v0, :bad
invoke-static {p0}, ${owner}->broadcastOutside(${receiver})V
invoke-static {v0}, ${owner}->pendingMutate(${pending_result})Landroid/os/Bundle;
invoke-virtual {v0}, ${pending_result}->finish()V
:finish_start
invoke-virtual {v0}, ${pending_result}->finish()V
:finish_end
goto :bad
.catch Ljava/lang/IllegalStateException; {:finish_start .. :finish_end} :finished_twice
:finished_twice
move-exception v1
sget v0, ${owner}->manifestCalls:I
add-int/lit8 v0, v0, 1
sput v0, ${owner}->manifestCalls:I
return-void
' + failure('manifest broadcast super call, async transfer or component finish'))
	for name, class_name in {'DynamicReceiver': dynamic_receiver, 'SiblingReceiver': sibling_receiver} {
		mut source := '.class public ${class_name}\n.super ${receiver}\n' +
			'.field public calls:I\n.field public error:Ljava/lang/Throwable;\n.field public expected:Landroid/os/Looper;\n' +
			'.field public latch:Ljava/util/concurrent/CountDownLatch;\n'
		if name == 'DynamicReceiver' {
			source += '.field public first:${pending_result}\n.field public extras:Landroid/os/Bundle;\n'
		}
		source += method('public constructor <init>(Landroid/os/Looper;Ljava/util/concurrent/CountDownLatch;)V', 0,
			'invoke-direct {p0}, ${receiver}-><init>()V\niput-object p1, p0, ${class_name}->expected:Landroid/os/Looper;\n' +
			'iput-object p2, p0, ${class_name}->latch:Ljava/util/concurrent/CountDownLatch;\nreturn-void')
		mut body := '
:callback_start
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
iget-object v1, p0, ${class_name}->expected:Landroid/os/Looper;
if-ne v0, v1, :bad
invoke-static {p0}, ${owner}->broadcastFresh(${receiver})V
iget v0, p0, ${class_name}->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${class_name}->calls:I
const/4 v1, 2
if-gt v0, v1, :bad
'
		if name == 'DynamicReceiver' {
			body += '
const/4 v1, 1
if-ne v0, v1, :second
invoke-static {p0}, ${owner}->broadcastMutate(${receiver})Landroid/os/Bundle;
move-result-object v1
iput-object v1, p0, ${class_name}->extras:Landroid/os/Bundle;
invoke-virtual {p0}, ${receiver}->goAsync()${pending_result}
move-result-object v0
if-eqz v0, :bad
iput-object v0, p0, ${class_name}->first:${pending_result}
invoke-static {p0}, ${owner}->broadcastOutside(${receiver})V
goto/16 :callback_end
:second
invoke-static {p0}, ${owner}->broadcastMutate(${receiver})Landroid/os/Bundle;
invoke-virtual {p0}, ${receiver}->goAsync()${pending_result}
move-result-object v0
if-eqz v0, :bad
iget-object v1, p0, ${class_name}->first:${pending_result}
if-eqz v1, :bad
if-eq v0, v1, :bad
invoke-static {v0}, ${owner}->pendingMutate(${pending_result})Landroid/os/Bundle;
const/16 v2, 99
invoke-virtual {v0, v2}, ${pending_result}->setResultCode(I)V
invoke-virtual {v1}, ${pending_result}->getResultCode()I
move-result v2
const/16 v3, 41
if-ne v2, v3, :bad
invoke-virtual {v1}, ${pending_result}->getResultData()Ljava/lang/String;
move-result-object v2
const-string v3, "retained-data"
invoke-virtual {v3, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
const/4 v2, 0
invoke-virtual {v1, v2}, ${pending_result}->getResultExtras(Z)Landroid/os/Bundle;
move-result-object v2
iget-object v3, p0, ${class_name}->extras:Landroid/os/Bundle;
if-ne v2, v3, :bad
invoke-virtual {v1}, ${pending_result}->getAbortBroadcast()Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v1}, ${pending_result}->finish()V
invoke-virtual {v1}, ${pending_result}->finish()V
invoke-virtual {v0}, ${pending_result}->finish()V
invoke-virtual {v0}, ${pending_result}->finish()V
invoke-static {p0}, ${owner}->broadcastOutside(${receiver})V
'
		} else {
			body += '
const/4 v1, 1
if-ne v0, v1, :callback_end
invoke-static {p0}, ${owner}->broadcastMutate(${receiver})Landroid/os/Bundle;
'
		}
		body += '
:callback_end
goto :signal
.catchall {:callback_start .. :callback_end} :callback_failed
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "registered broadcast thread, fresh state or async ownership"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
iput-object v0, p0, ${class_name}->error:Ljava/lang/Throwable;
goto :signal
:callback_failed
move-exception v0
iput-object v0, p0, ${class_name}->error:Ljava/lang/Throwable;
:signal
iget-object v0, p0, ${class_name}->latch:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V
return-void'
		source += method('public onReceive(${context}Landroid/content/Intent;)V', 4, body)
		classes[name] = source
	}
	classes['ThrowReceiver'] = '.class public ${throw_receiver}\n.super ${receiver}\n' +
		'.field public failure:Ljava/lang/RuntimeException;\n' +
		method('public constructor <init>()V', 2, '
invoke-direct {p0}, ${receiver}-><init>()V
new-instance v0, Ljava/lang/RuntimeException;
const-string v1, "expected broadcast callback failure"
invoke-direct {v0, v1}, Ljava/lang/RuntimeException;-><init>(Ljava/lang/String;)V
iput-object v0, p0, ${throw_receiver}->failure:Ljava/lang/RuntimeException;
return-void') + method('public onReceive(${context}Landroid/content/Intent;)V', 1, '
invoke-static {p0}, ${owner}->broadcastFresh(${receiver})V
const/16 v0, 73
invoke-virtual {p0, v0}, ${receiver}->setResultCode(I)V
invoke-virtual {p0}, ${receiver}->abortBroadcast()V
iget-object v0, p0, ${throw_receiver}->failure:Ljava/lang/RuntimeException;
throw v0')
	classes['BroadcastBarrier'] = '.class public Lorg/vinix/servicequery/BroadcastBarrier;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
		'.field private latch:Ljava/util/concurrent/CountDownLatch;\n' +
		method('public constructor <init>(Ljava/util/concurrent/CountDownLatch;)V', 0,
			'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, Lorg/vinix/servicequery/BroadcastBarrier;->latch:Ljava/util/concurrent/CountDownLatch;\nreturn-void') +
		method('public run()V', 1,
			'iget-object v0, p0, Lorg/vinix/servicequery/BroadcastBarrier;->latch:Ljava/util/concurrent/CountDownLatch;\ninvoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V\nreturn-void')
	return classes
}

fn main_class() string {
	mut source := '.class public ${owner}\n.super Landroid/app/Activity;\n.field public static manifestCalls:I\n'
	source += method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void')
	source += query_check()
	source += implicit_check()
	source += component_array_check()
	source += metadata_check()
	source += checks() + path_checks() + preferences_check() + storage_check()
	source += broadcast_checks()
	mut body := 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\nmove-object v0, p0\n'
	for wrapped in [false, true] {
		if wrapped {
			body += 'new-instance v0, Landroid/content/ContextWrapper;\ninvoke-direct {v0, p0}, Landroid/content/ContextWrapper;-><init>(${context})V\n'
		}
		body += query(client, 'Enabled', 0, 1)
		body += query(client, 'Disabled', 0, 0)
		body += query(client, 'Disabled', 0x10000200, 1)
		body += query(client, 'Multi', 0, 1)
		for name in ['BootAware', 'BootResource', 'BootFalse'] { body += query(client, name, 0, 1) }
		body += query(client, 'Missing', 0, 0)
		body += query('org.vinix.servicequery.absent', 'Multi', 0x200, 0)
		body += query(disabled, 'Enabled', 0, 0)
		body += query(disabled, 'Enabled', 0x200, 1)
		body += 'invoke-static {v0}, ${owner}->implicit(${context})V\n'
		body += 'invoke-static {v0}, ${owner}->metadata(${context})V\n'
		body += 'invoke-static {v0}, ${owner}->storage(${context})V\n'
	}
	body += 'invoke-static {p0}, ${owner}->broadcasts(${context})V\n'
	body += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "${marker}"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\ninvoke-virtual {v0}, Ljava/io/PrintStream;->flush()V\nnew-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(${context})V\nconst-string v1, "Explicit service metadata query passed"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\nreturn-void'
	return source + method('public onCreate(Landroid/os/Bundle;)V', 5, body)
}

fn trap_class(name string, parent string) string {
	return '.class public Lorg/vinix/servicequery/${name};\n.super Landroid/app/${parent};\n' +
		method('public constructor <init>()V', 2, 'invoke-direct {p0}, Landroid/app/${parent};-><init>()V\ngoto :bad\n' + failure('metadata query instantiated ${name}'))
}

fn manifest(name string) string {
	package_name := if name == 'client' { client } else { disabled }
	mut components := '<service android:name="org.vinix.servicequery.Enabled" android:exported="false"/>'
	if name == 'client' {
		components += '<service android:name="org.vinix.servicequery.Disabled" android:enabled="false" android:exported="false" android:directBootAware="false"/>'
		components += '<service android:name="org.vinix.servicequery.Multi" android:exported="true"><intent-filter><action android:name="org.vinix.servicequery.ACTION"/></intent-filter><intent-filter><action android:name="org.vinix.servicequery.ACTION"/></intent-filter></service>'
		components += '<service android:name="org.vinix.servicequery.BootAware" android:exported="false" android:directBootAware="true"/><service android:name="org.vinix.servicequery.BootResource" android:exported="false" android:directBootAware="@bool/direct_boot_true"/><service android:name="org.vinix.servicequery.BootFalse" android:exported="false" android:directBootAware="@bool/direct_boot_false"/>'
		components += '<activity android:name="org.vinix.servicequery.Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity>'
		components += '<receiver android:name="org.vinix.servicequery.ManifestReceiver" android:exported="false"><intent-filter><action android:name="org.vinix.servicequery.MANIFEST_BROADCAST"/></intent-filter></receiver>'
	} else {
		// The disabled companion is parsed for metadata only. Its Application
		// constructor traps any accidental startup while resolving these entries.
		components += '<activity android:name="org.vinix.servicequery.BootActivity" android:directBootAware="true"/><activity-alias android:name="org.vinix.servicequery.BootAlias" android:targetActivity="org.vinix.servicequery.BootActivity"/><activity android:name="org.vinix.servicequery.DefaultActivity"/>'
		components += '<receiver android:name="org.vinix.servicequery.BootReceiver" android:directBootAware="@bool/direct_boot_true"/><receiver android:name="org.vinix.servicequery.DefaultReceiver"/>'
		components += '<provider android:name="org.vinix.servicequery.BootProvider" android:authorities="org.vinix.servicequery.boot" android:directBootAware="true"/><provider android:name="org.vinix.servicequery.DefaultProvider" android:authorities="org.vinix.servicequery.default"/>'
	}
	app := if name == 'client' { '' } else { ' android:enabled="false" android:name="org.vinix.servicequery.TrapApp"' }
	return '<?xml version="1.0"?><manifest xmlns:android="http://schemas.android.com/apk/res/android" package="${package_name}" android:versionCode="1"><uses-sdk android:minSdkVersion="29" android:targetSdkVersion="29"/><application android:label="Service query ${name}"${app}>${components}</application></manifest>'
}

fn hash(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn recorded(out string, label string, args []string) string {
	r := os.exec(args)
	os.write_file(out + '/commands/' + label + '.json', json2.encode({
		'argv': json2.Any(args), 'exit_code': json2.Any(r.exit_code), 'output': json2.Any(r.output)
	}, prettify: true) + '\n') or { panic(err) }
	if r.exit_code != 0 { panic(r.output) }
	return r.output
}

fn inventory(root string, relative string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		if key == 'sha256.json' { continue }
		path := root + '/' + key
		if os.is_link(path) { return error('unexpected output symlink') }
		if os.is_dir(path) { inventory(root, key, mut pins)! } else if os.is_file(path) { pins[key] = hash(path) } else { return error('unexpected output file type') }
	}
}

fn main() {
	if os.args.len != 7 { panic('OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER') }
	out, aapt, resources, tools, java, signer := os.abs_path(os.args[1]), os.real_path(os.args[2]), os.real_path(os.args[3]), os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	repo := os.real_path(os.dir(@FILE) + '/../..')
	if os.exists(out) || out == repo || out.starts_with(repo + '/') { panic('fresh external output required') }
	os.mkdir_all(out + '/commands')!
	key, keytool := out + '/fixture.p12', os.dir(java) + '/keytool'
	recorded(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname', 'CN=Vinix Service Query Fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), aapt, resources, java, signer, keytool] { inputs[os.real_path(path)] = hash(path) }
	for name in os.ls(tools)! { if name.ends_with('.jar') { inputs[tools + '/' + name] = hash(tools + '/' + name) } }
	mut apks := map[string]string{}
	for name in ['client', 'disabled'] {
		dir := out + '/' + name
		smali := dir + '/smali/org/vinix/servicequery'
		os.mkdir_all(smali)!
		os.mkdir_all(dir + '/res/values')!
		os.write_file(dir + '/res/values/values.xml', '<resources><string name="probe">Service query</string><bool name="direct_boot_true">true</bool><bool name="direct_boot_false">false</bool></resources>')!
		os.write_file(dir + '/AndroidManifest.xml', manifest(name))!
		if name == 'client' {
			os.write_file(smali + '/Main.smali', main_class())!
			for class_name, source in broadcast_classes() { os.write_file(smali + '/' + class_name + '.smali', source)! }
		} else { os.write_file(smali + '/TrapApp.smali', trap_class('TrapApp', 'Application'))! }
		for service in if name == 'client' { ['Enabled', 'Disabled', 'Multi', 'BootAware', 'BootResource', 'BootFalse'] } else { ['Enabled'] } { os.write_file(smali + '/' + service + '.smali', trap_class(service, 'Service'))! }
		recorded(out, name + '-compile', [aapt, 'compile', '--dir', dir + '/res', '-o', dir + '/resources.zip'])
		recorded(out, name + '-link', [aapt, 'link', '-I', resources, dir + '/resources.zip', '--manifest', dir + '/AndroidManifest.xml', '-o', dir + '/unsigned.apk'])
		recorded(out, name + '-manifest', [aapt, 'dump', 'xmltree', dir + '/unsigned.apk', '--file', 'AndroidManifest.xml'])
		build_apk(out, name, dir, tools, java, signer, key)!
		apks[name + '/probe.apk'] = hash(dir + '/probe.apk')
	}
	finish(out, repo, inputs, apks)!
}

fn build_apk(out string, name string, dir string, tools string, java string, signer string, key string) ! {
	assembly := recorded(out, name + '-assemble', [java, '-Xmx512m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', dir + '/smali', '-o', dir + '/classes.dex'])
	assert assembly.trim_space() == '', assembly
	recorded(out, name + '-roundtrip', [java, '-Xmx512m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', dir + '/classes.dex', '-o', dir + '/roundtrip'])
	if name == 'client' {
		decoded := os.read_file(dir + '/roundtrip/org/vinix/servicequery/Main.smali')!
		for expected in [marker, '->createCredentialProtectedStorageContext()', '->isCredentialProtectedStorage()Z',
			'->createConfigurationContext(', '->commit()Z', '->sendBroadcast(Landroid/content/Intent;)V',
			'->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;Ljava/lang/String;Landroid/os/Handler;)',
			'->vinixDispatch(Landroid/content/Context;Landroid/content/Intent;Z)V'] { assert decoded.contains(expected), expected }
		manifest_probe := os.read_file(dir + '/roundtrip/org/vinix/servicequery/ManifestReceiver.smali')!
		assert manifest_probe.contains('invoke-super') && manifest_probe.contains('${receiver}->setResultCode(I)V')
		registered_probe := os.read_file(dir + '/roundtrip/org/vinix/servicequery/DynamicReceiver.smali')!
		for expected in ['->myLooper()', '${receiver}->goAsync()${pending_result}', '${pending_result}->finish()V'] {
			assert registered_probe.contains(expected), expected
		}
	}
	recorded(out, name + '-zip', ['/usr/bin/zip', '-q', '-j', dir + '/unsigned.apk', dir + '/classes.dex'])
	apk := dir + '/probe.apk'
	recorded(out, name + '-sign', [java, '-Xmx512m', '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', apk, dir + '/unsigned.apk'])
	verified := recorded(out, name + '-verify', [java, '-Xmx512m', '-jar', signer, 'verify', '--verbose', apk])
	assert verified.contains('Verified using v3 scheme (APK Signature Scheme v3): true')
}

fn finish(out string, repo string, inputs map[string]string, apks map[string]string) ! {
	for path, pin in inputs { assert hash(path) == pin, 'input changed: ' + path }
	revision := os.exec(['git', '-C', repo, 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	os.write_file(out + '/build.json', json2.encode({
		'argv': json2.Any(os.args), 'source_revision': json2.Any(revision.output.trim_space()),
		'inputs_sha256': json2.decode[json2.Any](json2.encode(inputs))!, 'apks_sha256': json2.decode[json2.Any](json2.encode(apks))!,
		'pass_marker': json2.Any(marker), 'scope': json2.Any('Generic explicit query, direct-boot metadata, credential/device storage Context and broadcast result API regression. Tests fresh CE factories and primed-cache DE-to-CE roundtrips; distinct paths/preferences, dual storage predicates, nested wrappers, configuration and app/resources identity. Real Context.sendBroadcast drives a manifest invoke-super result setter and registered receivers on a dedicated HandlerThread. Probes unordered/sticky hints, result code/data/extras/abort, detached receiver behavior, exact goAsync transfer, independent consecutive deliveries, sibling delivery despite abort, component versus registered finish, and exceptional dispatcher cleanup. Callback errors reach the main checker; shared callback wait and thread join total at most nine seconds. Storage namespaces are separate private directories without separate encryption/unlock states. Signed APK generation and DEX roundtrip only until ART execution; no account/network activity. Metadata lookup must not construct services or companion Application.')
	}, prettify: true) + '\n')!
	os.cp(@FILE, out + '/builder.v')!
	os.cp(os.executable(), out + '/builder')!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	os.write_file(out + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
	println('SERVICE-QUERY-FIXTURE-APKS ' + out)
	println('SERVICE-QUERY-FIXTURE-SEAL ' + hash(out + '/sha256.json'))
}
