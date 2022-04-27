let
    nixpkgs = import nix/nixpkgs;
in
    nixpkgs.mkShell {
        nativeBuildInputs = [
            nixpkgs.ldc                     # D compiler.
            nixpkgs.python3Packages.sphinx  # Documentation typesetter.
        ];
    }
