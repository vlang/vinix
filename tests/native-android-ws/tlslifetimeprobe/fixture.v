// SPDX-License-Identifier: GPL-2.0-or-later
module tlslifetimeprobe

import os

pub fn install(root string) ! {
	cert := os.getenv('VINIX_TLS_TEST_CERT')
	if cert == '' { return error('TLS lifetime fixture requires VINIX_TLS_TEST_CERT') }
	data := os.read_bytes(cert)!
	if data.len == 0 || data.len > 65536 { return error('bounded fixture CA required') }
	os.mkdir_all(root + '/assets')!
	os.write_file_array(root + '/assets/tls-lifetime-ca.pem', data)!
	os.write_file(root + '/smali/TlsLifetimeProbe.smali', r'.class public Lorg/vinix/bootstrap/TlsLifetimeProbe;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field socket:Ljavax/net/ssl/SSLSocket;
.field write:Z
.field volatile finished:Z
.field volatile failure:Ljava/lang/Throwable;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public run()V
.locals 4
:start
iget-object v0, p0, Lorg/vinix/bootstrap/TlsLifetimeProbe;->socket:Ljavax/net/ssl/SSLSocket;
iget-boolean v1, p0, Lorg/vinix/bootstrap/TlsLifetimeProbe;->write:Z
if-nez v1, :write
invoke-virtual {v0}, Ljavax/net/ssl/SSLSocket;->getInputStream()Ljava/io/InputStream;
move-result-object v0
invoke-virtual {v0}, Ljava/io/InputStream;->read()I
goto :unexpected
:write
invoke-virtual {v0}, Ljavax/net/ssl/SSLSocket;->getOutputStream()Ljava/io/OutputStream;
move-result-object v0
const/high16 v1, 0x10000
new-array v1, v1, [B
:loop
invoke-virtual {v0, v1}, Ljava/io/OutputStream;->write([B)V
goto :loop
:unexpected
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "silent peer unexpectedly returned read data"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
iput-object v0, p0, Lorg/vinix/bootstrap/TlsLifetimeProbe;->failure:Ljava/lang/Throwable;
:end
goto :done
.catch Ljava/io/IOException; {:start .. :end} :io
.catchall {:start .. :end} :failed
:io
move-exception v0
goto :done
:failed
move-exception v0
iput-object v0, p0, Lorg/vinix/bootstrap/TlsLifetimeProbe;->failure:Ljava/lang/Throwable;
:done
const/4 v0, 1
iput-boolean v0, p0, Lorg/vinix/bootstrap/TlsLifetimeProbe;->finished:Z
return-void
.end method
.method public static field(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
.locals 2
invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v0
invoke-virtual {v0, p1}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->setAccessible(Z)V
invoke-virtual {v0, p0}, Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
return-object v0
.end method
.method public static check(Landroid/content/Context;)V
.locals 12
invoke-virtual {p0}, Landroid/content/Context;->getAssets()Landroid/content/res/AssetManager;
move-result-object v0
const-string v1, "tls-lifetime-ca.pem"
invoke-virtual {v0, v1}, Landroid/content/res/AssetManager;->open(Ljava/lang/String;)Ljava/io/InputStream;
move-result-object v0
const-string v1, "X.509"
invoke-static {v1}, Ljava/security/cert/CertificateFactory;->getInstance(Ljava/lang/String;)Ljava/security/cert/CertificateFactory;
move-result-object v1
invoke-virtual {v1, v0}, Ljava/security/cert/CertificateFactory;->generateCertificate(Ljava/io/InputStream;)Ljava/security/cert/Certificate;
move-result-object v1
invoke-virtual {v0}, Ljava/io/InputStream;->close()V
const-string v0, "JKS"
invoke-static {v0}, Ljava/security/KeyStore;->getInstance(Ljava/lang/String;)Ljava/security/KeyStore;
move-result-object v0
const/4 v2, 0
invoke-virtual {v0, v2, v2}, Ljava/security/KeyStore;->load(Ljava/io/InputStream;[C)V
const-string v2, "fixture-only"
invoke-virtual {v0, v2, v1}, Ljava/security/KeyStore;->setCertificateEntry(Ljava/lang/String;Ljava/security/cert/Certificate;)V
const-string v1, "PKIX"
const-string v2, "wolfJSSE"
invoke-static {v1, v2}, Ljavax/net/ssl/TrustManagerFactory;->getInstance(Ljava/lang/String;Ljava/lang/String;)Ljavax/net/ssl/TrustManagerFactory;
move-result-object v1
invoke-virtual {v1, v0}, Ljavax/net/ssl/TrustManagerFactory;->init(Ljava/security/KeyStore;)V
invoke-virtual {v1}, Ljavax/net/ssl/TrustManagerFactory;->getTrustManagers()[Ljavax/net/ssl/TrustManager;
move-result-object v1
const-string v0, "TLS"
invoke-static {v0, v2}, Ljavax/net/ssl/SSLContext;->getInstance(Ljava/lang/String;Ljava/lang/String;)Ljavax/net/ssl/SSLContext;
move-result-object v0
const/4 v2, 0
invoke-virtual {v0, v2, v1, v2}, Ljavax/net/ssl/SSLContext;->init([Ljavax/net/ssl/KeyManager;[Ljavax/net/ssl/TrustManager;Ljava/security/SecureRandom;)V
invoke-virtual {v0}, Ljavax/net/ssl/SSLContext;->getSocketFactory()Ljavax/net/ssl/SSLSocketFactory;
move-result-object v10
const/4 v11, 0
:case
new-instance v0, Ljava/net/Socket;
const-string v1, "10.0.2.2"
const/16 v2, 28444
invoke-direct {v0, v1, v2}, Ljava/net/Socket;-><init>(Ljava/lang/String;I)V
move-object v8, v0
const/4 v3, 1
const/4 v4, 2
if-ne v11, v4, :owned
const/4 v3, 0
:owned
move-object v0, v10
move-object v4, v8
# createSocket(socket,host,port,autoClose)
invoke-virtual {v0, v4, v1, v2, v3}, Ljavax/net/ssl/SSLSocketFactory;->createSocket(Ljava/net/Socket;Ljava/lang/String;IZ)Ljava/net/Socket;
move-result-object v9
check-cast v9, Ljavax/net/ssl/SSLSocket;
const/16 v0, 2500
invoke-virtual {v9, v0}, Ljavax/net/ssl/SSLSocket;->setSoTimeout(I)V
invoke-virtual {v9}, Ljavax/net/ssl/SSLSocket;->startHandshake()V
invoke-virtual {v9}, Ljavax/net/ssl/SSLSocket;->getInputStream()Ljava/io/InputStream;
move-result-object v0
invoke-virtual {v0}, Ljava/io/InputStream;->read()I
move-result v0
const/16 v1, 82
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v0, 2
if-eq v11, v0, :borrowed
const/4 v0, 3
if-eq v11, v0, :idle
new-instance v7, Lorg/vinix/bootstrap/TlsLifetimeProbe;
invoke-direct {v7}, Lorg/vinix/bootstrap/TlsLifetimeProbe;-><init>()V
iput-object v9, v7, Lorg/vinix/bootstrap/TlsLifetimeProbe;->socket:Ljavax/net/ssl/SSLSocket;
iput-boolean v11, v7, Lorg/vinix/bootstrap/TlsLifetimeProbe;->write:Z
new-instance v6, Ljava/lang/Thread;
invoke-direct {v6, v7}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v6}, Ljava/lang/Thread;->start()V
const/16 v5, 200
:wait
const-string v1, "vinixIoCount"
invoke-static {v9, v1}, Lorg/vinix/bootstrap/TlsLifetimeProbe;->field(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/Integer;
invoke-virtual {v0}, Ljava/lang/Integer;->intValue()I
move-result v0
if-gtz v0, :close
const-wide/16 v0, 5
invoke-static {v0, v1}, Ljava/lang/Thread;->sleep(J)V
add-int/lit8 v5, v5, -1
if-gtz v5, :wait
goto :bad
:close
invoke-static {}, Ljava/lang/System;->nanoTime()J
move-result-wide v2
invoke-virtual {v9}, Ljavax/net/ssl/SSLSocket;->close()V
invoke-static {}, Ljava/lang/System;->nanoTime()J
move-result-wide v0
sub-long/2addr v0, v2
const-wide v2, 2000000000L
cmp-long v0, v0, v2
if-gez v0, :bad
const-wide/16 v0, 3000
invoke-virtual {v6, v0, v1}, Ljava/lang/Thread;->join(J)V
invoke-virtual {v6}, Ljava/lang/Thread;->isAlive()Z
move-result v0
if-nez v0, :bad
iget-object v0, v7, Lorg/vinix/bootstrap/TlsLifetimeProbe;->failure:Ljava/lang/Throwable;
if-nez v0, :failed
iget-boolean v0, v7, Lorg/vinix/bootstrap/TlsLifetimeProbe;->finished:Z
if-eqz v0, :bad
:released
const-string v1, "ssl"
invoke-static {v9, v1}, Lorg/vinix/bootstrap/TlsLifetimeProbe;->field(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
if-nez v0, :bad
invoke-virtual {v8}, Ljava/net/Socket;->isClosed()Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v9}, Ljavax/net/ssl/SSLSocket;->close()V
add-int/lit8 v11, v11, 1
const/4 v0, 4
if-lt v11, v0, :case
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "TLS-LIFETIME-PASS concurrent-read concurrent-write bounded-close native-release borrowed-transport idle-close"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:idle
invoke-virtual {v9}, Ljavax/net/ssl/SSLSocket;->close()V
goto :released
:borrowed
const-string v1, "ssl"
invoke-static {v9, v1}, Lorg/vinix/bootstrap/TlsLifetimeProbe;->field(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v7
move-object v4, v9
check-cast v4, Lcom/wolfssl/provider/jsse/WolfSSLSocket;
invoke-virtual {v4}, Lcom/wolfssl/provider/jsse/WolfSSLSocket;->vinixEnterIo()V
invoke-virtual {v9}, Ljavax/net/ssl/SSLSocket;->close()V
const-string v1, "ssl"
invoke-static {v9, v1}, Lorg/vinix/bootstrap/TlsLifetimeProbe;->field(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
if-ne v0, v7, :bad
const-string v1, "active"
invoke-static {v7, v1}, Lorg/vinix/bootstrap/TlsLifetimeProbe;->field(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/Boolean;
invoke-virtual {v0}, Ljava/lang/Boolean;->booleanValue()Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v8}, Ljava/net/Socket;->isClosed()Z
move-result v0
if-nez v0, :bad
invoke-virtual {v9}, Ljavax/net/ssl/SSLSocket;->isClosed()Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v4}, Lcom/wolfssl/provider/jsse/WolfSSLSocket;->vinixExitIo()V
const-string v1, "active"
invoke-static {v7, v1}, Lorg/vinix/bootstrap/TlsLifetimeProbe;->field(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/Boolean;
invoke-virtual {v0}, Ljava/lang/Boolean;->booleanValue()Z
move-result v0
if-nez v0, :bad
invoke-virtual {v8}, Ljava/net/Socket;->isClosed()Z
move-result v0
if-nez v0, :bad
invoke-virtual {v8}, Ljava/net/Socket;->close()V
goto :released
:failed
throw v0
:bad
invoke-virtual {v9}, Ljavax/net/ssl/SSLSocket;->close()V
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "TLS lifetime regression"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
')!
}
