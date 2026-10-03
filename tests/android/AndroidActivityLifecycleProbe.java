package android.app;

import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;
import sun.misc.Unsafe;

/** Exercises production lifecycle/transaction code without constructing a GTK window. */
public final class AndroidActivityLifecycleProbe {
    private static final List<String> events = new ArrayList<>();
    private static Unsafe unsafe;
    private static boolean controlledPassed;

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message + ": " + events);
    }

    private static void requireBefore(String first, String second, String message) {
        int firstIndex = events.indexOf(first);
        int secondIndex = events.indexOf(second);
        require(firstIndex >= 0 && secondIndex >= 0 && firstIndex < secondIndex, message);
    }

    public static final class BootstrapActivity extends Activity {
        @Override protected void onCreate(Bundle state) {
            super.onCreate(state);
            try {
                AndroidActivityLifecycleProbe.main(new String[0]);
            } catch (Throwable failure) {
                failure.printStackTrace();
                System.exit(1);
            }
        }
        @Override protected void onPostResume() {
            super.onPostResume();
            try {
                require(controlledPassed, "controlled ordering checks incomplete");
                final LiveFragment late = new LiveFragment();
                getFragmentManager().beginTransaction().add(late, "live-late").commit();
                require(getFragmentManager().findFragmentByTag("live-late") == null,
                        "production Handler commit executed synchronously");
                new Handler(Looper.getMainLooper()).post(new Runnable() {
                    @Override public void run() {
                        try {
                            require(getFragmentManager().findFragmentByTag("live-late") == late,
                                    "actual late fragment drain missing");
                            require(late.getActivity() == BootstrapActivity.this,
                                    "late fragment attached to wrong actual activity");
                            require(late.calls.equals(java.util.Arrays.asList("create", "activity-created", "start", "resume")),
                                    "actual Handler lifecycle order/count: " + late.calls);
                            System.out.println("ANDROID-ACTIVITY-LIFECYCLE-PASS create-before-start overrides=complete late=real-handler reentry=guarded exceptions=propagated");
                            System.exit(0);
                        } catch (Throwable failure) {
                            failure.printStackTrace();
                            System.exit(1);
                        }
                    }
                });
            } catch (Throwable failure) {
                failure.printStackTrace();
                System.exit(1);
            }
        }
    }

    public static final class LiveFragment extends Fragment {
        final List<String> calls = new ArrayList<>();
        @Override public void onCreate(Bundle state) { calls.add("create"); }
        @Override public void onActivityCreated(Bundle state) { calls.add("activity-created"); }
        @Override public void onStart() { calls.add("start"); }
        @Override public void onResume() { calls.add("resume"); }
    }

    static final class ProbeActivity extends Activity {
        List<Runnable> drains;
        ProbeFragment report;
        boolean inCreate, inStart, inResume;
        boolean destroyOnStart, addInPostCreate;
        int registrations, postCreates;
        @Override void postFragmentTransactionDrain(Runnable drain) { drains.add(drain); }
        @Override protected void onCreate(Bundle state) {
            events.add("activity-create-begin");
            inCreate = true;
            super.onCreate(state);
            getFragmentManager().beginTransaction().add(report, "report").commit();
            require(getFragmentManager().findFragmentByTag("report") == null, "uncommitted queue ran early");
            require(getFragmentManager().executePendingTransactions(), "committed add not executed");
            require(getFragmentManager().findFragmentByTag("report") == report, "tag lookup lost fragment");
            require(report.creates == 1, "fragment CREATED did not catch up inside activity onCreate");
            require(report.activityCreates == 0 && registrations == 0, "activityCreated ran inside activity onCreate");
            inCreate = false;
            events.add("activity-create-end");
        }
        @Override protected void onStart() {
            events.add("activity-start-begin");
            inStart = true;
            require(registrations >= 1, "ON_CREATE registration deferred until STARTED");
            require(fragmentState == 2, "start state became visible inside activity override");
            inStart = false;
            events.add("activity-start-end");
            if (destroyOnStart) performDestroy();
        }
        @Override protected void onPostCreate(Bundle state) {
            require(fragmentState == 3, "postCreate before start");
            postCreates++;
            events.add("activity-post-create");
            if (addInPostCreate) {
                getFragmentManager().beginTransaction().add(new ProbeFragment("post"), "post").commit();
            }
        }
        @Override protected void onResume() {
            events.add("activity-resume-begin");
            inResume = true;
            if (addInPostCreate) {
                ProbeFragment post = (ProbeFragment)getFragmentManager().findFragmentByTag("post");
                require(post != null && post.starts >= 1 && post.resumes == 0,
                        "postCreate transaction not caught up before onResume");
                addInPostCreate = false;
            }
            require(fragmentState == 3, "resume state became visible inside activity override");
            inResume = false;
            events.add("activity-resume-end");
        }
        @Override protected void onPause() { events.add("activity-pause"); }
        @Override protected void onStop() { events.add("activity-stop"); }
        @Override protected void onDestroy() { events.add("activity-destroy"); }
        void drain() {
            while (!drains.isEmpty()) drains.remove(0).run();
        }
    }

    static class ProbeFragment extends Fragment {
        final String label;
        int creates, activityCreates, starts, resumes, destroys;
        boolean addChild, failCreate, destroyOnPause, destroyOnCreate;
        ProbeFragment(String label) { this.label = label; }
        ProbeActivity host() { return (ProbeActivity)getActivity(); }
        void event(String phase) { events.add(label + "-" + phase); }
        @Override public void onCreate(Bundle state) { creates++; event("create"); }
        @Override public void onActivityCreated(Bundle state) {
            require(!host().inCreate, "fragment activityCreated before full override returned");
            require(host().fragmentState >= 2, "activity-created host state absent");
            require(host().fragmentState < 3 || !label.equals("report"), "initial registration at STARTED");
            activityCreates++;
            host().registrations++;
            event("activity-created");
            if (failCreate) throw new IllegalStateException("probe-create-failure");
            if (destroyOnCreate) { host().performDestroy(); return; }
            if (addChild) {
                addChild = false;
                host().getFragmentManager().beginTransaction().add(new ProbeFragment("child"), "child").commit();
                host().getFragmentManager().executePendingTransactions();
            }
        }
        @Override public void onStart() {
            require(!host().inStart && activityCreates == 1, "start before full override/create callback");
            starts++; event("start");
        }
        @Override public void onResume() {
            require(!host().inResume, "resume before full override returned");
            resumes++; event("resume");
        }
        @Override public void onPause() {
            event("pause");
            if (destroyOnPause) { destroyOnPause = false; host().performDestroy(); }
        }
        @Override public void onStop() { event("stop"); }
        @Override public void onDestroy() { destroys++; event("destroy"); }
    }

    private static ProbeActivity activity(ProbeFragment report) throws Exception {
        ProbeActivity a = (ProbeActivity)unsafe.allocateInstance(ProbeActivity.class);
        a.fragments = new ArrayList<>();
        a.pendingFragmentTransactions = new ArrayList<>();
        a.drains = new ArrayList<>();
        a.report = report;
        return a;
    }

    public static void main(String[] args) throws Exception {
        require(AndroidActivityLifecycleProbe.class.getClassLoader() == Activity.class.getClassLoader(),
                "fixture must be added to the genuine framework diagnostic classpath");
        Field field = Unsafe.class.getDeclaredField("theUnsafe");
        field.setAccessible(true);
        unsafe = (Unsafe)field.get(null);
        ProbeFragment report = new ProbeFragment("report");
        report.addChild = true;
        ProbeActivity a = activity(report);
        a.addInPostCreate = true;
        a.performCreate(null);
        require(report.creates == 1 && report.activityCreates == 1, "create callbacks repeated/missing");
        require(a.getFragmentManager().findFragmentByTag("child") != null, "reentrant child add missing");
        require(!a.getFragmentManager().executePendingTransactions(), "empty transaction drain changed state");
        a.performStart();
        a.performResume();
        requireBefore("activity-create-end", "report-activity-created", "create order");
        requireBefore("activity-start-end", "report-start", "start order");
        requireBefore("activity-resume-end", "report-resume", "resume order");
        ProbeFragment late = new ProbeFragment("late");
        a.getFragmentManager().beginTransaction().add(late, "late").commit();
        require(a.getFragmentManager().findFragmentByTag("late") == null, "late add was synchronous");
        a.drain();
        require(late.creates == 1 && late.activityCreates == 1 && late.starts == 1 && late.resumes == 1,
                "scheduled resumed-host catchup incomplete");
        a.performPause();
        requireBefore("report-pause", "activity-pause", "pause order");
        a.performStop();
        requireBefore("report-stop", "activity-stop", "stop order");
        a.performStart();
        a.performResume();
        require(report.creates == 1 && report.activityCreates == 1 && a.postCreates == 1, "restart replayed create/postCreate");
        a.performDestroy();
        a.performStart();
        a.performResume();
        require(a.fragmentState == -1 && report.destroys == 1, "destroyed host resurrected");
        boolean rejected = false;
        try { a.getFragmentManager().beginTransaction().add(new ProbeFragment("invalid"), "invalid").commit(); }
        catch (IllegalStateException expected) { rejected = true; }
        require(rejected, "commit to destroyed host accepted");

        events.clear();
        ProbeActivity finishing = activity(new ProbeFragment("report"));
        finishing.performCreate(null);
        finishing.destroyOnStart = true;
        finishing.performStart();
        require(finishing.destroyed && finishing.fragmentState == -1 && finishing.postCreates == 0,
                "reentrant destroy during start resurrected host");
        require(!events.contains("report-start") && !events.contains("report-resume"), "destroyed host advanced callbacks");

        events.clear();
        ProbeFragment pausingReport = new ProbeFragment("report");
        ProbeActivity pausing = activity(pausingReport);
        pausing.performCreate(null); pausing.performStart(); pausing.performResume();
        pausingReport.destroyOnPause = true;
        pausing.performPause();
        require(pausing.destroyed && !events.contains("activity-pause"), "pause callback ran after reentrant destroy");

        events.clear();
        ProbeActivity pendingStart = activity(new ProbeFragment("report"));
        pendingStart.performCreate(null);
        ProbeFragment destroyingStart = new ProbeFragment("pending-start");
        destroyingStart.destroyOnCreate = true;
        pendingStart.getFragmentManager().beginTransaction().add(destroyingStart, "pending-start").commit();
        pendingStart.performStart();
        require(pendingStart.destroyed && !events.contains("activity-start-begin"),
                "activity start ran after predrain destroyed host");

        events.clear();
        ProbeActivity pendingResume = activity(new ProbeFragment("report"));
        pendingResume.performCreate(null); pendingResume.performStart();
        ProbeFragment destroyingResume = new ProbeFragment("pending-resume");
        destroyingResume.destroyOnCreate = true;
        pendingResume.getFragmentManager().beginTransaction().add(destroyingResume, "pending-resume").commit();
        pendingResume.performResume();
        require(pendingResume.destroyed && !events.contains("activity-resume-begin"),
                "activity resume ran after predrain destroyed host");

        events.clear();
        ProbeFragment failingReport = new ProbeFragment("report");
        failingReport.failCreate = true;
        ProbeActivity failing = activity(failingReport);
        boolean failed = false;
        try { failing.performCreate(null); }
        catch (IllegalStateException expected) { failed = "probe-create-failure".equals(expected.getMessage()); }
        require(failed && failingReport.starts == 0 && failing.postCreates == 0,
                "create exception swallowed or later callbacks invoked");
        controlledPassed = true;
    }
}
