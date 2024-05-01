//! The Wasmer binary lib

#![deny(
    missing_docs,
    dead_code,
    nonstandard_style,
    unused_mut,
    unused_variables,
    unused_unsafe,
    unreachable_patterns,
    unstable_features
)]
#![doc(html_favicon_url = "https://wasmer.io/images/icons/favicon-32x32.png")]
#![doc(html_logo_url = "https://github.com/wasmerio.png?size=200")]

#[macro_use]
extern crate anyhow;

pub mod commands;
pub mod common;
#[macro_use]
pub mod error;
pub mod c_gen;
pub mod cli;
pub mod logging;
pub mod package_source;
pub mod store;
pub mod suggestions;
pub mod utils;
pub mod wasmer_home;

/// Version number of this crate.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
