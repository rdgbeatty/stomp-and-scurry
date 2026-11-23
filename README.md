# Stomp & Scurry

You’re an ant in a grassy backyard. Outrun the hungry spider and scurry out of the shoe-shaped shadow before the sneaker comes down. Each dodge earns a point, and each new stomp gives you a little less warning. The game saves your best score locally.

The Stomp & Scurry source is licensed under GPL-3.0-or-later. See [LICENSE](LICENSE) and [Godot's third-party notices](GODOT-NOTICES.txt).

The pack edition uses one `StompAndScurry.exe`. Play solo, host, or join from the game menu, with your saved player name and host address. Verified game updates download from the menu and play opens in the same window. See the [release guide](release/README.md) for publishing steps.

## Play

Open **`build/Stomp and Scurry - LAN.exe`** on 64-bit Windows, then choose **Play solo** or **Host LAN**. You can also open `project.godot` in Godot 4.3 and press **F5**.

| Action | Control |
| --- | --- |
| Move | WASD or arrow keys |
| Escape jump | Space during a run |
| Start or try again | Space, Enter, or click the button |
| Pause or resume | Esc or the pause button |
| Toggle sound | M or the sound button |

## Host and join with the launcher

1. On the host PC, run **serve-lan.bat**. It verifies the launcher against `build/launcher-release.json` before serving it. On each joining PC, visit `http://HOST-IP:8000/` and download the listed self-updating **Stomp and Scurry Launcher - LAN.exe**. The direct link is `http://HOST-IP:8000/launcher.exe`; `/launcher-release.json` reports its version and SHA-256. Once the download finishes, stop **serve-lan.bat** so the host launcher can use port 8000.
2. On the host PC, open **Stomp and Scurry Launcher - LAN.exe** from the project's `build` folder and click **Host LAN lobby**. Keep the launcher and host game open.
3. On each joining PC, open the downloaded launcher, enter the host's Wi-Fi or Ethernet IPv4 address, and click **Join LAN lobby**. The launcher remembers that address and downloads the game only when it needs the matching build.

The same standalone launcher runs on each PC and bundles its Godot runtime. Each Windows build publishes a SHA-256 build ID. Downloaded games stay in separate build folders under `%APPDATA%/Godot/app_userdata/Stomp and Scurry Launcher/versions`.

Enter a player name in the launcher before hosting or joining. The launcher saves it on that PC and shows it to everyone in the LAN lobby. Leave it blank to use the default numbered player label.

### Launcher updates

Install the self-updating launcher once. On **Join**, it checks the host's launcher version before downloading the game. If the host has a newer launcher, the app verifies the download and closes. A small embedded Windows helper waits for it to exit, replaces the executable in place, and restarts it with the same host address. If the replacement does not start, the helper restores the previous launcher. Keep the launcher in a folder you can write to, such as Downloads.

Game-only builds keep the launcher version and Windows builds reuse the existing launcher. To ship a launcher change, close the host launcher before publishing and increment `VERSION` in `launcher/app/updater.gd`. The bundled helper is built from `launcher/helper/restart.c`. Rebuild it from WSL or Linux with `python3 launcher/helper/build-helper.py` if the native helper changes.

## Play together on the LAN

1. Run the same build on **two to four computers** on the same Wi-Fi or Ethernet network.
2. One player selects **Host LAN**. The others enter the host's local IPv4 address and select **Join LAN**. If several addresses appear, use the Wi-Fi or Ethernet IPv4 address from `ipconfig`.
3. Everyone chooses **Ant** or **Shoe**, then selects **Ready**. The round starts once everyone is ready and both roles are represented.

Ants move with WASD or the arrow keys and jump with Space. Shoes aim with the mouse and left-click to stomp or collect a shoe pickup. Each shoe has its own cooldown and charge. When a live ant is caught, that player becomes a green zombie ant and can turn other live ants by touching them. A shield or a jump can evade a bite. The round ends when the last live ant turns. The host can open the lobby again for a rematch.

LAN play uses UDP port 24567 on the host. If Windows Firewall asks, allow the game on private networks. The spider chases the ant in both solo and LAN play.

## Power-ups

Run over a pickup to collect it. The yellow lightning bolt speeds up the ant for five seconds. The blue shield expires after 15 seconds or absorbs one hit from the shoe, spider, or a meteor. After absorbing a hit, it briefly protects the ant while it gets away. More pickups appear after you collect one.

Press **Space** to jump in the direction you're moving, or straight ahead when standing still. The ant can dodge the shoe and spider while airborne. After landing, it moves at 60% speed for 1.7 seconds and can jump again once it recovers.

In LAN play, the shoe player clicks diamond pickups to charge the next stomp. The orange clock makes the warning 0.6 seconds instead of 0.9. The purple arrows make the shoe and its shadow 30% wider and longer. The green Area Denial pickup turns the next stomp's footprint into terrain the ant cannot enter for eight seconds. It also blocks jumping across. If the ant survives the stomp inside the footprint, it can leave once. The next stomp uses the charge automatically.

## Random events

Random events happen in both solo and LAN play.

- A **meteor shower** drops 32 meteors over about 16 seconds. Orange rings mark the next impact zones. Targets cover the yard, with nearby impacts spaced apart in time.
- A **spider rush** brings in two extra spiders for eight seconds.
- A **wind gust** gives a one-second warning, then pushes the ant left or right for six seconds. Move against the wind to steer.
- During **snail trail**, a snail crosses the yard. The snail runs on its own timer and can cross the yard during any other event. Its first warning appears after 9–14 seconds. The next warning follows 12–18 seconds after the last trail clears. Its wide slime trail slows the ant to 25% speed. Jump over it or wait six seconds for it to fade.

## Build for Windows

Double-click `build-windows.bat` or run this from PowerShell in the project directory.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-windows.ps1
```

The script uses the cached Godot 4.3 downloads from the sibling `test-game` project when available. Otherwise, the first run downloads the editor and export templates, about 1.1 GB in total. The script verifies the archive checksums, keeps its tools in `.godot/build-tools/`, and starts the staged executable headlessly before copying it to `build/`. Use `-Offline` to require cached downloads. Build and startup logs are in `.godot/windows-export/`.

The **Windows Desktop** export preset also works from the Godot editor with matching export templates installed. The release embeds the game data in a single executable and uses Godot’s Compatibility renderer.
