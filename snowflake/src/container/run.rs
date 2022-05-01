// SPDX-License-Identifier: AGPL-3.0-only

use {
    super::{Command, Error, error::ResultExt, kill_guard::*},
    snowflake_os as os,
    std::{
        mem::forget,
        os::unix::io::AsRawFd,
        process::ExitStatus,
        slice,
        time::Duration,
    },
};

/// Error returned by [`Command::run`].
#[allow(missing_docs)]
#[derive(Debug, thiserror::Error)]
pub enum RunError
{
    #[error("{0}")]
    Container(#[from] Error),

    #[error("Command exceeded timeout: {0:?}")]
    Timeout(Duration),

    #[error("Command terminated unsuccessfully: Status {0}")]
    Unsuccessful(ExitStatus),
}

impl Command
{
    /// Spawn the container and wait for it to terminate.
    ///
    /// If the container takes longer to run than the timeout, it is killed.
    pub fn run(&self, timeout: Duration) -> Result<(), RunError>
    {
        // Spawn the child process.
        let (pid, pidfd) = self.spawn()?;
        let kill_guard = KillGuard::new(pid);

        // Once the pidfd is readable, the child process has terminated.
        let mut pollfd = os::pollfd{
            fd:      pidfd.as_raw_fd(),
            events:  os::POLLIN,
            revents: 0,
        };
        let npolled = os::poll(
            slice::from_mut(&mut pollfd),
            timeout.as_millis().try_into().unwrap_or(i32::MAX),
        ).context("poll")?;

        // If poll(2) returned 0, there was a timeout.
        if npolled == 0 {
            return Err(RunError::Timeout(timeout));
        }

        // Reap the child process and find its wait status.
        let (_, wstatus) = os::waitpid(pid, 0).context("waitpid")?;

        // No more need to kill and reap.
        forget(kill_guard);

        // Check the wait status of the child process.
        if !wstatus.success() {
            return Err(RunError::Unsuccessful(wstatus));
        }

        Ok(())
    }
}
