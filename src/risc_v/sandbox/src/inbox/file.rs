// SPDX-FileCopyrightText: 2024 TriliTech <contact@trili.tech>
//
// SPDX-License-Identifier: MIT

use serde::{Deserialize, Serialize};
use std::{fs, path::Path};

/// Single Inbox message
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(untagged)]
pub enum Message {
    /// Already serialised inbox message
    Raw(#[serde(with = "hex::serde")] Vec<u8>),

    /// External inbox message
    External {
        #[serde(with = "hex::serde")]
        external: Vec<u8>,
    },
}

/// Inbox contents read from a file grouped by levels.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct InboxFile(pub Vec<Vec<Message>>);

impl InboxFile {
    /// Load the Inbox file.
    pub fn load(path: &Path) -> Result<Self, Box<dyn std::error::Error>> {
        let contents = fs::read(path)?;
        let inbox = serde_json::de::from_slice(contents.as_slice())?;
        Ok(inbox)
    }

    /// Write the Inbox file to a file.
    #[allow(unused)]
    pub fn save(&self, path: &Path) -> Result<(), Box<dyn std::error::Error>> {
        let mut file = fs::File::create(path)?;
        serde_json::ser::to_writer_pretty(&mut file, self)?;
        Ok(())
    }
}
