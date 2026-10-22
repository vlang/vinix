// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Android HTTP clients discover legacy ALPN by the platform provider class.
// Expose that API using the installed wolfJSSE implementations: the adapter
// neither implements cryptography nor changes trust managers or provider order.
fn framework_tls_provider(smali string) ! {
	provider := 'Lcom/android/org/conscrypt/OpenSSLProvider;'
	path := smali + '/com/android/org/conscrypt/OpenSSLProvider.smali'
	if os.exists(path) { return error('a platform TLS provider already exists') }
	os.mkdir_all(os.dir(path))!
	os.write_file(path, '.class public final ${provider}
.super Ljava/security/Provider;
' + signature_method('public constructor <init>()V', '
move-object v0, p0
const-string v1, "VinixTLS"
const-wide/high16 v2, 0x3ff0000000000000L
const-string v4, "Vinix Android TLS adapter backed by wolfJSSE"
invoke-direct {v0, v1, v2, v3, v4}, Ljava/security/Provider;-><init>(Ljava/lang/String;DLjava/lang/String;)V
const-string v0, "wolfJSSE"
invoke-static {v0}, Ljava/security/Security;->getProvider(Ljava/lang/String;)Ljava/security/Provider;
move-result-object v0
if-nez v0, :copy
new-instance v0, Ljava/security/ProviderException;
const-string v1, "wolfJSSE TLS provider is not installed"
invoke-direct {v0, v1}, Ljava/security/ProviderException;-><init>(Ljava/lang/String;)V
throw v0
:copy
invoke-virtual {v0}, Ljava/security/Provider;->entrySet()Ljava/util/Set;
move-result-object v0
invoke-interface {v0}, Ljava/util/Set;->iterator()Ljava/util/Iterator;
move-result-object v0
:next
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v1
if-eqz v1, :done
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v1
check-cast v1, Ljava/util/Map$Entry;
invoke-interface {v1}, Ljava/util/Map$Entry;->getKey()Ljava/lang/Object;
move-result-object v2
check-cast v2, Ljava/lang/String;
const-string v3, "Provider."
invoke-virtual {v2, v3}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v3
if-nez v3, :next
invoke-interface {v1}, Ljava/util/Map$Entry;->getValue()Ljava/lang/Object;
move-result-object v1
invoke-virtual {p0, v2, v1}, Ljava/security/Provider;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
goto :next
:done
return-void') + signature_method('public static install()V', '
const-string v0, "VinixTLS"
invoke-static {v0}, Ljava/security/Security;->getProvider(Ljava/lang/String;)Ljava/security/Provider;
move-result-object v0
if-nez v0, :done
new-instance v0, ${provider}
invoke-direct {v0}, ${provider}-><init>()V
invoke-static {v0}, Ljava/security/Security;->addProvider(Ljava/security/Provider;)I
:done
return-void'))!
}
