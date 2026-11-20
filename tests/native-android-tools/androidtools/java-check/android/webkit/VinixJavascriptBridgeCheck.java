// SPDX-License-Identifier: GPL-2.0-or-later
package android.webkit;

import java.util.LinkedHashMap;

/** Host check for VinixJavascriptBridge; not part of the framework. */
public final class VinixJavascriptBridgeCheck {
    public static final class Sample {
        public String seen = "";

        @JavascriptInterface
        public String echo(String text) {
            return text;
        }

        @JavascriptInterface
        public int add(int a, long b) {
            return (int) (a + b);
        }

        @JavascriptInterface
        public double half(double value) {
            return value / 2;
        }

        @JavascriptInterface
        public boolean not(boolean value) {
            return !value;
        }

        @JavascriptInterface
        public void store(String a, boolean b, String c) {
            seen = a + "," + b + "," + c;
        }

        @JavascriptInterface
        public String nothing() {
            return null;
        }

        @JavascriptInterface
        public String fail() {
            throw new IllegalStateException("boom");
        }

        public String hidden() {
            return "hidden";
        }
    }

    private static void expect(String actual, String expected) {
        if (!actual.equals(expected)) {
            throw new AssertionError("expected <" + expected + "> got <" + actual + ">");
        }
    }

    public static void main(String[] args) {
        Sample sample = new Sample();
        LinkedHashMap<String, Object> interfaces = new LinkedHashMap<String, Object>();
        interfaces.put("mm", sample);
        interfaces.put("bad-name", sample);
        interfaces.put("empty", new Object());
        expect(VinixJavascriptBridge.spec(interfaces), "mm add echo fail half not nothing store");
        String astral = "hé😀";
        expect(VinixJavascriptBridge.call(sample, "echo", VinixJavascriptBridge.encode('s', astral)),
                "=" + VinixJavascriptBridge.encode('s', astral));
        expect(VinixJavascriptBridge.call(sample, "add", "2:n23:n40"), "=3:n42");
        expect(VinixJavascriptBridge.call(sample, "half", "2:n5"), "=4:n2.5");
        expect(VinixJavascriptBridge.call(sample, "not", "2:b0"), "=2:b1");
        expect(VinixJavascriptBridge.call(sample, "store", "2:sx2:b11:z"), "=1:u");
        expect(sample.seen, "x,true,null");
        expect(VinixJavascriptBridge.call(sample, "nothing", ""), "=1:z");
        expect(VinixJavascriptBridge.call(sample, "fail", ""), "!java.lang.IllegalStateException: boom");
        expect(VinixJavascriptBridge.call(sample, "hidden", ""), "!Method not found");
        expect(VinixJavascriptBridge.call(sample, "echo", ""), "!Method not found");
        expect(VinixJavascriptBridge.call(sample, "echo", "9:sx").substring(0, 1), "!");
        System.out.println("VINIX-JAVASCRIPT-BRIDGE-JAVA-PASS");
    }
}
