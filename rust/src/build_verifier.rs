use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};
use std::collections::HashMap;
use log::{info, warn, debug, error};
use serde::{Deserialize, Serialize};
use tokio::process::Command;
use crate::config::GccVersion;
use crate::error::{GccBuildError, Result as GccResult};
use crate::commands::CommandExecutor;

/// Automated GCC build verification and testing system
#[derive(Clone)]
pub struct BuildVerifier {
    executor: CommandExecutor,
    test_suite: TestSuite,
    verification_cache: HashMap<String, VerificationResult>,
}

#[derive(Debug, Clone)]
struct TestSuite {
    basic_tests: Vec<BasicTest>,
    compilation_tests: Vec<CompilationTest>,
    runtime_tests: Vec<RuntimeTest>,
    benchmark_tests: Vec<BenchmarkTest>,
}

#[derive(Debug, Clone)]
struct BasicTest {
    name: String,
    command: String,
    args: Vec<String>,
    expected_output: Option<String>,
    timeout: Duration,
}

#[derive(Debug, Clone)]
struct CompilationTest {
    name: String,
    source_code: String,
    expected_flags: Vec<String>,
    should_compile: bool,
    language: Language,
}

#[derive(Debug, Clone)]
struct RuntimeTest {
    name: String,
    source_code: String,
    expected_output: String,
    compile_flags: Vec<String>,
    language: Language,
}

#[derive(Debug, Clone)]
struct BenchmarkTest {
    name: String,
    source_code: String,
    compile_flags: Vec<String>,
    expected_performance: PerformanceThreshold,
    language: Language,
}

#[derive(Debug, Clone)]
enum Language {
    C,
    Cpp,
    Fortran,
    Ada,
}

#[derive(Debug, Clone)]
struct PerformanceThreshold {
    max_compile_time_sec: f64,
    max_runtime_sec: f64,
    min_optimization_ratio: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationResult {
    pub gcc_version: String,
    pub install_path: PathBuf,
    pub verification_time: String,
    pub overall_success: bool,
    pub test_results: Vec<TestResult>,
    pub performance_metrics: PerformanceMetrics,
    pub warnings: Vec<String>,
    pub errors: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TestResult {
    pub test_name: String,
    pub test_type: String,
    pub passed: bool,
    pub duration: f64,
    pub output: String,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceMetrics {
    pub compilation_speed_files_per_sec: f64,
    pub binary_size_efficiency: f64,
    pub runtime_performance_score: f64,
    pub memory_usage_mb: f64,
}

impl BuildVerifier {
    pub fn new() -> Self {
        Self {
            executor: CommandExecutor::new(),
            test_suite: Self::create_test_suite(),
            verification_cache: HashMap::new(),
        }
    }
    
    /// Verify a GCC installation comprehensively
    pub async fn verify_gcc_build(
        &mut self,
        gcc_version: &GccVersion,
        install_path: &Path,
    ) -> GccResult<VerificationResult> {
        let verification_key = format!("{}-{}", gcc_version, install_path.display());
        
        info!("🔍 Starting comprehensive verification of GCC {} at {}", 
              gcc_version, install_path.display());
        
        let start_time = Instant::now();
        let mut test_results = Vec::new();
        let mut warnings = Vec::new();
        let mut errors = Vec::new();
        
        // Basic functionality tests
        info!("🧪 Running basic functionality tests...");
        let basic_results = self.run_basic_tests(install_path, &mut warnings).await?;
        test_results.extend(basic_results);
        
        // Compilation tests
        info!("🔨 Running compilation tests...");
        let compilation_results = self.run_compilation_tests(install_path, &mut warnings).await?;
        test_results.extend(compilation_results);
        
        // Runtime tests
        info!("🏃 Running runtime tests...");
        let runtime_results = self.run_runtime_tests(install_path, &mut warnings).await?;
        test_results.extend(runtime_results);
        
        // Performance benchmarks
        info!("⚡ Running performance benchmarks...");
        let (benchmark_results, performance_metrics) = self.run_benchmark_tests(install_path).await?;
        test_results.extend(benchmark_results);
        
        // Feature detection tests
        info!("🔧 Testing GCC features...");
        let feature_results = self.test_gcc_features(gcc_version, install_path, &mut warnings).await?;
        test_results.extend(feature_results);
        
        let verification_time = chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
        let overall_success = test_results.iter().all(|r| r.passed) && errors.is_empty();
        
        let result = VerificationResult {
            gcc_version: gcc_version.to_string(),
            install_path: install_path.to_path_buf(),
            verification_time,
            overall_success,
            test_results,
            performance_metrics,
            warnings,
            errors,
        };
        
        // Cache result
        self.verification_cache.insert(verification_key, result.clone());
        
        let duration = start_time.elapsed();
        if overall_success {
            info!("✅ GCC {} verification PASSED ({} tests, {:.1}s)", 
                  gcc_version, result.test_results.len(), duration.as_secs_f64());
        } else {
            warn!("❌ GCC {} verification FAILED ({} errors, {:.1}s)", 
                  gcc_version, result.errors.len(), duration.as_secs_f64());
        }
        
        Ok(result)
    }
    
    /// Run basic functionality tests
    async fn run_basic_tests(
        &self,
        install_path: &Path,
        warnings: &mut Vec<String>,
    ) -> GccResult<Vec<TestResult>> {
        let mut results = Vec::new();
        
        for test in &self.test_suite.basic_tests {
            let start_time = Instant::now();
            let gcc_path = install_path.join("bin").join(&test.command);
            
            if !gcc_path.exists() {
                results.push(TestResult {
                    test_name: test.name.clone(),
                    test_type: "basic".to_string(),
                    passed: false,
                    duration: 0.0,
                    output: String::new(),
                    error_message: Some(format!("Executable not found: {}", gcc_path.display())),
                });
                continue;
            }
            
            let output = tokio::time::timeout(
                test.timeout,
                Command::new(&gcc_path)
                    .args(&test.args)
                    .output()
            ).await;
            
            let duration = start_time.elapsed().as_secs_f64();
            
            let (passed, output_str, error_message) = match output {
                Ok(Ok(output)) => {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    let combined_output = format!("{}\n{}", stdout, stderr);
                    
                    let passed = if let Some(expected) = &test.expected_output {
                        combined_output.contains(expected)
                    } else {
                        output.status.success()
                    };
                    
                    (passed, combined_output, None)
                }
                Ok(Err(e)) => (false, String::new(), Some(e.to_string())),
                Err(_) => (false, String::new(), Some("Test timed out".to_string())),
            };
            
            if !passed && error_message.is_none() {
                warnings.push(format!("Basic test '{}' failed", test.name));
            }
            
            results.push(TestResult {
                test_name: test.name.clone(),
                test_type: "basic".to_string(),
                passed,
                duration,
                output: output_str,
                error_message,
            });
        }
        
        Ok(results)
    }
    
    /// Run compilation tests
    async fn run_compilation_tests(
        &self,
        install_path: &Path,
        warnings: &mut Vec<String>,
    ) -> GccResult<Vec<TestResult>> {
        let mut results = Vec::new();
        let temp_dir = tempfile::tempdir()?;
        
        for test in &self.test_suite.compilation_tests {
            let start_time = Instant::now();
            
            // Write test source file
            let source_ext = match test.language {
                Language::C => "c",
                Language::Cpp => "cpp",
                Language::Fortran => "f90",
                Language::Ada => "adb",
            };
            
            let source_path = temp_dir.path().join(format!("test_{}.{}", test.name, source_ext));
            tokio::fs::write(&source_path, &test.source_code).await?;
            
            // Get appropriate compiler
            let compiler = match test.language {
                Language::C => "gcc",
                Language::Cpp => "g++",
                Language::Fortran => "gfortran",
                Language::Ada => "gnat",
            };
            
            let compiler_path = install_path.join("bin").join(compiler);
            if !compiler_path.exists() {
                results.push(TestResult {
                    test_name: test.name.clone(),
                    test_type: "compilation".to_string(),
                    passed: false,
                    duration: 0.0,
                    output: String::new(),
                    error_message: Some(format!("Compiler not found: {}", compiler)),
                });
                continue;
            }
            
            // Compile test
            let output_path = temp_dir.path().join(format!("test_{}", test.name));
            let mut args = test.expected_flags.clone();
            args.extend(vec![
                source_path.to_str().unwrap().to_string(),
                "-o".to_string(),
                output_path.to_str().unwrap().to_string(),
            ]);
            
            let output = Command::new(&compiler_path)
                .args(&args)
                .output()
                .await;
            
            let duration = start_time.elapsed().as_secs_f64();
            
            let (passed, output_str, error_message) = match output {
                Ok(output) => {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    let combined_output = format!("{}\n{}", stdout, stderr);
                    
                    let compilation_success = output.status.success();
                    let passed = compilation_success == test.should_compile;
                    
                    (passed, combined_output, None)
                }
                Err(e) => (false, String::new(), Some(e.to_string())),
            };
            
            if !passed {
                warnings.push(format!("Compilation test '{}' failed", test.name));
            }
            
            results.push(TestResult {
                test_name: test.name.clone(),
                test_type: "compilation".to_string(),
                passed,
                duration,
                output: output_str,
                error_message,
            });
        }
        
        Ok(results)
    }
    
    /// Run runtime tests
    async fn run_runtime_tests(
        &self,
        install_path: &Path,
        warnings: &mut Vec<String>,
    ) -> GccResult<Vec<TestResult>> {
        let mut results = Vec::new();
        let temp_dir = tempfile::tempdir()?;
        
        for test in &self.test_suite.runtime_tests {
            let start_time = Instant::now();
            
            // Compile and run test
            let compile_result = self.compile_and_run_test(
                install_path,
                &temp_dir,
                test,
            ).await;
            
            let duration = start_time.elapsed().as_secs_f64();
            
            let (passed, output_str, error_message) = match compile_result {
                Ok(actual_output) => {
                    let passed = actual_output.trim() == test.expected_output.trim();
                    if !passed {
                        warnings.push(format!("Runtime test '{}' output mismatch", test.name));
                    }
                    (passed, actual_output, None)
                }
                Err(e) => (false, String::new(), Some(e.to_string())),
            };
            
            results.push(TestResult {
                test_name: test.name.clone(),
                test_type: "runtime".to_string(),
                passed,
                duration,
                output: output_str,
                error_message,
            });
        }
        
        Ok(results)
    }
    
    /// Compile and run a test
    async fn compile_and_run_test(
        &self,
        install_path: &Path,
        temp_dir: &tempfile::TempDir,
        test: &RuntimeTest,
    ) -> GccResult<String> {
        // Write source file
        let source_ext = match test.language {
            Language::C => "c",
            Language::Cpp => "cpp",
            Language::Fortran => "f90",
            Language::Ada => "adb",
        };
        
        let source_path = temp_dir.path().join(format!("test_{}.{}", test.name, source_ext));
        tokio::fs::write(&source_path, &test.source_code).await?;
        
        // Get compiler
        let compiler = match test.language {
            Language::C => "gcc",
            Language::Cpp => "g++",
            Language::Fortran => "gfortran",
            Language::Ada => "gnat",
        };
        
        let compiler_path = install_path.join("bin").join(compiler);
        let output_path = temp_dir.path().join(format!("test_{}", test.name));
        
        // Compile
        let mut args = test.compile_flags.clone();
        args.extend(vec![
            source_path.to_str().unwrap().to_string(),
            "-o".to_string(),
            output_path.to_str().unwrap().to_string(),
        ]);
        
        let compile_output = Command::new(&compiler_path)
            .args(&args)
            .output()
            .await?;
        
        if !compile_output.status.success() {
            return Err(GccBuildError::compilation(format!(
                "Compilation failed: {}", 
                String::from_utf8_lossy(&compile_output.stderr)
            )));
        }
        
        // Run
        let run_output = Command::new(&output_path)
            .output()
            .await?;
        
        if !run_output.status.success() {
            return Err(GccBuildError::test_execution(format!(
                "Runtime failed: {}", 
                String::from_utf8_lossy(&run_output.stderr)
            )));
        }
        
        Ok(String::from_utf8_lossy(&run_output.stdout).to_string())
    }
    
    /// Run performance benchmark tests
    async fn run_benchmark_tests(
        &self,
        install_path: &Path,
    ) -> GccResult<(Vec<TestResult>, PerformanceMetrics)> {
        let mut results = Vec::new();
        let temp_dir = tempfile::tempdir()?;
        
        let mut total_compile_time = 0.0;
        let mut total_files = 0;
        let mut total_binary_size = 0u64;
        let mut total_runtime_score = 0.0;
        
        for test in &self.test_suite.benchmark_tests {
            let start_time = Instant::now();
            
            // Benchmark compilation speed
            let (compile_time, binary_size) = self.benchmark_compilation(
                install_path,
                &temp_dir,
                test,
            ).await?;
            
            // Benchmark runtime performance
            let runtime_score = self.benchmark_runtime(
                install_path,
                &temp_dir,
                test,
            ).await?;
            
            let duration = start_time.elapsed().as_secs_f64();
            
            let passed = compile_time <= test.expected_performance.max_compile_time_sec;
            
            total_compile_time += compile_time;
            total_files += 1;
            total_binary_size += binary_size;
            total_runtime_score += runtime_score;
            
            results.push(TestResult {
                test_name: test.name.clone(),
                test_type: "benchmark".to_string(),
                passed,
                duration,
                output: format!("Compile: {:.2}s, Size: {}KB, Runtime: {:.2}", 
                               compile_time, binary_size / 1024, runtime_score),
                error_message: None,
            });
        }
        
        let performance_metrics = PerformanceMetrics {
            compilation_speed_files_per_sec: if total_compile_time > 0.0 {
                total_files as f64 / total_compile_time
            } else {
                0.0
            },
            binary_size_efficiency: total_binary_size as f64 / total_files as f64,
            runtime_performance_score: total_runtime_score / total_files as f64,
            memory_usage_mb: 0.0, // Would need process monitoring
        };
        
        Ok((results, performance_metrics))
    }
    
    /// Benchmark compilation performance
    async fn benchmark_compilation(
        &self,
        install_path: &Path,
        temp_dir: &tempfile::TempDir,
        test: &BenchmarkTest,
    ) -> GccResult<(f64, u64)> {
        let source_path = temp_dir.path().join(format!("bench_{}.c", test.name));
        tokio::fs::write(&source_path, &test.source_code).await?;
        
        let compiler_path = install_path.join("bin/gcc");
        let output_path = temp_dir.path().join(format!("bench_{}", test.name));
        
        let start_time = Instant::now();
        
        let mut args = test.compile_flags.clone();
        args.extend(vec![
            source_path.to_str().unwrap().to_string(),
            "-o".to_string(),
            output_path.to_str().unwrap().to_string(),
        ]);
        
        let output = Command::new(&compiler_path)
            .args(&args)
            .output()
            .await?;
        
        let compile_time = start_time.elapsed().as_secs_f64();
        
        if !output.status.success() {
            return Err(GccBuildError::compilation(
                "Benchmark compilation failed".to_string()
            ));
        }
        
        let binary_size = if output_path.exists() {
            tokio::fs::metadata(&output_path).await?.len()
        } else {
            0
        };
        
        Ok((compile_time, binary_size))
    }
    
    /// Benchmark runtime performance
    async fn benchmark_runtime(
        &self,
        _install_path: &Path,
        temp_dir: &tempfile::TempDir,
        test: &BenchmarkTest,
    ) -> GccResult<f64> {
        let binary_path = temp_dir.path().join(format!("bench_{}", test.name));
        
        if !binary_path.exists() {
            return Ok(0.0);
        }
        
        let start_time = Instant::now();
        let output = Command::new(&binary_path).output().await?;
        let runtime = start_time.elapsed().as_secs_f64();
        
        if !output.status.success() {
            return Ok(0.0);
        }
        
        // Simple performance score (inverse of runtime)
        let score = if runtime > 0.0 { 1.0 / runtime } else { 0.0 };
        Ok(score)
    }
    
    /// Test GCC-specific features
    async fn test_gcc_features(
        &self,
        gcc_version: &GccVersion,
        install_path: &Path,
        warnings: &mut Vec<String>,
    ) -> GccResult<Vec<TestResult>> {
        let mut results = Vec::new();
        
        // Test version reporting
        let version_test = self.test_version_output(install_path).await?;
        results.push(version_test);
        
        // Test optimization levels
        let opt_tests = self.test_optimization_levels(install_path).await?;
        results.extend(opt_tests);
        
        // Test language standards
        let std_tests = self.test_language_standards(install_path, gcc_version).await?;
        results.extend(std_tests);
        
        // Test target architectures
        let arch_tests = self.test_target_architectures(install_path, warnings).await?;
        results.extend(arch_tests);
        
        Ok(results)
    }
    
    async fn test_version_output(&self, install_path: &Path) -> GccResult<TestResult> {
        let start_time = Instant::now();
        let gcc_path = install_path.join("bin/gcc");
        
        let output = Command::new(&gcc_path)
            .args(&["--version"])
            .output()
            .await?;
        
        let duration = start_time.elapsed().as_secs_f64();
        let stdout = String::from_utf8_lossy(&output.stdout);
        let passed = output.status.success() && stdout.contains("gcc");
        
        Ok(TestResult {
            test_name: "version_output".to_string(),
            test_type: "feature".to_string(),
            passed,
            duration,
            output: stdout.to_string(),
            error_message: None,
        })
    }
    
    async fn test_optimization_levels(&self, install_path: &Path) -> GccResult<Vec<TestResult>> {
        let mut results = Vec::new();
        let optimization_levels = ["-O0", "-O1", "-O2", "-O3", "-Os", "-Oz"];
        
        for opt_level in &optimization_levels {
            let start_time = Instant::now();
            let gcc_path = install_path.join("bin/gcc");
            
            let output = Command::new(&gcc_path)
                .args(&[opt_level, "--help=optimizers"])
                .output()
                .await?;
            
            let duration = start_time.elapsed().as_secs_f64();
            let passed = output.status.success();
            
            results.push(TestResult {
                test_name: format!("optimization_{}", opt_level.trim_start_matches('-')),
                test_type: "feature".to_string(),
                passed,
                duration,
                output: String::from_utf8_lossy(&output.stdout).to_string(),
                error_message: if passed { None } else { Some("Optimization level not supported".to_string()) },
            });
        }
        
        Ok(results)
    }
    
    async fn test_language_standards(&self, install_path: &Path, gcc_version: &GccVersion) -> GccResult<Vec<TestResult>> {
        let mut results = Vec::new();
        
        // Test C standards
        let c_standards = if gcc_version.major >= 11 {
            vec!["-std=c11", "-std=c17", "-std=c2x"]
        } else {
            vec!["-std=c11", "-std=c17"]
        };
        
        for std in &c_standards {
            let result = self.test_standard_support(install_path, "gcc", std).await?;
            results.push(result);
        }
        
        // Test C++ standards
        let cpp_standards = if gcc_version.major >= 11 {
            vec!["-std=c++14", "-std=c++17", "-std=c++20"]
        } else {
            vec!["-std=c++14", "-std=c++17"]
        };
        
        for std in &cpp_standards {
            let result = self.test_standard_support(install_path, "g++", std).await?;
            results.push(result);
        }
        
        Ok(results)
    }
    
    async fn test_standard_support(&self, install_path: &Path, compiler: &str, standard: &str) -> GccResult<TestResult> {
        let start_time = Instant::now();
        let compiler_path = install_path.join("bin").join(compiler);
        
        let output = Command::new(&compiler_path)
            .args(&[standard, "-x", "c", "-", "-fsyntax-only"])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()?
            .wait_with_output()
            .await?;
        
        let duration = start_time.elapsed().as_secs_f64();
        let passed = output.status.success() || 
                     !String::from_utf8_lossy(&output.stderr).contains("unrecognized");
        
        Ok(TestResult {
            test_name: format!("standard_{}_{}", compiler, standard.trim_start_matches('-')),
            test_type: "feature".to_string(),
            passed,
            duration,
            output: String::from_utf8_lossy(&output.stderr).to_string(),
            error_message: None,
        })
    }
    
    async fn test_target_architectures(&self, install_path: &Path, warnings: &mut Vec<String>) -> GccResult<Vec<TestResult>> {
        let mut results = Vec::new();
        let gcc_path = install_path.join("bin/gcc");
        
        let output = Command::new(&gcc_path)
            .args(&["--help=target"])
            .output()
            .await?;
        
        let target_help = String::from_utf8_lossy(&output.stdout);
        let has_multilib = target_help.contains("multilib");
        
        if !has_multilib {
            warnings.push("Multilib support not detected".to_string());
        }
        
        results.push(TestResult {
            test_name: "target_architectures".to_string(),
            test_type: "feature".to_string(),
            passed: output.status.success(),
            duration: 0.0,
            output: target_help.to_string(),
            error_message: None,
        });
        
        Ok(results)
    }
    
    /// Create comprehensive test suite
    fn create_test_suite() -> TestSuite {
        let basic_tests = vec![
            BasicTest {
                name: "gcc_version".to_string(),
                command: "gcc".to_string(),
                args: vec!["--version".to_string()],
                expected_output: Some("gcc".to_string()),
                timeout: Duration::from_secs(10),
            },
            BasicTest {
                name: "gpp_version".to_string(),
                command: "g++".to_string(),
                args: vec!["--version".to_string()],
                expected_output: Some("g++".to_string()),
                timeout: Duration::from_secs(10),
            },
            BasicTest {
                name: "help_output".to_string(),
                command: "gcc".to_string(),
                args: vec!["--help".to_string()],
                expected_output: Some("Usage:".to_string()),
                timeout: Duration::from_secs(10),
            },
        ];
        
        let compilation_tests = vec![
            CompilationTest {
                name: "hello_world_c".to_string(),
                source_code: r#"
#include <stdio.h>
int main() {
    printf("Hello, World!\n");
    return 0;
}
"#.to_string(),
                expected_flags: vec!["-O2".to_string()],
                should_compile: true,
                language: Language::C,
            },
            CompilationTest {
                name: "hello_world_cpp".to_string(),
                source_code: r#"
#include <iostream>
int main() {
    std::cout << "Hello, World!" << std::endl;
    return 0;
}
"#.to_string(),
                expected_flags: vec!["-O2".to_string(), "-std=c++17".to_string()],
                should_compile: true,
                language: Language::Cpp,
            },
            CompilationTest {
                name: "syntax_error".to_string(),
                source_code: "int main() { return ); }".to_string(),
                expected_flags: vec![],
                should_compile: false,
                language: Language::C,
            },
        ];
        
        let runtime_tests = vec![
            RuntimeTest {
                name: "simple_arithmetic".to_string(),
                source_code: r#"
#include <stdio.h>
int main() {
    printf("%d\n", 2 + 2);
    return 0;
}
"#.to_string(),
                expected_output: "4".to_string(),
                compile_flags: vec!["-O2".to_string()],
                language: Language::C,
            },
            RuntimeTest {
                name: "cpp_stl".to_string(),
                source_code: r#"
#include <iostream>
#include <vector>
#include <algorithm>
int main() {
    std::vector<int> v = {3, 1, 4, 1, 5};
    std::sort(v.begin(), v.end());
    std::cout << v[0] << std::endl;
    return 0;
}
"#.to_string(),
                expected_output: "1".to_string(),
                compile_flags: vec!["-O2".to_string(), "-std=c++17".to_string()],
                language: Language::Cpp,
            },
        ];
        
        let benchmark_tests = vec![
            BenchmarkTest {
                name: "compilation_speed".to_string(),
                source_code: r#"
#include <stdio.h>
#include <math.h>
int main() {
    double sum = 0.0;
    for (int i = 0; i < 1000000; i++) {
        sum += sin(i) * cos(i);
    }
    printf("%.6f\n", sum);
    return 0;
}
"#.to_string(),
                compile_flags: vec!["-O3".to_string(), "-lm".to_string()],
                expected_performance: PerformanceThreshold {
                    max_compile_time_sec: 30.0,
                    max_runtime_sec: 5.0,
                    min_optimization_ratio: 0.8,
                },
                language: Language::C,
            },
        ];
        
        TestSuite {
            basic_tests,
            compilation_tests,
            runtime_tests,
            benchmark_tests,
        }
    }
    
    /// Get verification summary
    pub fn get_verification_summary(&self) -> VerificationSummary {
        let total_verifications = self.verification_cache.len();
        let successful_verifications = self.verification_cache.values()
            .filter(|r| r.overall_success)
            .count();
        
        let average_test_count = if total_verifications > 0 {
            self.verification_cache.values()
                .map(|r| r.test_results.len())
                .sum::<usize>() as f64 / total_verifications as f64
        } else {
            0.0
        };
        
        VerificationSummary {
            total_verifications,
            successful_verifications,
            success_rate: if total_verifications > 0 {
                successful_verifications as f64 / total_verifications as f64 * 100.0
            } else {
                0.0
            },
            average_test_count,
        }
    }
}

#[derive(Debug)]
pub struct VerificationSummary {
    pub total_verifications: usize,
    pub successful_verifications: usize,
    pub success_rate: f64,
    pub average_test_count: f64,
}