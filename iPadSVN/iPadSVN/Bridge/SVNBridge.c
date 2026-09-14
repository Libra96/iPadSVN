#include "SVNBridge.h"

#include "svn_client.h"
#include "svn_pools.h"
#include "svn_auth.h"
#include "svn_opt.h"
#include "svn_dso.h"
#include "svn_diff.h"
#include "svn_io.h"
#include "svn_utf.h"
#include "svn_types.h"
#include "svn_wc.h"
#include "svn_version.h"
#include "apr_general.h"
#include "apr_pools.h"
#include "apr_strings.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_initialized = 0;

typedef struct {
    const char *username;
    const char *password;
} svn_bridge_creds_t;

static void write_err(char *errbuf, int errbuf_len, const char *msg) {
    if (!errbuf || errbuf_len <= 0) return;
    snprintf(errbuf, (size_t)errbuf_len, "%s", msg ? msg : "unknown error");
}

static void write_svn_err(char *errbuf, int errbuf_len, svn_error_t *err) {
    if (!err) return;
    char buf[1024];
    svn_error_t *err2 = svn_err_to_str(err, buf, sizeof(buf));
    if (err2) {
        write_err(errbuf, errbuf_len, "svn error");
        svn_error_clear(err2);
    } else {
        write_err(errbuf, errbuf_len, buf);
    }
}

static svn_error_t *simple_auth_provider(
    void *baton,
    const char **username,
    const char **password,
    svn_boolean_t *may_save,
    apr_pool_t *pool)
{
    svn_bridge_creds_t *c = baton;
    if (c && c->username) *username = apr_pstrdup(pool, c->username);
    if (c && c->password) *password = apr_pstrdup(pool, c->password);
    if (may_save) *may_save = FALSE;
    return SVN_NO_ERROR;
}

static svn_error_t *make_client(
    svn_client_ctx_t **out_ctx,
    svn_bridge_creds_t *creds,
    apr_pool_t *pool)
{
    svn_client_ctx_t *ctx = NULL;
    svn_auth_provider_object_t *providers[3];
    int nproviders = 0;

    SVN_ERR(svn_client_create(&ctx, pool));
    SVN_ERR(svn_auth_get_simple_provider2(&providers[nproviders++], simple_auth_provider, creds, pool));
    SVN_ERR(svn_auth_get_username_provider(&providers[nproviders++], pool));
    SVN_ERR(svn_client_auth_tenant_set(ctx, providers, nproviders, pool));
    *out_ctx = ctx;
    return SVN_NO_ERROR;
}

int svn_bridge_init(void) {
    if (g_initialized) return 0;
    apr_initialize();
    svn_dso_initialize2();
    g_initialized = 1;
    return 0;
}

int svn_bridge_checkout(
    const char *url,
    const char *local_path,
    const char *username,
    const char *password,
    int64_t *out_revision,
    char *errbuf,
    int errbuf_len)
{
    apr_pool_t *pool = NULL;
    svn_error_t *err = NULL;
    svn_client_ctx_t *ctx = NULL;
    svn_revnum_t rev = SVN_INVALID_REVNUM;
    svn_bridge_creds_t creds = { username, password };

    if (!url || !local_path) {
        write_err(errbuf, errbuf_len, "url and local_path required");
        return -1;
    }

    svn_bridge_init();
    apr_pool_create(&pool, NULL);

    err = make_client(&ctx, &creds, pool);
    if (err) goto cleanup;

    err = svn_client_checkout3(
        NULL,
        url,
        local_path,
        NULL,
        rev,
        svn_depth_infinity,
        FALSE,
        FALSE,
        ctx,
        pool);

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
        apr_pool_destroy(pool);
        return -1;
    }

    if (out_revision) {
        int64_t r = 0;
        if (svn_bridge_wc_revision(local_path, &r, errbuf, errbuf_len) == 0) {
            *out_revision = r;
        }
    }

    apr_pool_destroy(pool);
    return 0;
}

int svn_bridge_update(
    const char *wc_path,
    const char *username,
    const char *password,
    int64_t *out_revision,
    char *errbuf,
    int errbuf_len)
{
    apr_pool_t *pool = NULL;
    svn_error_t *err = NULL;
    svn_client_ctx_t *ctx = NULL;
    svn_revnum_t rev = SVN_INVALID_REVNUM;
    svn_bridge_creds_t creds = { username, password };

    svn_bridge_init();
    apr_pool_create(&pool, NULL);

    err = make_client(&ctx, &creds, pool);
    if (err) goto cleanup;

    err = svn_client_update4(
        &rev,
        wc_path,
        svn_depth_infinity,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        ctx,
        pool);

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
        apr_pool_destroy(pool);
        return -1;
    }

    if (out_revision) *out_revision = (int64_t)rev;
    apr_pool_destroy(pool);
    return 0;
}

int svn_bridge_wc_revision(
    const char *wc_path,
    int64_t *out_revision,
    char *errbuf,
    int errbuf_len)
{
    apr_pool_t *pool = NULL;
    svn_error_t *err = NULL;
    svn_client_ctx_t *ctx = NULL;
    svn_revnum_t rev = SVN_INVALID_REVNUM;

    svn_bridge_init();
    apr_pool_create(&pool, NULL);
    err = svn_client_create(&ctx, pool);
    if (err) goto cleanup;

    err = svn_client_revision_from_path2(&rev, wc_path, ctx, pool, pool);
cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
        apr_pool_destroy(pool);
        return -1;
    }
    if (out_revision) *out_revision = (int64_t)rev;
    apr_pool_destroy(pool);
    return 0;
}

typedef struct {
    apr_array_header_t *items;
    apr_pool_t *pool;
} status_baton_t;

static svn_error_t *status_handler(void *baton, const char *path, const svn_client_status_t *status) {
    status_baton_t *b = baton;
    if (!status || !status->node_status) return SVN_NO_ERROR;
    if (status->node_status == svn_wc_status_none || status->node_status == svn_wc_status_normal) {
        return SVN_NO_ERROR;
    }

    const char *st = "unknown";
    switch (status->node_status) {
        case svn_wc_status_modified: st = "modified"; break;
        case svn_wc_status_added: st = "added"; break;
        case svn_wc_status_deleted: st = "deleted"; break;
        case svn_wc_status_replaced: st = "replaced"; break;
        case svn_wc_status_conflicted: st = "conflicted"; break;
        case svn_wc_status_ignored: st = "ignored"; break;
        case svn_wc_status_unversioned: st = "unversioned"; break;
        case svn_wc_status_missing: st = "missing"; break;
        default: break;
    }

    char *rel = apr_pstrdup(b->pool, path);
    char *entry = apr_psprintf(b->pool, "{\"path\":\"%s\",\"status\":\"%s\"}", rel, st);
    APR_ARRAY_PUSH(b->items, char *) = entry;
    return SVN_NO_ERROR;
}

int svn_bridge_status_json(
    const char *wc_path,
    const char *username,
    const char *password,
    char **out_json,
    char *errbuf,
    int errbuf_len)
{
    apr_pool_t *pool = NULL;
    svn_error_t *err = NULL;
    svn_client_ctx_t *ctx = NULL;
    svn_bridge_creds_t creds = { username, password };
    status_baton_t baton;

    svn_bridge_init();
    apr_pool_create(&pool, NULL);
    baton.pool = pool;
    baton.items = apr_array_make(pool, 16, sizeof(char *));

    err = make_client(&ctx, &creds, pool);
    if (err) goto cleanup;

    err = svn_client_status4(
        wc_path,
        NULL,
        svn_depth_infinity,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        status_handler,
        &baton,
        ctx,
        pool);

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
        apr_pool_destroy(pool);
        return -1;
    }

    apr_size_t cap = 256;
    apr_size_t len = 2;
    char *json = apr_palloc(pool, cap);
    strcpy(json, "[");
    for (int i = 0; i < baton.items->nelts; i++) {
        char *item = APR_ARRAY_IDX(baton.items, i, char *);
        apr_size_t need = len + strlen(item) + 2;
        if (need >= cap) {
            cap = need * 2;
            char *n = apr_palloc(pool, cap);
            memcpy(n, json, len + 1);
            json = n;
        }
        if (i > 0) strcat(json, ",");
        strcat(json, item);
        len = strlen(json);
    }
    strcat(json, "]");

    if (out_json) {
        *out_json = strdup(json);
    }
    apr_pool_destroy(pool);
    return 0;
}

typedef struct {
    apr_array_header_t *items;
    apr_pool_t *pool;
} log_baton_t;

static svn_error_t *log_handler(
    void *baton,
    apr_hash_t *changed_paths,
    svn_revnum_t revision,
    const char *author,
    const char *date,
    const char *message,
    apr_pool_t *pool)
{
    (void)changed_paths;
    log_baton_t *b = baton;
    char *safe_msg = message ? apr_pstrdup(b->pool, message) : "";
    for (char *p = safe_msg; *p; p++) {
        if (*p == '"') *p = '\'';
        if (*p == '\n' || *p == '\r') *p = ' ';
    }
    char *entry = apr_psprintf(
        b->pool,
        "{\"revision\":%ld,\"author\":\"%s\",\"date\":\"%s\",\"message\":\"%s\"}",
        (long)revision,
        author ? author : "",
        date ? date : "",
        safe_msg);
    APR_ARRAY_PUSH(b->items, char *) = entry;
    return SVN_NO_ERROR;
}

int svn_bridge_log_json(
    const char *wc_path,
    const char *username,
    const char *password,
    int limit,
    char **out_json,
    char *errbuf,
    int errbuf_len)
{
    apr_pool_t *pool = NULL;
    svn_error_t *err = NULL;
    svn_client_ctx_t *ctx = NULL;
    svn_bridge_creds_t creds = { username, password };
    log_baton_t baton;
    apr_array_header_t *revlist = NULL;
    svn_opt_revision_t peg, rev_start, rev_end;

    svn_bridge_init();
    apr_pool_create(&pool, NULL);
    baton.pool = pool;
    baton.items = apr_array_make(pool, 16, sizeof(char *));

    err = make_client(&ctx, &creds, pool);
    if (err) goto cleanup;

    peg.kind = svn_opt_revision_head;
    rev_start.kind = svn_opt_revision_number;
    rev_start.value.number = 0;
    rev_end.kind = svn_opt_revision_head;

    err = svn_client_log5(
        wc_path,
        &peg,
        &rev_start,
        &rev_end,
        limit > 0 ? limit : 20,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        log_handler,
        &baton,
        ctx,
        pool);

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
        apr_pool_destroy(pool);
        return -1;
    }

    apr_size_t cap = 512;
    char *json = apr_palloc(pool, cap);
    strcpy(json, "[");
    for (int i = 0; i < baton.items->nelts; i++) {
        char *item = APR_ARRAY_IDX(baton.items, i, char *);
        if (i > 0) strcat(json, ",");
        strcat(json, item);
    }
    strcat(json, "]");
    if (out_json) *out_json = strdup(json);
    (void)revlist;
    apr_pool_destroy(pool);
    return 0;
}

int svn_bridge_commit(
    const char *wc_path,
    const char *username,
    const char *password,
    const char *message,
    const char *paths_json,
    int64_t *out_revision,
    char *errbuf,
    int errbuf_len)
{
    apr_pool_t *pool = NULL;
    svn_error_t *err = NULL;
    svn_client_ctx_t *ctx = NULL;
    svn_bridge_creds_t creds = { username, password };
    apr_array_header_t *targets = NULL;
    const svn_commit_info_t *commit_info = NULL;

    (void)paths_json; /* v0.2: filter paths; currently commit all changes under wc */

    svn_bridge_init();
    apr_pool_create(&pool, NULL);

    err = make_client(&ctx, &creds, pool);
    if (err) goto cleanup;

    targets = apr_array_make(pool, 1, sizeof(const char *));
    APR_ARRAY_PUSH(targets, const char *) = apr_pstrdup(pool, wc_path);

    err = svn_client_commit5(
        &commit_info,
        targets,
        svn_depth_infinity,
        FALSE,
        FALSE,
        FALSE,
        NULL,
        message ? message : "",
        NULL,
        ctx,
        pool);

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
        apr_pool_destroy(pool);
        return -1;
    }

    if (out_revision && commit_info) *out_revision = (int64_t)commit_info->revision;
    apr_pool_destroy(pool);
    return 0;
}

int svn_bridge_revert(
    const char *wc_path,
    const char *username,
    const char *password,
    const char *relative_path,
    char *errbuf,
    int errbuf_len)
{
    apr_pool_t *pool = NULL;
    svn_error_t *err = NULL;
    svn_client_ctx_t *ctx = NULL;
    svn_bridge_creds_t creds = { username, password };
    apr_array_header_t *targets = NULL;
    char *full = NULL;

    svn_bridge_init();
    apr_pool_create(&pool, NULL);

    err = make_client(&ctx, &creds, pool);
    if (err) goto cleanup;

    full = apr_psprintf(pool, "%s/%s", wc_path, relative_path);
    targets = apr_array_make(pool, 1, sizeof(const char *));
    APR_ARRAY_PUSH(targets, const char *) = full;

    err = svn_client_revert2(targets, svn_depth_empty, FALSE, ctx, pool);

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
        apr_pool_destroy(pool);
        return -1;
    }
    apr_pool_destroy(pool);
    return 0;
}

int svn_bridge_diff_text(
    const char *wc_path,
    const char *username,
    const char *password,
    const char *relative_path,
    char **out_diff,
    char *errbuf,
    int errbuf_len)
{
    apr_pool_t *pool = NULL;
    svn_error_t *err = NULL;
    svn_client_ctx_t *ctx = NULL;
    svn_bridge_creds_t creds = { username, password };
    apr_file_t *outfile = NULL;
    const char *tmp_path = NULL;
    char *full = NULL;
    svn_opt_revision_t peg, rev1, rev2;

    (void)username;
    (void)password;

    svn_bridge_init();
    apr_pool_create(&pool, NULL);

    err = make_client(&ctx, &creds, pool);
    if (err) goto cleanup;

    full = apr_psprintf(pool, "%s/%s", wc_path, relative_path);
    tmp_path = apr_psprintf(pool, "%s/.svn_diff_tmp", wc_path);
    err = apr_file_open(&outfile, tmp_path, APR_CREATE | APR_WRITE | APR_TRUNCATE, APR_OS_DEFAULT, pool);
    if (err) goto cleanup;

    peg.kind = svn_opt_revision_head;
    rev1.kind = svn_opt_revision_base;
    rev2.kind = svn_opt_revision_working;

    err = svn_client_diff_peg2(
        NULL,
        full,
        &peg,
        &rev1,
        &rev2,
        NULL,
        svn_depth_empty,
        FALSE,
        FALSE,
        FALSE,
        NULL,
        outfile,
        NULL,
        NULL,
        ctx,
        pool);

    apr_file_close(outfile);

    if (err) goto cleanup;

    apr_off_t length = 0;
    err = svn_io_file_length(&length, tmp_path, pool);
    if (err) goto cleanup;

    char *buf = malloc((size_t)length + 1);
    if (!buf) {
        write_err(errbuf, errbuf_len, "out of memory");
        apr_pool_destroy(pool);
        return -1;
    }

    apr_file_t *in = NULL;
    err = apr_file_open(&in, tmp_path, APR_READ, APR_OS_DEFAULT, pool);
    if (err) {
        free(buf);
        goto cleanup;
    }
    apr_size_t n = (apr_size_t)length;
    err = apr_file_read(in, buf, &n);
    apr_file_close(in);
    if (err) {
        free(buf);
        goto cleanup;
    }
    buf[n] = '\0';
    if (out_diff) *out_diff = buf;
    else free(buf);

    apr_pool_destroy(pool);
    return 0;

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
    }
    if (out_diff) *out_diff = strdup("");
    apr_pool_destroy(pool);
    return err ? -1 : 0;
}
