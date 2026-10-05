#include <stdio.h>
#include <stdlib.h>
#include <glib/gstdio.h>
#include <libsoup/soup.h>

#ifndef ATL_COOKIE_SOURCE
#error "Pass the exact production CookieManager.c path with ATL_COOKIE_SOURCE"
#endif
/* Delay only a validation-copy insertion, then call the real Soup provider.
 * This makes expiration between the snapshot and insertion deterministic. */
static gboolean pause_validation_insert;
static void delayed_cookie_insert(SoupCookieJar *jar, SoupCookie *cookie);
#define soup_cookie_jar_add_cookie delayed_cookie_insert
#include ATL_COOKIE_SOURCE
#undef soup_cookie_jar_add_cookie

static void delayed_cookie_insert(SoupCookieJar *jar, SoupCookie *cookie)
{
	if (pause_validation_insert && !strcmp(soup_cookie_get_name(cookie), "edgeSecure")) {
		pause_validation_insert = FALSE;
		g_usleep(2200000);
	}
	soup_cookie_jar_add_cookie(jar, cookie);
}

static char *test_directory;
char *get_app_data_dir(void) { return test_directory; }

#define REQUIRE(expression) do { if (!(expression)) { \
	fprintf(stderr, "ANDROID-COOKIE-FAIL line=%d check=%s\n", __LINE__, #expression); \
	exit(1); } } while (0)

static void reset_store(void)
{
	if (cookie_store.jar) g_object_unref(cookie_store.jar);
	if (cookie_store.database) REQUIRE(sqlite3_close(cookie_store.database) == SQLITE_OK);
	cookie_store = (AtlCookieStore){0};
}

static int contains(const char *url, const char *expected)
{
	char *header = get_cookie_locked(url);
	int found = header && strstr(header, expected) != NULL;
	g_free(header);
	return found;
}

static gint64 verify_saved_attributes(void)
{
	GSList *cookies = soup_cookie_jar_all_cookies(cookie_store.jar);
	gint64 expiry = 0;
	int found_session = 0;
	for (GSList *item = cookies; item; item = item->next) {
		SoupCookie *cookie = item->data;
		if (!strcmp(soup_cookie_get_name(cookie), "token")) {
			REQUIRE(!strcmp(soup_cookie_get_domain(cookie), ".example.com"));
			REQUIRE(soup_cookie_get_secure(cookie));
			REQUIRE(soup_cookie_get_http_only(cookie));
			REQUIRE(soup_cookie_get_same_site_policy(cookie) == SOUP_SAME_SITE_POLICY_NONE);
			REQUIRE(soup_cookie_get_expires(cookie));
			expiry = g_date_time_to_unix(soup_cookie_get_expires(cookie));
		}
		if (!strcmp(soup_cookie_get_name(cookie), "session")) {
			REQUIRE(!strcmp(soup_cookie_get_domain(cookie), "auth.example.com"));
			REQUIRE(soup_cookie_get_secure(cookie));
			REQUIRE(soup_cookie_get_http_only(cookie));
			REQUIRE(soup_cookie_get_same_site_policy(cookie) == SOUP_SAME_SITE_POLICY_STRICT);
			REQUIRE(soup_cookie_get_expires(cookie) == NULL);
			found_session = 1;
		}
	}
	g_slist_free_full(cookies, (GDestroyNotify)soup_cookie_free);
	REQUIRE(expiry > 0 && found_session);
	GUri *uri = cookie_uri("https://auth.example.com/");
	char *script_cookies = soup_cookie_jar_get_cookies(cookie_store.jar, uri, FALSE);
	REQUIRE(!script_cookies || (!strstr(script_cookies, "token=") && !strstr(script_cookies, "session=")));
	g_free(script_cookies);
	g_uri_unref(uri);
	return expiry;
}

int main(void)
{
	test_directory = g_dir_make_tmp("atl-cookie-test-XXXXXX", NULL);
	REQUIRE(test_directory != NULL);
	g_mutex_lock(&cookie_store_mutex);
	REQUIRE(initialize_cookie_store_locked());
	REQUIRE(set_cookie_locked("example.com", "bare=host; Path=/"));
	REQUIRE(contains("http://example.com/", "bare=host"));
	REQUIRE(!set_cookie_locked("example.com", "bad=bareSecure; Secure"));
	REQUIRE(!set_cookie_locked("ftp://example.com/", "bad=scheme"));
	REQUIRE(set_cookie_locked("https://auth.example.com/", "token=persistent; Domain=example.com; Path=/; Secure; HttpOnly; SameSite=None; Max-Age=3600"));
	REQUIRE(set_cookie_locked("https://auth.example.com/", "token=persistent; Domain=example.com; Path=/; Secure; HttpOnly; SameSite=None; Max-Age=3600"));
	REQUIRE(set_cookie_locked("https://auth.example.com/", "session=alive; Path=/; Secure; HttpOnly; SameSite=Strict"));
	REQUIRE(set_cookie_locked("https://auth.example.com/", "sid=root; Path=/"));
	REQUIRE(set_cookie_locked("https://auth.example.com/area/", "sid=area; Path=/area"));
	char *header = get_cookie_locked("https://auth.example.com/area/play");
	REQUIRE(header && !strncmp(header, "sid=area;", 9));
	REQUIRE(strstr(header, "sid=root") != NULL);
	g_free(header);
	REQUIRE(!contains("https://auth.example.com/area-other", "sid=area"));
	REQUIRE(contains("https://cdn.example.com/", "token=persistent"));
	REQUIRE(!contains("https://cdn.example.com/", "session=alive"));
	REQUIRE(!contains("http://auth.example.com/", "token=persistent"));
	REQUIRE(!set_cookie_locked("http://auth.example.com/", "token=attack; Domain=example.com; Path=/"));
	REQUIRE(contains("https://auth.example.com/", "token=persistent"));
	REQUIRE(!set_cookie_locked("https://auth.example.com/", ""));
	REQUIRE(!set_cookie_locked("https://auth.example.com/", ";"));
	REQUIRE(!set_cookie_locked("https://auth.example.com/", "bad=control\001"));
	REQUIRE(!set_cookie_locked("https://auth.example.com/", "bad=domain; Domain=elsewhere.example"));
	REQUIRE(!set_cookie_locked("https://auth.co.uk/", "bad=suffix; Domain=co.uk"));
	REQUIRE(!set_cookie_locked("http://auth.example.com/", "bad=secure; Secure"));
	REQUIRE(!set_cookie_locked("https://auth.example.com/", "bad=samesite; SameSite=None"));
	REQUIRE(!set_cookie_locked("https://auth.example.com/", "__Secure-bad=prefix"));
	REQUIRE(!set_cookie_locked("https://auth.example.com/", "__Host-bad=domain; Secure; Domain=example.com; Path=/"));
	REQUIRE(!set_cookie_locked("https://auth.example.com/", "__Host-bad=path; Secure; Path=/area"));
	REQUIRE(set_cookie_locked("https://auth.example.com/", "__Host-valid=good; Secure; Path=/"));
	REQUIRE(set_cookie_locked("https://auth.example.com/", "gone=value; Max-Age=300"));
	REQUIRE(set_cookie_locked("https://auth.example.com/", "gone=value; Max-Age=0"));
	REQUIRE(!contains("https://auth.example.com/", "gone=value"));
	REQUIRE(set_cookie_locked("https://auth.example.com/", "absent=value; Max-Age=0"));
	REQUIRE(!set_cookie_locked("http://auth.example.com/", "absent=value; Max-Age=0; Secure"));
	REQUIRE(set_cookie_locked("https://auth.example.com/", "staleSecure=value; Domain=example.com; Path=/; Secure; Max-Age=1"));
	g_usleep(2200000);
	REQUIRE(!set_cookie_locked("http://auth.example.com/", "staleSecure=value; Domain=example.com; Path=/; Max-Age=0"));
	REQUIRE(!set_cookie_locked("http://auth.example.com/", "staleSecure=value; Domain=EXAMPLE.COM; Path=/; Max-Age=0"));
	/* The provider rejects a case-mismatched Domain during origin parsing. */
	REQUIRE(!set_cookie_locked("https://auth.example.com/", "staleSecure=value; Domain=EXAMPLE.COM; Path=/; Max-Age=0"));
	/* Its jar identity table is case-insensitive even though origin parsing is
	 * not. Check that copied expired security state protects that identity. */
	GUri *insecure_origin = cookie_uri("http://auth.example.com/");
	SoupCookie *case_deletion = soup_cookie_new("staleSecure", "value", ".EXAMPLE.COM", "/", 0);
	REQUIRE(!valid_expired_deletion(cookie_store.jar, case_deletion, insecure_origin));
	soup_cookie_free(case_deletion);
	g_uri_unref(insecure_origin);
	REQUIRE(set_cookie_locked("https://auth.example.com/", "staleSecure=value; Domain=example.com; Path=/; Max-Age=0"));
	REQUIRE(set_cookie_locked("https://auth.example.com/", "edgeSecure=value; Path=/; Secure; Max-Age=1"));
	pause_validation_insert = TRUE;
	REQUIRE(!set_cookie_locked("http://auth.example.com/", "edgeSecure=value; Path=/; Max-Age=0"));
	REQUIRE(!pause_validation_insert);
	REQUIRE(set_cookie_locked("https://auth.example.com/", "edgeSecure=value; Path=/; Max-Age=0"));
	REQUIRE(set_cookie_locked("https://auth.example.com/", "unicode=\360\237\230\200; Path=/"));
	REQUIRE(contains("https://auth.example.com/", "unicode=\360\237\230\200"));
	gint64 saved_expiry = verify_saved_attributes();
	REQUIRE(flush_cookie_store_locked());
	reset_store();
	REQUIRE(initialize_cookie_store_locked());
	REQUIRE(verify_saved_attributes() == saved_expiry);
	REQUIRE(contains("https://auth.example.com/", "token=persistent"));
	REQUIRE(contains("https://auth.example.com/", "session=alive"));
	REQUIRE(contains("https://auth.example.com/area/play", "sid=area"));
	REQUIRE(contains("https://auth.example.com/area/play", "sid=root"));
	REQUIRE(contains("https://auth.example.com/", "__Host-valid=good"));
	REQUIRE(!contains("http://auth.example.com/", "token=persistent"));
	REQUIRE(contains("https://cdn.example.com/", "token=persistent"));
	REQUIRE(!contains("https://cdn.example.com/", "session=alive"));
	REQUIRE(!contains("https://auth.example.com/", "gone=value"));
	REQUIRE(set_cookie_locked("https://auth.example.com/area/play", "sid=deleted; Path=/area; Max-Age=0"));
	REQUIRE(!contains("https://auth.example.com/area/play", "sid=area"));
	REQUIRE(contains("https://auth.example.com/area/play", "sid=root"));
	REQUIRE(flush_cookie_store_locked());
	reset_store();
	REQUIRE(initialize_cookie_store_locked());
	REQUIRE(!contains("https://auth.example.com/area/play", "sid=area"));
	REQUIRE(contains("https://auth.example.com/area/play", "sid=root"));

	/* A real second connection prevents the writer's COMMIT. Its checked
	 * rollback must retain the prior durable snapshot, while leaving the
	 * current in-memory cookie available for a later successful flush. */
	char *database_name = g_build_filename(test_directory, "cookies.sqlite", NULL);
	sqlite3 *reader = NULL;
	REQUIRE(sqlite3_open(database_name, &reader) == SQLITE_OK);
	REQUIRE(sqlite3_exec(reader, "BEGIN; SELECT * FROM atl_cookies_v1", NULL, NULL, NULL) == SQLITE_OK);
	REQUIRE(sqlite3_busy_timeout(cookie_store.database, 1) == SQLITE_OK);
	REQUIRE(set_cookie_locked("https://auth.example.com/", "token=latest; Domain=example.com; Path=/; Secure; HttpOnly; SameSite=None; Max-Age=3600"));
	REQUIRE(!flush_cookie_store_locked());
	REQUIRE(contains("https://auth.example.com/", "token=latest"));
	REQUIRE(sqlite3_exec(reader, "ROLLBACK", NULL, NULL, NULL) == SQLITE_OK);
	REQUIRE(sqlite3_close(reader) == SQLITE_OK);
	reset_store();
	REQUIRE(initialize_cookie_store_locked());
	REQUIRE(contains("https://auth.example.com/", "token=persistent"));
	REQUIRE(!contains("https://auth.example.com/", "token=latest"));
	REQUIRE(flush_cookie_store_locked());
	REQUIRE(sqlite3_exec(cookie_store.database, "UPDATE atl_cookies_v1 SET secure=4294967296", NULL, NULL, NULL) == SQLITE_OK);
	reset_store();
	REQUIRE(!initialize_cookie_store_locked());
	REQUIRE(!cookie_store.jar && !cookie_store.database);
	g_mutex_unlock(&cookie_store_mutex);
	g_remove(database_name);
	g_rmdir(test_directory);
	g_free(database_name);
	g_free(test_directory);
	puts("ANDROID-COOKIE-PASS validation=real-soup paths=distinct session=persisted reload=verified rollback=durable corruption=rejected");
	return 0;
}
