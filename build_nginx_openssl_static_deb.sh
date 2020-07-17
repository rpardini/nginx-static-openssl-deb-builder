#! /bin/bash

logInfo() {
    echo "LOG: INFO: $@"
}

logWarn() {
    echo "LOG: WARN: $@"
}

set -e

# Defaults.
MY_ARCH=$(dpkg --print-architecture)
OPENSSL_VERSION_DEFAULT="1.1.1g"
NGINX_BASE_VERSION_DEFAULT="1.18.0"
NGINX_PACKAGE_DISTRO=$(lsb_release -c -s)
NGINX_PACKAGE_SUFFIX_DEFAULT="-1~${NGINX_PACKAGE_DISTRO}"
NGINX_EXTRA_SUFFIX="-rp6"
NGINX_PACKAGE_TAR_FORMAT="tar.xz"
DPKG_SOURCE_EXTRACT="--extract"
ADD_STACK_PROTECTOR="-fstack-protector-strong"
FORCE_UPGRADE_SOURCES_TO=""

# Trusty needs hacks. 1) latest available prepackaged is 1.16.0
if [[ "${NGINX_PACKAGE_DISTRO}" == "trusty" ]]; then
  logWarn "Enabling trusty hacks..."
  FORCE_UPGRADE_SOURCES_TO="${NGINX_BASE_VERSION_DEFAULT}"
  NGINX_BASE_VERSION_DEFAULT="1.16.0"                                                      # This is the latest released nginx version for trusty.
  NGINX_PACKAGE_TAR_FORMAT="tar.gz"                                                        # Trusty published sources in tar.gz, not tar.xz format
  DPKG_SOURCE_EXTRACT="-x"                                                                 # Trusty's dpkg-source did not know --extract, but -x is the same
  ADD_STACK_PROTECTOR="-fstack-protector"                                                  # Trusty's gcc did not have -fstack-protector-strong so we do our best
  NGINX_FINAL_PACKAGE_VERSION="${FORCE_UPGRADE_SOURCES_TO}${NGINX_PACKAGE_SUFFIX_DEFAULT}" # Make the final package have the correct version
fi

DO_INSTALL=${DO_INSTALL:-no}
ADD_RTMP=${ADD_RTMP:-no}
ADD_XSLT=${ADD_XSLT:-no}
OPENSSL_VERSION=${OPENSSL_VERSION:-"${OPENSSL_VERSION_DEFAULT}"}
NGINX_BASE_VERSION=${NGINX_BASE_VERSION:-"${NGINX_BASE_VERSION_DEFAULT}"}
NGINX_PACKAGE_SUFFIX=${NGINX_PACKAGE_SUFFIX:-"${NGINX_PACKAGE_SUFFIX_DEFAULT}"}
NGINX_PACKAGE_VERSION="${NGINX_BASE_VERSION}${NGINX_PACKAGE_SUFFIX}"
NGINX_FINAL_PACKAGE_VERSION="${NGINX_FINAL_PACKAGE_VERSION:-"${NGINX_PACKAGE_VERSION}"}"

BUILD_DIR=/usr/src/nginx_openssl_tlsv13
OPENSSL_SOURCE_DIR=${BUILD_DIR}/openssl-${OPENSSL_VERSION}
NGINX_PACKAGE_DIR="${BUILD_DIR}/nginx-${NGINX_BASE_VERSION}"
BASE_URL_NGINX_STABLE="http://nginx.org/packages/ubuntu/pool/nginx/n/nginx"
BASE_URL_NGINX_MAINLINE="http://nginx.org/packages/mainline/ubuntu/pool/nginx/n/nginx/"

logInfo "Using MY_ARCH: ${MY_ARCH} [autocalc]"
logInfo "Using BUILD_DIR: ${BUILD_DIR} [hardcoded]"
logInfo "Using DO_INSTALL: ${DO_INSTALL} [change by setting env var]"
logInfo "Using ADD_RTMP: ${ADD_RTMP} [change by setting env var]"
logInfo "Using OPENSSL_VERSION: ${OPENSSL_VERSION} [change by setting env var]"
logInfo "Using NGINX_BASE_VERSION: ${NGINX_BASE_VERSION}  [change by setting env var]"
logInfo "Using NGINX_PACKAGE_SUFFIX: ${NGINX_PACKAGE_SUFFIX}  [change by setting env var]"
logInfo "Using NGINX_PACKAGE_VERSION: ${NGINX_PACKAGE_VERSION} [autocalc]"
logInfo "Using OPENSSL_SOURCE_DIR: ${OPENSSL_SOURCE_DIR} [autocalc]"
logInfo "Using NGINX_PACKAGE_DIR: ${NGINX_PACKAGE_DIR} [autocalc]"
NGINX_MINOR_VERSION="$(echo "${NGINX_BASE_VERSION}" | cut -d "." -f 2)"
BASE_URL_NGINX=${BASE_URL_NGINX_MAINLINE}
if [ $((NGINX_MINOR_VERSION % 2)) -eq 0 ]; then
  BASE_URL_NGINX=${BASE_URL_NGINX_STABLE}
fi
logInfo "Using BASE_URL_NGINX: ${BASE_URL_NGINX} [autocalc]"

logInfo "Preparing build dir and cleaning old build dirs and artifacts..."
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"
[[ -d ${OPENSSL_SOURCE_DIR} ]] && rm -rf "${OPENSSL_SOURCE_DIR}"
[[ -d ${NGINX_PACKAGE_DIR} ]] && rm -rf "${NGINX_PACKAGE_DIR}"
rm -f ${BUILD_DIR}/*.changes ${BUILD_DIR}/*.deb || true

logInfo "Downloading sources and source packages..."
[[ ! -f ${BUILD_DIR}/openssl-${OPENSSL_VERSION}.tar.gz ]] && wget -O "${BUILD_DIR}/openssl-${OPENSSL_VERSION}.tar.gz" "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
[[ ! -f ${BUILD_DIR}/nginx_${NGINX_PACKAGE_VERSION}.debian.${NGINX_PACKAGE_TAR_FORMAT} ]] && wget -O "${BUILD_DIR}/nginx_${NGINX_PACKAGE_VERSION}.debian.${NGINX_PACKAGE_TAR_FORMAT}" ${BASE_URL_NGINX}/nginx_${NGINX_PACKAGE_VERSION}.debian.${NGINX_PACKAGE_TAR_FORMAT}
[[ ! -f ${BUILD_DIR}/nginx_${NGINX_PACKAGE_VERSION}.dsc ]] && wget -O "${BUILD_DIR}/nginx_${NGINX_PACKAGE_VERSION}.dsc" ${BASE_URL_NGINX}/nginx_${NGINX_PACKAGE_VERSION}.dsc
[[ ! -f ${BUILD_DIR}/nginx_${NGINX_BASE_VERSION}.orig.tar.gz ]] && wget -O "${BUILD_DIR}/nginx_${NGINX_BASE_VERSION}.orig.tar.gz" ${BASE_URL_NGINX}/nginx_${NGINX_BASE_VERSION}.orig.tar.gz

if [[ "a${FORCE_UPGRADE_SOURCES_TO}" != "a" ]]; then
  logWarn "Downloading force-update source package ${FORCE_UPGRADE_SOURCES_TO} "
  [[ ! -f ${BUILD_DIR}/nginx_${FORCE_UPGRADE_SOURCES_TO}.orig.tar.gz ]] && wget -O "${BUILD_DIR}/nginx_${FORCE_UPGRADE_SOURCES_TO}.orig.tar.gz" ${BASE_URL_NGINX}/nginx_${FORCE_UPGRADE_SOURCES_TO}.orig.tar.gz
fi

if [[ "a${ADD_RTMP}" == "ayes" ]]; then
  logInfo "Cloning RTMP module..."
  cd "${BUILD_DIR}"
  git clone https://github.com/arut/nginx-rtmp-module.git
  RTMP_MODULE_DIR=${BUILD_DIR}/nginx-rtmp-module
else
  logInfo "RTMP module not enabled."
fi

logInfo "Unpacking..."
cd "${BUILD_DIR}"
tar xzf "openssl-${OPENSSL_VERSION}.tar.gz"
[[ -d ${OPENSSL_SOURCE_DIR} ]] || {
  logError "Extraction did not produce expected OPENSSL_SOURCE_DIR ${OPENSSL_SOURCE_DIR}"
  exit 3
}

cd "${BUILD_DIR}"
dpkg-source --no-check ${DPKG_SOURCE_EXTRACT} "nginx_${NGINX_PACKAGE_VERSION}.dsc"
[[ -d ${NGINX_PACKAGE_DIR} ]] || {
  logError "Extraction did not produce expected NGINX_PACKAGE_DIR ${NGINX_PACKAGE_DIR}"
  exit 3
}

if [[ "a${FORCE_UPGRADE_SOURCES_TO}" != "a" ]]; then
  logInfo "Source version before forcing upgrade: "
  cat ${NGINX_PACKAGE_DIR}/src/core/nginx.h | grep NGINX_VERSION
  logWarn "Overriding sources with those from ${FORCE_UPGRADE_SOURCES_TO}"
  cd "${BUILD_DIR}"
  [[ -d "${BUILD_DIR}/source-upgrade-${FORCE_UPGRADE_SOURCES_TO}" ]] && rm -rf "${BUILD_DIR}/source-upgrade-${FORCE_UPGRADE_SOURCES_TO}"
  mkdir "${BUILD_DIR}/source-upgrade-${FORCE_UPGRADE_SOURCES_TO}"
  cd "${BUILD_DIR}/source-upgrade-${FORCE_UPGRADE_SOURCES_TO}"
  tar xzf ${BUILD_DIR}/nginx_${FORCE_UPGRADE_SOURCES_TO}.orig.tar.gz
  cp -r ${BUILD_DIR}/source-upgrade-${FORCE_UPGRADE_SOURCES_TO}/nginx-${FORCE_UPGRADE_SOURCES_TO}/* ${NGINX_PACKAGE_DIR}/
  logInfo "Source version AFTER forcing upgrade: "
  cat ${NGINX_PACKAGE_DIR}/src/core/nginx.h | grep NGINX_VERSION
fi

logInfo "Now patching Server: header in nginx for HTTP v1..."
cd "${NGINX_PACKAGE_DIR}"

cat <<'EOD' | patch -p0
--- src/http/ngx_http_header_filter_module.c       2019-08-13 14:51:43.000000000 +0200
+++ src/http/ngx_http_header_filter_module.c       2020-03-31 02:08:18.160487422 +0200
@@ -279,7 +279,7 @@

     clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

-    if (r->headers_out.server == NULL) {
+    if (0 == 1) {
         if (clcf->server_tokens == NGX_HTTP_SERVER_TOKENS_ON) {
             len += sizeof(ngx_http_server_full_string) - 1;

@@ -448,7 +448,7 @@
     }
     *b->last++ = CR; *b->last++ = LF;

-    if (r->headers_out.server == NULL) {
+    if (0 == 1) {
         if (clcf->server_tokens == NGX_HTTP_SERVER_TOKENS_ON) {
             p = ngx_http_server_full_string;
             len = sizeof(ngx_http_server_full_string) - 1;


EOD

logInfo "Patching done for Server: header for HTTP v1."

logInfo "Now patching Server: header in nginx for HTTP v2..."
cd "${NGINX_PACKAGE_DIR}"
cat <<'EOD' | patch -p0
--- src/http/v2/ngx_http_v2_filter_module.c     2020-03-31 04:26:34.815493201 +0200
+++ src/http/v2/ngx_http_v2_filter_module.c     2020-03-31 04:27:56.871878980 +0200
@@ -259,7 +259,7 @@

     clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

-    if (r->headers_out.server == NULL) {
+    if (0 == 1) {

         if (clcf->server_tokens == NGX_HTTP_SERVER_TOKENS_ON) {
             len += 1 + nginx_ver_len;
@@ -463,7 +463,7 @@
         pos = ngx_sprintf(pos, "%03ui", r->headers_out.status);
     }

-    if (r->headers_out.server == NULL) {
+    if (0 == 1) {

         if (clcf->server_tokens == NGX_HTTP_SERVER_TOKENS_ON) {
             ngx_log_debug1(NGX_LOG_DEBUG_HTTP, fc->log, 0,
EOD
logInfo "Patching done for Server: header for HTTP v2."

logInfo "Creating a new Changelog for Package, so we get a marker version built."
cat <<EOD >"${NGINX_PACKAGE_DIR}/debian/changelog"
nginx (${NGINX_FINAL_PACKAGE_VERSION}${NGINX_EXTRA_SUFFIX}) ${NGINX_PACKAGE_DISTRO}; urgency=low

  * ${NGINX_FINAL_PACKAGE_VERSION} plus my patches.
  * Built with static OpenSSL version ${OPENSSL_VERSION}
  * This nginx does not write "Server:" headers.

 -- Ricardo Pardini <ricardo@pardini.net>  Tue, 13 Aug 2019 13:05:00 +0300

EOD

logInfo "Here is the final changelog:"
cat "${NGINX_PACKAGE_DIR}/debian/changelog"

logInfo "Removing libssl-dev as a dependency from control, we're building it static after all ..."
cat "${NGINX_PACKAGE_DIR}/debian/control" | grep -v libssl-dev >"${NGINX_PACKAGE_DIR}/debian/control.new"
mv "${NGINX_PACKAGE_DIR}/debian/control.new" "${NGINX_PACKAGE_DIR}/debian/control"

logInfo "Now patching debian/rules for nginx ${NGINX_BASE_VERSION}"
cd "${BUILD_DIR}"

[[ ! -f ${NGINX_PACKAGE_DIR}/debian/rules.orig ]] && cp "${NGINX_PACKAGE_DIR}/debian/rules" "${NGINX_PACKAGE_DIR}/debian/rules.orig"

# We need -Wno-error=missing-field-initializers when compiling OpenSSL together with nginx.
sed -i -e 's/CFLAGS=""/CFLAGS="-Wno-error=missing-field-initializers"/g' "${NGINX_PACKAGE_DIR}/debian/rules"

# Add OpenSSL-related options to configure lines.
EXTRA_CONFIGURE_OPT_OPENSSL="--with-openssl=\"${OPENSSL_SOURCE_DIR}\""

# If enabled, add the module for rtmp
if [[ "a${ADD_RTMP}" == "ayes" ]]; then
  logInfo "Enabling RTMP module..."
  EXTRA_CONFIGURE_OPT_OPENSSL="${EXTRA_CONFIGURE_OPT_OPENSSL} --add-module=\"${RTMP_MODULE_DIR}\""
fi

# If enabled, add the module for rtmp
if [[ "a${ADD_XSLT}" == "ayes" ]]; then
  logInfo "Enabling XSLT module..."
  EXTRA_CONFIGURE_OPT_OPENSSL="${EXTRA_CONFIGURE_OPT_OPENSSL} --with-http_xslt_module"
fi

EXTRA_CONFIGURE_OPT_OPENSSL=$(echo "${EXTRA_CONFIGURE_OPT_OPENSSL}" | sed -e 's/\//\\\//g') # Double escape forward slashes
EXTRA_CONFIGURE_OPT_OPENSSL_OPT="--with-openssl-opt=\"enable-ssl3 enable-ssl3-method enable-weak-ssl-ciphers no-shared -DOPENSSL_NO_HEARTBEATS ${ADD_STACK_PROTECTOR}\""
SEARCH_STR="\.\/configure"
sed -i -e "s/${SEARCH_STR}/${SEARCH_STR} ${EXTRA_CONFIGURE_OPT_OPENSSL} ${EXTRA_CONFIGURE_OPT_OPENSSL_OPT}/g" "${NGINX_PACKAGE_DIR}/debian/rules"

logInfo "Resulting patch file: "
diff -u "${NGINX_PACKAGE_DIR}/debian/rules.orig" "${NGINX_PACKAGE_DIR}/debian/rules" || true

logInfo "Building nginx package..."
cd "${NGINX_PACKAGE_DIR}"
# Building nginx together with openssl requires a single thread (-j1). it is really, really slow.
# @TODO: I dunno if eatmydata makes it any faster (it does under bare metal, but under docker+qemu I doubt it)
eatmydata dpkg-buildpackage -b -us -uc -j1

logInfo "Calling sync..."
sync

logWarn "Package was built, but not installed."
logWarn "To install, use: dpkg -i ${BUILD_DIR}/nginx_${NGINX_FINAL_PACKAGE_VERSION}${NGINX_EXTRA_SUFFIX}_${MY_ARCH}.deb && apt-mark hold nginx"

logInfo "Done..."
