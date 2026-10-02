#!/usr/bin/env bash
# Builds the GitHub Pages site that serves Gutter's Flatpak repository:
#   <site>/repo/              the OSTree repository (already signed)
#   <site>/gutter.flatpakrepo adds the repository: flatpak remote-add
#   <site>/gutter.flatpakref  installs Gutter from it: flatpak install
#   <site>/index.html         how to install
# Usage: tool/make_flatpak_site.sh <repo> <site> <base-url> <public-key.gpg>
set -euo pipefail

repo=${1:?usage: make_flatpak_site.sh <repo> <site> <base-url> <public-key.gpg>}
site=${2:?}
url=${3%/}
key=${4:?}
if [[ ! -s "$key" ]]; then
  echo "No public key in $key" >&2
  exit 1
fi
app=dev.gutter.gutter
here=$(cd "$(dirname "$0")/.." && pwd)

mkdir -p "$site"
cp -a "$repo" "$site/repo"
cp "$here/linux/flatpak/icons/128.png" "$site/icon.png"
gpg_key=$(base64 -w0 < "$key")

cat > "$site/gutter.flatpakrepo" <<EOF
[Flatpak Repo]
Title=Gutter
Url=$url/repo/
Homepage=https://github.com/serjlee/gutter
Comment=A fast, local-only git client
Icon=$url/icon.png
GPGKey=$gpg_key
EOF

# The runtime comes from Flathub.
cat > "$site/gutter.flatpakref" <<EOF
[Flatpak Ref]
Name=$app
Branch=master
Title=Gutter
Url=$url/repo/
SuggestRemoteName=gutter
Homepage=https://github.com/serjlee/gutter
Icon=$url/icon.png
RuntimeRepo=https://dl.flathub.org/repo/flathub.flatpakrepo
IsRuntime=false
GPGKey=$gpg_key
EOF

cat > "$site/index.html" <<EOF
<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Gutter Flatpak repository</title>
<style>
  :root { color-scheme: light dark; }
  body { font: 16px/1.5 system-ui, sans-serif; max-width: 52rem;
         margin: 3rem auto; padding: 0 1rem; }
  pre { padding: .75rem 1rem; border-radius: 6px; overflow-x: auto;
        background: color-mix(in srgb, currentColor 8%, transparent); }
  img { vertical-align: middle; margin-right: .5rem; }
</style>
<h1><img src="icon.png" width="48" height="48" alt="">Gutter</h1>
<p>A fast, local-only git client. This is its Flatpak repository: install
Gutter from it once, and from then on it updates itself (or with
<code>flatpak update</code> and your software center).</p>
<h2>Install</h2>
<pre>flatpak install --user $url/gutter.flatpakref</pre>
<p>Or add the repository, then install from it:</p>
<pre>flatpak remote-add --user --if-not-exists gutter $url/gutter.flatpakrepo
flatpak install --user gutter $app</pre>
<p>The runtime comes from <a href="https://flathub.org">Flathub</a>. Gutter
runs your system's git, which needs to be installed.</p>
<p><a href="https://github.com/serjlee/gutter">Source, other platforms and
release notes</a></p>
EOF
echo "Site ready in $site"
