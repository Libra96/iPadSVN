#ifndef SVNBridge_h
#define SVNBridge_h

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 初始化 libsvn/apr（进程内调用一次）
int svn_bridge_init(void);

/// Checkout：url → localPath，成功返回 0
int svn_bridge_checkout(
    const char *url,
    const char *local_path,
    const char *username,
    const char *password,
    int64_t *out_revision,
    char *errbuf,
    int errbuf_len
);

/// Update 工作副本
int svn_bridge_update(
    const char *wc_path,
    const char *username,
    const char *password,
    int64_t *out_revision,
    char *errbuf,
    int errbuf_len
);

/// 获取 WC 当前 revision
int svn_bridge_wc_revision(
    const char *wc_path,
    int64_t *out_revision,
    char *errbuf,
    int errbuf_len
);

/// Status JSON 数组写入 out_json（调用方 free）
/// [{"path":"src/a.swift","status":"modified"}, ...]
int svn_bridge_status_json(
    const char *wc_path,
    const char *username,
    const char *password,
    char **out_json,
    char *errbuf,
    int errbuf_len
);

/// Log JSON 数组写入 out_json（调用方 free）
/// [{"revision":1284,"author":"you","date":"...","message":"..."}, ...]
int svn_bridge_log_json(
    const char *wc_path,
    const char *username,
    const char *password,
    int limit,
    char **out_json,
    char *errbuf,
    int errbuf_len
);

/// Commit；paths_json 为 JSON 字符串数组或 null 表示全部
int svn_bridge_commit(
    const char *wc_path,
    const char *username,
    const char *password,
    const char *message,
    const char *paths_json,
    int64_t *out_revision,
    char *errbuf,
    int errbuf_len
);

/// Revert 单文件（相对 WC 根路径）
int svn_bridge_revert(
    const char *wc_path,
    const char *username,
    const char *password,
    const char *relative_path,
    char *errbuf,
    int errbuf_len
);

/// 统一 diff 文本写入 out_diff（调用方 free）；非版本控制文件返回空字符串
int svn_bridge_diff_text(
    const char *wc_path,
    const char *username,
    const char *password,
    const char *relative_path,
    char **out_diff,
    char *errbuf,
    int errbuf_len
);

#ifdef __cplusplus
}
#endif

#endif /* SVNBridge_h */
