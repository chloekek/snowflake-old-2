# SPDX-License-Identifier: AGPL-3.0-only

let
    nixpkgs = import nix/nixpkgs;

    rustChannel = nixpkgs.rustChannelOf {
        date = "2022-05-01";
        channel = "nightly";
        sha256 = "0yshryfh3n0fmsblna712bqgcra53q3wp1asznma1sf6iqrkrl02";
    };
in
    nixpkgs.mkShell {

        # Tools available in Nix shell.
        nativeBuildInputs = [
            nixpkgs.blake3
            nixpkgs.cacert
            nixpkgs.perl
            nixpkgs.python3Packages.sphinx
            rustChannel.rust
        ];

        # Environment variables used during build.
        SNOWFLAKE_BASH_PATH      = nixpkgs.bash;
        SNOWFLAKE_COREUTILS_PATH = nixpkgs.coreutils;

    }
