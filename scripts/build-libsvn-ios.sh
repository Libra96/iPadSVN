#!/usr/bin/env bash
# Build libsvn and dependencies as static libraries for iOS / iOS Simulator.
# Produces: build/output/libsvn.xcframework
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT}/build"
DEPS_DIR="${BUILD_DIR}/sources"
OUTPUT_DIR="${BUILD_DIR}/output"
INSTALL_ROOT="${BUILD_DIR}/install"
LOG_FILE="${BUILD_DIR}/build.log"

SVN_VERSION="1.14.5"
OPENSSL_VERSION="3.0.15"
MIN_IOS="16.0"

mkdir -p "${DEPS_DIR}" "${OUTPUT_DIR}" "${INSTALL_ROOT}"
: > "${LOG_FILE}"

log() {
  echo "[$(date '+%H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

die() {
  log "ERROR: $*"
  exit 1
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This script must run on macOS (use GitHub Actions if you are on Windows)."
  command -v xcodebuild >/dev/null || die "Xcode command line tools not found."
}

download() {
  local dest="$1"
  shift
  local url
  if [[ -f "${dest}" ]]; then
    log "Already downloaded: $(basename "${dest}")"
    return
  fi
  for url in "$@"; do
    log "Downloading $(basename "${dest}") from ${url}..."
    if curl -fsSL "${url}" -o "${dest}"; then
      return
    fi
    log "Failed: ${url}"
    rm -f "${dest}"
  done
  die "Failed to download $(basename "${dest}")"
}

extract_tar() {
  local archive="$1"
  local dest="$2"
  if [[ -d "${dest}" ]]; then
    log "Already extracted: $(basename "${dest}")"
    return
  fi
  log "Extracting $(basename "${archive}")..."
  tar -xf "${archive}" -C "${DEPS_DIR}"
}

setup_ios_env() {
  local platform="$1"
  local arch="$2"

  case "${platform}" in
    iphoneos)
      SDK="iphoneos"
      MIN_FLAG="-miphoneos-version-min=${MIN_IOS}"
      HOST="aarch64-apple-darwin"
      ;;
    iphonesimulator)
      SDK="iphonesimulator"
      MIN_FLAG="-mios-simulator-version-min=${MIN_IOS}"
      HOST="aarch64-apple-darwin"
      ;;
    *)
      die "Unknown platform: ${platform}"
      ;;
  esac

  SYSROOT="$(xcrun --sdk "${SDK}" --show-sdk-path)"
  PREFIX="${INSTALL_ROOT}/${platform}-${arch}"
  mkdir -p "${PREFIX}/lib" "${PREFIX}/include"

  export CC="xcrun -sdk ${SDK} clang -arch ${arch} -isysroot ${SYSROOT} ${MIN_FLAG}"
  export CXX="xcrun -sdk ${SDK} clang++ -arch ${arch} -isysroot ${SYSROOT} ${MIN_FLAG}"
  export AR="xcrun -sdk ${SDK} ar"
  export RANLIB="xcrun -sdk ${SDK} ranlib"
  export STRIP="xcrun -sdk ${SDK} strip"
  export LD="xcrun -sdk ${SDK} ld"
  export CFLAGS="-isysroot ${SYSROOT} -arch ${arch} ${MIN_FLAG} -O2"
  export CXXFLAGS="${CFLAGS}"
  export LDFLAGS="-isysroot ${SYSROOT} -arch ${arch} ${MIN_FLAG} -L${PREFIX}/lib"
  export CPPFLAGS="-isysroot ${SYSROOT} -I${PREFIX}/include"
  export PATH="${PREFIX}/bin:${PATH}"

  log "Platform=${platform} arch=${arch} prefix=${PREFIX}"
}

build_zlib() {
  log "Building zlib..."
  cd "${DEPS_DIR}/zlib-1.3.1"
  make clean >/dev/null 2>&1 || true
  CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" ./configure --static --prefix="${PREFIX}"
  make -j"$(sysctl -n hw.ncpu)" install
}

build_openssl() {
  log "Building OpenSSL..."
  cd "${DEPS_DIR}/openssl-${OPENSSL_VERSION}"

  local target
  case "${SDK}" in
    iphoneos) target="ios64-cross" ;;
    iphonesimulator) target="iossimulator-xcrun" ;;
    *) die "Unsupported SDK for OpenSSL: ${SDK}" ;;
  esac

  make clean >/dev/null 2>&1 || true
  ./Configure "${target}" \
    --prefix="${PREFIX}" \
    --openssldir="${PREFIX}" \
    no-shared no-dso no-hw no-engine no-tests \
    "${CFLAGS}"

  make -j"$(sysctl -n hw.ncpu)"
  make install_sw install_ssldirs
}

build_expat() {
  log "Building expat..."
  cd "${DEPS_DIR}/libexpat-R_2_6_2"
  ./buildconf.sh >/dev/null 2>&1 || true
  ./configure \
    --host="${HOST}" \
    --prefix="${PREFIX}" \
    --enable-static \
    --disable-shared \
    --without-docbook \
    CC="${CC}" \
    CFLAGS="${CFLAGS}" \
    LDFLAGS="${LDFLAGS}"
  make -j"$(sysctl -n hw.ncpu)" install
}

build_apr() {
  log "Building APR..."
  cd "${DEPS_DIR}/apr"
  make clean >/dev/null 2>&1 || true
  ./buildconf >/dev/null 2>&1 || true
  ./configure \
    --host="${HOST}" \
    --prefix="${PREFIX}" \
    --enable-static \
    --disable-shared \
    --disable-dso \
    --with-devrandom=/dev/urandom \
    CC="${CC}" \
    CFLAGS="${CFLAGS}" \
    LDFLAGS="${LDFLAGS}" \
    ac_cv_file__dev_zero=yes \
    ac_cv_func_setpgrp_void=yes \
    ac_cv_strerror_r_rc_int=yes \
    ac_cv_sizeof_struct_iovec=8 \
    apr_cv_mutex_recursive=yes \
    apr_cv_process_shared_works=no \
    apr_cv_mutex_robust_shared=no \
    apr_cv_tcp_nodelay_with_cork=yes
  # APR's libtool makefiles race under -jN during cross-compile (mmap.lo empty).
  make -j1 install
}

build_apr_util() {
  log "Building APR-util..."
  cd "${DEPS_DIR}/apr-util"
  make clean >/dev/null 2>&1 || true
  ./buildconf >/dev/null 2>&1 || true
  ./configure \
    --host="${HOST}" \
    --prefix="${PREFIX}" \
    --enable-static \
    --disable-shared \
    --with-apr="${PREFIX}" \
    --with-expat="${PREFIX}" \
    --with-openssl="${PREFIX}" \
    CC="${CC}" \
    CFLAGS="${CFLAGS}" \
    LDFLAGS="${LDFLAGS} -L${PREFIX}/lib" \
    CPPFLAGS="${CPPFLAGS} -I${PREFIX}/include/apr-1"
  make -j1 install
}

build_serf() {
  log "Building serf..."
  cd "${DEPS_DIR}/serf"
  make clean >/dev/null 2>&1 || true

  # serf SCons expects APR/APU install prefixes (finds bin/apr-1-config inside).
  export SERF_PREFIX="${PREFIX}"
  scons \
    PREFIX="${PREFIX}" \
    CC="${CC}" \
    CFLAGS="${CFLAGS} -I${PREFIX}/include/apr-1 -I${PREFIX}/include/apr-util-1" \
    LINKFLAGS="${LDFLAGS}" \
    APR="${PREFIX}" \
    APU="${PREFIX}" \
    OPENSSL="${PREFIX}" \
    ZLIB="${PREFIX}" \
    APR_STATIC=yes \
    install
}

build_sqlite_amalgamation() {
  log "Building sqlite amalgamation..."
  cd "${DEPS_DIR}/subversion-${SVN_VERSION}/sqlite-amalgamation"
  ${CC} -c -o sqlite3.o sqlite3.c \
    -DSQLITE_THREADSAFE=1 -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS4 \
    -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_UNLOCK_NOTIFY \
    ${CFLAGS}
  ${AR} rcs "${PREFIX}/lib/libsqlite3.a" sqlite3.o
  cp sqlite3.h sqlite3ext.h "${PREFIX}/include/"
}

patch_subversion_configure_expat() {
  local cfg="${DEPS_DIR}/subversion-${SVN_VERSION}/configure"
  # Cross-compiling cannot reliably pass Subversion's Expat link/compile probe.
  # BSD sed breaks on PREFIX paths containing slashes; use Python instead.
  python3 - "${cfg}" "${PREFIX}" <<'PY'
import sys

path, prefix = sys.argv[1], sys.argv[2]
old = '      as_fn_error $? "Expat not found" "$LINENO" 5'
new = (
    f'      svn_lib_expat=yes; SVN_XML_INCLUDES="-I{prefix}/include"; '
    f'SVN_XML_LIBS="-L{prefix}/lib -lexpat"; '
    r'{ $as_echo "$as_me:${as_lineno-$LINENO}: result: yes (iOS cross)" >&5; '
    r'$as_echo "yes" >&6; }'
)
text = open(path, encoding="utf-8").read()
if old not in text:
    sys.exit("Expat probe line not found in configure")
open(f"{path}.bak", "w", encoding="utf-8").write(text)
open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
PY
}

build_subversion() {
  log "Building Subversion (libsvn)..."
  cd "${DEPS_DIR}/subversion-${SVN_VERSION}"
  make clean >/dev/null 2>&1 || true
  patch_subversion_configure_expat

  ./configure \
    --host="${HOST}" \
    --prefix="${PREFIX}" \
    --disable-shared \
    --enable-static \
    --without-apache-mod \
    --without-swig \
    --without-javahl \
    --without-berkeley-db \
    --without-sasl \
    --with-utf8proc=internal \
    --with-serf="${PREFIX}" \
    --with-apr="${PREFIX}" \
    --with-apr-util="${PREFIX}" \
    --with-zlib="${PREFIX}" \
    --with-openssl="${PREFIX}" \
    --with-libs="${PREFIX}/lib" \
    --with-editor=none \
    CC="${CC}" \
    CFLAGS="${CFLAGS} -I${PREFIX}/include/apr-1 -I${PREFIX}/include/apr-util-1" \
    CPPFLAGS="${CPPFLAGS} -I${PREFIX}/include" \
    LDFLAGS="${LDFLAGS} -L${PREFIX}/lib" \
    ac_cv_path_EGREP=/usr/bin/grep \
    ac_cv_path_AWK=/usr/bin/awk

  make -j"$(sysctl -n hw.ncpu)" \
    CFLAGS="${CFLAGS} -include ${ROOT}/scripts/ios-svn-compat.h -I${PREFIX}/include/apr-1 -I${PREFIX}/include/apr-util-1" \
    install
}

merge_static_libs() {
  log "Merging static libraries into libsvn_merged.a..."
  cd "${PREFIX}/lib"
  local libs=()
  shopt -s nullglob
  for lib in libsvn_*.a libapr*.a libserf-*.a libexpat.a libz.a libsqlite3.a libssl.a libcrypto.a; do
    [[ -f "${lib}" ]] && libs+=("${lib}")
  done
  shopt -u nullglob

  if [[ ${#libs[@]} -eq 0 ]]; then
    die "No static libraries found to merge in ${PREFIX}/lib"
  fi

  log "Merging: ${libs[*]}"
  libtool -static -o libsvn_merged.a "${libs[@]}"
  log "Merged library size: $(du -h libsvn_merged.a | cut -f1)"
}

prepare_sources() {
  log "Preparing source trees..."
  cd "${DEPS_DIR}"

  download "subversion-${SVN_VERSION}.tar.bz2" \
    "https://dlcdn.apache.org/subversion/subversion-${SVN_VERSION}.tar.bz2" \
    "https://downloads.apache.org/subversion/subversion-${SVN_VERSION}.tar.bz2" \
    "https://archive.apache.org/dist/subversion/subversion-${SVN_VERSION}.tar.bz2"
  extract_tar "subversion-${SVN_VERSION}.tar.bz2" "subversion-${SVN_VERSION}"

  download "zlib-1.3.1.tar.gz" \
    "https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz" \
    "https://zlib.net/fossils/zlib-1.3.1.tar.gz"
  extract_tar "zlib-1.3.1.tar.gz" "zlib-1.3.1"

  download "expat-2.6.2.tar.bz2" \
    "https://github.com/libexpat/libexpat/releases/download/R_2_6_2/expat-2.6.2.tar.bz2"
  if [[ ! -d "libexpat-R_2_6_2" ]]; then
    tar -xf expat-2.6.2.tar.bz2
    mv expat-2.6.2 libexpat-R_2_6_2
  fi

  download "openssl-${OPENSSL_VERSION}.tar.gz" \
    "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" \
    "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
  extract_tar "openssl-${OPENSSL_VERSION}.tar.gz" "openssl-${OPENSSL_VERSION}"

  # Fetch APR, APR-util, serf, sqlite via Subversion's get-deps.sh (HTTP only, no svn CLI)
  cd "${DEPS_DIR}/subversion-${SVN_VERSION}"
  if [[ ! -d apr || ! -f sqlite-amalgamation/sqlite3.c ]]; then
    log "Running get-deps.sh for APR/APR-util/serf/sqlite..."
    chmod +x ./get-deps.sh
    export APR_VERSION="1.7.5"
    export APU_VERSION="1.6.3"
    export SERF_VERSION="1.3.10"
    ./get-deps.sh apr serf sqlite
  fi

  ln -sfn "${DEPS_DIR}/subversion-${SVN_VERSION}/apr" "${DEPS_DIR}/apr"
  ln -sfn "${DEPS_DIR}/subversion-${SVN_VERSION}/apr-util" "${DEPS_DIR}/apr-util"
  ln -sfn "${DEPS_DIR}/subversion-${SVN_VERSION}/serf" "${DEPS_DIR}/serf"
}

build_for_platform() {
  local platform="$1"
  local arch="$2"

  setup_ios_env "${platform}" "${arch}"

  build_zlib
  build_openssl
  build_expat
  build_apr
  build_apr_util
  build_serf
  build_sqlite_amalgamation
  build_subversion
  merge_static_libs

  log "Done: ${PREFIX}/lib/libsvn_merged.a"
}

create_xcframework() {
  log "Creating libsvn.xcframework..."
  local device_lib="${INSTALL_ROOT}/iphoneos-arm64/lib/libsvn_merged.a"
  local sim_lib="${INSTALL_ROOT}/iphonesimulator-arm64/lib/libsvn_merged.a"
  local headers="${INSTALL_ROOT}/iphoneos-arm64/include"

  [[ -f "${device_lib}" ]] || die "Missing device library: ${device_lib}"
  [[ -f "${sim_lib}" ]] || die "Missing simulator library: ${sim_lib}"
  [[ -d "${headers}" ]] || die "Missing headers: ${headers} (expected after make install)"

  rm -rf "${OUTPUT_DIR}/libsvn.xcframework"
  xcodebuild -create-xcframework \
    -library "${device_lib}" -headers "${headers}" \
    -library "${sim_lib}" -headers "${headers}" \
    -output "${OUTPUT_DIR}/libsvn.xcframework"

  log "XCFramework created at ${OUTPUT_DIR}/libsvn.xcframework"
}

write_summary() {
  local summary="${BUILD_DIR}/build-summary.txt"
  {
    echo "libsvn iOS Build Summary"
    echo "========================"
    echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Subversion: ${SVN_VERSION}"
    echo "OpenSSL: ${OPENSSL_VERSION}"
    echo "Min iOS: ${MIN_IOS}"
    echo ""
    echo "Artifacts:"
    find "${OUTPUT_DIR}" -type f 2>/dev/null || true
    echo ""
    echo "Library sizes:"
    du -h "${INSTALL_ROOT}"/*/lib/libsvn_merged.a 2>/dev/null || true
  } | tee "${summary}"
}

main() {
  require_macos
  log "Starting libsvn iOS cross-compilation..."
  log "Root: ${ROOT}"

  prepare_sources
  build_for_platform "iphoneos" "arm64"
  build_for_platform "iphonesimulator" "arm64"
  create_xcframework
  write_summary

  log "SUCCESS: libsvn iOS build completed."
}

main "$@"
