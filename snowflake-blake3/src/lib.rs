// SPDX-License-Identifier: AGPL-3.0-only

//! BLAKE3 cryptographic hash function.
//!
//! This is the hash function Snowflake uses for cache keys,
//! because it is fast and has an easy to use implementation.

#![warn(missing_docs)]

use {
    snowflake_blake3_sys as sys,
    std::mem::MaybeUninit,
};

/// BLAKE3 hasher state.
pub struct Blake3
{
    inner: sys::blake3_hasher,
}

impl Blake3
{
    /// Create a new BLAKE3 hasher state.
    pub fn new() -> Self
    {
        let mut inner = MaybeUninit::uninit();
        unsafe {
            sys::blake3_hasher_init(
                /* self */ inner.as_mut_ptr(),
            );
            Self{inner: inner.assume_init()}
        }
    }

    /// Update the hasher state with new input.
    pub fn update(&mut self, input: &[u8])
    {
        unsafe {
            sys::blake3_hasher_update(
                /* self      */ &mut self.inner,
                /* input     */ input.as_ptr() as *const libc::c_void,
                /* input_len */ input.len(),
            );
        }
    }

    /// Extract the hash from the hasher state.
    pub fn finish(mut self) -> [u8; 32]
    {
        let mut out = MaybeUninit::uninit();
        unsafe {
            sys::blake3_hasher_finalize(
                /* self    */ &mut self.inner,
                /* out     */ out.as_mut_ptr() as *mut u8,
                /* out_len */ 32,
            );
            out.assume_init()
        }
    }
}

#[cfg(test)]
mod tests
{
    use super::*;

    #[test]
    fn example()
    {
        let mut blake3 = Blake3::new();
        blake3.update(b"Hello, ");
        blake3.update(b"world!");
        let actual = blake3.finish();

        let expected =
            b"\xED\xE5\xC0\xB1\x0F\x2E\xC4\x97\x9C\x69\xB5\x2F\x61\xE4\x2F\xF5\
              \xB4\x13\x51\x9C\xE0\x9B\xE0\xF1\x4D\x09\x8D\xCF\xE5\xF6\xF9\x8D";

        assert_eq!(&actual, expected);
    }
}
