// SPDX-License-Identifier: AGPL-3.0-only

//! Working with NUL-terminated strings.

use std::{
    ffi::{CStr, CString},
    io::Result,
    mem::transmute,
    ops::Deref,
    ptr::null_mut,
};

////////////////////////////////////////////////////////////////////////////////
// cstr macro

/// Create a NUL-terminated string from a literal.
#[macro_export]
macro_rules! cstr
{
    ($str:expr) => {
        unsafe {
            let ptr = concat!($str, "\0").as_ptr();
            let ptr = ptr as *const std::os::raw::c_char;
            std::ffi::CStr::from_ptr(ptr)
        }
    };
}

////////////////////////////////////////////////////////////////////////////////
// CStringArray and CStringArr

/// Null-terminated array of NUL-terminated strings.
///
/// This facilitates the safe wrapper around execve(2),
/// which takes two pointers to such arrays.
pub struct CStringArray
{
    elements: Vec<*mut libc::c_char>,
}

/// Borrowed form of [`CStringArray`].
#[repr(transparent)]
pub struct CStringArr
{
    elements: [*mut libc::c_char],
}

impl CStringArray
{
    /// Create a new array with no strings.
    pub fn new() -> Self
    {
        Self{elements: vec![null_mut()]}
    }

    /// Append a string to the array.
    pub fn push(&mut self, element: CString)
    {
        self.elements.insert(
            self.elements.len() - 1,
            element.into_raw(),
        );
    }
}

impl CStringArr
{
    /// Obtain a pointer to the array.
    ///
    /// The last element of the array is a null pointer.
    pub fn as_ptr(&self) -> *const *const libc::c_char
    {
        self.elements.as_ptr()
            as *const *const libc::c_char
    }
}

impl Drop for CStringArray
{
    fn drop(&mut self)
    {
        for &element in &self.elements {
            unsafe {
                drop(CString::from_raw(element));
            }
        }
    }
}

impl Deref for CStringArray
{
    type Target = CStringArr;

    fn deref(&self) -> &Self::Target
    {
        let this: &[*mut libc::c_char] = &self.elements;
        unsafe { transmute(this) }
    }
}

impl FromIterator<CString> for CStringArray
{
    fn from_iter<T>(iter: T) -> Self
        where T: IntoIterator<Item=CString>
    {
        let mut this = Self::new();
        for element in iter {
            this.push(element);
        }
        this
    }
}

////////////////////////////////////////////////////////////////////////////////
// WithCStr

/// Conversions to NUL-terminated strings.
pub trait WithCStr
{
    /// Call `f` with a NUL-terminated string equivalent to `self`.
    ///
    /// If `self` contains interior NULs, return an error without calling `f`.
    /// If the string needs to be copied into a buffer,
    /// the implementation should prefer a stack allocation.
    fn with_cstr<F, R>(self, f: F) -> Result<R>
        where F: FnOnce(&CStr) -> Result<R>;
}

impl<'a> WithCStr for &'a CStr
{
    fn with_cstr<F, R>(self, f: F) -> Result<R>
        where F: FnOnce(&CStr) -> Result<R>
    {
        f(self)
    }
}

impl<'a> WithCStr for &'a CString
{
    fn with_cstr<F, R>(self, f: F) -> Result<R>
        where F: FnOnce(&CStr) -> Result<R>
    {
        let this: &CStr = self;
        f(this)
    }
}

impl WithCStr for CString
{
    fn with_cstr<F, R>(self, f: F) -> Result<R>
        where F: FnOnce(&CStr) -> Result<R>
    {
        f(&self)
    }
}

impl<'a> WithCStr for &'a str
{
    fn with_cstr<F, R>(self, f: F) -> Result<R>
        where F: FnOnce(&CStr) -> Result<R>
    {
        CString::new(self)?.with_cstr(f)
    }
}

impl WithCStr for String
{
    fn with_cstr<F, R>(self, f: F) -> Result<R>
        where F: FnOnce(&CStr) -> Result<R>
    {
        CString::new(self)?.with_cstr(f)
    }
}
