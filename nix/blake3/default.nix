# SPDX-License-Identifier: AGPL-3.0-only

{ stdenv }:

stdenv.mkDerivation rec {

    pname = "blake3";
    version = "1.3.1";

    src = fetchTarball {
        url = "https://github.com/BLAKE3-team/BLAKE3/archive/${version}.tar.gz";
        sha256 = "0azlab8hzcf2xy0jk74qaqzk1p5aasdkzn8qhk45f8hfdmizmv6n";
    };

    buildPhase = ''
        cd c
        gcc -O3 -shared -o libblake3.so \
            blake3{,_dispatch,_portable}.c \
            blake3{_sse2,_sse41,_avx2,_avx512}_x86-64_unix.S
    '';

    installPhase = ''
        mkdir --parents "$out/include" "$out/lib"
        mv blake3.h "$out/include"
        mv libblake3.so "$out/lib"
    '';

}
