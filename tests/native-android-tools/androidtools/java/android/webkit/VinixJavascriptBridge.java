// SPDX-License-Identifier: GPL-2.0-or-later
package android.webkit;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Map;
import java.util.TreeSet;

/**
 * Java side of the WebView JavaScript bridge (build-support/android/browseripc/
 * jsbridge.v). Values are tagged text: a UTF-16 length, ':', a tag (s string,
 * n number, b boolean, z null, u undefined) and its text, so no JSON parser is
 * needed. Like Android, only public methods annotated @JavascriptInterface are
 * exposed, chosen by name and argument count.
 */
final class VinixJavascriptBridge {
    private static final int MAX_INTERFACES = 16;
    private static final int MAX_METHODS = 256;

    private VinixJavascriptBridge() {
    }

    static boolean identifier(String name) {
        if (name == null || name.isEmpty() || name.length() > 128) {
            return false;
        }
        for (int i = 0; i < name.length(); i++) {
            char c = name.charAt(i);
            boolean letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '$';
            if (!letter && (i == 0 || c < '0' || c > '9')) {
                return false;
            }
        }
        return true;
    }

    private static boolean exposed(Method method) {
        return Modifier.isPublic(method.getModifiers()) && !Modifier.isStatic(method.getModifiers())
                && method.isAnnotationPresent(JavascriptInterface.class);
    }

    /** One line per interface: its name and its exposed method names. */
    static String spec(Map<String, Object> interfaces) {
        StringBuilder out = new StringBuilder();
        int count = 0;
        for (Map.Entry<String, Object> entry : interfaces.entrySet()) {
            if (count == MAX_INTERFACES || !identifier(entry.getKey()) || entry.getValue() == null) {
                continue;
            }
            TreeSet<String> names = new TreeSet<String>();
            for (Method method : entry.getValue().getClass().getMethods()) {
                if (exposed(method) && identifier(method.getName()) && names.size() < MAX_METHODS) {
                    names.add(method.getName());
                }
            }
            if (names.isEmpty()) {
                continue;
            }
            if (out.length() != 0) {
                out.append('\n');
            }
            out.append(entry.getKey());
            for (String name : names) {
                out.append(' ').append(name);
            }
            count++;
        }
        return out.toString();
    }

    static ArrayList<String> decode(String list) {
        ArrayList<String> values = new ArrayList<String>();
        int position = 0;
        while (position < list.length()) {
            int colon = list.indexOf(':', position);
            if (colon <= position) {
                throw new IllegalArgumentException("invalid Java bridge arguments");
            }
            int length = Integer.parseInt(list.substring(position, colon));
            int end = colon + 1 + length;
            if (length < 1 || end > list.length()) {
                throw new IllegalArgumentException("invalid Java bridge arguments");
            }
            values.add(list.substring(colon + 1, end));
            position = end;
        }
        return values;
    }

    static String encode(char tag, String text) {
        return (1 + text.length()) + ":" + tag + text;
    }

    private static double number(String value) {
        if (value.charAt(0) != 'n') {
            return 0;
        }
        try {
            return Double.parseDouble(value.substring(1));
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    // Android's conversions for the parameter types bridge methods use.
    static Object convert(String value, Class<?> type) {
        char tag = value.charAt(0);
        String text = value.substring(1);
        if (type == String.class) {
            if (tag == 's' || tag == 'n') {
                return text;
            }
            return tag == 'b' ? (text.equals("1") ? "true" : "false") : null;
        }
        if (type == boolean.class || type == Boolean.class) {
            return tag == 'b' ? Boolean.valueOf(text.equals("1")) : (type == boolean.class ? Boolean.FALSE : null);
        }
        double n = number(value);
        if (type == int.class || type == Integer.class) {
            return Integer.valueOf((int) n);
        }
        if (type == long.class || type == Long.class) {
            return Long.valueOf((long) n);
        }
        if (type == double.class || type == Double.class) {
            return Double.valueOf(n);
        }
        if (type == float.class || type == Float.class) {
            return Float.valueOf((float) n);
        }
        if (type == short.class || type == Short.class) {
            return Short.valueOf((short) n);
        }
        if (type == byte.class || type == Byte.class) {
            return Byte.valueOf((byte) n);
        }
        if (type == char.class || type == Character.class) {
            return Character.valueOf((char) n);
        }
        return null;
    }

    static String result(Object value, Class<?> type) {
        if (type == void.class) {
            return encode('u', "");
        }
        if (value == null) {
            return encode('z', "");
        }
        if (value instanceof Boolean) {
            return encode('b', ((Boolean) value).booleanValue() ? "1" : "0");
        }
        if (value instanceof Double || value instanceof Float) {
            return encode('n', String.valueOf(((Number) value).doubleValue()));
        }
        if (value instanceof Number) {
            return encode('n', String.valueOf(((Number) value).longValue()));
        }
        return encode('s', value.toString());
    }

    /** Returns "=" and one tagged value, or "!" and an exception message. */
    static String call(Object target, String name, String arguments) {
        try {
            ArrayList<String> values = decode(arguments);
            for (Method method : target.getClass().getMethods()) {
                Class<?>[] types = method.getParameterTypes();
                if (!exposed(method) || !method.getName().equals(name) || types.length != values.size()) {
                    continue;
                }
                Object[] args = new Object[types.length];
                for (int i = 0; i < types.length; i++) {
                    args[i] = convert(values.get(i), types[i]);
                }
                method.setAccessible(true);
                return "=" + result(method.invoke(target, args), method.getReturnType());
            }
            return "!Method not found";
        } catch (InvocationTargetException e) {
            Throwable cause = e.getCause() != null ? e.getCause() : e;
            return "!" + cause;
        } catch (RuntimeException e) {
            return "!" + e;
        } catch (Exception e) {
            return "!" + e;
        }
    }
}
