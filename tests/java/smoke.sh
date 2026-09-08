#!/bin/sh
set -eu

export PATH=/usr/lib/jvm/java-25-openjdk/bin:/usr/bin:/bin:/usr/sbin:/sbin
export HOME=/root
export JAVA_HOME=/usr/lib/jvm/java-25-openjdk

work=/tmp/vinix-java-smoke
rm -rf "$work"
mkdir -p "$work/classes"

java -version
javac -version
keytool -list -keystore "$JAVA_HOME/lib/security/cacerts" \
    -storepass changeit >/dev/null
javac -d "$work/classes" /root/VinixJavaSmoke.java
java -Xms16m -Xmx128m -cp "$work/classes" VinixJavaSmoke

jar --create --file "$work/vinix-java-smoke.jar" -C "$work/classes" .
java -Xms16m -Xmx128m -cp "$work/vinix-java-smoke.jar" VinixJavaSmoke

echo "VINIX ARM64 OPENJDK JRE/JDK BOOT TEST: PASS"
