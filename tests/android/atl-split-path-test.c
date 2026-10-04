/* Compile the real ATL launcher source; exercise its path and GLib CLI boundary. */
#define main atl_production_main
#include ATL_MAIN_SOURCE
#undef main

static int parsed_options(GApplication *app, GVariantDict *options, gpointer data)
{
    struct jni_callback_data *args = data;
    (void)app;
    (void)options;
    g_assert_nonnull(args->split_apks);
    g_assert_cmpstr(args->split_apks[0], ==, "first.apk");
    g_assert_cmpstr(args->split_apks[1], ==, "second.apk");
    g_assert_null(args->split_apks[2]);
    return 0; /* Stop before GTK, ART, or application code starts. */
}

static void rejects(const char *base, char **splits)
{
    GError *error = NULL;
    char *paths = build_apk_archive_paths(base, splits, &error);
    g_assert_null(paths);
    g_assert_error(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT);
    g_clear_error(&error);
}

int main(void)
{
    GError *error = NULL;
    char *directory = g_dir_make_tmp("atl-split-path-XXXXXX", &error);
    g_assert_no_error(error);
    char *base = g_build_filename(directory, "base.apk", NULL);
    char *split = g_build_filename(directory, "arm64.apk", NULL);
    char *alias = g_build_filename(directory, "alias.apk", NULL);
    char *colon = g_build_filename(directory, "bad:name.apk", NULL);
    char *missing = g_build_filename(directory, "missing.apk", NULL);
    g_assert_true(g_file_set_contents(base, "fixture", -1, &error));
    g_assert_true(g_file_set_contents(split, "fixture", -1, &error));
    g_assert_true(g_file_set_contents(colon, "fixture", -1, &error));
    g_assert_cmpint(symlink(split, alias), ==, 0);
    char *splits[] = { split, NULL };
    char *actual = build_apk_archive_paths(base, splits, &error);
    char *expected = g_strdup_printf("%s:%s", base, split);
    g_assert_no_error(error);
    g_assert_cmpstr(actual, ==, expected);
    g_free(actual);
    g_free(expected);
    actual = build_apk_archive_paths(base, NULL, &error);
    g_assert_cmpstr(actual, ==, base);
    g_free(actual);
    char *duplicate_base[] = { base, NULL };
    char *duplicate_split[] = { split, alias, NULL };
    char *missing_split[] = { missing, NULL };
    char *directory_split[] = { directory, NULL };
    char *colon_split[] = { colon, NULL };
    rejects(base, duplicate_base);
    rejects(base, duplicate_split);
    rejects(base, missing_split);
    rejects(base, directory_split);
    rejects(base, colon_split);
    rejects(missing, NULL);
    rejects(directory, NULL);
    rejects(colon, NULL);
    if (geteuid() != 0) {
        g_assert_cmpint(chmod(split, 0), ==, 0);
        rejects(base, splits);
        g_assert_cmpint(chmod(split, 0600), ==, 0);
    }

    GApplication *app = g_application_new("org.vinix.tests.splitcli", G_APPLICATION_NON_UNIQUE);
    struct jni_callback_data args = {0};
    init_cmd_parameters(app, &args);
    g_signal_connect(app, "handle-local-options", G_CALLBACK(parsed_options), &args);
    char *argv[] = { "atl-split-test", "--split-apk", "first.apk", "--split-apk", "second.apk", NULL };
    g_assert_cmpint(g_application_run(app, 5, argv), ==, 0);
    g_strfreev(args.split_apks);
    g_object_unref(app);
    g_assert_cmpint(unlink(alias), ==, 0);
    g_assert_cmpint(unlink(base), ==, 0);
    g_assert_cmpint(unlink(split), ==, 0);
    g_assert_cmpint(unlink(colon), ==, 0);
    g_assert_cmpint(rmdir(directory), ==, 0);
    g_free(base); g_free(split); g_free(alias); g_free(colon); g_free(missing); g_free(directory);
    puts("ATL-SPLIT-PATH-PASS base-first canonical duplicates=reject nonfiles=reject colon=reject repeated-cli=ordered");
    return 0;
}
