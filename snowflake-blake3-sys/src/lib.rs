// SPDX-License-Identifier: AGPL-3.0-only

//! See `c/blake.h` in the BLAKE3 repository.

pub const BLAKE3_BLOCK_LEN: usize = 64;
pub const BLAKE3_MAX_DEPTH: usize = 54;
pub const BLAKE3_OUT_LEN:   usize = 32;

#[repr(C)]
pub struct blake3_chunk_state
{
    cv:                [u32; 8],
    chunk_counter:     u64,
    buf:               [u8; BLAKE3_BLOCK_LEN],
    buf_len:           u8,
    blocks_compressed: u8,
    flags:             u8,
}

#[repr(C)]
pub struct blake3_hasher
{
    key:          [u32; 8],
    chunk:        blake3_chunk_state,
    cv_stack_len: u8,
    cv_stack:     [u8; (BLAKE3_MAX_DEPTH + 1) * BLAKE3_OUT_LEN],
}

#[link(name = "blake3")]
extern "C"
{
    pub fn blake3_version() -> *const libc::c_char;
    pub fn blake3_hasher_init(this: *mut blake3_hasher);
    pub fn blake3_hasher_update(
        this:      *mut blake3_hasher,
        input:     *const libc::c_void,
        input_len: libc::size_t,
    );
    pub fn blake3_hasher_finalize(
        this:    *mut blake3_hasher,
        out:     *mut u8,
        out_len: libc::size_t,
    );
}

#[cfg(test)]
mod tests
{
    use {
        super::*,
        std::ffi::CStr,
    };

    /// Test that BLAKE3 is still ABI-compatible.
    #[test]
    fn abi_compatibility()
    {
        let version = unsafe { CStr::from_ptr(blake3_version()) };
        assert_eq!(version, CStr::from_bytes_with_nul(b"1.3.1\0").unwrap(),
            "BLAKE3 is not of the expected version! \
             Please check that this crate still matches the C interface, \
             and change the version number in this failed assertion."
        );
    }
}
