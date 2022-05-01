// SPDX-License-Identifier: AGPL-3.0-only

use std::os::unix::io::RawFd;

pub use self::run::*;

mod run;

pub struct ActionContext
{
    pub scratch_dir: RawFd,
    pub log_file: RawFd,
}
