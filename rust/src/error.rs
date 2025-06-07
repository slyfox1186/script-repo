#![allow(dead_code)]
use thiserror::Error;

#[derive(Error, Debug)]
pub enum GccBuildError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    
    #[error("HTTP error: {message}")]
    Http { message: String },
    
    #[error("JSON parsing error: {0}")]
    Json(#[from] serde_json::Error),
    
    #[error("System requirements not met: {message}")]
    SystemRequirements { message: String },
    
    #[error("Package manager error: {message}")]
    PackageManager { message: String },
    
    #[error("Download failed: {url} - {reason}")]
    Download { url: String, reason: String },
    
    #[error("Checksum verification failed: expected {expected}, got {actual}")]
    ChecksumMismatch { expected: String, actual: String },
    
    #[error("Build failed: {stage} - {message}")]
    BuildFailed { stage: String, message: String },
    
    #[error("Configuration error: {message}")]
    Configuration { message: String },
    
    #[error("Command execution failed: {command} - {exit_code}")]
    CommandFailed { command: String, exit_code: i32 },
    
    #[error("File operation failed: {operation} on {path} - {reason}")]
    FileOperation { operation: String, path: String, reason: String },
    
    #[error("Directory operation failed: {operation} on {path} - {reason}")]
    DirectoryOperation { operation: String, path: String, reason: String },
    
    #[error("Unsupported GCC version: {version}")]
    UnsupportedGccVersion { version: String },
    
    #[error("Network timeout: {operation}")]
    NetworkTimeout { operation: String },
    
    #[error("Resource exhausted: {resource} - {details}")]
    ResourceExhausted { resource: String, details: String },
    
    #[error("Compilation failed: {message}")]
    Compilation { message: String },
    
    #[error("Test execution failed: {message}")]
    TestExecution { message: String },
    
    #[error("IO operation failed: {operation} - {message}")]
    IoError { operation: String, message: String },
}

impl GccBuildError {
    pub fn system_requirements(message: impl Into<String>) -> Self {
        Self::SystemRequirements { message: message.into() }
    }
    
    pub fn package_manager(message: impl Into<String>) -> Self {
        Self::PackageManager { message: message.into() }
    }
    
    pub fn download(url: impl Into<String>, reason: impl Into<String>) -> Self {
        Self::Download { 
            url: url.into(), 
            reason: reason.into() 
        }
    }
    
    pub fn checksum_mismatch(expected: impl Into<String>, actual: impl Into<String>) -> Self {
        Self::ChecksumMismatch { 
            expected: expected.into(), 
            actual: actual.into() 
        }
    }
    
    pub fn build_failed(stage: impl Into<String>, message: impl Into<String>) -> Self {
        Self::BuildFailed { 
            stage: stage.into(), 
            message: message.into() 
        }
    }
    
    pub fn configuration(message: impl Into<String>) -> Self {
        Self::Configuration { message: message.into() }
    }
    
    pub fn command_failed(command: impl Into<String>, exit_code: i32) -> Self {
        Self::CommandFailed { 
            command: command.into(), 
            exit_code 
        }
    }
    
    pub fn file_operation(operation: impl Into<String>, path: impl Into<String>, reason: impl Into<String>) -> Self {
        Self::FileOperation { 
            operation: operation.into(), 
            path: path.into(), 
            reason: reason.into() 
        }
    }
    
    pub fn directory_operation(operation: impl Into<String>, path: impl Into<String>, reason: impl Into<String>) -> Self {
        Self::DirectoryOperation { 
            operation: operation.into(), 
            path: path.into(), 
            reason: reason.into() 
        }
    }
    
    pub fn unsupported_gcc_version(version: impl Into<String>) -> Self {
        Self::UnsupportedGccVersion { version: version.into() }
    }
    
    pub fn network_timeout(operation: impl Into<String>) -> Self {
        Self::NetworkTimeout { operation: operation.into() }
    }
    
    pub fn resource_exhausted(resource: impl Into<String>, details: impl Into<String>) -> Self {
        Self::ResourceExhausted { 
            resource: resource.into(), 
            details: details.into() 
        }
    }
    
    pub fn compilation(message: impl Into<String>) -> Self {
        Self::Compilation { message: message.into() }
    }
    
    pub fn test_execution(message: impl Into<String>) -> Self {
        Self::TestExecution { message: message.into() }
    }
    
    pub fn io_error(operation: impl Into<String>, message: impl Into<String>) -> Self {
        Self::IoError { 
            operation: operation.into(), 
            message: message.into() 
        }
    }
}

pub type Result<T> = std::result::Result<T, GccBuildError>;