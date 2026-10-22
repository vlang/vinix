// SPDX-License-Identifier: GPL-2.0-or-later
// Signed native WS regression. Requires live, certificate-verified Internet TLS.
module main

import os
import startupfixture

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn method(signature string, body string) string {
	return '.method ${signature}\n.locals 8\n${body}\n.end method\n'
}

fn main() {
	if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
	out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	tools, java, signer := os.args[3], os.args[4], os.args[5]
	dir := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(dir)!
	startupfixture.install_connectivity_probe(dir)!
	activity := 'Lorg/vinix/bootstrap/Main;'
	probe := 'Lorg/vinix/bootstrap/TlsProbe;'
	provider := 'Lcom/android/org/conscrypt/OpenSSLProvider;'
	failure := ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "TLS provider or ALPN contract failed"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0\n'
	os.write_file(dir + '/Main.smali', '.class public ${activity}\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {}, Lorg/vinix/bootstrap/ConnectivityProbe;->check()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Checking network policy and verified TLS ALPN..."
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
new-instance v1, ${probe}
invoke-direct {v1, v0}, ${probe}-><init>(Landroid/widget/TextView;)V
new-instance v0, Ljava/lang/Thread;
invoke-direct {v0, v1}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
return-void'))!
	os.write_file(dir + '/TlsProbe.smali', '.class public ${probe}
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private view:Landroid/widget/TextView;
.field private finished:Z
' + method('public constructor <init>(Landroid/widget/TextView;)V', '
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, ${probe}->view:Landroid/widget/TextView;
return-void') + method('public run()V', '
iget-boolean v0, p0, ${probe}->finished:Z
if-eqz v0, :test
iget-object v0, p0, ${probe}->view:Landroid/widget/TextView;
const-string v1, "Verified TLS h2 and network policy checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
return-void
:test
new-instance v0, Landroid/net/ConnectivityManager;
invoke-direct {v0}, Landroid/net/ConnectivityManager;-><init>()V
const/16 v1, 150
:route
invoke-virtual {v0}, Landroid/net/ConnectivityManager;->getActiveNetwork()Landroid/net/Network;
move-result-object v2
invoke-virtual {v0, v2}, Landroid/net/ConnectivityManager;->getNetworkCapabilities(Landroid/net/Network;)Landroid/net/NetworkCapabilities;
move-result-object v2
if-eqz v2, :wait
const/16 v3, 12
invoke-virtual {v2, v3}, Landroid/net/NetworkCapabilities;->hasCapability(I)Z
move-result v2
if-nez v2, :connected
:wait
add-int/lit8 v1, v1, -1
if-eqz v1, :bad
const-wide/16 v2, 200
invoke-static {v2, v3}, Ljava/lang/Thread;->sleep(J)V
goto :route
:connected
const-string v0, "VinixTLS"
invoke-static {v0}, Ljava/security/Security;->getProvider(Ljava/lang/String;)Ljava/security/Provider;
move-result-object v6
if-eqz v6, :bad
invoke-static {}, ${provider}->install()V
invoke-static {v0}, Ljava/security/Security;->getProvider(Ljava/lang/String;)Ljava/security/Provider;
move-result-object v1
if-ne v1, v6, :bad
const-string v0, "TLS"
invoke-static {v0, v6}, Ljavax/net/ssl/SSLContext;->getInstance(Ljava/lang/String;Ljava/security/Provider;)Ljavax/net/ssl/SSLContext;
move-result-object v6
const/4 v0, 0
invoke-virtual {v6, v0, v0, v0}, Ljavax/net/ssl/SSLContext;->init([Ljavax/net/ssl/KeyManager;[Ljavax/net/ssl/TrustManager;Ljava/security/SecureRandom;)V
invoke-virtual {v6}, Ljavax/net/ssl/SSLContext;->getSocketFactory()Ljavax/net/ssl/SSLSocketFactory;
move-result-object v0
const-string v2, "mobilemaps.googleapis.com"
invoke-static {v2}, Ljava/net/InetAddress;->getAllByName(Ljava/lang/String;)[Ljava/net/InetAddress;
move-result-object v3
const/4 v4, 0
:address
array-length v5, v3
if-ge v4, v5, :bad
aget-object v5, v3, v4
instance-of v6, v5, Ljava/net/Inet4Address;
add-int/lit8 v4, v4, 1
if-eqz v6, :address
new-instance v1, Ljava/net/Socket;
invoke-direct {v1}, Ljava/net/Socket;-><init>()V
new-instance v3, Ljava/net/InetSocketAddress;
const/16 v4, 443
invoke-direct {v3, v5, v4}, Ljava/net/InetSocketAddress;-><init>(Ljava/net/InetAddress;I)V
const/16 v5, 10000
invoke-virtual {v1, v3, v5}, Ljava/net/Socket;->connect(Ljava/net/SocketAddress;I)V
const/16 v3, 443
const/4 v4, 1
invoke-virtual/range {v0 .. v4}, Ljavax/net/ssl/SSLSocketFactory;->createSocket(Ljava/net/Socket;Ljava/lang/String;IZ)Ljava/net/Socket;
move-result-object v6
check-cast v6, Lcom/wolfssl/provider/jsse/WolfSSLSocket;
const/16 v0, 15000
invoke-virtual {v6, v0}, Ljava/net/Socket;->setSoTimeout(I)V
const/4 v0, 3
new-array v0, v0, [B
const/4 v1, 0
const/4 v2, 2
aput-byte v2, v0, v1
const/4 v1, 1
const/16 v2, 104
aput-byte v2, v0, v1
const/4 v1, 2
const/16 v2, 50
aput-byte v2, v0, v1
invoke-virtual {v6, v0}, Lcom/wolfssl/provider/jsse/WolfSSLSocket;->setAlpnProtocols([B)V
invoke-virtual {v6}, Ljavax/net/ssl/SSLSocket;->startHandshake()V
invoke-virtual {v6}, Lcom/wolfssl/provider/jsse/WolfSSLSocket;->getAlpnSelectedProtocol()[B
move-result-object v0
if-eqz v0, :bad
new-instance v1, Ljava/lang/String;
const-string v2, "UTF-8"
invoke-direct {v1, v0, v2}, Ljava/lang/String;-><init>([BLjava/lang/String;)V
const-string v0, "h2"
invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v6}, Ljavax/net/ssl/SSLSocket;->getSession()Ljavax/net/ssl/SSLSession;
move-result-object v7
invoke-static {}, Ljavax/net/ssl/HttpsURLConnection;->getDefaultHostnameVerifier()Ljavax/net/ssl/HostnameVerifier;
move-result-object v0
const-string v1, "mobilemaps.googleapis.com"
invoke-interface {v0, v1, v7}, Ljavax/net/ssl/HostnameVerifier;->verify(Ljava/lang/String;Ljavax/net/ssl/SSLSession;)Z
move-result v1
if-eqz v1, :bad
const-string v1, "invalid.vinix.example"
invoke-interface {v0, v1, v7}, Ljavax/net/ssl/HostnameVerifier;->verify(Ljava/lang/String;Ljavax/net/ssl/SSLSession;)Z
move-result v1
if-nez v1, :bad
invoke-virtual {v6}, Ljava/net/Socket;->close()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "TLS-ALPN-PASS provider-idempotent default-trust hostname-rejection h2 mobilemaps.googleapis.com"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const/4 v0, 1
iput-boolean v0, p0, ${probe}->finished:Z
iget-object v0, p0, ${probe}->view:Landroid/widget/TextView;
invoke-virtual {v0, p0}, Landroid/view/View;->post(Ljava/lang/Runnable;)Z
return-void
' + failure))!
	for name in ['App', 'High', 'Low'] { os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', dir + '/' + name + '.smali')! }
	dex := out + '/classes.dex'
	if os.exists(dex) { os.rm(dex)! }
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', dex])
	assert os.is_file(dex)
	os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])
	checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	println('NETWORK-TLS-APK ' + out + '/probe.apk')
}
