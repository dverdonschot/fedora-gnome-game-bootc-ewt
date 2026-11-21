# fedora-gnome-game-bootc-ewt

A custom Fedora 45 GNOME bootc image for the ODROID-H3+ game box (Intel N100,
32 GB RAM, TV via HDMI, 2 USB NES pads): the same image as
[fedora-gnome-bootc-ewt](https://github.com/dverdonschot/fedora-gnome-bootc-ewt)
minus the AMD GPU / UM790 hardware bits, plus a retro-gaming stack (ES-DE
frontend + RetroArch). Same package list, same forgejo-runner, same
monitoring and auto-update setup. **Container runtime is podman** (with the
`podman-docker` shim).

To be published to **`ghcr.io/dverdonschot/fedora-gnome-game-bootc-ewt`** by
GitHub Actions (same workflow as the sibling images: push/PR build, weekly
rebuild, cosign-signed keylessly). Bootc reference notes:
[docs/bootc-doc-index.md](docs/bootc-doc-index.md).

## Layout

```
Containerfile                    # Single source of truth
files/
  system/                        # /usr + /etc overlay (presets, sysusers, ES-DE autostart)
  forgejo-runner/                # Runner unit + post-rebase setup
  scripts/                       # One-shot post-rebase helpers
build/
  build.sh                       # `buildah bud` wrapper (local + VPS + CI)
  install-flatpaks.sh            # Flatpak installer (idempotent; see Flatpaks)
  flatpak-list.txt               # Flatpak manifest, read at build time
.github/workflows/build.yml      # CI: build, lint, push, sign
docs/bootc-doc-index.md          # Curated bootc references + local lessons
```

No `files/bootc/install/` drop-ins on this image — the H3+ needs no
hardware-specific kargs (siblings carry the AMD GPU + UM790 idle ones).
The ODROID-H3+ (Intel N100, Intel UHD iGPU, 2x 2.5GbE RTL8125,
HDMI 2.0 + DisplayPort) is fully supported by stock Fedora — nothing
hardware-specific to carry.

## Gaming stack

- **ES-DE** (`org.es_de.emulationstation`) — the TV-friendly game library
  frontend: box art, controller-driven browsing, launches emulators.
- **RetroArch** (`org.libretro.RetroArch`) — the emulator engine (libretro
  cores) ES-DE drives: Mesen/Nestopia (NES), bsnes/snes9x (SNES),
  Genesis Plus GX, mGBA, mupen64plus-next (N64), SwanStation (PS1),
  Flycast (Dreamcast), DOSBox Pure (DOS).
- Both are system flatpaks in `build/flatpak-list.txt`, installed after
  rebase with `./build/install-flatpaks.sh` — **not baked into the image**
  (flatpaks live in `/var`; see the Flatpaks section for why).
- ES-DE autostarts on login via
  `files/system/etc/xdg/autostart/es-de.desktop`. To stop autostarting
  (the box doubles as a workstation):

  ```bash
  sudo rm /etc/xdg/autostart/es-de.desktop    # /etc is writable on bootc
  ```

### Casting (optional)

`org.gnome.NetworkDisplays` mirrors the desktop to a Cast/Miracast display.
The Fire TV Stick needs a Cast-receiver app for discovery; whether such an
app accepts GNOME's live desktop-mirror session (vs. media casts only) is
untested — see the manifest comment. Miracast is out on this box (no Wi-Fi
radio). Mirrored casting is for desktop use; gaming stays on the HDMI
cable, or use Sunshine (host) + Moonlight on the stick for interactive
low-latency control.

### ROMs and BIOS are user data, not image content

The ROM library lives outside the image (odroid share or local copy —
source still to be settled, see Open items). ES-DE's default ROM root is
`~/ROMs`; the staged tree (`nes/`, `snes/`, `gba/`, `dos/`, `bios/`) drops
straight into it. Point RetroArch at the BIOS set once:
Settings → Directory → System/BIOS → `~/ROMs/bios`.

Controllers: the NES USB pads enumerate as standard HID — no udev rules;
RetroArch's autoconfig picks them up (map once if buttons are swapped).

## Differences vs fedora-gnome-bootc-ewt

- **Removed:** AMD GPU kargs drop-ins (`00-amdgpu.toml`), UM790 idle kargs
  (`01-um790-idle.toml`), UM790 USB-serial modules, `lact` + its COPR repo,
  the `rocm-*` packages.
- **Added:** gaming flatpaks (ES-DE, RetroArch) in the manifest, ES-DE
  autostart drop-in.
- **Unchanged:** everything else — podman + shim, forgejo-runner, libvirt,
  nix, alloy log shipping, node_exporter, tailscale, automatic update
  staging, firefox-removal, lint behavior.

## Build

```bash
./build/build.sh                                # build only
./build/build.sh --push                         # build + push to ghcr.io/dverdonschot
FEDORA_VERSION=45 ./build/build.sh --push       # override silverblue tag
LINT_SKIP= ./build/build.sh                     # full bootc container lint
```

Env vars: `FEDORA_VERSION` (45), `REGISTRY` (ghcr.io), `REGISTRY_NAMESPACE`
(dverdonschot), `IMAGE` (fedora-gnome-game-bootc-ewt), `PLATFORM`
(linux/amd64), `LINT_SKIP` (`--skip=var-tmpfiles` — IMA EACCES story on
Fedora hosts, see the lint section in `Containerfile`). Auth for `--push`:
`REGISTRY_USER` + `REGISTRY_TOKEN` (GHCR PAT with `write:packages`), else
interactive prompt. The raw `buildah` command is documented at the top of
`Containerfile`.

### CI

`.github/workflows/build.yml` builds on push/PR and rebuilds weekly
(Monday 04:30 UTC) so the image tracks the latest `silverblue:45`. Push +
signing happen only on `main`; PRs are build-only. Signing is cosign
keyless — verify with:

```bash
cosign verify ghcr.io/dverdonschot/fedora-gnome-game-bootc-ewt:45
```

## Automatic updates

Identical to the sibling images: `AutomaticUpdatePolicy=stage` in
`files/system/etc/rpm-ostreed.conf` + preset-enabled
`rpm-ostreed-automatic.timer` (stock cadence: ~1h after boot, then daily
while on; updates stage in the background and deploy at next power-on).
Bootstrap a machine running an older image once by hand
(`sudo rpm-ostree upgrade && reboot`). Verify on a machine:

```bash
rpm-ostree status     # header shows: AutomaticUpdates: stage; ...
```

Flatpaks and the nix toolchain update independently (`flatpak update`,
`nix profile upgrade`).

## Install / rebase

> [!WARNING]
> [This is an experimental feature](https://www.fedoraproject.org/wiki/Changes/OstreeNativeContainerStable),
> try at your own discretion.

From an existing Fedora Atomic install (e.g. the current Bazzite box —
Bazzite is rpm-ostree based, so the rebase works; layered packages and
local `/etc` changes ride along, so check `rpm-ostree status` after
the switch and `rpm-ostree uninstall` anything Bazzite-specific you
do not want kept):

  # 1. Unsigned rebase — pulls the signing key + policy on the way.
  sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/dverdonschot/fedora-gnome-game-bootc-ewt:45
  sudo systemctl reboot

  # 2. Signed rebase.
  sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/dverdonschot/fedora-gnome-game-bootc-ewt:45
  sudo systemctl reboot

Fresh disk install:

  sudo bootc install to-disk --filesystem=xfs \
    ostree-image-signed:docker://ghcr.io/dverdonschot/fedora-gnome-game-bootc-ewt:45 /dev/sdX

## Post-rebase

One-time, as your normal user:

```bash
systemctl --user enable --now podman.socket   # activate the per-user podman socket
./build/install-flatpaks.sh                   # system flatpaks incl. ES-DE + RetroArch
/usr/local/bin/setup-forgejo-runner.sh --enable   # if you want CI on this box
/usr/local/bin/setup-libvirt.sh                  # if you use virt-manager
nix profile install --file nix/apps.nix          # CLI/dev toolchain (see Nix)
```

First gaming session: run the flatpak installer, drop the ROM tree into
`~/ROMs`, launch ES-DE (or just log in — it autostarts), scrape artwork
once (ES-DE → scraper, free ScreenScraper account), map the pads in
RetroArch if buttons are swapped.

## Flatpaks

Firefox, Flatseal, FreeTube, Zed, Zen, **ES-DE, RetroArch, Network
Displays** — **not baked
into the image**. Flatpaks live in `/var`, which bootc only seeds from the
image on first install and never touches on upgrade: a baked copy would be
frozen at build-day versions and wouldn't arrive on a rebase either.
`build/flatpak-list.txt` is the single source of truth. After
rebase/install, run once as your user (idempotent):

```bash
./build/install-flatpaks.sh
```

## Nix

The image ships the Fedora `nix` + `nix-daemon` packages with
`nix-daemon.socket` preset-enabled; the user-level toolchain is declared in
[`nix/apps.nix`](nix/apps.nix) and applied after rebase:

```bash
nix-channel --add https://nixos.org/channels/nixos-25.11 nixpkgs   # one-time pin
nix-channel --update
nix profile install --file nix/apps.nix
```

**Rule of thumb for where a package lives:** `nix/apps.nix` — pure
user-space CLI tools; `Containerfile` — anything needing kernel modules, a
system daemon, or a preset unit.

## Customizations vs. stock silverblue

- Podman as the container runtime (rootless via `podman.socket`), plus the
  `podman-docker` shim.
- Forgejo Actions runner pre-staged (operator runs setup script).
- libvirt/KVM preset (`80-virtualization.preset`), virt-manager, qemu-kvm.
- Nix + nix-daemon, user-level toolchain in `nix/apps.nix`.
- `node_exporter` enabled with the systemd collector drop-in (feeds the
  Container Health Grafana dashboard).
- Log shipping baked in: `alloy` tails the persistent host journal to the
  homelab Loki (host-agnostic config; journald made persistent).
- Gaming: ES-DE + RetroArch flatpaks in the manifest, ES-DE autostart on
  login (see Gaming stack).
- Flatpaks via manifest + idempotent script.
- Automatic update staging enabled (stage policy +
  `rpm-ostreed-automatic.timer`).

## Build mechanism

Package install uses `dnf5 install/remove` against the silverblue base, not
`rpm-ostree install/override remove/kargs` (broken inside `buildah bud`,
see [coreos/rpm-ostree#3738](https://github.com/coreos/rpm-ostree/issues/3738);
dnf5 is the supported build-time tool per
[Changes/DNFAndBootcInImageModeFedora](https://fedoraproject.org/wiki/Changes/DNFAndBootcInImageModeFedora)).
No install-time kargs on this image (see Layout). The build ends with
`bootc container lint`.

## Open items

- **ROM source:** odroid share (automount) vs. local copy + sync — pending
  odroid reachability; the staged tree is small (~57 MB) either way.
- **Artwork scraping:** one-time ES-DE scrape after first launch.
- **Remote repos:** GitHub repo + Actions, Forgejo mirror — not created yet
  (this repo is local-only until then).
