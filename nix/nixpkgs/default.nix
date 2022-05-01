# SPDX-License-Identifier: AGPL-3.0-only

let
    tarball = fetchTarball (fromTOML (builtins.readFile ./pinned.toml));
    overlays = [
        (import ../blake3/overlay.nix)
        (import ../nixpkgs-mozilla/overlay.nix)
    ];
in
    import tarball {
        inherit overlays;
    }
