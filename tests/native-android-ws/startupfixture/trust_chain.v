// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os
import encoding.base64

pub fn install_trust_chain_probe(dir string) ! {
	probe := 'Lorg/vinix/bootstrap/TrustChainProbe;'
	cert := 'Ljava/security/cert/X509Certificate;'
	array := '[${cert}'
	manager := 'Ljavax/net/ssl/X509TrustManager;'
	failure := ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "cross-signed trust chain validation"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0\n'
	mut body := '.class public final ${probe}\n.super Ljava/lang/Object;\n'
	for name in ['root', 'wrong', 'intermediate', 'leaf', 'cross', 'corrupt'] {
		encoded := base64.encode(os.read_bytes(os.dir(@FILE) + '/../trust-certificates/${name}.der')!)
		body += method('private static ${name}()${cert}', '
const-string v0, "${encoded}"
const/4 v1, 0
invoke-static {v0, v1}, Landroid/util/Base64;->decode(Ljava/lang/String;I)[B
move-result-object v0
new-instance v1, Ljava/io/ByteArrayInputStream;
invoke-direct {v1, v0}, Ljava/io/ByteArrayInputStream;-><init>([B)V
const-string v0, "X.509"
invoke-static {v0}, Ljava/security/cert/CertificateFactory;->getInstance(Ljava/lang/String;)Ljava/security/cert/CertificateFactory;
move-result-object v0
invoke-virtual {v0, v1}, Ljava/security/cert/CertificateFactory;->generateCertificate(Ljava/io/InputStream;)Ljava/security/cert/Certificate;
move-result-object v0
check-cast v0, ${cert}
return-object v0')
	}
	body += method('private static store(${cert})Ljava/security/KeyStore;', '
const-string v0, "JKS"
invoke-static {v0}, Ljava/security/KeyStore;->getInstance(Ljava/lang/String;)Ljava/security/KeyStore;
move-result-object v0
const/4 v1, 0
invoke-virtual {v0, v1, v1}, Ljava/security/KeyStore;->load(Ljava/io/InputStream;[C)V
if-eqz p0, :done
const-string v1, "root"
invoke-virtual {v0, v1, p0}, Ljava/security/KeyStore;->setCertificateEntry(Ljava/lang/String;Ljava/security/cert/Certificate;)V
:done
return-object v0')
	body += method('private static manager(${cert})${manager}', '
invoke-static {p0}, ${probe}->store(${cert})Ljava/security/KeyStore;
move-result-object v0
invoke-static {}, Ljavax/net/ssl/TrustManagerFactory;->getDefaultAlgorithm()Ljava/lang/String;
move-result-object v1
invoke-static {v1}, Ljavax/net/ssl/TrustManagerFactory;->getInstance(Ljava/lang/String;)Ljavax/net/ssl/TrustManagerFactory;
move-result-object v1
invoke-virtual {v1}, Ljavax/net/ssl/TrustManagerFactory;->getProvider()Ljava/security/Provider;
move-result-object v2
invoke-virtual {v2}, Ljava/security/Provider;->getName()Ljava/lang/String;
move-result-object v2
const-string v3, "VinixTLS"
invoke-virtual {v3, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v1, v0}, Ljavax/net/ssl/TrustManagerFactory;->init(Ljava/security/KeyStore;)V
invoke-virtual {v1}, Ljavax/net/ssl/TrustManagerFactory;->getTrustManagers()[Ljavax/net/ssl/TrustManager;
move-result-object v0
const/4 v1, 0
aget-object v0, v0, v1
check-cast v0, ${manager}
return-object v0
' + failure)
	body += method('private static reject(${manager}${array})V', '
:try
const-string v0, "RSA"
invoke-interface {p0, p1, v0}, ${manager}->checkServerTrusted(${array}Ljava/lang/String;)V
:end
goto :bad
:rejected
move-exception v0
return-void
.catch Ljava/security/cert/CertificateException; {:try .. :end} :rejected
' + failure)
	body += method('public static check()V', '
invoke-static {}, ${probe}->root()${cert}
move-result-object v0
invoke-static {v0}, ${probe}->manager(${cert})${manager}
move-result-object v0
const/4 v1, 3
new-array v1, v1, ${array}
const/4 v2, 0
invoke-static {}, ${probe}->leaf()${cert}
move-result-object v3
aput-object v3, v1, v2
const/4 v2, 1
invoke-static {}, ${probe}->intermediate()${cert}
move-result-object v3
aput-object v3, v1, v2
const/4 v2, 2
invoke-static {}, ${probe}->cross()${cert}
move-result-object v3
aput-object v3, v1, v2
# Reproduce the original provider failure, with the same root and chain.
invoke-static {}, ${probe}->root()${cert}
move-result-object v2
invoke-static {v2}, ${probe}->store(${cert})Ljava/security/KeyStore;
move-result-object v2
new-instance v3, Lcom/wolfssl/provider/jsse/WolfSSLTrustX509;
invoke-direct {v3, v2}, Lcom/wolfssl/provider/jsse/WolfSSLTrustX509;-><init>(Ljava/security/KeyStore;)V
invoke-static {v3, v1}, ${probe}->reject(${manager}${array})V
const-string v2, "RSA"
invoke-interface {v0, v1, v2}, ${manager}->checkServerTrusted(${array}Ljava/lang/String;)V
invoke-interface {v0, v1, v2}, ${manager}->checkClientTrusted(${array}Ljava/lang/String;)V
check-cast v0, Landroid/atl/VinixTrustManager;
const-string v3, "localhost"
invoke-virtual {v0, v1, v2, v3}, Landroid/atl/VinixTrustManager;->checkServerTrusted(${array}Ljava/lang/String;Ljava/lang/String;)Ljava/util/List;
move-result-object v2
invoke-interface {v2}, Ljava/util/List;->size()I
move-result v3
const/4 v4, 3
if-ne v3, v4, :bad
const/4 v3, 2
invoke-interface {v2, v3}, Ljava/util/List;->get(I)Ljava/lang/Object;
move-result-object v2
invoke-static {}, ${probe}->root()${cert}
move-result-object v3
invoke-virtual {v3, v2}, Ljava/security/cert/Certificate;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
# Normalization must not mutate the caller chain.
array-length v2, v1
if-ne v2, v4, :bad
const/4 v2, 2
aget-object v2, v1, v2
invoke-static {}, ${probe}->cross()${cert}
move-result-object v3
invoke-virtual {v3, v2}, Ljava/security/cert/Certificate;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
# The native wolfSSL callback supplies the same chain in root-first order.
const/4 v2, 3
new-array v2, v2, ${array}
const/4 v3, 0
const/4 v4, 2
aget-object v5, v1, v4
aput-object v5, v2, v3
aget-object v5, v1, v3
aput-object v5, v2, v4
const/4 v3, 1
aget-object v5, v1, v3
aput-object v5, v2, v3
const-string v3, "RSA"
invoke-interface {v0, v2, v3}, ${manager}->checkServerTrusted(${array}Ljava/lang/String;)V
invoke-interface {v0, v2, v3}, ${manager}->checkClientTrusted(${array}Ljava/lang/String;)V
const/4 v3, 0
aget-object v3, v2, v3
invoke-static {}, ${probe}->cross()${cert}
move-result-object v4
invoke-virtual {v4, v3}, Ljava/security/cert/Certificate;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
# Same subject with a different public key must not count as an anchor.
invoke-static {}, ${probe}->wrong()${cert}
move-result-object v2
invoke-static {v2}, ${probe}->manager(${cert})${manager}
move-result-object v2
invoke-static {v2, v1}, ${probe}->reject(${manager}${array})V
# An untrusted self-signed root supplied by the peer must still fail.
invoke-static {}, ${probe}->root()${cert}
move-result-object v3
const/4 v4, 2
aput-object v3, v1, v4
invoke-static {v2, v1}, ${probe}->reject(${manager}${array})V
# Empty trust stores must not trust any of the supplied certificates.
const/4 v2, 0
invoke-static {v2}, ${probe}->manager(${cert})${manager}
move-result-object v2
invoke-static {v2, v1}, ${probe}->reject(${manager}${array})V
# Anchoring a valid root must not hide a corrupt leaf signature.
const/4 v2, 0
invoke-static {}, ${probe}->corrupt()${cert}
move-result-object v3
aput-object v3, v1, v2
invoke-static {v0, v1}, ${probe}->reject(${manager}${array})V
# A missing intermediate must also fail.
const/4 v1, 1
new-array v1, v1, ${array}
invoke-static {}, ${probe}->leaf()${cert}
move-result-object v3
aput-object v3, v1, v2
invoke-static {v0, v1}, ${probe}->reject(${manager}${array})V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "TRUST-CHAIN-PASS cross-signed-root server client android-verified-chain root-first input-unchanged wrong-key untrusted-root empty-store corrupt-signature missing-intermediate"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
' + failure)
	os.write_file(dir + '/TrustChainProbe.smali', body)!
}
