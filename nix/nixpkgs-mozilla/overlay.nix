# SPDX-License-Identifier: AGPL-3.0-only

let
    tarball = fetchTarball (fromTOML (builtins.readFile ./pinned.toml));
in
    import tarball
