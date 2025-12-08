//! Shared HTTP client with optimized settings for GCC downloads.
//!
//! Uses `OnceLock` for lazy initialization of a single shared client instance,
//! following reqwest best practices for connection pooling and resource efficiency.

use reqwest::Client;
use std::sync::OnceLock;
use std::time::Duration;

/// Global HTTP client instance for all download operations
static HTTP_CLIENT: OnceLock<Client> = OnceLock::new();

/// Default timeouts for HTTP operations (in seconds)
pub mod timeouts {
    /// Connection timeout - how long to wait for initial TCP connection
    pub const CONNECT_SECS: u64 = 10;
    /// Read timeout - how long to wait for data after connection established
    pub const READ_SECS: u64 = 30;
    /// Overall request timeout for small requests (checksums, version lookups)
    pub const REQUEST_SECS: u64 = 60;
    /// Overall request timeout for large file downloads
    pub const DOWNLOAD_SECS: u64 = 600; // 10 minutes for large tarballs
}

/// Get or initialize the shared HTTP client
///
/// This client is configured with:
/// - Connection pooling for efficient reuse
/// - Appropriate timeouts for stalled connection detection
/// - Built-in decompression support (enabled by default in reqwest)
///
/// # Example
/// ```ignore
/// let client = get_client();
/// let response = client.get("https://example.com").send().await?;
/// ```
pub fn get_client() -> &'static Client {
    HTTP_CLIENT.get_or_init(|| {
        Client::builder()
            .connect_timeout(Duration::from_secs(timeouts::CONNECT_SECS))
            .read_timeout(Duration::from_secs(timeouts::READ_SECS))
            .timeout(Duration::from_secs(timeouts::REQUEST_SECS))
            .pool_max_idle_per_host(4)
            .build()
            .expect("Failed to create HTTP client")
    })
}

/// Create a client specifically configured for large file downloads
///
/// Uses longer timeouts suitable for downloading GCC tarballs (100+ MB)
pub fn create_download_client() -> reqwest::Result<Client> {
    Client::builder()
        .connect_timeout(Duration::from_secs(timeouts::CONNECT_SECS))
        .read_timeout(Duration::from_secs(timeouts::READ_SECS))
        .timeout(Duration::from_secs(timeouts::DOWNLOAD_SECS))
        .pool_max_idle_per_host(2)
        .build()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_client_initialization() {
        let client = get_client();
        // Client should be the same instance on subsequent calls
        let client2 = get_client();
        assert!(std::ptr::eq(client, client2));
    }

    #[test]
    fn test_download_client_creation() {
        let client = create_download_client();
        assert!(client.is_ok());
    }
}
