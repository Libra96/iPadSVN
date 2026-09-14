#include "SVNBridge.h"

#include "svn_client.h"
#include "svn_pools.h"
#include "svn_auth.h"
#include "svn_config.h"
#include "svn_error.h"
#include "svn_opt.h"
#include "svn_io.h"
#include "svn_props.h"
#include "svn_dirent_uri.h"
#include "svn_types.h"
#include "svn_wc.h"
#include "svn_hash.h"
#include "svn_string.h"
#include "apr_general.h"
#include "apr_pools.h"
#include "apr_strings.h"
#include "apr_hash.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_initialized = 0;

typedef struct {
    const char *username;
    const char *password;
} svn_bridge_creds_t;

typedef struct {
    const char *message;
} svn_bridge_logmsg_t;

typedef struct {
    svn_revnum_t revision;
} svn_bridge_commit_baton_t;

typedef struct {
    apr_array_header_t *items;
    apr_pool_t *pool;
    const char *wc_abspath;
} status_baton_t;

typedef struct {
    apr_array_header_t *items;
    apr_pool_t *pool;
} log_baton_t;

typedef struct {
    svn_revnum_t rev;
} info_baton_t;

static void write_err(char *errbuf, int errbuf_len, const char *msg) {
    if (!errbuf || errbuf_len <= 0) return;
    snprintf(errbuf, (size_t)errbuf_len, "%s", msg ? msg : "unknown error");
}

static void write_svn_err(char *errbuf, int errbuf_len, svn_error_t *err) {
    char buf[1024];
    const char *msg;
    if (!err) return;
    msg = svn_err_best_message(err, buf, sizeof(buf));
    write_err(errbuf, errbuf_len, msg);
}

static const char *json_escape(const char *src, apr_pool_t *pool) {
    apr_size_t i, len, extra = 0;
    char *out;
    apr_size_t j = 0;

    if (!src) src = "";
    len = strlen(src);
    for (i = 0; i < len; i++) {
        if (src[i] == '"' || src[i] == '\\' || src[i] == '\n' || src[i] == '\r' || src[i] == '\t') {
            extra++;
        }
    }
    out = apr_palloc(pool, len + extra + 1);
    for (i = 0; i < len; i++) {
        char c = src[i];
        if (c == '"' || c == '\\') {
            out[j++] = '\\';
            out[j++] = c;
        } else if (c == '\n') {
            out[j++] = '\\';
            out[j++] = 'n';
        } else if (c == '\r') {
            out[j++] = '\\';
            out[j++] = 'r';
        } else if (c == '\t') {
            out[j++] = '\\';
            out[j++] = 't';
        } else {
            out[j++] = c;
        }
    }
    out[j] = '\0';
    return out;
}

static svn_error_t *simple_prompt(
    svn_auth_cred_simple_t **cred,
    void *baton,
    const char *realm,
    const char *username,
    svn_boolean_t may_save,
    apr_pool_t *pool)
{
    svn_bridge_creds_t *c = baton;
    svn_auth_cred_simple_t *ret = apr_pcalloc(pool, sizeof(*ret));
    (void)realm;
    (void)may_save;
    ret->username = apr_pstrdup(pool, (c && c->username && c->username[0])
                                    ? c->username
                                    : (username ? username : ""));
    ret->password = apr_pstrdup(pool, (c && c->password) ? c->password : "");
    ret->may_save = FALSE;
    *cred = ret;
    return SVN_NO_ERROR;
}

static svn_error_t *ssl_server_trust_prompt(
    svn_auth_cred_ssl_server_trust_t **cred,
    void *baton,
    const char *realm,
    apr_uint32_t failures,
    const svn_auth_ssl_server_cert_info_t *cert_info,
    svn_boolean_t may_save,
    apr_pool_t *pool)
{
    svn_auth_cred_ssl_server_trust_t *ret = apr_pcalloc(pool, sizeof(*ret));
    (void)baton;
    (void)realm;
    (void)cert_info;
    (void)may_save;
    ret->may_save = FALSE;
    ret->accepted_failures = failures;
    *cred = ret;
    return SVN_NO_ERROR;
}

static svn_error_t *commit_log_callback(
    const char **log_msg,
    const char **tmp_file,
    const apr_array_header_t *commit_items,
    void *baton,
    apr_pool_t *pool)
{
    svn_bridge_logmsg_t *msg = baton;
    (void)commit_items;
    *tmp_file = NULL;
    *log_msg = apr_pstrdup(pool, (msg && msg->message) ? msg->message : "");
    return SVN_NO_ERROR;
}

static svn_error_t *commit_callback(
    const svn_commit_info_t *commit_info,
    void *baton,
    apr_pool_t *pool)
{
    svn_bridge_commit_baton_t *b = baton;
    (void)pool;
    if (b && commit_info) b->revision = commit_info->revision;
    return SVN_NO_ERROR;
}

static svn_error_t *make_client(
    svn_client_ctx_t **out_ctx,
    svn_bridge_creds_t *creds,
    svn_bridge_logmsg_t *logmsg,
    apr_pool_t *pool)
{
    svn_client_ctx_t *ctx = NULL;
    apr_array_header_t *providers;
    svn_auth_provider_object_t *provider;

    SVN_ERR(svn_client_create_context2(&ctx, NULL, pool));
    SVN_ERR(svn_config_get_config(&ctx->config, NULL, pool));

    providers = apr_array_make(pool, 4, sizeof(svn_auth_provider_object_t *));

    svn_auth_get_simple_prompt_provider(&provider, simple_prompt, creds, 2, pool);
    APR_ARRAY_PUSH(providers, svn_auth_provider_object_t *) = provider;

    svn_auth_get_ssl_server_trust_prompt_provider(
        &provider, ssl_server_trust_prompt, NULL, pool);
    APR_ARRAY_PUSH(providers, svn_auth_provider_object_t *) = provider;

    svn_auth_open(&ctx->auth_baton, providers, pool);
    if (creds && creds->username && creds->username[0]) {
        svn_auth_set_parameter(ctx->auth_baton,
                               SVN_AUTH_PARAM_DEFAULT_USERNAME,
                               creds->username);
    }
    if (creds && creds->password) {
        svn_auth_set_parameter(ctx->auth_baton,
                               SVN_AUTH_PARAM_DEFAULT_PASSWORD,
                               creds->password);
    }
    svn_auth_set_parameter(ctx->auth_baton, SVN_AUTH_PARAM_NON_INTERACTIVE, "");

    if (logmsg) {
        ctx->log_msg_func3 = commit_log_callback;
        ctx->log_msg_baton3 = logmsg;
    }

    *out_ctx = ctx;
    return SVN_NO_ERROR;
}

int svn_bridge_init(void) {
    if (g_initialized) return 0;
    if (apr_initialize() != APR_SUCCESS) return -1;
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
    svn_revnum_t result_rev = SVN_INVALID_REVNUM;
    svn_bridge_creds_t creds = { username, password };
    svn_opt_revision_t peg, rev;
    const char *canon_url = NULL;
    const char *abspath = NULL;

    if (!url || !local_path) {
        write_err(errbuf, errbuf_len, "url and local_path required");
        return -1;
    }

    svn_bridge_init();
    pool = svn_pool_create(NULL);

    err = make_client(&ctx, &creds, NULL, pool);
    if (err) goto cleanup;

    canon_url = svn_uri_canonicalize(url, pool);
    err = svn_dirent_get_absolute(&abspath, local_path, pool);
    if (err) goto cleanup;

    peg.kind = svn_opt_revision_unspecified;
    rev.kind = svn_opt_revision_head;
    err = svn_client_checkout3(
        &result_rev,
        canon_url,
        abspath,
        &peg,
        &rev,
        svn_depth_infinity,
        FALSE,
        FALSE,
        ctx,
        pool);

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
        svn_pool_destroy(pool);
        return -1;
    }
    if (out_revision) *out_revision = (int64_t)result_rev;
    svn_pool_destroy(pool);
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
    svn_bridge_creds_t creds = { username, password };
    svn_opt_revision_t rev;
    apr_array_header_t *paths = NULL;
    apr_array_header_t *result_revs = NULL;
    const char *abspath = NULL;

    svn_bridge_init();
    pool = svn_pool_create(NULL);

    err = make_client(&ctx, &creds, NULL, pool);
    if (err) goto cleanup;

    err = svn_dirent_get_absolute(&abspath, wc_path, pool);
    if (err) goto cleanup;

    paths = apr_array_make(pool, 1, sizeof(const char *));
    APR_ARRAY_PUSH(paths, const char *) = abspath;
    rev.kind = svn_opt_revision_head;

    err = svn_client_update4(
        &result_revs,
        paths,
        &rev,
        svn_depth_infinity,
        FALSE,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        ctx,
        pool);

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
        svn_pool_destroy(pool);
        return -1;
    }
    if (out_revision) {
        if (result_revs && result_revs->nelts > 0) {
            *out_revision = (int64_t)APR_ARRAY_IDX(result_revs, 0, svn_revnum_t);
        } else {
            *out_revision = -1;
        }
    }
    svn_pool_destroy(pool);
    return 0;
}

static svn_error_t *info_receiver(
    void *baton,
    const char *abspath_or_url,
    const svn_client_info2_t *info,
    apr_pool_t *scratch_pool)
{
    info_baton_t *b = baton;
    (void)abspath_or_url;
    (void)scratch_pool;
    if (b && info) b->rev = info->rev;
    return SVN_NO_ERROR;
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
    svn_opt_revision_t peg, rev;
    const char *abspath = NULL;
    info_baton_t baton;

    svn_bridge_init();
    pool = svn_pool_create(NULL);
    baton.rev = SVN_INVALID_REVNUM;

    err = make_client(&ctx, NULL, NULL, pool);
    if (err) goto cleanup;

    err = svn_dirent_get_absolute(&abspath, wc_path, pool);
    if (err) goto cleanup;

    peg.kind = svn_opt_revision_unspecified;
    rev.kind = svn_opt_revision_working;
    err = svn_client_info4(
        abspath,
        &peg,
        &rev,
        svn_depth_empty,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        info_receiver,
        &baton,
        ctx,
        pool);

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
        svn_pool_destroy(pool);
        return -1;
    }
    if (out_revision) *out_revision = (int64_t)baton.rev;
    svn_pool_destroy(pool);
    return 0;
}

static svn_error_t *status_handler(
    void *baton,
    const char *path,
    const svn_client_status_t *status,
    apr_pool_t *scratch_pool)
{
    status_baton_t *b = baton;
    const char *rel;
    const char *st = "unknown";
    char *entry;
    (void)path;
    (void)scratch_pool;

    if (!status) return SVN_NO_ERROR;
    if (status->node_status == svn_wc_status_none ||
        status->node_status == svn_wc_status_normal) {
        return SVN_NO_ERROR;
    }

    switch (status->node_status) {
        case svn_wc_status_modified: st = "modified"; break;
        case svn_wc_status_added: st = "added"; break;
        case svn_wc_status_deleted: st = "deleted"; break;
        case svn_wc_status_replaced: st = "replaced"; break;
        case svn_wc_status_conflicted: st = "conflicted"; break;
        case svn_wc_status_ignored: st = "ignored"; break;
        case svn_wc_status_unversioned: st = "unversioned"; break;
        case svn_wc_status_missing: st = "missing"; break;
        case svn_wc_status_obstructed: st = "obstructed"; break;
        default: break;
    }

    rel = svn_dirent_skip_ancestor(b->wc_abspath, status->local_abspath);
    if (!rel || !*rel) rel = status->local_abspath ? status->local_abspath : path;
    entry = apr_psprintf(b->pool, "{\"path\":\"%s\",\"status\":\"%s\"}",
                         json_escape(rel, b->pool), st);
    APR_ARRAY_PUSH(b->items, char *) = entry;
    return SVN_NO_ERROR;
}

static char *items_to_json(apr_array_header_t *items, apr_pool_t *pool) {
    int i;
    char *json = apr_pstrdup(pool, "[");
    for (i = 0; i < items->nelts; i++) {
        char *item = APR_ARRAY_IDX(items, i, char *);
        if (i > 0) json = apr_pstrcat(pool, json, ",", item, SVN_VA_NULL);
        else json = apr_pstrcat(pool, json, item, SVN_VA_NULL);
    }
    return apr_pstrcat(pool, json, "]", SVN_VA_NULL);
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
    svn_opt_revision_t rev;
    const char *abspath = NULL;

    svn_bridge_init();
    pool = svn_pool_create(NULL);
    baton.pool = pool;
    baton.items = apr_array_make(pool, 16, sizeof(char *));

    err = make_client(&ctx, &creds, NULL, pool);
    if (err) goto cleanup;

    err = svn_dirent_get_absolute(&abspath, wc_path, pool);
    if (err) goto cleanup;
    baton.wc_abspath = abspath;

    rev.kind = svn_opt_revision_working;
    err = svn_client_status6(
        NULL,
        ctx,
        abspath,
        &rev,
        svn_depth_infinity,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        status_handler,
        &baton,
        pool);

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
        svn_pool_destroy(pool);
        return -1;
    }
    if (out_json) *out_json = strdup(items_to_json(baton.items, pool));
    svn_pool_destroy(pool);
    return 0;
}

static svn_error_t *log_receiver(
    void *baton,
    svn_log_entry_t *entry,
    apr_pool_t *scratch_pool)
{
    log_baton_t *b = baton;
    const char *author = "";
    const char *date = "";
    const char *message = "";
    char *json;
    (void)scratch_pool;

    if (!entry || entry->revision == SVN_INVALID_REVNUM) return SVN_NO_ERROR;
    if (entry->revprops) {
        svn_string_t *s;
        s = svn_hash_gets(entry->revprops, SVN_PROP_REVISION_AUTHOR);
        if (s && s->data) author = s->data;
        s = svn_hash_gets(entry->revprops, SVN_PROP_REVISION_DATE);
        if (s && s->data) date = s->data;
        s = svn_hash_gets(entry->revprops, SVN_PROP_REVISION_LOG);
        if (s && s->data) message = s->data;
    }
    json = apr_psprintf(
        b->pool,
        "{\"revision\":%ld,\"author\":\"%s\",\"date\":\"%s\",\"message\":\"%s\"}",
        (long)entry->revision,
        json_escape(author, b->pool),
        json_escape(date, b->pool),
        json_escape(message, b->pool));
    APR_ARRAY_PUSH(b->items, char *) = json;
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
    apr_array_header_t *targets;
    apr_array_header_t *ranges;
    apr_array_header_t *revprops;
    svn_opt_revision_t peg;
    svn_opt_revision_range_t *range;
    const char *abspath = NULL;

    svn_bridge_init();
    pool = svn_pool_create(NULL);
    baton.pool = pool;
    baton.items = apr_array_make(pool, 16, sizeof(char *));

    err = make_client(&ctx, &creds, NULL, pool);
    if (err) goto cleanup;

    err = svn_dirent_get_absolute(&abspath, wc_path, pool);
    if (err) goto cleanup;

    targets = apr_array_make(pool, 1, sizeof(const char *));
    APR_ARRAY_PUSH(targets, const char *) = abspath;

    range = apr_pcalloc(pool, sizeof(*range));
    range->start.kind = svn_opt_revision_head;
    range->end.kind = svn_opt_revision_number;
    range->end.value.number = 1;
    ranges = apr_array_make(pool, 1, sizeof(svn_opt_revision_range_t *));
    APR_ARRAY_PUSH(ranges, svn_opt_revision_range_t *) = range;

    revprops = apr_array_make(pool, 3, sizeof(const char *));
    APR_ARRAY_PUSH(revprops, const char *) = SVN_PROP_REVISION_AUTHOR;
    APR_ARRAY_PUSH(revprops, const char *) = SVN_PROP_REVISION_DATE;
    APR_ARRAY_PUSH(revprops, const char *) = SVN_PROP_REVISION_LOG;

    peg.kind = svn_opt_revision_unspecified;
    err = svn_client_log5(
        targets,
        &peg,
        ranges,
        limit > 0 ? limit : 20,
        FALSE,
        FALSE,
        FALSE,
        revprops,
        log_receiver,
        &baton,
        ctx,
        pool);

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
        svn_pool_destroy(pool);
        return -1;
    }
    if (out_json) *out_json = strdup(items_to_json(baton.items, pool));
    svn_pool_destroy(pool);
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
    svn_bridge_logmsg_t logmsg;
    svn_bridge_commit_baton_t commit_baton;
    apr_array_header_t *targets;
    const char *abspath = NULL;
    (void)paths_json;

    svn_bridge_init();
    pool = svn_pool_create(NULL);
    logmsg.message = message ? message : "";
    commit_baton.revision = SVN_INVALID_REVNUM;

    err = make_client(&ctx, &creds, &logmsg, pool);
    if (err) goto cleanup;

    err = svn_dirent_get_absolute(&abspath, wc_path, pool);
    if (err) goto cleanup;

    targets = apr_array_make(pool, 1, sizeof(const char *));
    APR_ARRAY_PUSH(targets, const char *) = abspath;

    err = svn_client_commit6(
        targets,
        svn_depth_infinity,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        FALSE,
        NULL,
        NULL,
        commit_callback,
        &commit_baton,
        ctx,
        pool);

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
        svn_pool_destroy(pool);
        return -1;
    }
    if (out_revision) *out_revision = (int64_t)commit_baton.revision;
    svn_pool_destroy(pool);
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
    apr_array_header_t *targets;
    const char *abspath = NULL;
    const char *full = NULL;

    svn_bridge_init();
    pool = svn_pool_create(NULL);

    err = make_client(&ctx, &creds, NULL, pool);
    if (err) goto cleanup;

    err = svn_dirent_get_absolute(&abspath, wc_path, pool);
    if (err) goto cleanup;
    full = svn_dirent_join(abspath, relative_path ? relative_path : "", pool);

    targets = apr_array_make(pool, 1, sizeof(const char *));
    APR_ARRAY_PUSH(targets, const char *) = full;

    err = svn_client_revert3(
        targets,
        svn_depth_empty,
        NULL,
        FALSE,
        FALSE,
        ctx,
        pool);

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
        svn_pool_destroy(pool);
        return -1;
    }
    svn_pool_destroy(pool);
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
    svn_stringbuf_t *sb = NULL;
    svn_stream_t *outstream = NULL;
    svn_stream_t *errstream = NULL;
    const char *abspath = NULL;
    const char *full = NULL;
    svn_opt_revision_t peg, start_rev, end_rev;

    svn_bridge_init();
    pool = svn_pool_create(NULL);

    err = make_client(&ctx, &creds, NULL, pool);
    if (err) goto cleanup;

    err = svn_dirent_get_absolute(&abspath, wc_path, pool);
    if (err) goto cleanup;
    full = svn_dirent_join(abspath, relative_path ? relative_path : "", pool);

    sb = svn_stringbuf_create_empty(pool);
    outstream = svn_stream_from_stringbuf(sb, pool);
    errstream = svn_stream_empty(pool);

    peg.kind = svn_opt_revision_working;
    start_rev.kind = svn_opt_revision_base;
    end_rev.kind = svn_opt_revision_working;

    err = svn_client_diff_peg6(
        NULL,
        full,
        &peg,
        &start_rev,
        &end_rev,
        NULL,
        svn_depth_empty,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        "UTF-8",
        outstream,
        errstream,
        NULL,
        ctx,
        pool);
    if (err) goto cleanup;

    if (out_diff) *out_diff = strdup(sb->data ? sb->data : "");
    svn_pool_destroy(pool);
    return 0;

cleanup:
    if (err) {
        write_svn_err(errbuf, errbuf_len, err);
        svn_error_clear(err);
    }
    svn_pool_destroy(pool);
    return -1;
}
