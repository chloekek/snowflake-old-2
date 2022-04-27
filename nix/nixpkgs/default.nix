let
    tarball = fetchTarball (fromTOML (builtins.readFile ./pinned.toml));
    overlays = [
        (import ../blake3/overlay.nix)
    ];
in
    import tarball {
        inherit overlays;
    }
