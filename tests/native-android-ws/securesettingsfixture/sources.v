// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const resolver_type = 'Lorg/vinix/bootstrap/SettingsResolver;'
const secure_type = 'Landroid/provider/Settings$Secure;'
const content_resolver_type = 'Landroid/content/ContentResolver;'
const values_type = 'Landroid/content/ContentValues;'
const uri_type = 'Landroid/net/Uri;'
const tile_type = 'Landroid/service/quicksettings/TileService;'
const tile_adapter_type = 'Lorg/vinix/bootstrap/TileAdapter;'
const recording_context_type = 'Lorg/vinix/bootstrap/RecordingContext;'
const component_type = 'Landroid/content/ComponentName;'
const tile_request = 'requestListeningState(Landroid/content/Context;Landroid/content/ComponentName;)V'
const put_signature = 'putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z'
const caller_key = 'nearby_sharing_component'
const caller_component = 'com.google.android.gms/com.google.android.gms.nearby.sharing.main.MainActivity'
const pass_marker = 'SECURE-SETTINGS-PASS public-static virtual-insert secure-uri exact-string-null-values nearby-component empty-clear provider-result SQLException narrow-exceptions null-resolver absent-provider preserved-getters tile-broadcast intent-payload nullable-component fresh-intents inherited-static'
const fail_marker = 'SECURE-SETTINGS-FAIL'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn assertion_helpers() string {
	return method('private static equal(IILjava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static text(Ljava/lang/Object;Ljava/lang/String;)V', 2, '
if-eqz p1, :null_expected
instance-of v0, p0, Ljava/lang/String;
if-eqz v0, :bad
invoke-virtual {p1, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
return-void
:null_expected
if-nez p0, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "exact String or explicit null entry required"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
}

fn shape_source() string {
	return method('private static publicStaticQuery()V', 5, '
const-class v0, ${secure_type}
const-string v1, "putString"
const/4 v2, 3
new-array v2, v2, [Ljava/lang/Class;
const-class v3, ${content_resolver_type}
const/4 v4, 0
aput-object v3, v2, v4
const-class v3, Ljava/lang/String;
const/4 v4, 1
aput-object v3, v2, v4
const/4 v4, 2
aput-object v3, v2, v4
invoke-virtual {v0, v1, v2}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;
move-result-object v1
sget-object v2, Ljava/lang/Boolean;->TYPE:Ljava/lang/Class;
const-string v4, "Secure.putString must return primitive boolean"
invoke-static {v1, v2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getModifiers()I
move-result v0
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isPublic(I)Z
move-result v1
const/4 v2, 1
const-string v4, "Secure.putString must be public"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isStatic(I)Z
move-result v1
const-string v4, "Secure.putString must be static"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

fn write_source() string {
	return method('private static write(${resolver_type}Ljava/lang/String;Ljava/lang/String;Z)V', 6, '
iget v0, p0, ${resolver_type}->calls:I
add-int/lit8 v0, v0, 1
invoke-static {p0, p1, p2}, ${secure_type}->${put_signature}
move-result v1
const-string v2, "provider URI result or SQLException outcome"
invoke-static {v1, p3, v2}, ${main_type}->equal(IILjava/lang/String;)V
iget v1, p0, ${resolver_type}->calls:I
const-string v2, "exactly one virtual insert required"
invoke-static {v1, v0, v2}, ${main_type}->equal(IILjava/lang/String;)V
iget-object v0, p0, ${resolver_type}->uri:${uri_type}
sget-object v1, ${secure_type}->CONTENT_URI:${uri_type}
const-string v2, "insert must receive actual Secure.CONTENT_URI object"
invoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, ${uri_type}->toString()Ljava/lang/String;
move-result-object v0
const-string v1, "content://settings/secure"
invoke-static {v0, v1}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
iget-object v0, p0, ${resolver_type}->values:${values_type}
invoke-virtual {v0}, ${values_type}->size()I
move-result v1
const/4 v2, 2
const-string v3, "exactly name and value entries required"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
const-string v1, "name"
invoke-virtual {v0, v1}, ${values_type}->containsKey(Ljava/lang/String;)Z
move-result v2
const/4 v3, 1
const-string v4, "explicit name key required even for null name"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0, v1}, ${values_type}->get(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v2
invoke-static {v2, p1}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
const-string v1, "value"
invoke-virtual {v0, v1}, ${values_type}->containsKey(Ljava/lang/String;)Z
move-result v2
const-string v4, "explicit value key required even for null value"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0, v1}, ${values_type}->get(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v2
invoke-static {v2, p2}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
return-void')
}

fn propagation_source() string {
	return method('private static rejects(${resolver_type}Ljava/lang/RuntimeException;)V', 5, '
iput-object p1, p0, ${resolver_type}->failure:Ljava/lang/RuntimeException;
iget v0, p0, ${resolver_type}->calls:I
add-int/lit8 v0, v0, 1
const-string v1, "${caller_key}"
const-string v2, "exception-control"
:try_start
invoke-static {p0, v1, v2}, ${secure_type}->${put_signature}
:try_end
new-instance v1, Ljava/lang/AssertionError;
const-string v2, "non-SQL exception must propagate"
invoke-direct {v1, v2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v1
:caught
move-exception v1
const-string v2, "non-SQL exception identity must remain unchanged"
invoke-static {v1, p1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
iget v1, p0, ${resolver_type}->calls:I
const-string v2, "exception must originate from exactly one insert"
invoke-static {v1, v0, v2}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v1, 0
iput-object v1, p0, ${resolver_type}->failure:Ljava/lang/RuntimeException;
return-void
.catch Ljava/lang/RuntimeException; {:try_start .. :try_end} :caught') +
		method('private static nullResolver()V', 4, '
const/4 v0, 0
const-string v1, "${caller_key}"
const-string v2, "null-resolver"
:try_start
invoke-static {v0, v1, v2}, ${secure_type}->${put_signature}
:try_end
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "null resolver must throw NPE"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:caught
move-exception v3
return-void
.catch Ljava/lang/NullPointerException; {:try_start .. :try_end} :caught')
}

fn preservation_source() string {
	return method('private static preserved(${content_resolver_type})V', 4, '
const-string v0, "${caller_key}"
invoke-static {p0, v0}, ${secure_type}->getString(${content_resolver_type}Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
const-string v2, "NOTICEME"
invoke-static {v1, v2}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
const/16 v2, 37
invoke-static {p0, v0, v2}, ${secure_type}->getInt(${content_resolver_type}Ljava/lang/String;I)I
move-result v1
const-string v3, "existing unknown secure integer default must remain unchanged"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
const-string v1, "user_setup_complete"
invoke-static {p0, v1}, ${secure_type}->getInt(${content_resolver_type}Ljava/lang/String;)I
move-result v1
const/4 v2, 1
const-string v3, "existing known Secure integer fallback must remain unchanged"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v0}, ${secure_type}->getUriFor(Ljava/lang/String;)${uri_type}
move-result-object v1
invoke-virtual {v1}, ${uri_type}->toString()Ljava/lang/String;
move-result-object v1
const-string v2, "content://settings/secure/${caller_key}"
invoke-static {v1, v2}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
return-void') + method('private static providerless(Landroid/content/Context;)V', 4, '
invoke-virtual {p0}, Landroid/content/Context;->getContentResolver()${content_resolver_type}
move-result-object v0
const-string v1, "${caller_key}"
const-string v2, "${caller_component}"
invoke-static {v0, v1, v2}, ${secure_type}->${put_signature}
move-result v0
const/4 v1, 0
const-string v2, "missing real settings provider must not claim successful write"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
return-void')
}

fn tile_source() string {
	return method('private static tileShape()V', 5, '
const-class v0, ${tile_type}
invoke-virtual {v0}, Ljava/lang/Class;->getSuperclass()Ljava/lang/Class;
move-result-object v1
const-class v2, Landroid/app/Service;
const-string v4, "TileService must extend the actual Service base"
invoke-static {v1, v2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v1, "requestListeningState"
const/4 v2, 2
new-array v2, v2, [Ljava/lang/Class;
const-class v3, Landroid/content/Context;
const/4 v4, 0
aput-object v3, v2, v4
const-class v3, ${component_type}
const/4 v4, 1
aput-object v3, v2, v4
invoke-virtual {v0, v1, v2}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;
move-result-object v1
sget-object v2, Ljava/lang/Void;->TYPE:Ljava/lang/Class;
const-string v4, "TileService listening request must return void"
invoke-static {v1, v2, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getModifiers()I
move-result v0
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isPublic(I)Z
move-result v1
const/4 v2, 1
const-string v4, "TileService listening request must be public"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isStatic(I)Z
move-result v1
const-string v4, "TileService listening request must be static"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isFinal(I)Z
move-result v1
const-string v4, "TileService listening request must be final"
invoke-static {v1, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-void') + method('private static tileCheck(${recording_context_type}${component_type}ILandroid/content/Intent;)V', 5, '
iget v0, p0, ${recording_context_type}->calls:I
const-string v1, "each TileService request must dispatch exactly one permission-aware broadcast"
invoke-static {v0, p2, v1}, ${main_type}->equal(IILjava/lang/String;)V
iget-object v0, p0, ${recording_context_type}->intent:Landroid/content/Intent;
if-eqz v0, :bad
if-eq v0, p3, :bad
invoke-virtual {v0}, Landroid/content/Intent;->getAction()Ljava/lang/String;
move-result-object v1
const-string v2, "android.service.quicksettings.action.REQUEST_LISTENING"
invoke-static {v1, v2}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Landroid/content/Intent;->getPackage()Ljava/lang/String;
move-result-object v1
const-string v2, "com.android.systemui"
invoke-static {v1, v2}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
iget-object v1, p0, ${recording_context_type}->permission:Ljava/lang/String;
const-string v2, "android.permission.BIND_QUICK_SETTINGS_TILE"
invoke-static {v1, v2}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
const-string v1, "android.intent.extra.COMPONENT_NAME"
invoke-virtual {v0, v1}, Landroid/content/Intent;->hasExtra(Ljava/lang/String;)Z
move-result v2
const/4 v3, 1
const-string v4, "component extra must remain present even for a null component"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0, v1}, Landroid/content/Intent;->getParcelableExtra(Ljava/lang/String;)Landroid/os/Parcelable;
move-result-object v2
const-string v4, "TileService must forward the exact component object or explicit null"
invoke-static {v2, p1, v4}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Landroid/content/Intent;->getExtras()Landroid/os/Bundle;
move-result-object v1
invoke-virtual {v1}, Landroid/os/Bundle;->size()I
move-result v2
const-string v4, "TileService request must contain exactly its component extra"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "every listening request must allocate a fresh Intent"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') + method('private static tileRejects(${recording_context_type}${component_type}Ljava/lang/RuntimeException;)V', 5, '
iget v0, p0, ${recording_context_type}->calls:I
add-int/lit8 v0, v0, 1
iget-object v1, p0, ${recording_context_type}->intent:Landroid/content/Intent;
iput-object p2, p0, ${recording_context_type}->failure:Ljava/lang/RuntimeException;
:try_start
invoke-static {p0, p1}, ${tile_type}->${tile_request}
:try_end
new-instance v2, Ljava/lang/AssertionError;
const-string v3, "broadcast exception must propagate from TileService"
invoke-direct {v2, v3}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v2
:caught
move-exception v2
const-string v3, "TileService must preserve exact broadcast exception identity"
invoke-static {v2, p2, v3}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {p0, p1, v0, v1}, ${main_type}->tileCheck(${recording_context_type}${component_type}ILandroid/content/Intent;)V
const/4 v2, 0
iput-object v2, p0, ${recording_context_type}->failure:Ljava/lang/RuntimeException;
return-void
.catch Ljava/lang/RuntimeException; {:try_start .. :try_end} :caught') +
		method('private static tileNullContext(${component_type})V', 3, '
const/4 v0, 0
:try_start
invoke-static {v0, p0}, ${tile_type}->${tile_request}
:try_end
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "null TileService request context must throw NPE"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:caught
move-exception v2
return-void
.catch Ljava/lang/NullPointerException; {:try_start .. :try_end} :caught')
}

fn tile_controls_source() string {
	return method('private static tileControls(Landroid/content/Context;)V', 7, '
invoke-static {}, ${main_type}->tileShape()V
new-instance v1, ${component_type}
const-string v2, "org.vinix.bootstrap"
const-string v3, "org.vinix.bootstrap.TileAdapter"
invoke-direct {v1, v2, v3}, ${component_type}-><init>(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v1}, ${component_type}->flattenToString()Ljava/lang/String;
move-result-object v4
invoke-virtual {v1}, ${component_type}->hashCode()I
move-result v5
# Real-context calls are smoke checks only; callback absence is not inferred.
invoke-static {p0, v1}, ${tile_type}->${tile_request}
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v2
invoke-static {v2, v1}, ${tile_adapter_type}->${tile_request}
const/4 v2, 0
invoke-static {p0, v2}, ${tile_type}->${tile_request}
new-instance v0, ${recording_context_type}
invoke-direct {v0, p0}, ${recording_context_type}-><init>(Landroid/content/Context;)V
iget-object v3, v0, ${recording_context_type}->intent:Landroid/content/Intent;
invoke-static {v0, v1}, ${tile_adapter_type}->${tile_request}
const/4 v2, 1
invoke-static {v0, v1, v2, v3}, ${main_type}->tileCheck(${recording_context_type}${component_type}ILandroid/content/Intent;)V
iget-object v3, v0, ${recording_context_type}->intent:Landroid/content/Intent;
invoke-static {v0, v1}, ${tile_type}->${tile_request}
const/4 v2, 2
invoke-static {v0, v1, v2, v3}, ${main_type}->tileCheck(${recording_context_type}${component_type}ILandroid/content/Intent;)V
iget-object v3, v0, ${recording_context_type}->intent:Landroid/content/Intent;
const/4 v6, 0
invoke-static {v0, v6}, ${tile_adapter_type}->${tile_request}
const/4 v2, 3
invoke-static {v0, v6, v2, v3}, ${main_type}->tileCheck(${recording_context_type}${component_type}ILandroid/content/Intent;)V
new-instance v6, Ljava/lang/SecurityException;
invoke-direct {v6}, Ljava/lang/SecurityException;-><init>()V
invoke-static {v0, v1, v6}, ${main_type}->tileRejects(${recording_context_type}${component_type}Ljava/lang/RuntimeException;)V
iget-object v3, v0, ${recording_context_type}->intent:Landroid/content/Intent;
invoke-static {v0, v1}, ${tile_type}->${tile_request}
const/4 v2, 5
invoke-static {v0, v1, v2, v3}, ${main_type}->tileCheck(${recording_context_type}${component_type}ILandroid/content/Intent;)V
invoke-virtual {v1}, ${component_type}->flattenToString()Ljava/lang/String;
move-result-object v2
invoke-static {v2, v4}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1}, ${component_type}->hashCode()I
move-result v2
const-string v3, "listening requests must preserve caller component state"
invoke-static {v2, v5, v3}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v1}, ${main_type}->tileNullContext(${component_type})V
new-instance v0, ${tile_type}
invoke-direct {v0}, ${tile_type}-><init>()V
const/4 v3, 0
invoke-virtual {v0, v3}, ${tile_type}->onBind(Landroid/content/Intent;)Landroid/os/IBinder;
move-result-object v1
const-string v2, "unsupported TileService binding must return null"
invoke-static {v1, v3, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
new-instance v4, Landroid/content/Intent;
invoke-direct {v4}, Landroid/content/Intent;-><init>()V
invoke-virtual {v0, v4}, ${tile_type}->onBind(Landroid/content/Intent;)Landroid/os/IBinder;
move-result-object v1
invoke-static {v1, v3, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
new-instance v0, ${tile_adapter_type}
invoke-direct {v0}, ${tile_adapter_type}-><init>()V
invoke-virtual {v0, v3}, ${tile_type}->onBind(Landroid/content/Intent;)Landroid/os/IBinder;
move-result-object v1
invoke-static {v1, v3, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void')
}

fn recording_tile_sources() map[string]string {
	return {
		'org/vinix/bootstrap/RecordingContext.smali': '.class public final ${recording_context_type}\n.super Landroid/content/ContextWrapper;\n' +
			'.field public intent:Landroid/content/Intent;\n.field public permission:Ljava/lang/String;\n.field public calls:I\n.field public failure:Ljava/lang/RuntimeException;\n' +
			method('public constructor <init>(Landroid/content/Context;)V', 0, 'invoke-direct {p0, p1}, Landroid/content/ContextWrapper;-><init>(Landroid/content/Context;)V\nreturn-void') +
			method('public sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V', 1, '
iget v0, p0, ${recording_context_type}->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${recording_context_type}->calls:I
iput-object p1, p0, ${recording_context_type}->intent:Landroid/content/Intent;
iput-object p2, p0, ${recording_context_type}->permission:Ljava/lang/String;
iget-object v0, p0, ${recording_context_type}->failure:Ljava/lang/RuntimeException;
if-eqz v0, :done
throw v0
:done
return-void')
		'org/vinix/bootstrap/TileAdapter.smali': '.class public final ${tile_adapter_type}\n.super ${tile_type}\n' +
			method('public constructor <init>()V', 0, 'invoke-direct {p0}, ${tile_type}-><init>()V\nreturn-void') +
			method('public dormantTile()Landroid/service/quicksettings/Tile;', 1, '
invoke-virtual {p0}, ${tile_adapter_type}->getQsTile()Landroid/service/quicksettings/Tile;
move-result-object v0
return-object v0')
	}
}

fn run_source() string {
	mut body := '
invoke-static {}, ${main_type}->publicStaticQuery()V
invoke-static {p0}, ${main_type}->providerless(Landroid/content/Context;)V
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v1
invoke-static {v1}, ${main_type}->providerless(Landroid/content/Context;)V
new-instance v0, ${resolver_type}
invoke-direct {v0}, ${resolver_type}-><init>()V
const-string v1, "content://fixture/accepted"
invoke-static {v1}, ${uri_type}->parse(Ljava/lang/String;)${uri_type}
move-result-object v4
iput-object v4, v0, ${resolver_type}->resultUri:${uri_type}
invoke-static {v0}, ${main_type}->preserved(${content_resolver_type})V
const/4 v3, 1
'
	for pair in [
		['"${caller_key}"', '"${caller_component}"'],
		['"${caller_key}"', '""'],
		['"${caller_key}"', ''],
		['', '"null-name-value"'],
		['""', '""'],
		['"${caller_key}"', '"value with spaces / ? = &"'],
		['"${caller_key}"', '"replacement-without-persistence"'],
	] {
		for i, register in ['v1', 'v2'] {
			body += if pair[i] == '' { 'const/4 ${register}, 0\n' } else { 'const-string ${register}, ${pair[i]}\n' }
		}
		body += 'invoke-static {v0, v1, v2, v3}, ${main_type}->write(${resolver_type}Ljava/lang/String;Ljava/lang/String;Z)V\n'
	}
	body += 'const/4 v3, 0
iput-object v3, v0, ${resolver_type}->resultUri:${uri_type}
invoke-static {v0, v1, v2, v3}, ${main_type}->write(${resolver_type}Ljava/lang/String;Ljava/lang/String;Z)V
iput-object v4, v0, ${resolver_type}->resultUri:${uri_type}
new-instance v5, Landroid/database/SQLException;
invoke-direct {v5}, Landroid/database/SQLException;-><init>()V
iput-object v5, v0, ${resolver_type}->failure:Ljava/lang/RuntimeException;
invoke-static {v0, v1, v2, v3}, ${main_type}->write(${resolver_type}Ljava/lang/String;Ljava/lang/String;Z)V
'
	for exception_type in ['SecurityException', 'IllegalArgumentException', 'NullPointerException'] {
		body += 'new-instance v5, Ljava/lang/${exception_type};\ninvoke-direct {v5}, Ljava/lang/${exception_type};-><init>()V\n' +
			'invoke-static {v0, v5}, ${main_type}->rejects(${resolver_type}Ljava/lang/RuntimeException;)V\n'
	}
	body += 'const-string v1, "${caller_key}"
const-string v2, "after-exceptions"
const/4 v3, 1
invoke-static {v0, v1, v2, v3}, ${main_type}->write(${resolver_type}Ljava/lang/String;Ljava/lang/String;Z)V
invoke-static {v0}, ${main_type}->preserved(${content_resolver_type})V
iget v1, v0, ${resolver_type}->calls:I
const/16 v2, 13
const-string v3, "all thirteen recording resolver calls must execute"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {}, ${main_type}->nullResolver()V
invoke-static {p0}, ${main_type}->tileControls(Landroid/content/Context;)V
return-void'
	return method('private static run(Landroid/content/Context;)V', 6, body)
}

fn resolver_source() string {
	return '.class public final ${resolver_type}\n.super ${content_resolver_type}\n' +
		'.field public calls:I\n.field public uri:${uri_type}\n.field public values:${values_type}\n' +
		'.field public resultUri:${uri_type}\n.field public failure:Ljava/lang/RuntimeException;\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, ${content_resolver_type}-><init>()V\nreturn-void') +
		method('public insert(${uri_type}${values_type})${uri_type}', 1, '
iget v0, p0, ${resolver_type}->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${resolver_type}->calls:I
iput-object p1, p0, ${resolver_type}->uri:${uri_type}
iput-object p2, p0, ${resolver_type}->values:${values_type}
iget-object v0, p0, ${resolver_type}->failure:Ljava/lang/RuntimeException;
if-eqz v0, :result
throw v0
:result
iget-object v0, p0, ${resolver_type}->resultUri:${uri_type}
return-object v0')
}

fn fixture_sources() map[string]string {
	main_source := '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		assertion_helpers() + shape_source() + write_source() + propagation_source() + preservation_source() +
		tile_source() + tile_controls_source() + run_source() +
		method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {p0}, ${main_type}->run(Landroid/content/Context;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Secure settings delegation passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
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
	mut sources := recording_tile_sources()
	sources['org/vinix/bootstrap/Main.smali'] = main_source
	sources['org/vinix/bootstrap/SettingsResolver.smali'] = resolver_source()
	return sources
}

fn expected_classes() []string {
	return ['org/vinix/bootstrap/Main.smali', 'org/vinix/bootstrap/RecordingContext.smali', 'org/vinix/bootstrap/SettingsResolver.smali',
		'org/vinix/bootstrap/TileAdapter.smali']
}

fn verify_source_references(source string) {
	if source.starts_with('.class public final ${main_type}') {
		for reference in ['${secure_type}->${put_signature}',
			'${values_type}->containsKey(Ljava/lang/String;)Z', '${main_type}->rejects(', '${main_type}->nullResolver()V',
			'${main_type}->preserved(', caller_key, caller_component, 'Landroid/database/SQLException;',
			'Ljava/lang/SecurityException;', 'Ljava/lang/IllegalArgumentException;', 'Ljava/lang/NullPointerException;',
			'${tile_type}->${tile_request}', '${tile_adapter_type}->${tile_request}',
			'android.service.quicksettings.action.REQUEST_LISTENING', 'android.intent.extra.COMPONENT_NAME',
			'com.android.systemui', 'android.permission.BIND_QUICK_SETTINGS_TILE',
			'${tile_type}->onBind(Landroid/content/Intent;)Landroid/os/IBinder;'] {
			assert source.contains(reference), 'missing runtime assertion reference: ' + reference
		}
		assert source.count('.catch Ljava/lang/RuntimeException;') == 2, 'narrow write and tile exception identity probes required'
	} else if source.starts_with('.class public final ${resolver_type}') {
		assert source.contains('.method public insert(${uri_type}${values_type})${uri_type}')
	} else if source.starts_with('.class public final ${recording_context_type}') {
		assert source.contains('.super Landroid/content/ContextWrapper;')
		assert source.contains('.method public sendBroadcast(Landroid/content/Intent;Ljava/lang/String;)V')
	} else {
		assert source.starts_with('.class public final ${tile_adapter_type}') && source.contains('.super ${tile_type}'), 'unexpected fixture class'
		assert source.contains('->getQsTile()Landroid/service/quicksettings/Tile;'), 'retain dormant unsupported tile continuation'
	}
	assert !source.contains('.class public final Landroid/'), 'fixture must not supply platform stubs'
	assert !source.contains('UserManager') && !source.contains('StatusBarManager'), 'SDK-33 provisional paths must remain absent'
}
