# Gutter

A fast git client for macOS and Linux, inspired by GitKraken. Built with
Flutter on top of your system `git`: no accounts, no cloud features.

> **Disclaimer:** This app was heavily vibe coded with Claude Opus 5.5. Mostly out of spite of GitKraken becoming ever so bloated and unstable.

![Commit graph](docs/graph.png)

## Install

Download the latest build from the
[Releases](https://github.com/serjlee/gutter/releases) page. Gutter needs
`git` installed.

- **macOS** (`Gutter-macos-<version>.zip`, Apple Silicon and Intel): move
  `Gutter.app` to `/Applications`, then clear the quarantine flag (the app
  isn't notarized):
  `xattr -dr com.apple.quarantine /Applications/Gutter.app`
- **Linux, Flatpak**: `flatpak install --user gutter-linux-x64-<version>.flatpak`
- **Linux, tarball**: extract `gutter-linux-x64-<version>.tar.gz` and run
  `./gutter` (needs GTK 3).

<details>
<summary>More on installing</summary>

**macOS.** Gutter is ad-hoc signed, not notarized (there's no paid Apple
Developer account behind it), so macOS blocks it until the quarantine flag
is cleared, after every update. Besides the `xattr` command:

- `tool/install_macos.sh` downloads the latest release (needs `gh`),
  installs it and clears the flag. It also takes a downloaded zip:
  `tool/install_macos.sh ~/Downloads/Gutter-macos-0.1.0.zip`.
- Or open Gutter once, then System Settings → Privacy & Security →
  **Open Anyway**. On macOS 15 and later, right-click → Open no longer
  bypasses the block.

Install git with `xcode-select --install` or Homebrew. The first time you
scan a folder under Documents or Desktop, macOS asks for access. The app
isn't sandboxed (`macos/Runner/*.entitlements`): it runs `git` and reads
repositories anywhere on disk.

**Flatpak.** It fetches the Freedesktop runtime from Flathub. Gutter runs
your system's git through `flatpak-spawn --host`, so your config,
credential helpers, signing keys and hooks work as in a terminal, and it
can read files anywhere (`--filesystem=host`).

**Which git.** Gutter looks on `PATH`, then in `/opt/homebrew/bin`,
`/usr/local/bin` and `/usr/bin` (Homebrew's first on macOS: apps opened
from Finder don't get your shell's `PATH`, and `/usr/bin/git` needs
Apple's command line tools). You can pick another on the home tab.

</details>

## Features

- **Commit graph**: lane-colored branches, merged local/remote ref labels,
  tags, a WIP row, stashes next to the commit they were made on, author
  pictures (GitHub avatars, or initials), search and keyboard navigation.
  History loads in batches as you scroll.
- **Tabs**, one per repository, restored on start. Only the active tab
  auto-fetches.
- **Repository discovery**: every repository under a folder is found in
  the background. Open, clone or init from the home tab.
- **Staging** of files, hunks or single lines.
- **Diffs**: unified, split or full file (images too), with optional
  syntax highlighting.
- **Branches and history**: checkout (double-click; on a remote branch it
  updates the local one), branches and tags, merge, rebase, cherry-pick,
  revert, reset, stash, pull and push (with force push, from the toolbar
  or a branch's menu).
- **Multiple commits**: Shift/Ctrl-click to cherry-pick several commits or
  squash them.
- **Interactive rebase** without a text editor, with keyboard shortcuts
  and actions on several commits at once.
- **Conflicts**: continue / skip / abort, take ours or theirs per file.
- **Errors explained**, with the full output one click away in each tab's
  **Output** panel, which logs every git command it ran.
- **UI zoom** for high-DPI screens.

<details>
<summary>Screenshots</summary>

![Home tab](docs/dashboard.png)
![Line staging](docs/line-staging.png)
![Diff with syntax highlighting](docs/diff-highlight.png)
![Interactive rebase](docs/interactive-rebase.png)

</details>

<details>
<summary>Keyboard shortcuts</summary>

| Keys | Action |
| --- | --- |
| `Ctrl/Cmd T` | Repositories (home) tab |
| `Ctrl/Cmd O` | Open repository |
| `Ctrl/Cmd W` | Close tab |
| `Ctrl Tab` / `Ctrl Shift Tab` | Next / previous tab |
| `Ctrl/Cmd 1…9` | Go to tab |
| `Ctrl/Cmd R`, `F5` | Refresh |
| `Ctrl/Cmd F` | Search commits (`Enter` / `Shift Enter` to step) |
| `↑ ↓ PgUp PgDn Home End` | Move through the graph |
| `Ctrl/Cmd Enter` | Commit (in the message box) |
| `Esc`, mouse back button | Close diff |
| `P R E S F D` | Interactive rebase: pick / reword / edit / squash / fixup / drop the selected commits |
| `Alt ↑ ↓` | Interactive rebase: move the selected commits |
| `Ctrl/Cmd + / - / 0` | Zoom in / out / reset (or `Ctrl/Cmd` + mouse wheel) |

</details>

<details>
<summary>Performance</summary>

git's output is parsed off the UI thread, the graph is laid out in an
isolate in compact typed arrays, and only visible rows are painted: the
85k commits of git.git take about 1.5 MB and lay out in about 130 ms. A
large repository without a commit-graph file gets one, which makes
loading history several times faster.

</details>

## Network and privacy

Besides your own fetch, pull and push, Gutter makes two kinds of requests:

- **Update check**: every 6 hours it asks GitHub for the latest release of
  Gutter, and shows a link on the home tab when there's a newer one.
- **GitHub avatars** (repositories on GitHub only): each author's picture
  is requested from GitHub's avatar server by commit email, as rows come
  into view. Emails without a GitHub account keep their initials, and that
  answer is remembered for a week (`avatars.json`, next to the settings).
  Can be turned off on the home tab.

Fetch, pull and push use your git setup (SSH agent, credential helper).
Gutter never shows a password prompt: an operation that needs one fails
with an explanation instead of hanging.

## Development

You need Flutter (stable) and git; on Linux also
`clang cmake ninja-build pkg-config libgtk-3-dev`.

```sh
flutter run -d macos          # or: -d linux
flutter analyze && flutter test
```

<details>
<summary>More commands, layout and releases</summary>

```sh
xvfb-run flutter drive --profile -d linux \
  --driver test_driver/integration_test.dart \
  --target integration_test/app_test.dart         # real app, AOT-compiled
dart run tool/bench_layout.dart 200000            # graph layout benchmark
dart run tool/bench_repo.dart /path/to/big/repo   # history load timings
tool/make_demo_repo.sh /tmp/demo                  # branchy demo repository
tool/make_icons.sh                                # icons from assets/icon/source.png
```

```
lib/git/     git runner, parsers, Repository API, partial patches, rebase plans
lib/graph/   lane layout + row painter
lib/scan/    repository discovery
lib/app/     app state, settings, theme, zoom, avatars
lib/ui/      shell, tabs, graph view, sidebar, details, diff, dialogs
```

- **Releases**: `git tag -a v0.1.0 -m "What's new…" && git push origin
  v0.1.0` builds the macOS zip, the Linux tarball and the Flatpak, and
  publishes them as a GitHub Release (`.github/workflows/release.yml`).
  The tag's message opens the release notes.
- **Version label**: tagged builds embed their version, shown on the home
  tab. For a local build, pass
  `--dart-define=GUTTER_VERSION=0.1.0 --dart-define=GUTTER_COMMIT=$(git rev-parse --short HEAD)`.
- **Flatpak locally**: see `linux/flatpak/dev.gutter.gutter.yml`.

</details>

## License

GPL-3.0-or-later. Copyright (C) 2026 the Gutter contributors. See
[LICENSE](LICENSE).
