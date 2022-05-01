// SPDX-License-Identifier: AGPL-3.0-only

use std::{borrow::Cow, error, fmt, io};

/// Error related to containers.
///
/// The container machinery consists of a lot of different steps.
/// Each of those steps can fail with an error from the operating system.
/// This type wraps [`io::Error`] and adds detailed contextual information.
///
/// These errors can be created without allocating memory.
/// This is important to `child_pre_execve`.
#[derive(Debug)]
pub struct Error
{
    /// Which error ultimately occurred.
    pub inner: io::Error,

    /// Which step the error comes from.
    pub context: Cow<'static, str>,
}

impl Error
{
    /// Mimics [`io::Error::from_raw_os_error`].
    pub fn from_raw_os_error<C>(code: i32, context: C) -> Self
        where C: Into<Cow<'static, str>>
    {
        Self{
            inner: io::Error::from_raw_os_error(code),
            context: context.into(),
        }
    }

    /// Mimics [`io::Error::last_os_error`].
    pub fn last_os_error<C>(context: C) -> Self
        where C: Into<Cow<'static, str>>
    {
        Self{
            inner: io::Error::last_os_error(),
            context: context.into(),
        }
    }

    /// Mimics [`io::Error::other`].
    pub fn other<E, C>(error: E, context: C) -> Self
        where E: Into<Box<dyn error::Error + Send + Sync>>
            , C: Into<Cow<'static, str>>
    {
        Self{
            inner: io::Error::other(error),
            context: context.into(),
        }
    }
}

impl error::Error for Error
{
}

impl fmt::Display for Error
{
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result
    {
        write!(f, "{}: {}", self.context, self.inner)
    }
}

pub trait ResultExt
{
    type Ok;

    fn context<C>(self, context: C) -> Result<Self::Ok, Error>
        where C: Into<Cow<'static, str>>;
}

impl<T> ResultExt for Result<T, io::Error>
{
    type Ok = T;

    fn context<C>(self, context: C) -> Result<T, Error>
        where C: Into<Cow<'static, str>>
    {
        self.map_err(|inner| Error{inner, context: context.into()})
    }
}
