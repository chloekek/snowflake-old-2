// SPDX-License-Identifier: AGPL-3.0-only

//! Snowflake configuration.

/// Nix store path for the bash package.
pub const BASH_PATH: &str = env!("SNOWFLAKE_BASH_PATH");

/// Nix store path for the coreutils package.
pub const COREUTILS_PATH: &str = env!("SNOWFLAKE_BASH_PATH");
