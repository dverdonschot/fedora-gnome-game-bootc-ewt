# Declarative list of user-level CLI/dev packages for the bootc workstation.
#
# These are deliberately NOT baked into the image: they live in /nix, which
# sits outside the ostree container. That means:
#   - updating them never needs a rebase or a reboot;
#   - the image stays small (no toolchain churn in the Containerfile).
#
# Apply / reinstall:
#   nix profile install --file nix/apps.nix
# Upgrade everything to the latest pinned channel revision:
#   nix-channel --update && nix profile upgrade
#
# Rules for what belongs in this file vs. the Containerfile:
#   HERE       — pure user-space CLI tools, no system daemon, no kernel/GPU
#                integration, no /usr/lib/systemd units.
#   IMAGE      — anything needing kernel modules, GPU access (rocm), a
#                system daemon (ollama, node_exporter), a preset unit
#                (libvirt), or the podman-docker shim.
#
# The channel pin below keeps builds reproducible; bump the URL/revision
# deliberately, then run `nix-channel --update && nix profile upgrade`.
{ pkgs ? import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/nixos-25.11.tar.gz";
  }) {} }:

with pkgs; [
  # Editors & shell
  micro
  vim
  tmux
  oh-my-posh
  ranger
  nerd-fonts.hack
  age

  # Languages & runtimes
  python3
  python3Packages.pip
  uv

  # Compilers & build tools
  clang
  llvm
  gnumake
  pkgconf
  git

  # Networking & monitoring
  nmap
  socat
  wireshark
  btop
  iotop
  nethogs
  sysstat
  strace
  net-tools
  traceroute
  hwinfo

  # Kubernetes
  kubectl
  kubernetes-helm
]
