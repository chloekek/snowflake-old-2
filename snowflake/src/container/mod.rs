// SPDX-License-Identifier: AGPL-3.0-only

//! Running a command in a container.

use {
    snowflake_os::cstr::CStringArray,
    std::{ffi::CString, os::unix::io::RawFd},
};

pub use {self::{error::Error, run::*}, std::process::ExitStatus};

mod error;
mod kill_guard;
mod run;
mod spawn;

/// Command to be run in a container.
#[allow(missing_docs)]
pub struct Command
{
    // Because std::process::Command does not let us specify CLONE_NEWPID,
    // and because unshare(CLONE_NEWPID) does not have the desired effect,
    // we must replicate most of the implementation of std::process::Command.

    // The fields in here must be sufficiently prepared
    // for the code running between clone3(2) and execve(2).
    // Their use must not require any heap allocations.
    // So we use CString instead of OsString, etc.

    /// Contents of `/proc/self/{setgroups,{u,g}id_map}`.
    pub setgroups: Vec<u8>,
    pub uid_map:   Vec<u8>,
    pub gid_map:   Vec<u8>,

    /// Directory to change to before mounting.
    pub fchdir: RawFd,

    /// Mounts to perform.
    pub mounts: Vec<Mount>,

    /// Root directory.
    pub chroot: CString,

    /// Directory to change to after entering chroot.
    pub chroot_chdir: CString,

    /// Arguments to execve(2).
    pub execve_pathname: CString,
    pub execve_argv:     CStringArray,
    pub execve_envp:     CStringArray,

    /// File descriptors to adjust.
    pub stdin:  Stdio,
    pub stdout: Stdio,
    pub stderr: Stdio,
}

/// Arguments to mount(2).
#[allow(missing_docs)]
pub struct Mount
{
    pub source:         CString,
    pub target:         CString,
    pub filesystemtype: CString,
    pub mountflags:     libc::c_ulong,
    pub data:           CString,
}

/// How to adjust a file descriptor.
#[allow(missing_docs)]
#[derive(Clone, Copy)]
pub enum Stdio
{
    /// Do not adjust the file descriptor.
    Inherit,

    /// Close the file descriptor.
    Close,

    /// Duplicate `oldfd` into the file descriptor.
    Dup2{oldfd: RawFd},
}
