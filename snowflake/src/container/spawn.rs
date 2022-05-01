// SPDX-License-Identifier: AGPL-3.0-only

use {
    super::{Command, Error, Stdio, error::ResultExt, kill_guard::*},
    snowflake_os as os,
    std::{
        ffi::{CStr, CString},
        fs::File,
        io::{self, Read, Write},
        mem::{MaybeUninit, forget, size_of_val, zeroed},
        os::{linux::process::PidFd, unix::io::{FromRawFd, RawFd}},
        panic::always_abort,
    },
};

impl Command
{
    /// Spawn the container.
    pub fn spawn(&self) -> Result<(os::pid_t, PidFd), Error>
    {
        // For unknown reasons, using fchdir(2) in the child process
        // prevents mount(2) and chroot(2) from working with relative paths.
        // Using chdir("/proc/self/fd/{}") isn't sufficient either.
        // Dereferencing it and *then* calling chdir(2) works fine.
        let fchdir_magic_link = format!("/proc/self/fd/{}", self.fchdir);
        let mut fchdir = MaybeUninit::uninit_array::<1024>();
        let fchdir = os::readlink(fchdir_magic_link, &mut fchdir)
            .context("readlink: fchdir_magic_link")?;
        let fchdir = CString::new(fchdir)
            .expect("Symbolic links do not contain NULs");

        // Create a pipe for the child to communicate pre-execve errors.
        let [pipe_r, pipe_w] = os::pipe2(0).context("pipe2")?;
        let mut pipe_r = File::from(pipe_r);
        let mut pipe_w = File::from(pipe_w);

        // Prepare the call to clone3(2).
        let clone3_flags = {
            os::CLONE_NEWCGROUP |  // New cgroup namespace.
            os::CLONE_NEWIPC    |  // New IPC namespace.
            os::CLONE_NEWNET    |  // New network namespace.
            os::CLONE_NEWNS     |  // New mount namespace.
            os::CLONE_NEWPID    |  // New PID namespace.
            os::CLONE_NEWUSER   |  // New user namespace.
            os::CLONE_NEWUTS    |  // New UTS namespace.
            os::CLONE_PIDFD        // Create new pidfd.
        };

        // clone3(2) will store the pidfd in here.
        let mut pidfd: RawFd = -1;

        // SAFETY: The child process gets a new address space,
        //         and child_pre_execve is async-signal-safe.
        let pid = unsafe {
            #[repr(C)]
            struct clone_args
            {
                flags:        u64,
                pidfd:        u64,
                child_tid:    u64,
                parent_tid:   u64,
                exit_signal:  u64,
                stack:        u64,
                stack_size:   u64,
                tls:          u64,
                set_tid:      u64,
                set_tid_size: u64,
                cgroup:       u64,
            }
            let mut cl_args = zeroed::<clone_args>();
            cl_args.flags       = clone3_flags as u64;
            cl_args.pidfd       = &mut pidfd as *mut RawFd as u64;
            cl_args.exit_signal = os::SIGCHLD as u64;
            libc::syscall(libc::SYS_clone3, &cl_args, size_of_val(&cl_args))
        };

        // If clone3(2) returns -1, an error occurred.
        if pid == -1 {
            return Err(Error::last_os_error("clone3"));
        }

        // If clone3(2) returns 0, we are the child process.
        if pid == 0 {

            // Make sure panics don't bubble up the stack.
            always_abort();

            // Only returns if something went wrong.
            let error = self.child_pre_execve(pipe_r, fchdir);
            let error = error.into_err();

            // If an error occurred, send it to the parent process.
            let errno = error.inner.raw_os_error().unwrap_or(-1);
            let _ = pipe_w.write(&errno.to_ne_bytes());
            let _ = pipe_w.write(error.context.as_bytes());
            os::_exit(1);

        }

        // Otherwise, we are the parent process.
        let pid = pid as os::pid_t;

        // If anything below fails, kill and reap the child process.
        let kill_guard = KillGuard::new(pid);

        // Close the write end of the pipe.
        drop(pipe_w);

        // SAFETY: This is definitely a pidfd.
        let pidfd = unsafe { PidFd::from_raw_fd(pidfd) };

        // Wait for the execve(2) call to complete in the child process.
        // Once it does, pipe_w will be closed due to CLOEXEC,
        // which in turn causes this read to complete at EOF.
        // If this read completes with data, an error was sent.
        let mut buf = Vec::new();
        match pipe_r.read_to_end(&mut buf).context("read: pipe_r")? {
            0 => {
                forget(kill_guard);  // Keep it running!
                Ok((pid, pidfd))
            },
            n if n > 4 => {
                let errno = [buf[0], buf[1], buf[2], buf[3]];
                let errno = i32::from_ne_bytes(errno);
                let context = String::from_utf8_lossy(&buf[4 ..]);
                let context = context.into_owned();  // Can't borrow buf.
                Err(Error::from_raw_os_error(errno, context))
            },
            _ => {
                // Unlikely scenario where the child process
                // couldn't write the entire error packet.
                Err(Error::other("Unknown error", "child_pre_execve"))
            },
        }
    }

    /// The code that runs in the child process.
    ///
    /// Everything in here must be async-signal-safe!
    /// That implies no allocations and no panics may occur.
    fn child_pre_execve(&self, pipe_r: File, fchdir: CString)
        -> Result<!, Error>
    {
        // Close the read end of the pipe.
        drop(pipe_r);

        // Write to these files as requested.
        Self::write_file(os::cstr!("/proc/self/setgroups"), &self.setgroups)
            .context("/proc/self/setgroups")?;
        Self::write_file(os::cstr!("/proc/self/uid_map"), &self.uid_map)
            .context("/proc/self/uid_map")?;
        Self::write_file(os::cstr!("/proc/self/gid_map"), &self.gid_map)
            .context("/proc/self/gid_map")?;

        // Set working directory as requested.
        os::chdir(fchdir).context("fchdir")?;

        // Perform each mount as requested.
        for mount in &self.mounts {
            os::mount(
                &mount.source,
                &mount.target,
                &mount.filesystemtype,
                mount.mountflags,
                &mount.data,
            ).context("mount")?;
        }

        // Set root and working directories as requested.
        os::chroot(&self.chroot).context("chroot")?;
        os::chdir(&self.chroot_chdir).context("chroot_chdir")?;

        // Configure stdio as requested.
        // SAFETY: We will no longer use these file descriptors.
        unsafe {
            Self::adjust_fd(0, self.stdin).context("stdin")?;
            Self::adjust_fd(1, self.stdout).context("stdout")?;
            Self::adjust_fd(2, self.stderr).context("stderr")?;
        }

        // Replace the process with the requested program.
        let error = os::execve(&self.execve_pathname,
                               &self.execve_argv,
                               &self.execve_envp);
        Err(Error{inner: error, context: "execve".into()})
    }

    /// Write to a given file with a single write call.
    fn write_file(path: &CStr, data: &[u8]) -> Result<(), io::Error>
    {
        let file = os::open(path, os::O_TRUNC | os::O_WRONLY, 0)?;
        let mut file = File::from(file);
        let nwritten = file.write(data)?;
        if nwritten != data.len() {
            return Err(io::Error::from_raw_os_error(os::EAGAIN));
        }
        Ok(())
    }

    /// Adjust a file descriptor.
    ///
    /// # Safety
    ///
    /// This will close the given file descriptor,
    /// which may be unexpected if it is still used.
    unsafe fn adjust_fd(fd: RawFd, stdio: Stdio) -> Result<(), io::Error>
    {
        match stdio {

            Stdio::Inherit =>
                Ok(()),

            Stdio::Close => {
                libc::close(fd);
                Ok(())
            },

            Stdio::Dup2{oldfd} =>
                match libc::dup2(oldfd, fd) {
                    -1 => Err(io::Error::last_os_error()),
                    _  => Ok(()),
                },

        }
    }
}
