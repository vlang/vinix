// SPDX-License-Identifier: GPL-2.0-or-later
// Build after bootstrap-fixture.v; run as org.vinix.bootstrap in the native WS
// suite with startup_seconds >= 100. Internet and DHCP are required. The probe
// uses the default trust manager and hostname verifier without overrides.
import os

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn main() {
	if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
	out := os.abs_path(os.args[1])
	fixture := os.abs_path(os.args[2])
	tools := os.abs_path(os.args[3])
	os.mkdir_all(out + '/smali/org/vinix/bootstrap')!
	source := '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
		'.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void\n.end method\n' +
		'.method public onCreate(Landroid/os/Bundle;)V\n.locals 6\n' + '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
const-wide/32 v0, 30000
invoke-static {v0, v1}, Ljava/lang/Thread;->sleep(J)V
const-string v0, "1.1.1.1"
invoke-static {v0}, Lorg/vinix/bootstrap/Main;->probe(Ljava/lang/String;)V
const-string v0, "mobilemaps-pa-gz.googleapis.com"
invoke-static {v0}, Lorg/vinix/bootstrap/Main;->probe(Ljava/lang/String;)V
:tls
new-instance v0, Ljava/net/URL;
const-string v1, "https://mobilemaps-pa-gz.googleapis.com/"
invoke-direct {v0, v1}, Ljava/net/URL;-><init>(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/net/URL;->openConnection()Ljava/net/URLConnection;
move-result-object v0
const/16 v1, 5000
invoke-virtual {v0, v1}, Ljava/net/URLConnection;->setConnectTimeout(I)V
invoke-virtual {v0, v1}, Ljava/net/URLConnection;->setReadTimeout(I)V
check-cast v0, Ljava/net/HttpURLConnection;
invoke-virtual {v0}, Ljava/net/HttpURLConnection;->getResponseCode()I
move-result v1
invoke-virtual {v0}, Ljava/net/HttpURLConnection;->disconnect()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v2, "JAVA-HTTPS-RESPONSE"
invoke-virtual {v0, v2}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(I)V
const-string v0, "https://self-signed.badssl.com/"
invoke-static {v0}, Lorg/vinix/bootstrap/Main;->reject(Ljava/lang/String;)V
const-string v0, "https://wrong.host.badssl.com/"
invoke-static {v0}, Lorg/vinix/bootstrap/Main;->reject(Ljava/lang/String;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "HTTPS-FIXTURE-PASS trusted-google self-signed-rejected wrong-host-rejected"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
:tlsend
goto :ui
:tlsbad
move-exception v0
invoke-virtual {v0}, Ljava/lang/Throwable;->printStackTrace()V
throw v0
:ui
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "HTTPS certificate checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
.catch Ljava/lang/Exception; {:tls .. :tlsend} :tlsbad
.end method
.method public static probe(Ljava/lang/String;)V
.locals 6
sget-object v5, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v0, "JAVA-TCP-PROBE"
invoke-virtual {v5, v0}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v5, p0}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
:try
invoke-static {p0}, Ljava/net/InetAddress;->getAllByName(Ljava/lang/String;)[Ljava/net/InetAddress;
move-result-object v0
invoke-static {v0}, Ljava/util/Arrays;->toString([Ljava/lang/Object;)Ljava/lang/String;
move-result-object v0
invoke-virtual {v5, v0}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Ljava/net/Socket;
invoke-direct {v0}, Ljava/net/Socket;-><init>()V
new-instance v1, Ljava/net/InetSocketAddress;
const/16 v2, 443
invoke-direct {v1, p0, v2}, Ljava/net/InetSocketAddress;-><init>(Ljava/lang/String;I)V
const/16 v2, 3000
invoke-virtual {v0, v1, v2}, Ljava/net/Socket;->connect(Ljava/net/SocketAddress;I)V
invoke-virtual {v0}, Ljava/net/Socket;->close()V
const-string v0, "JAVA-TCP-CONNECTED"
invoke-virtual {v5, v0}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
:end
return-void
:bad
move-exception v0
invoke-virtual {v0}, Ljava/lang/Throwable;->printStackTrace()V
return-void
.catch Ljava/lang/Exception; {:try .. :end} :bad
.end method
.method public static reject(Ljava/lang/String;)V
.locals 4
:try
new-instance v0, Ljava/net/URL;
invoke-direct {v0, p0}, Ljava/net/URL;-><init>(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/net/URL;->openConnection()Ljava/net/URLConnection;
move-result-object v0
const/16 v1, 8000
invoke-virtual {v0, v1}, Ljava/net/URLConnection;->setConnectTimeout(I)V
invoke-virtual {v0, v1}, Ljava/net/URLConnection;->setReadTimeout(I)V
check-cast v0, Ljava/net/HttpURLConnection;
invoke-virtual {v0}, Ljava/net/HttpURLConnection;->getResponseCode()I
:end
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "HTTPS accepted invalid certificate"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:rejected
move-exception v0
sget-object v1, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v2, "JAVA-HTTPS-REJECTED"
invoke-virtual {v1, v2}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v1, p0}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/Throwable;->printStackTrace()V
return-void
.catch Ljavax/net/ssl/SSLHandshakeException; {:try .. :end} :rejected
.catch Ljavax/net/ssl/SSLPeerUnverifiedException; {:try .. :end} :rejected
.end method
'
	os.write_file(out + '/smali/org/vinix/bootstrap/Main.smali', source)!
	// Keep the fixture Application and providers which its manifest names.
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', out + '/smali/org/vinix/bootstrap/' + name + '.smali')!
	}
	java := os.args[4]
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o',
		out + '/classes.dex'])
	os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	checked([java, '-jar', os.abs_path(os.args[5]), 'sign', '--ks', fixture + '/fixture.p12',
		'--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android',
		'--out', out + '/probe.apk', out + '/unsigned.apk'])
	println('HTTPS-FIXTURE-APK ' + out + '/probe.apk')
}
