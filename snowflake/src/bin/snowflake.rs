// SPDX-License-Identifier: AGPL-3.0-only

#![feature(duration_constants)]

use {
    snowflake::container::{Command, Mount, Stdio},
    snowflake_os as os,
    std::{ffi::CString, io::Result, os::unix::io::AsRawFd, time::Duration},
};

fn main() -> Result<()>
{
    let scratch_dir = os::open(
        "/home/r/Garbage/scratch",
        os::O_DIRECTORY | os::O_PATH,
        0,
    )?;

    let command = Command{

        setgroups: b"deny\0".to_vec(),
        uid_map:   format!("0 {} 1\n", os::getuid()).into(),
        gid_map:   format!("0 {} 1\n", os::getgid()).into(),

        fchdir: scratch_dir.as_raw_fd(),

        mounts: vec![
            Mount{
                source:         os::cstr!("none").into(),
                target:         os::cstr!("/").into(),
                filesystemtype: CString::default(),
                mountflags:     os::MS_PRIVATE | os::MS_REC,
                data:           CString::default(),
            },
            Mount{
                source:         os::cstr!("proc").into(),
                target:         os::cstr!("proc").into(),
                filesystemtype: os::cstr!("proc").into(),
                mountflags:     os::MS_NODEV | os::MS_NOEXEC | os::MS_NOSUID,
                data:           CString::default(),
            },
            Mount{
                source:         os::cstr!("/nix/store").into(),
                target:         os::cstr!("nix/store").into(),
                filesystemtype: CString::default(),
                mountflags:     os::MS_BIND | os::MS_REC,
                data:           CString::default(),
            },
            Mount{
                source:         os::cstr!("none").into(),
                target:         os::cstr!("nix/store").into(),
                filesystemtype: CString::default(),
                mountflags:     os::MS_BIND | os::MS_RDONLY |
                                os::MS_REMOUNT | os::MS_REC,
                data:           CString::default(),
            },
        ],

        chroot: os::cstr!(".").into(),
        chroot_chdir: os::cstr!("/build").into(),

        execve_pathname: os::cstr!("/nix/store/wyjmlzvqkkq0pn41aag1jvinc62aldb1-coreutils-9.0/bin/slee").into(),
        execve_argv: os::cstr::CStringArray::from_iter([
            os::cstr!("sleep").into(),
            os::cstr!("5").into(),
        ]),
        execve_envp: os::cstr::CStringArray::new(),

        stdin: Stdio::Close,
        stdout: Stdio::Inherit,
        stderr: Stdio::Inherit,

    };

    if let Err(err) = command.run(2 * Duration::SECOND) {
        panic!("{}", err);
    }

    Ok(())
}
