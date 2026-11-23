# Stomp & Scurry pack releases

Players keep one `StompAndScurry.exe` in a folder they can write to. The game menu has **Play solo**, **Host LAN**, **Join LAN**, and the saved player name and host address. Update status appears in that menu. A verified pack opens in the same window, and the game serves it to other players while hosting. **Menu** in solo play and **Leave** in LAN play bring you back to the front screen.

Solo and host play check the release feed for a game pack. Join uses the exact pack in the host's signed manifest. The app caches working packs for offline play and fallback. If switching to a different pack after one has loaded, the app briefly reopens and continues the selected action automatically.

Each release ships `StompAndScurry.exe`, `StompAndScurry.pck`, `release.json`, and the license notices. `release.json` contains a signed payload with the release tag, increasing sequence, runtime version, pack ABI, and both SHA-256 digests. The executable embeds only the public key and feed address. Publish all of the assets before marking the release latest.

## Publish with GitHub Actions

The workflow runs from the default branch and builds an existing tag from that branch's history. The Windows job installs the verified Godot 4.3 tools, exports the game, and checks that the packaged executable starts the external pack. It uses the public key in `release/public-key.pem`. The Linux job signs the manifest, verifies it, and publishes the GitHub release. A game-only release reuses the executable from the latest signed stable release.

### One-time setup

Sign in with `gh auth login`. Upload the matching private PEM as the repository secret `STOMP_RELEASE_PRIVATE_KEY` using the authenticated terminal:

```bash
gh secret set STOMP_RELEASE_PRIVATE_KEY --repo rdgbeatty/stomp-and-scurry < /path/to/private.pem
```

Keep a secure backup of the key outside the repository. If the original key is unavailable and no public build has shipped, generate a replacement from your checkout. Commit the new public key before pushing the workflow. Public executables use that key to validate every update.

```bash
umask 077
key_dir=$(mktemp -d "$HOME/stomp-release-key.XXXXXXXX")
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$key_dir/private.pem"
openssl pkey -in "$key_dir/private.pem" -pubout -out release/public-key.pem
gh secret set STOMP_RELEASE_PRIVATE_KEY --repo rdgbeatty/stomp-and-scurry < "$key_dir/private.pem"
```

If you have the existing checkout with the initial two tags, fetch the updated bundle and fast-forward the default branch:

```bash
git switch main
git fetch /path/to/adler-game/build/stomp-and-scurry.bundle main
git merge --ff-only FETCH_HEAD
git push origin main --tags
```

For a new checkout, clone the bundle, point `origin` at the repo you created, and push:

```bash
git clone build/stomp-and-scurry.bundle ../stomp-and-scurry
cd ../stomp-and-scurry
git remote set-url origin https://github.com/rdgbeatty/stomp-and-scurry.git
git push -u origin main
git push origin --tags
```

### Run a release

Open **Actions → Release Stomp & Scurry → Run workflow**. Run `v0.1.0` with sequence `1` and wait for it to publish. Download the executable and open a solo game to cache its first pack. Then run `v0.1.1` with sequence `2`. Reopen the original executable to confirm it downloads the new pack. Run a host and join check on two Windows PCs. The public download is `https://github.com/rdgbeatty/stomp-and-scurry/releases/latest/download/StompAndScurry.exe`.

For later releases, push the new tag and increase the sequence. Keep older tagged releases accessible for players joining an older host. When changing the executable or updater, bump `RUNTIME_VERSION` in `launcher/app/pack_release.gd`. Increase `PACK_ABI` only when changing the runtime in a way that makes old packs incompatible.

If an upload fails and leaves a draft, delete that draft before rerunning the workflow. Leave its Git tag in place.

## Local development feed

For local releases use `--local-feed http://127.0.0.1:8001` and a separate development key. Build each release into `build/pack-preview/download/<tag>`. Copy that release's `release.json` to `build/pack-preview/latest/download/release.json` to make it current. To serve the feed, run `python -m http.server 8001 --bind 127.0.0.1 --directory build/pack-preview`. Port 8000 remains available for the LAN lobby.

To open an offline preview, run the executable from a tagged folder with its signed manifest and pack alongside it. The advertised feed is compiled into the executable, so rebuild with the public repository and release key for public distribution.
