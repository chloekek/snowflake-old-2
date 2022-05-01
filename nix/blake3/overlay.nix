# SPDX-License-Identifier: AGPL-3.0-only

self: super:

{
    blake3 = super.callPackage ./. { };
}
