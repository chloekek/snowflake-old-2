// SPDX-License-Identifier: AGPL-3.0-only

//! Wrappers for various system calls.
//!
//! The wrappers retain the original names and behaviors of the system calls,
//! making it easy to look up their exact behavior in the man pages.
//! However, there are a few trivial differences for ease of use:
//!
//!  - Errors are reported via using [`Result`] instead of `errno`.
//!  - New file descriptors are returned using [`OwnedFd`].
//!  - `*_CLOEXEC` is passed to file handle creation functions by default,
//!    as setting this flag in a separate call incurs a race condition.
//!  - String arguments and array arguments are passed in a memory-safe way.
//!    The exact ways in which this is done are ad-hoc for some functions.
//!
//! These functions do not allocate memory except:
//!
//!  - When they call a trait method that allocates memory.
//!  - When otherwise noted.

#![feature(io_safety)]
#![feature(maybe_uninit_slice)]
#![feature(never_type)]
#![feature(unwrap_infallible)]
#![warn(missing_docs)]

use {
    crate::cstr::{CStringArr, WithCStr},
    std::{
        io::{Error, Result},
        mem::MaybeUninit,
        os::unix::{io::{AsRawFd, FromRawFd, OwnedFd}, process::ExitStatusExt},
        process::ExitStatus,
    },
};

pub use libc::{
    AT_FDCWD,
    CLONE_NEWCGROUP,
    CLONE_NEWIPC,
    CLONE_NEWNET,
    CLONE_NEWNS,
    CLONE_NEWPID,
    CLONE_NEWUSER,
    CLONE_NEWUTS,
    CLONE_PIDFD,
    EAGAIN,
    MS_BIND,
    MS_NODEV,
    MS_NOEXEC,
    MS_NOSUID,
    MS_PRIVATE,
    MS_RDONLY,
    MS_REC,
    MS_REMOUNT,
    O_DIRECTORY,
    O_PATH,
    O_TRUNC,
    O_WRONLY,
    POLLIN,
    SIGCHLD,
    SIGKILL,
    gid_t,
    mode_t,
    pid_t,
    pollfd,
    uid_t,
};

pub mod cstr;

/// _exit(2).
pub fn _exit(status: libc::c_int) -> !
{
    unsafe {
        libc::_exit(status);
    }
}

/// chdir(2).
pub fn chdir(path: impl WithCStr) -> Result<()>
{
    path.with_cstr(|path| {
        unsafe {
            match libc::chdir(path.as_ptr()) {
                -1 => Err(Error::last_os_error()),
                _  => Ok(()),
            }
        }
    })
}

/// chroot(2).
pub fn chroot(path: impl WithCStr) -> Result<()>
{
    path.with_cstr(|path| {
        unsafe {
            match libc::chroot(path.as_ptr()) {
                -1 => Err(Error::last_os_error()),
                _  => Ok(()),
            }
        }
    })
}

/// execve(2).
pub fn execve(
    pathname: impl WithCStr,
    argv:     &CStringArr,
    envp:     &CStringArr,
) -> Error
{
    let result: Result<!> = pathname.with_cstr(|pathname| {
        unsafe {
            libc::execve(pathname.as_ptr(), argv.as_ptr(), envp.as_ptr());
        }
        Err(Error::last_os_error())
    });
    result.into_err()
}

/// getgid(2).
pub fn getgid() -> gid_t
{
    unsafe {
        libc::getgid()
    }
}

/// getuid(2).
pub fn getuid() -> uid_t
{
    unsafe {
        libc::getuid()
    }
}

/// kill(2).
pub fn kill(pid: pid_t, sig: libc::c_int) -> Result<()>
{
    unsafe {
        match libc::kill(pid, sig) {
            -1 => Err(Error::last_os_error()),
            _  => Ok(())
        }
    }
}

/// mkdirat(2).
pub fn mkdirat(
    dirfd:    &impl AsRawFd,
    pathname: impl WithCStr,
    mode:     mode_t,
) -> Result<()>
{
    pathname.with_cstr(|pathname| {
        unsafe {
            match libc::mkdirat(dirfd.as_raw_fd(), pathname.as_ptr(), mode) {
                -1 => Err(Error::last_os_error()),
                _  => Ok(()),
            }
        }
    })
}

/// mount(2).
pub fn mount(
    source:         impl WithCStr,
    target:         impl WithCStr,
    filesystemtype: impl WithCStr,
    mountflags:     libc::c_ulong,
    data:           impl WithCStr,
) -> Result<()>
{
    source        .with_cstr(|source|
    target        .with_cstr(|target|
    filesystemtype.with_cstr(|filesystemtype|
    data          .with_cstr(|data| {
        unsafe {
            match
                libc::mount(
                    source.as_ptr(),
                    target.as_ptr(),
                    filesystemtype.as_ptr(),
                    mountflags,
                    data.as_ptr() as *const libc::c_void,
                )
            {
                -1 => Err(Error::last_os_error()),
                _  => Ok(()),
            }
        }
    }))))
}

/// open(2).
pub fn open(
    pathname:  impl WithCStr,
    mut flags: libc::c_int,
    mode:      mode_t,
) -> Result<OwnedFd>
{
    flags |= libc::O_CLOEXEC;
    pathname.with_cstr(|pathname| {
        unsafe {
            match libc::open(pathname.as_ptr(), flags, mode) {
                -1 => Err(Error::last_os_error()),
                fd => Ok(OwnedFd::from_raw_fd(fd)),
            }
        }
    })
}

/// pipe2(2).
pub fn pipe2(mut flags: libc::c_int) -> Result<[OwnedFd; 2]>
{
    flags |= libc::O_CLOEXEC;
    unsafe {
        let mut pipefd = [0, 0];
        match libc::pipe2(pipefd.as_mut_ptr(), flags) {
            -1 => Err(Error::last_os_error()),
            _  => Ok(pipefd.map(|fd| OwnedFd::from_raw_fd(fd))),
        }
    }
}

/// poll(2).
pub fn poll(fds: &mut [pollfd], timeout: libc::c_int) -> Result<usize>
{
    unsafe {
        match libc::poll(fds.as_mut_ptr(), fds.len() as u64, timeout) {
            -1 => Err(Error::last_os_error()),
            n  => Ok(n as usize),
        }
    }
}

/// readlink(2).
pub fn readlink<'a>(
    pathname: impl WithCStr,
    buf:      &'a mut [MaybeUninit<u8>],
) -> Result<&'a mut [u8]>
{
    pathname.with_cstr(|pathname| {
        unsafe {
            match
                libc::readlink(
                    pathname.as_ptr(),
                    buf.as_mut_ptr() as *mut libc::c_char,
                    buf.len(),
                )
            {
                -1  => Err(Error::last_os_error()),
                len => {
                    let subbuf = &mut buf[0 .. len as usize];
                    Ok(MaybeUninit::slice_assume_init_mut(subbuf))
                },
            }
        }
    })
}

/// readlinkat(2).
pub fn readlinkat<'a>(
    dirfd:    &impl AsRawFd,
    pathname: impl WithCStr,
    buf:      &'a mut [MaybeUninit<u8>],
) -> Result<&'a mut [u8]>
{
    pathname.with_cstr(|pathname| {
        unsafe {
            match
                libc::readlinkat(
                    dirfd.as_raw_fd(),
                    pathname.as_ptr(),
                    buf.as_mut_ptr() as *mut libc::c_char,
                    buf.len(),
                )
            {
                -1  => Err(Error::last_os_error()),
                len => {
                    let subbuf = &mut buf[0 .. len as usize];
                    Ok(MaybeUninit::slice_assume_init_mut(subbuf))
                },
            }
        }
    })
}

/// symlinkat(2).
pub fn symlinkat(
    target:   impl WithCStr,
    newdirfd: &impl AsRawFd,
    linkpath: impl WithCStr,
) -> Result<()>
{
    target.with_cstr(|target|
    linkpath.with_cstr(|linkpath| {
        unsafe {
            match
                libc::symlinkat(
                    target.as_ptr(),
                    newdirfd.as_raw_fd(),
                    linkpath.as_ptr(),
                )
            {
                -1 => Err(Error::last_os_error()),
                _  => Ok(()),
            }
        }
    }))
}

/// waitpid(2).
pub fn waitpid(pid: pid_t, options: libc::c_int)
    -> Result<(pid_t, ExitStatus)>
{
    unsafe {
        let mut wstatus = 0;
        match libc::waitpid(pid, &mut wstatus, options) {
            -1  => Err(Error::last_os_error()),
            pid => Ok((pid, ExitStatus::from_raw(wstatus))),
        }
    }
}
