// SPDX-License-Identifier: GPL-2.0-or-later
package android.view;

import android.content.Context;
import android.graphics.Rect;
import android.util.AttributeSet;
import java.io.StringReader;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import org.xmlpull.v1.XmlPullParser;
import org.xmlpull.v1.XmlPullParserFactory;
import sun.misc.Unsafe;

/** Test actual framework inflation/focus dispatch without creating GTK widgets. */
public final class AndroidLayoutFocusProbe {
    private static final Unsafe ALLOCATOR;
    private static final ArrayList<String> EVENTS = new ArrayList<>();
    private static final LinkedHashMap<String, FocusGroup> VIEWS = new LinkedHashMap<>();

    static {
        try {
            Field field = Unsafe.class.getDeclaredField("theUnsafe");
            field.setAccessible(true);
            ALLOCATOR = (Unsafe) field.get(null);
        } catch (ReflectiveOperationException error) {
            throw new ExceptionInInitializerError(error);
        }
    }

    // Constructor-free test views avoid GTK initialization. Only attachment and
    // successful focus acquisition are observed doubles; the production
    // LayoutInflater, restoreDefaultFocus and hidden-view gate run unchanged.
    private static final class FocusGroup extends ViewGroup {
        String name;
        int requests;
        int childCountAtRequest;
        boolean finishes;
        boolean hidden;
        boolean result;
        LayoutParams parameters;

        private FocusGroup(Context context) { super(context); }

        @Override public String getIdName() { return name; }
        @Override public LayoutParams generateLayoutParams(AttributeSet attrs) {
            return new LayoutParams(1, 1);
        }
        @Override protected LayoutParams generateDefaultLayoutParams() {
            return new LayoutParams(1, 1);
        }
        @Override public void setLayoutParams(LayoutParams value) { parameters = value; }
        @Override public LayoutParams getLayoutParams() { return parameters; }
        @Override public void addView(View child, LayoutParams value) {
            child.parent = this;
            children.add(child);
            EVENTS.add("attach:" + ((FocusGroup) child).name + ":" + name);
        }
        @Override public boolean requestFocus(int direction, Rect previous) {
            require(direction == FOCUS_DOWN, "default focus direction");
            require(!finishes, "focus restored before onFinishInflate");
            for (View child : children) require(child.getParent() == this, "child attached before focus");
            requests++;
            childCountAtRequest = children.size();
            EVENTS.add("focus:" + name);
            result = hidden ? super.requestFocus(direction, previous) : true;
            return result;
        }
        @Override protected void onFinishInflate() {
            finishes = true;
            EVENTS.add("finish:" + name);
        }
        @Override protected void finalize() {} // No native object was allocated.
    }

    private static void field(View view, String name, Object value) throws Exception {
        Field field = View.class.getDeclaredField(name);
        field.setAccessible(true);
        field.set(view, value);
    }

    private static FocusGroup view(String name) throws Exception {
        FocusGroup view = (FocusGroup) ALLOCATOR.allocateInstance(FocusGroup.class);
        view.name = name;
        view.children = new ArrayList<>();
        view.hidden = name.equals("hidden");
        field(view, "atl_enabled", true);
        field(view, "atl_focusable", true);
        field(view, "visibility", view.hidden ? View.GONE : View.VISIBLE);
        VIEWS.put(name, view);
        return view;
    }

    private static FocusGroup inflate(String xml, FocusGroup root) throws Exception {
        XmlPullParser parser = XmlPullParserFactory.newInstance().newPullParser();
        parser.setInput(new StringReader(xml));
        LayoutInflater inflater = new LayoutInflater(null);
        inflater.setFactory2((parent, name, context, attrs) -> {
            require(!name.equals("ignored"), "marker subtree never creates views");
            try { return view(name); }
            catch (Exception error) { throw new RuntimeException(error); }
        });
        return (FocusGroup) inflater.inflate(parser, root, root != null);
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message + ": " + EVENTS);
    }

    private static void reset() { EVENTS.clear(); VIEWS.clear(); }

    public static void main(String[] args) throws Exception {
        for (String xml : Arrays.asList(
                "<group><requestFocus/><child/></group>",
                "<group><child/><requestFocus/></group>",
                "<group><requestFocus><ignored><ignored/></ignored></requestFocus><child/><requestFocus/></group>")) {
            reset();
            FocusGroup root = inflate(xml, null);
            require(root.requests == 1 && root.childCountAtRequest == 1, "one deferred request after all children");
            require(EVENTS.indexOf("attach:child:group") < EVENTS.indexOf("focus:group"), "tag order preserves attachment");
            require(EVENTS.indexOf("focus:group") < EVENTS.indexOf("finish:group"), "finish ordering");
        }
        reset();
        FocusGroup plain = inflate("<plain><child/></plain>", null);
        require(plain.requests == 0, "no tag means no focus request");
        reset();
        FocusGroup nested = inflate("<outer><inner><requestFocus/><child/></inner><sibling/></outer>", null);
        require(nested.requests == 0 && VIEWS.get("inner").requests == 1, "focus belongs to containing parent");
        require(EVENTS.indexOf("focus:inner") < EVENTS.indexOf("attach:inner:outer"), "subtree completes before outer attachment");
        reset();
        FocusGroup hidden = inflate("<hidden><requestFocus/></hidden>", null);
        require(hidden.requests == 1 && !hidden.result, "real hidden View gate rejects focus without JNI");
        reset();
        FocusGroup merged = view("merged");
        require(inflate("<merge><requestFocus/><child/></merge>", merged) == merged, "merge returns its root");
        require(merged.requests == 1 && merged.childCountAtRequest == 1 && !merged.finishes,
                "merge restores focus without onFinishInflate");
        System.out.println("ANDROID-LAYOUT-FOCUS-PASS order=verified subtree=consumed hidden=rejected merge=verified");
    }
}
