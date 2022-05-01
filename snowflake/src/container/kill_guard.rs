// SPDX-License-Identifier: AGPL-3.0-only

use snowflake_os as os;

/// Kills and reaps a child process when dropped.
///
/// Normally, sending SIGKILL to a process is frowned upon.
/// But this is a container; it won't affect anything else.
pub struct KillGuard(os::pid_t);

impl KillGuard
{
    /// Create a kill guard for a given pid.
    pub fn new(pid: os::pid_t) -> Self
    {
        Self(pid)
    }
}

impl Drop for KillGuard
{
    fn drop(&mut self)
    {
        let _ = os::kill(self.0, os::SIGKILL);
        let _ = os::waitpid(self.0, 0);
    }
}
