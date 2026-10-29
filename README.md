# herdr graphics patch

An unofficial patch for [herdr](https://github.com/herdrdev/herdr) that keeps Kitty graphics on herdr's
file transports with a local Ghostty client. It makes pixel apps such as
[terminal-browser](https://github.com/zenbu-labs/terminal-browser) and
[terminal-code (tode)](https://github.com/zenbu-labs/terminal-code) fast inside herdr on macOS again.

Not affiliated with herdr. Herdr does not accept outside pull requests
([CONTRIBUTING.md](https://github.com/herdrdev/herdr/blob/master/CONTRIBUTING.md)), so this lives here
as a patch you apply to your own build. Drop it once herdr fixes these upstream.

## The problem

Since herdr 0.9.2, apps show images through standard Kitty graphics and herdr forwards them to the
outer terminal. For a local Ghostty client herdr is meant to hand images over as files. On macOS that
never sticks, so every frame goes through herdr's server and client as raw pixels and then to Ghostty
as base64: hundreds of MB per second for a browser pane. The herdr client spends its time writing
base64, typing lags in every pane, and large panes stay blank.

Related herdr issues: [#5134](https://github.com/herdrdev/herdr/issues/5134),
[#3877](https://github.com/herdrdev/herdr/issues/3877), [#3946](https://github.com/herdrdev/herdr/issues/3946).

## What the patch changes

| | change |
|---|---|
| 1 | macOS: the client writes its Kitty temporary files under the per-user temporary directory. Ghostty resolves `/tmp` to `/private/tmp` and rejects files there ("temporary file not in temp dir"). |
| 2 | When the server retires a file transfer because the image moved or the pane went inactive, file transfers pause for one second instead of stopping until the client reconnects. The client no longer stops its side either. Real failures still disable file transfers. |
| 3 | Decoded file exports may be up to 64 MiB instead of 16 MiB, enough for a full pane on a high-density display. |
| 4 | An image too large for herdr's inline budget can still reach a file-capable client instead of being dropped. |
| 5 | Image fingerprints use foldhash instead of SipHash, about 9x faster on a 23 MB frame. |

About 150 lines in 17 files. herdr's own test suite passes with it (3,848 passed, 0 failed).

## Results

macOS 26.6, Ghostty 1.3.1, herdr 0.9.5, a large pane on a Retina display, a page that updates one line
of text 30 times a second. CPU seconds over a 10 second run:

| | frame size | herdr server | herdr client |
|---|---|---|---|
| herdr 0.9.5 | 19.5 MB | 6.4 | 6.8 |
| herdr 0.9.5 | 23 MB | nothing is drawn | |
| herdr 0.9.5 + this patch | 23 MB | 1.8 | 0.6 |

In the patched runs every file transfer was acknowledged and no image fell back to inline.

## Use

Requirements: a standalone herdr install (not Homebrew or Nix), git, [rustup](https://rustup.rs), and
[Zig 0.16](https://ziglang.org/download/) on `PATH` (or set `ZIG=/path/to/zig`).

```sh
git clone https://github.com/flemx/herdr-graphics-patch
cd herdr-graphics-patch
./update-herdr.sh            # build your installed herdr version with the patch and install it
herdr server stop            # when it suits you: this ends pane processes
herdr                        # start again; herdr restores your session layout
```

- The script builds herdr's official release tag for the version you have installed, applies the patch,
  backs up the official binary under `~/.local/state/herdr-graphics-patch/`, and swaps in the new one.
  It never stops herdr for you.
- If the patch does not apply to your version, it stops and leaves your herdr untouched.
- After `herdr update` replaces the binary, run `./update-herdr.sh` again.
- `./update-herdr.sh --check` only checks that the patch applies. `--test` runs herdr's graphics tests
  before installing. `--version X.Y.Z` builds another release.
- Undo: `./update-herdr.sh --restore`, then restart herdr.

A weekly GitHub Action checks that the patch still applies to herdr's latest release.

## License

Apache-2.0, like herdr. The patch modifies herdr source code.
