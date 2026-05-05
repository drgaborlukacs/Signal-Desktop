#!/bin/bash
# Lay out the Slackware package tree from release/linux-unpacked/, strip ELFs,
# and run /sbin/makepkg. Mirrors the original signal-desktop-selfcompiled
# SlackBuild's output.
#
# Required env vars (set by the calling workflow):
#   PRGNAM, BINNAME, VERSION, ARCH, BUILD, TAG, PKGTYPE
#   SRC_DIR     -- path to checked-out Signal-Desktop repo
#   RELEASE_DIR -- path to release/linux-unpacked/
#   OUT_DIR     -- where the .${PKGTYPE} ends up
set -eux

PKG=/tmp/package-${PRGNAM}
rm -rf "$PKG"
install -d "$PKG/opt/Signal" "$PKG/usr/bin" \
           "$PKG/usr/doc/${PRGNAM}-${VERSION}" "$PKG/install"

cp -a "$RELEASE_DIR"/. "$PKG/opt/Signal/"
ln -sf ../../opt/Signal/signal-desktop "$PKG/usr/bin/${BINNAME}"

# Docs (matches the original SlackBuild)
for f in LICENSE.electron.txt LICENSES.chromium.html; do
  [ -f "$PKG/opt/Signal/$f" ] && cp "$PKG/opt/Signal/$f" "$PKG/usr/doc/${PRGNAM}-${VERSION}/"
done
if [ -f "$PKG/opt/Signal/resources/app-update.yml" ]; then
  gzip -c "$PKG/opt/Signal/resources/app-update.yml" \
    > "$PKG/usr/doc/${PRGNAM}-${VERSION}/changelog.gz"
fi

# CI-equivalent of the SlackBuild's "ship the build recipe" line: copy the
# workflow + checked-in helper files into the docs dir.
cp "$SRC_DIR/.github/workflows/fork-build-slackware.yml"     "$PKG/usr/doc/${PRGNAM}-${VERSION}/"
cp "$SRC_DIR/.github/slackware/install-build-tools.sh"        "$PKG/usr/doc/${PRGNAM}-${VERSION}/"
cp "$SRC_DIR/.github/slackware/build-package.sh"              "$PKG/usr/doc/${PRGNAM}-${VERSION}/"
cp "$SRC_DIR/.github/slackware/slack-desc"                    "$PKG/usr/doc/${PRGNAM}-${VERSION}/"
cp "$SRC_DIR/.github/slackware/doinst.sh"                     "$PKG/usr/doc/${PRGNAM}-${VERSION}/"

# Conditional copies preserved from the original SlackBuild (no-ops for
# --linux dir output; kept for parity).
if [ -f "$PKG/opt/Signal/resources/signal-desktop.desktop" ]; then
  install -d "$PKG/usr/share/applications"
  cp "$PKG/opt/Signal/resources/signal-desktop.desktop" "$PKG/usr/share/applications/"
fi
if [ -d "$PKG/opt/Signal/resources/icons" ]; then
  install -d "$PKG/usr/share/icons/hicolor"
  cp -a "$PKG/opt/Signal/resources/icons/." "$PKG/usr/share/icons/hicolor/" 2>/dev/null || true
fi

install -m 0644 "$SRC_DIR/.github/slackware/slack-desc" "$PKG/install/slack-desc"
install -m 0755 "$SRC_DIR/.github/slackware/doinst.sh"  "$PKG/install/doinst.sh"

# Strip ELFs by ELF magic, not by `file`(1). Skip .node addons.
find "$PKG" -type f ! -name '*.node' ! -name '*.so*' -perm -u+x -print0 \
  | xargs -0 -I{} sh -c '
      head -c4 "{}" 2>/dev/null | grep -q "^.ELF" && strip --strip-unneeded "{}" 2>/dev/null || true
    '
find "$PKG" -type f -name '*.so*' -print0 \
  | xargs -0 -I{} strip --strip-unneeded "{}" 2>/dev/null || true

mkdir -p "$OUT_DIR"
OUT=${OUT_DIR}/${PRGNAM}-${VERSION}-${ARCH}-${BUILD}${TAG}.${PKGTYPE}
( cd "$PKG" && /sbin/makepkg -l y -c y "$OUT" )
ls -lh "$OUT"
