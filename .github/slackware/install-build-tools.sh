#!/bin/bash
# Install everything the Slackware 15.0 CI build needs and verify the result.
# aclemons/slackware:15.0 is minimal, slackpkg has no transitive-dep resolution,
# and slackpkg exits 0 even when a package isn't in the repo. So: install
# everything up front, then verify each requested package landed, each tool
# we'll invoke is on PATH, and each tool's shared-lib closure resolves.
set -eux

sed -i \
  -e 's/^CHECKGPG=.*/CHECKGPG=off/' \
  -e 's/^BATCH=.*/BATCH=on/' \
  -e 's/^DEFAULT_ANSWER=.*/DEFAULT_ANSWER=y/' \
  /etc/slackpkg/slackpkg.conf

slackpkg -batch=on -default_answer=y update

# Every entry verified to exist in
# http://slackware.osuosl.org/slackware64-15.0/slackware64/PACKAGES.TXT.
# Anything not in the main repo is downloaded separately by the workflow
# (protoc from GitHub, cmake from Kitware, Node from nodejs.org, rustup via sh).
PACKAGES=(
  # Compilers + build tools
  gcc gcc-g++ make binutils cmake
  # Autotools (some npm native modules use ./configure)
  bison flex m4 autoconf automake libtool pkg-config
  # Languages
  python3 perl llvm
  # Headers / libc
  glibc kernel-headers
  # Network + HTTPS deps for git/curl/wget
  git curl wget nghttp2 ca-certificates cyrus-sasl libssh2 brotli openssl
  # Compression
  xz tar gzip bzip2 zlib libarchive lz4
  # Shared libs that build tools dynamically link to.
  # libguile/gc -> make ; lz4/libxml2 -> cmake ; elfutils -> objdump.
  guile gc libxml2 elfutils
  # Common shared-lib transitives that other packages dlopen/link
  expat libffi libuv ncurses readline jansson
  # Misc utilities required by build scripts
  file patchelf which
)
slackpkg -batch=on -default_answer=y install "${PACKAGES[@]}"

# Generate /etc/ssl/certs/ca-certificates.crt -- slackpkg in batch mode
# doesn't always run package doinst.sh.
/usr/sbin/update-ca-certificates --fresh
test -s /etc/ssl/certs/ca-certificates.crt

# Verify every package we requested actually got installed.
shopt -s nullglob
missing_pkgs=()
for pkg in "${PACKAGES[@]}"; do
  files=( /var/log/packages/${pkg}-[0-9]* )
  [ ${#files[@]} -gt 0 ] || missing_pkgs+=("$pkg")
done
if [ ${#missing_pkgs[@]} -gt 0 ]; then
  echo "::error::slackpkg silently skipped these packages (not in Slackware 15.0 repo?): ${missing_pkgs[*]}"
  echo "Installed packages:"
  ls /var/log/packages/ | sort
  exit 1
fi

# Verify every command the rest of the workflow will invoke.
missing_cmds=()
for cmd in git curl wget gcc g++ make cmake flex bison m4 autoconf automake \
           libtool pkg-config patchelf python3 perl xz tar gzip bzip2 file \
           strip objdump which; do
  command -v "$cmd" >/dev/null 2>&1 || missing_cmds+=("$cmd")
done
if [ ${#missing_cmds[@]} -gt 0 ]; then
  echo "::error::missing commands on PATH after install: ${missing_cmds[*]}"
  exit 1
fi

# Verify each tool's shared-lib closure resolves -- a tool can be installed
# yet still fail to launch with "libfoo.so: cannot open shared object file"
# the first time it's invoked deep into a build script.
broken=()
for cmd in gcc g++ make cmake git curl wget patchelf python3 perl ar strip objdump; do
  bin=$(command -v "$cmd")
  if ldd "$bin" 2>&1 | grep -q "not found"; then
    echo "Broken shared-lib closure for $cmd ($bin):"
    ldd "$bin" | grep "not found" | sed 's/^/  /'
    broken+=("$cmd")
  fi
done
if [ ${#broken[@]} -gt 0 ]; then
  echo "::error::tools with unresolved shared libs: ${broken[*]}"
  exit 1
fi
