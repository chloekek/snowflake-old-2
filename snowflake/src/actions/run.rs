// SPDX-License-Identifier: AGPL-3.0-only

use {
    crate::{
        config::{BASH_PATH, COREUTILS_PATH},
        container::{Command, Mount, RunError, Stdio},
    },
    super::ActionContext,
    snowflake_os::{self as os, cstr, cstr::CStringArray},
    std::{ffi::CString, io, time::Duration},
    thiserror::Error,
};

/// Information needed for performing a run action.
pub struct PerformRunAction
{
    /// The program to run.
    pub program: CString,

    /// Arguments to pass to the program.
    pub arguments: CStringArray,

    /// Environment entries to pass to the program.
    pub environment: CStringArray,

    /// The maximum time the program may spend.
    pub timeout: Duration,
}

/// Error that occurs during a run action.
#[derive(Debug, Error)]
pub enum RunActionError
{
    #[error("{0}")]
    Io(#[from] io::Error),

    #[error("{0}")]
    Run(#[from] RunError),
}

pub fn perform_run_action(
    context: &ActionContext,
    info:    PerformRunAction,
) -> Result<(), RunActionError>
{

    // Create root directory structure.
    os::mkdirat(&context.scratch_dir, "bin",       0o755)?;
    os::mkdirat(&context.scratch_dir, "nix",       0o755)?;
    os::mkdirat(&context.scratch_dir, "nix/store", 0o755)?;
    os::mkdirat(&context.scratch_dir, "proc",      0o555)?;
    os::mkdirat(&context.scratch_dir, "usr",       0o755)?;
    os::mkdirat(&context.scratch_dir, "usr/bin",   0o755)?;

    // Create working directory for the command.
    os::mkdirat(&context.scratch_dir, "build", 0o755)?;

    // These executables are expected to exist by many programs.
    // Consider scripts with #!/usr/bin/env or programs calling system(3).
    // So we always make these available even if not declared as inputs.
    // NOTE: When adding an entry here, add it to the hash of the run action.
    os::symlinkat(
        format!("{}/bin/bash", BASH_PATH),
        &context.scratch_dir, "bin/sh",
    )?;
    os::symlinkat(
        format!("{}/bin/env", COREUTILS_PATH),
        &context.scratch_dir, "usr/bin/env",
    )?;

    // Run the command of the run action.
    run_command(context, info)?;

    Ok(())
}

fn run_command(
    context: &ActionContext,
    info:    PerformRunAction,
) -> Result<(), RunActionError>
{
    // Configure the command to run.
    let command = Command{

        // Map root inside container to actual user outside container.
        setgroups: "deny\n".into(),
        uid_map:   format!("0 {} 1\n", os::getuid()).into(),
        gid_map:   format!("0 {} 1\n", os::getgid()).into(),

        // Set the working directory to the scratch directory.
        fchdir: context.scratch_dir,

        // Set up all the mounts.
        mounts: collect_mounts(),

        // Set the root directory of the container to the working directory.
        // Then set the working directory to the build directory.
        chroot:       cstr!(".").into(),
        chroot_chdir: cstr!("/build").into(),

        // Configure the command to execute.
        execve_pathname: info.program,
        execve_argv:     info.arguments,
        execve_envp:     info.environment,

        // Open the log file and redirect stdio.
        stdin:  Stdio::Close,
        stdout: Stdio::Dup2{oldfd: context.log_file},
        stderr: Stdio::Dup2{oldfd: context.log_file},

    };

    // Run the command.
    command.run(info.timeout)?;

    Ok(())
}

/// Collect all mounts into a vector.
fn collect_mounts() -> Vec<Mount>
{
    let mut mounts = Vec::new();

    // systemd mounts `/` as `MS_SHARED`, but `MS_PRIVATE` is more isolated.
    mounts.push(Mount{
        source:         cstr!("none").into(),
        target:         cstr!("/").into(),
        filesystemtype: CString::default(),
        mountflags:     os::MS_PRIVATE | os::MS_REC,
        data:           CString::default(),
    });

    // Mount `/proc` which is required for some programs to function properly.
    mounts.push(Mount{
        source:         cstr!("proc").into(),
        target:         cstr!("proc").into(),
        filesystemtype: cstr!("proc").into(),
        mountflags:     os::MS_NODEV | os::MS_NOEXEC | os::MS_NOSUID,
        data:           CString::default(),
    });

    // Create bind mounts so the container can access outside files.
    mount_bind_rdonly(
        &mut mounts,
        cstr!("/nix/store").into(),
        cstr!("nix/store").into(),
    );

    mounts
}

/// Create a read-only bind mount.
///
/// This is more involved than simply passing `MS_BIND | MS_RDONLY`.
/// See https://unix.stackexchange.com/a/492462 for more information.
fn mount_bind_rdonly(
    mounts: &mut Vec<Mount>,
    source: CString,
    target: CString,
)
{
    let flags1 = os::MS_BIND | os::MS_REC;
    let flags2 = flags1 | os::MS_RDONLY | os::MS_REMOUNT;
    mounts.push(Mount{
        source:         source,
        target:         target.clone(),
        filesystemtype: CString::default(),
        mountflags:     flags1,
        data:           CString::default(),
    });
    mounts.push(Mount{
        source:         cstr!("none").into(),
        target:         target,
        filesystemtype: CString::default(),
        mountflags:     flags2,
        data:           CString::default(),
    });
}
