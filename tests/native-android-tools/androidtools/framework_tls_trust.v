// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// The staged wolfJSSE requires every supplied CA to verify, including redundant
// cross-signed roots. Stop at an existing trust anchor with the same subject
// and public key, then let wolfJSSE verify every remaining certificate. Peer
// certificates never become trust anchors. This adapter also retains Android's
// three-argument checkServerTrusted API and its verified-chain return value.
fn framework_tls_trust(smali string) !string {
	factory := 'Landroid/atl/VinixTrustManagerFactory;'
	manager := 'Landroid/atl/VinixTrustManager;'
	wolf := 'Lcom/wolfssl/provider/jsse/WolfSSLTrustX509;'
	mut services := ''
	for i, algorithm in ['PKIX', 'SunX509', 'X509'] {
		child := 'Landroid/atl/VinixTrustManagerFactory${i};'
		services += '
const-string v1, "TrustManagerFactory"
const-string v2, "${algorithm}"
invoke-virtual {v0, v1, v2}, Ljava/security/Provider;->getService(Ljava/lang/String;Ljava/lang/String;)Ljava/security/Provider\$Service;
move-result-object v1
if-eqz v1, :trust_next_${i}
const-string v1, "TrustManagerFactory.${algorithm}"
const-string v2, "android.atl.VinixTrustManagerFactory${i}"
invoke-virtual {p0, v1, v2}, Ljava/security/Provider;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
:trust_next_${i}
'
		os.write_file(smali + '/android/atl/VinixTrustManagerFactory${i}.smali', '.class public final ${child}\n.super ${factory}\n' +
			signature_method('public constructor <init>()V', 'const-string v0, "${algorithm}"\ninvoke-direct {p0, v0}, ${factory}-><init>(Ljava/lang/String;)V\nreturn-void'))!
	}
	os.write_file(smali + '/android/atl/VinixTrustManagerFactory.smali', '.class public ${factory}\n.super Ljavax/net/ssl/TrustManagerFactorySpi;\n.field private delegate:Ljavax/net/ssl/TrustManagerFactory;\n' +
		signature_method('public constructor <init>(Ljava/lang/String;)V', '
invoke-direct {p0}, Ljavax/net/ssl/TrustManagerFactorySpi;-><init>()V
const-string v0, "wolfJSSE"
invoke-static {p1, v0}, Ljavax/net/ssl/TrustManagerFactory;->getInstance(Ljava/lang/String;Ljava/lang/String;)Ljavax/net/ssl/TrustManagerFactory;
move-result-object v0
iput-object v0, p0, ${factory}->delegate:Ljavax/net/ssl/TrustManagerFactory;
return-void') +
		signature_method('protected engineInit(Ljava/security/KeyStore;)V', '
iget-object v0, p0, ${factory}->delegate:Ljavax/net/ssl/TrustManagerFactory;
invoke-virtual {v0, p1}, Ljavax/net/ssl/TrustManagerFactory;->init(Ljava/security/KeyStore;)V
return-void') +
		signature_method('protected engineInit(Ljavax/net/ssl/ManagerFactoryParameters;)V', '
iget-object v0, p0, ${factory}->delegate:Ljavax/net/ssl/TrustManagerFactory;
invoke-virtual {v0, p1}, Ljavax/net/ssl/TrustManagerFactory;->init(Ljavax/net/ssl/ManagerFactoryParameters;)V
return-void') +
		signature_method('protected engineGetTrustManagers()[Ljavax/net/ssl/TrustManager;', '
iget-object v0, p0, ${factory}->delegate:Ljavax/net/ssl/TrustManagerFactory;
invoke-virtual {v0}, Ljavax/net/ssl/TrustManagerFactory;->getTrustManagers()[Ljavax/net/ssl/TrustManager;
move-result-object v0
const/4 v1, 0
:next
array-length v2, v0
if-ge v1, v2, :done
aget-object v2, v0, v1
instance-of v3, v2, ${wolf}
if-eqz v3, :skip
check-cast v2, ${wolf}
new-instance v3, ${manager}
invoke-direct {v3, v2}, ${manager}-><init>(${wolf})V
aput-object v3, v0, v1
:skip
add-int/lit8 v1, v1, 1
goto :next
:done
return-object v0'))!
	mut body := '.class public final ${manager}\n.super Ljava/lang/Object;\n.implements Ljavax/net/ssl/X509TrustManager;\n.field private delegate:${wolf}\n' +
		signature_method('public constructor <init>(${wolf})V', '
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, ${manager}->delegate:${wolf}
return-void') +
		signature_method('public getAcceptedIssuers()[Ljava/security/cert/X509Certificate;', '
iget-object v0, p0, ${manager}->delegate:${wolf}
invoke-virtual {v0}, ${wolf}->getAcceptedIssuers()[Ljava/security/cert/X509Certificate;
move-result-object v0
return-object v0') +
		signature_method('private ordered([Ljava/security/cert/X509Certificate;)[Ljava/security/cert/X509Certificate;', '
# The staged wolfSSL native verify callback supplies root-first chains.
# Android and JSSE callers supply leaf-first chains. Copy before reversing.
if-eqz p1, :unchanged
array-length v0, p1
const/4 v1, 1
if-le v0, v1, :unchanged
const/4 v1, 0
aget-object v2, p1, v1
if-eqz v2, :unchanged
invoke-virtual {v2}, Ljava/security/cert/X509Certificate;->getBasicConstraints()I
move-result v2
if-ltz v2, :unchanged
add-int/lit8 v2, v0, -1
aget-object v3, p1, v2
if-eqz v3, :unchanged
invoke-virtual {v3}, Ljava/security/cert/X509Certificate;->getBasicConstraints()I
move-result v3
if-gez v3, :unchanged
new-array v3, v0, [Ljava/security/cert/X509Certificate;
:reverse
if-ge v1, v0, :done
aget-object v4, p1, v2
aput-object v4, v3, v1
add-int/lit8 v1, v1, 1
add-int/lit8 v2, v2, -1
goto :reverse
:done
return-object v3
:unchanged
return-object p1') +
		signature_method('private chain([Ljava/security/cert/X509Certificate;)[Ljava/security/cert/X509Certificate;', '
invoke-direct {p0, p1}, ${manager}->ordered([Ljava/security/cert/X509Certificate;)[Ljava/security/cert/X509Certificate;
move-result-object p1
if-eqz p1, :unchanged
array-length v0, p1
const/4 v1, 1
if-le v0, v1, :unchanged
invoke-virtual {p0}, ${manager}->getAcceptedIssuers()[Ljava/security/cert/X509Certificate;
move-result-object v0
:peer
array-length v2, p1
if-ge v1, v2, :unchanged
aget-object v2, p1, v1
if-eqz v2, :unchanged
invoke-virtual {v2}, Ljava/security/cert/X509Certificate;->getBasicConstraints()I
move-result v3
if-ltz v3, :next_peer
const/4 v3, 0
:anchor
array-length v4, v0
if-ge v3, v4, :next_peer
aget-object v4, v0, v3
invoke-virtual {v4}, Ljava/security/cert/X509Certificate;->getBasicConstraints()I
move-result v5
if-ltz v5, :next_anchor
invoke-virtual {v2}, Ljava/security/cert/X509Certificate;->getSubjectX500Principal()Ljavax/security/auth/x500/X500Principal;
move-result-object v5
invoke-virtual {v4}, Ljava/security/cert/X509Certificate;->getSubjectX500Principal()Ljavax/security/auth/x500/X500Principal;
move-result-object v6
invoke-virtual {v5, v6}, Ljavax/security/auth/x500/X500Principal;->equals(Ljava/lang/Object;)Z
move-result v5
if-eqz v5, :next_anchor
invoke-virtual {v2}, Ljava/security/cert/X509Certificate;->getPublicKey()Ljava/security/PublicKey;
move-result-object v5
invoke-interface {v5}, Ljava/security/PublicKey;->getEncoded()[B
move-result-object v5
invoke-virtual {v4}, Ljava/security/cert/X509Certificate;->getPublicKey()Ljava/security/PublicKey;
move-result-object v6
invoke-interface {v6}, Ljava/security/PublicKey;->getEncoded()[B
move-result-object v6
invoke-static {v5, v6}, Ljava/util/Arrays;->equals([B[B)Z
move-result v5
if-eqz v5, :next_anchor
new-array v0, v1, [Ljava/security/cert/X509Certificate;
const/4 v2, 0
invoke-static {p1, v2, v0, v2, v1}, Ljava/lang/System;->arraycopy(Ljava/lang/Object;ILjava/lang/Object;II)V
return-object v0
:next_anchor
add-int/lit8 v3, v3, 1
goto :anchor
:next_peer
add-int/lit8 v1, v1, 1
goto :peer
:unchanged
return-object p1')
	for name in ['checkClientTrusted', 'checkServerTrusted'] {
		body += signature_method('public ${name}([Ljava/security/cert/X509Certificate;Ljava/lang/String;)V', '
invoke-direct {p0, p1}, ${manager}->chain([Ljava/security/cert/X509Certificate;)[Ljava/security/cert/X509Certificate;
move-result-object v1
iget-object v0, p0, ${manager}->delegate:${wolf}
invoke-virtual {v0, v1, p2}, ${wolf}->${name}([Ljava/security/cert/X509Certificate;Ljava/lang/String;)V
return-void')
	}
	body += signature_method('public checkServerTrusted([Ljava/security/cert/X509Certificate;Ljava/lang/String;Ljava/lang/String;)Ljava/util/List;', '
invoke-direct {p0, p1}, ${manager}->chain([Ljava/security/cert/X509Certificate;)[Ljava/security/cert/X509Certificate;
move-result-object v1
iget-object v0, p0, ${manager}->delegate:${wolf}
invoke-virtual {v0, v1, p2, p3}, ${wolf}->checkServerTrusted([Ljava/security/cert/X509Certificate;Ljava/lang/String;Ljava/lang/String;)Ljava/util/List;
move-result-object v0
return-object v0')
	os.write_file(smali + '/android/atl/VinixTrustManager.smali', body)!
	return services
}
