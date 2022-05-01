// SPDX-License-Identifier: AGPL-3.0-only

#![feature(io_error_other)]
#![feature(io_safety)]
#![feature(linux_pidfd)]
#![feature(maybe_uninit_uninit_array)]
#![feature(never_type)]
#![feature(panic_always_abort)]
#![feature(unwrap_infallible)]
#![warn(missing_docs)]

pub mod actions;
pub mod config;
pub mod container;
