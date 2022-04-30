let
    nixpkgs = import nix/nixpkgs;
in
    nixpkgs.mkShell {

        # Tools available in Nix shell.
        nativeBuildInputs = [
            nixpkgs.blake3                  # Hash function.
            nixpkgs.ldc                     # D compiler.
            nixpkgs.python3Packages.sphinx  # Documentation typesetter.
        ];

        # Environment variables used by build script.
        SNOWFLAKE_BASH_PATH      = nixpkgs.bash;
        SNOWFLAKE_COREUTILS_PATH = nixpkgs.coreutils;

    }
