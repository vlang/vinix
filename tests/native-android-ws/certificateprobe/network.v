// SPDX-License-Identifier: GPL-2.0-or-later
module certificateprobe

import os

pub fn install_network(root string) ! {
	os.write_file(root + '/smali/CertificateNetwork.smali', r'.class public Lorg/vinix/bootstrap/CertificateNetwork;
.super Ljava/lang/Object;
.method public static tcp(Ljava/lang/String;I)Ljava/net/Socket;
.locals 5
invoke-static {p0}, Ljava/net/InetAddress;->getAllByName(Ljava/lang/String;)[Ljava/net/InetAddress;
move-result-object v0
const/4 v1, 0
:next
array-length v2, v0
if-ge v1, v2, :bad
aget-object v2, v0, v1
add-int/lit8 v1, v1, 1
instance-of v3, v2, Ljava/net/Inet4Address;
if-eqz v3, :next
new-instance v0, Ljava/net/Socket;
invoke-direct {v0}, Ljava/net/Socket;-><init>()V
:connect
new-instance v1, Ljava/net/InetSocketAddress;
invoke-direct {v1, v2, p1}, Ljava/net/InetSocketAddress;-><init>(Ljava/net/InetAddress;I)V
const/16 v2, 5000
invoke-virtual {v0, v1, v2}, Ljava/net/Socket;->connect(Ljava/net/SocketAddress;I)V
:connect_end
return-object v0
:failed
move-exception v1
invoke-virtual {v0}, Ljava/net/Socket;->close()V
throw v1
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "No IPv4 address for certificate test"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.catchall {:connect .. :connect_end} :failed
.end method
.method public static check()V
.locals 8
invoke-static {}, Lorg/vinix/bootstrap/CertificateNetwork;->timeout()V
const-string v2, "mobilemaps.googleapis.com"
const/16 v3, 443
invoke-static {v2, v3}, Lorg/vinix/bootstrap/CertificateNetwork;->tcp(Ljava/lang/String;I)Ljava/net/Socket;
move-result-object v1
const/16 v4, 1234
invoke-virtual {v1, v4}, Ljava/net/Socket;->setSoTimeout(I)V
const/16 v0, 10000
const/4 v5, 0
invoke-static {v0, v5}, Landroid/net/SSLCertificateSocketFactory;->getDefault(ILandroid/net/SSLSessionCache;)Ljavax/net/ssl/SSLSocketFactory;
move-result-object v0
const/4 v4, 1
invoke-virtual {v0, v1, v2, v3, v4}, Ljavax/net/ssl/SSLSocketFactory;->createSocket(Ljava/net/Socket;Ljava/lang/String;IZ)Ljava/net/Socket;
move-result-object v1
:trusted
invoke-virtual {v1}, Ljava/net/Socket;->getSoTimeout()I
move-result v0
const/16 v2, 1234
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/16 v2, 10000
invoke-virtual {v1, v2}, Ljava/net/Socket;->setSoTimeout(I)V
invoke-virtual {v1}, Ljava/net/Socket;->getOutputStream()Ljava/io/OutputStream;
move-result-object v0
const-string v2, "HEAD / HTTP/1.1\r\nHost: mobilemaps.googleapis.com\r\nConnection: close\r\n\r\n"
const-string v3, "US-ASCII"
invoke-virtual {v2, v3}, Ljava/lang/String;->getBytes(Ljava/lang/String;)[B
move-result-object v2
invoke-virtual {v0, v2}, Ljava/io/OutputStream;->write([B)V
invoke-virtual {v1}, Ljava/net/Socket;->getInputStream()Ljava/io/InputStream;
move-result-object v0
invoke-virtual {v0}, Ljava/io/InputStream;->read()I
move-result v0
const/16 v2, 72
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
:trusted_end
invoke-virtual {v1}, Ljava/net/Socket;->close()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "CERTIFICATE-TRUSTED-PASS verified-http restored-read-timeout"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const/4 v6, 3
:repeat_rejections
const-string v0, "wrong.host.badssl.com"
const/4 v1, 1
invoke-static {v0, v1}, Lorg/vinix/bootstrap/CertificateNetwork;->reject(Ljava/lang/String;I)V
const-string v0, "self-signed.badssl.com"
const/4 v1, 2
invoke-static {v0, v1}, Lorg/vinix/bootstrap/CertificateNetwork;->reject(Ljava/lang/String;I)V
add-int/lit8 v6, v6, -1
if-gtz v6, :repeat_rejections
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "CERTIFICATE-NETWORK-PASS trusted-http wrong-host-rejected untrusted-chain-rejected"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:trusted_failed
move-exception v0
invoke-virtual {v1}, Ljava/net/Socket;->close()V
throw v0
.catchall {:trusted .. :trusted_end} :trusted_failed
.end method
.method public static reject(Ljava/lang/String;I)V
.locals 7
const/4 v6, 3
:retry
const/16 v3, 443
invoke-static {p0, v3}, Lorg/vinix/bootstrap/CertificateNetwork;->tcp(Ljava/lang/String;I)Ljava/net/Socket;
move-result-object v1
const/16 v0, 10000
const/4 v2, 0
invoke-static {v0, v2}, Landroid/net/SSLCertificateSocketFactory;->getDefault(ILandroid/net/SSLSessionCache;)Ljavax/net/ssl/SSLSocketFactory;
move-result-object v0
move-object v2, p0
const/4 v4, 1
:reject
invoke-virtual {v0, v1, v2, v3, v4}, Ljavax/net/ssl/SSLSocketFactory;->createSocket(Ljava/net/Socket;Ljava/lang/String;IZ)Ljava/net/Socket;
move-result-object v0
invoke-virtual {v0}, Ljava/net/Socket;->close()V
:reject_end
goto :bad
:hostname
move-exception v0
const/4 v2, 1
invoke-static {p1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
goto :closed
:chain
move-exception v0
const/4 v2, 2
invoke-static {p1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v3
sget-object v4, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v5, "CERTIFICATE-CHAIN-DETAIL"
invoke-virtual {v4, v5}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v4, v3}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const-string v4, "error state on socket (error code: -308)"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v4
if-nez v4, :transport_retry
const-string v4, "ASN self-signed certificate error (error code: -275)"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v4
if-nez v4, :closed
const-string v4, "ASN no signer error to confirm failure (error code: -188)"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v4
if-nez v4, :closed
const/16 v2, 8
:cause
instance-of v3, v0, Ljava/security/cert/CertificateException;
if-nez v3, :closed
invoke-virtual {v0}, Ljava/lang/Throwable;->getCause()Ljava/lang/Throwable;
move-result-object v0
if-eqz v0, :bad
add-int/lit8 v2, v2, -1
if-gtz v2, :cause
goto :bad
:transport_retry
invoke-virtual {v1}, Ljava/net/Socket;->close()V
add-int/lit8 v6, v6, -1
if-lez v6, :bad
const-wide/16 v4, 200
invoke-static {v4, v5}, Ljava/lang/Thread;->sleep(J)V
goto :retry
:closed
invoke-virtual {v1}, Ljava/net/Socket;->isClosed()Z
move-result v0
const/4 v2, 1
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
:bad
invoke-virtual {v1}, Ljava/net/Socket;->close()V
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Certificate rejection did not qualify: "
invoke-virtual {v1, p0}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.catch Ljavax/net/ssl/SSLPeerUnverifiedException; {:reject .. :reject_end} :hostname
.catch Ljavax/net/ssl/SSLHandshakeException; {:reject .. :reject_end} :chain
.end method
.method public static timeout()V
.locals 8
const-string v2, "10.0.2.2"
const/16 v3, 28443
invoke-static {v2, v3}, Lorg/vinix/bootstrap/CertificateNetwork;->tcp(Ljava/lang/String;I)Ljava/net/Socket;
move-result-object v1
const-string v2, "stall.invalid"
const/16 v0, 250
const/4 v4, 0
invoke-static {v0, v4}, Landroid/net/SSLCertificateSocketFactory;->getDefault(ILandroid/net/SSLSessionCache;)Ljavax/net/ssl/SSLSocketFactory;
move-result-object v0
const/4 v4, 1
invoke-static {}, Ljava/lang/System;->nanoTime()J
move-result-wide v5
:stall
invoke-virtual {v0, v1, v2, v3, v4}, Ljavax/net/ssl/SSLSocketFactory;->createSocket(Ljava/net/Socket;Ljava/lang/String;IZ)Ljava/net/Socket;
move-result-object v0
invoke-virtual {v0}, Ljava/net/Socket;->close()V
:stall_end
goto :bad
:timed_out
move-exception v0
invoke-static {}, Ljava/lang/System;->nanoTime()J
move-result-wide v2
sub-long/2addr v2, v5
const-wide v5, 5000000000L
cmp-long v0, v2, v5
if-gtz v0, :bad
invoke-virtual {v1}, Ljava/net/Socket;->isClosed()Z
move-result v0
const/4 v2, 1
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "CERTIFICATE-TIMEOUT-PASS stalled-handshake closed-transport"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
invoke-virtual {v1}, Ljava/net/Socket;->close()V
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Handshake timeout missing or exceeded five seconds"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.catch Ljava/net/SocketTimeoutException; {:stall .. :stall_end} :timed_out
.end method
')!
}
