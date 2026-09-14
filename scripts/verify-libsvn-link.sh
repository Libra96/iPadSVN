#!/usr/bin/env bash
# Compile and link a minimal program against libsvn_merged.a for iOS device SDK.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT}/build"
INSTALL_ROOT="${BUILD_DIR}/install"
VERIFY_DIR="${BUILD_DIR}/verify"
LOG_FILE="${BUILD_DIR}/verify.log"

MIN_IOS="16.0"
SDK="iphoneos"
ARCH="arm64"
PREFIX="${INSTALL_ROOT}/${SDK}-${ARCH}"
LIB="${PREFIX}/lib/libsvn_merged.a"
HEADERS="${PREFIX}/include"

mkdir -p "${VERIFY_DIR}"
: > "${LOG_FILE}"

log() {
  echo "[verify] $*" | tee -a "${LOG_FILE}"
}

die() {
  log "FAIL: $*"
  exit 1
}

[[ -f "${LIB}" ]] || die "Library not found: ${LIB}"

SYSROOT="$(xcrun --sdk "${SDK}" --show-sdk-path)"
CC="xcrun -sdk ${SDK} clang -arch ${ARCH} -isysroot ${SYSROOT} -miphoneos-version-min=${MIN_IOS}"

# Write minimal test source
cat > "${VERIFY_DIR}/minimal_svn_test.c" <<'EOF'
#include <stdio.h>
#include "svn_client.h"
#include "svn_pools.h"
#include "svn_version.h"

int main(void) {
    const svn_version_t *version = svn_client_version();
    if (version == NULL) {
        fprintf(stderr, "svn_client_version returned NULL\n");
        return 1;
    }
    printf("libsvn OK: %d.%d.%d\n", version->major, version->minor, version->patch);
    return 0;
}
EOF

log "Compiling minimal_svn_test.c..."
${CC} -c "${VERIFY_DIR}/minimal_svn_test.c" -o "${VERIFY_DIR}/minimal_svn_test.o" \
  -I"${HEADERS}/subversion-1" \
  -I"${PREFIX}/include/apr-1" \
  -I"${PREFIX}/include/apr-util-1" \
  2>&1 | tee -a "${LOG_FILE}"

log "Linking against ${LIB}..."
${CC} "${VERIFY_DIR}/minimal_svn_test.o" -o "${VERIFY_DIR}/minimal_svn_test" \
  "${LIB}" \
  -L"${PREFIX}/lib" \
  -lz \
  -liconv \
  -framework CoreFoundation \
  -framework Security \
  -framework SystemConfiguration \
  2>&1 | tee -a "${LOG_FILE}"

log "Checking binary architecture..."
file "${VERIFY_DIR}/minimal_svn_test" | tee -a "${LOG_FILE}"
lipo -info "${VERIFY_DIR}/minimal_svn_test" 2>&1 | tee -a "${LOG_FILE}" || true

log "PASS: libsvn linked successfully for iOS device (arm64)."
