#!/bin/bash

# Log Collector and Sensitive Data Filter
# This script collects build logs and filters sensitive information
# 
# Version: Enhanced with timestamp consistency fix and output stream management
# Original commit: 24d032c07a54d63da2596249f7c037ffdf3d625b
# Fix: Use BUILD_TIMESTAMP environment variable for consistency
# Fix: Handle multi-line commands properly
# Fix: Redirect all status messages to stderr (>&2) to prevent polluting stdout result capture

set -euo pipefail

# Configuration
LOG_DIR="build-logs"

# 修复：使用环境变量中的时间戳，或者生成新的
if [[ -n "${BUILD_TIMESTAMP:-}" ]]; then
    TIMESTAMP="$BUILD_TIMESTAMP"
else
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
fi

WORKFLOW_RUN_ID="${GITHUB_RUN_ID:-unknown}"
JOB_NAME="${GITHUB_JOB:-unknown}"
STEP_NAME="${GITHUB_STEP:-unknown}"

# Create log directory with enhanced error handling
mkdir -p "$LOG_DIR" || {
    echo "❌ Failed to create log directory: $LOG_DIR" >&2
    echo "Current working directory: $(pwd)" >&2
    echo "Available space: $(df -h . | tail -1)" >&2
    exit 1
}

# Verify directory was created
if [[ ! -d "$LOG_DIR" ]]; then
    echo "❌ Log directory was not created successfully: $LOG_DIR" >&2
    exit 1
fi

echo "✅ Log directory created: $LOG_DIR" >&2
echo "📅 Using timestamp: $TIMESTAMP" >&2

# Sensitive data patterns to filter (enhanced patterns)
SENSITIVE_PATTERNS=(
    # GitHub tokens
    "ghp_[a-zA-Z0-9]{36}"
    "gho_[a-zA-Z0-9]{36}"
    "ghu_[a-zA-Z0-9]{36}"
    "ghs_[a-zA-Z0-9]{36}"
    "ghr_[a-zA-Z0-9]{36}"
    "github_token[[:space:]]*=[[:space:]]*['\"][^\"']*['\"]"
    
    # JKS keystore data (base64 patterns)
    "JKS[[:space:]]*=[[:space:]]*['\"][a-zA-Z0-9+\/=]{100,}['\"]"
    "keyStorePassword[[:space:]]*=[[:space:]]*['\"][^\"']*['\"]"
    "keyPassword[[:space:]]*=[[:space:]]*['\"][^\"']*['\"]"
    "signingKey[[:space:]]*=[[:space:]]*['\"][a-zA-Z0-9+\/=]{100,}['\"]"
    
    # Cachix tokens
    "CACHIX_TOKEN[[:space:]]*=[[:space:]]*['\"][^\"']*['\"]"
    
    # Other potential secrets
    "WORKFLOW_TOKEN[[:space:]]*=[[:space:]]*['\"][^\"']*['\"]"
    "secret[s]?[[:space:]]*=[[:space:]]*['\"][^\"']{8,}['\"]"
    
    # Email addresses (partial masking)
    "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"
)

# Replacement patterns (enhanced replacements)
REPLACEMENTS=(
    "s/ghp_[a-zA-Z0-9]{36}/ghp_***************/g"
    "s/gho_[a-zA-Z0-9]{36}/gho_***************/g"
    "s/ghu_[a-zA-Z0-9]{36}/ghu_***************/g"
    "s/ghs_[a-zA-Z0-9]{36}/ghs_***************/g"
    "s/ghr_[a-zA-Z0-9]{36}/ghr_***************/g"
    "s/github_token[[:space:]]*=[[:space:]]*['\"][^\"']*['\"]/github_token=\"***\"/g"
    "s/JKS[[:space:]]*=[[:space:]]*['\"][a-zA-Z0-9+\/=]{100,}['\"]/JKS=\"***BASE64_DATA***\"/g"
    "s/keyStorePassword[[:space:]]*=[[:space:]]*['\"][^\"']*['\"]/keyStorePassword=\"***\"/g"
    "s/keyPassword[[:space:]]*=[[:space:]]*['\"][^\"']*['\"]/keyPassword=\"***\"/g"
    "s/signingKey[[:space:]]*=[[:space:]]*['\"][a-zA-Z0-9+\/=]{100,}['\"]/signingKey=\"***BASE64_DATA***\"/g"
    "s/CACHIX_TOKEN[[:space:]]*=[[:space:]]*['\"][^\"']*['\"]/CACHIX_TOKEN=\"***\"/g"
    "s/WORKFLOW_TOKEN[[:space:]]*=[[:space:]]*['\"][^\"']*['\"]/WORKFLOW_TOKEN=\"***\"/g"
    "s/secret[s]?[[:space:]]*=[[:space:]]*['\"][^\"']{8,}['\"]/secret=\"***\"/g"
    "s/[a-zA-Z0-9._%+-]\{1,3\}@[a-zA-Z0-9.-]\+\.[a-zA-Z]\{2,\}/***@***.***/"
)

# Function to filter sensitive data (enhanced with temp file handling)
filter_sensitive_data() {
    local input_file="$1"
    local output_file="$2"
    
    echo "🔒 Filtering sensitive data from $input_file..." >&2
    
    # Create a temporary file for processing
    local temp_file="${output_file}.tmp"
    
    # Copy content to temp file if input and output are different files
    if [[ "$input_file" != "$output_file" ]]; then
        cp "$input_file" "$temp_file"
    else
        # If same file, create temp copy
        cp "$input_file" "$temp_file"
    fi
    
    # Apply all replacements to temp file
    for replacement in "${REPLACEMENTS[@]}"; do
        sed -i.bak -E "$replacement" "$temp_file"
    done
    
    # Remove backup files
    rm -f "$temp_file".bak
    
    # Move temp file to final location
    mv "$temp_file" "$output_file"
    
    echo "✅ Sensitive data filtered" >&2
}

# Function to collect system information (enhanced)
collect_system_info() {
    local info_file="$LOG_DIR/system-info-$TIMESTAMP.txt"
    
    echo "📊 Collecting system information..." >&2
    
    {
        echo "=== Build System Information ==="
        echo "Timestamp: $(date)"
        echo "Build Timestamp: $TIMESTAMP"
        echo "Workflow Run ID: $WORKFLOW_RUN_ID"
        echo "Job Name: $JOB_NAME"
        echo "Step Name: $STEP_NAME"
        echo "Repository: $GITHUB_REPOSITORY"
        echo "Branch: $GITHUB_REF_NAME"
        echo "Commit: $GITHUB_SHA"
        echo "Runner OS: $RUNNER_OS"
        echo "Runner Architecture: $(uname -m)"
        echo ""
        
        echo "=== Environment Variables (Safe) ==="
        env | grep -E -v "(TOKEN|SECRET|KEY|PASSWORD|JKS|CACHIX)" | sort
        echo ""
        
        echo "=== Disk Usage ==="
        df -h
        echo ""
        
        echo "=== Memory Usage ==="
        free -h
        echo ""
        
        echo "=== CPU Info ==="
        if command -v lscpu >/dev/null 2>&1; then
            lscpu
        else
            cat /proc/cpuinfo | head -20
        fi
        echo ""
        
        echo "=== Java Version ==="
        if command -v java >/dev/null 2>&1; then
            java -version 2>&1
        fi
        echo ""
        
        echo "=== Gradle Version ==="
        if command -v ./gradlew >/dev/null 2>&1; then
            ./gradlew --version 2>&1 || echo "Gradle wrapper not available"
        fi
        echo ""
        
        echo "=== Nix Version ==="
        if command -v nix >/dev/null 2>&1; then
            nix --version
        else
            echo "Nix not available"
        fi
        
    } > "$info_file"
    
    # Filter sensitive data from system info
    filter_sensitive_data "$info_file" "$info_file"
    
    echo "✅ System information collected" >&2
}

# Function to start log collection for a command (enhanced)
start_command_log() {
    local command_name="$1"
    local log_file="$LOG_DIR/${command_name}-${TIMESTAMP}.log"
    
    echo "📝 Starting log collection for: $command_name" >&2
    echo "=== Command: $command_name ===" > "$log_file"
    echo "Timestamp: $(date)" >> "$log_file"
    echo "Build Timestamp: $TIMESTAMP" >> "$log_file"
    echo "Working Directory: $(pwd)" >> "$log_file"
    echo "" >> "$log_file"
    
    # Return the log file path
    echo "$log_file"
}

# Function to execute command with logging (fixed multi-line command handling and output stream)
execute_with_logging() {
    local command_name="$1"
    shift
    local command="$@"
    
    local log_file="$LOG_DIR/${command_name}-${TIMESTAMP}.log"
    local filtered_log_file="$LOG_DIR/${command_name}-${TIMESTAMP}-filtered.log"
    
    echo "🚀 Executing: $command" >&2
    echo "📝 Logging to: $log_file" >&2
    
    # Ensure log directory exists and is writable
    if [[ ! -d "$LOG_DIR" ]]; then
        echo "❌ Log directory does not exist: $LOG_DIR" >&2
        echo "Creating directory..." >&2
        mkdir -p "$LOG_DIR" || {
            echo "❌ Failed to create log directory: $LOG_DIR" >&2
            exit 1
        }
    fi
    
    if [[ ! -w "$LOG_DIR" ]]; then
        echo "❌ Log directory is not writable: $LOG_DIR" >&2
        echo "Directory permissions: $(ls -ld "$LOG_DIR")" >&2
        echo "Current user: $(whoami)" >&2
        exit 1
    fi
    
    # Create log file with enhanced header
    {
        echo "=== Command: $command ==="
        echo "Timestamp: $(date)"
        echo "Build Timestamp: $TIMESTAMP"
        echo "Working Directory: $(pwd)"
        echo "Environment:"
        env | grep -E -v "(TOKEN|SECRET|KEY|PASSWORD|JKS|CACHIX)" | sort
        echo ""
        echo "=== Output ==="
    } > "$log_file"
    
    # Execute command and capture output (fixed: use bash -c for multi-line commands)
    local exit_code=0
    # Note: The command output (stdout and stderr) is redirected to $log_file
    if bash -c "$command" >> "$log_file" 2>&1; then
        exit_code=0
        echo "✅ Command completed successfully" >> "$log_file"
    else
        exit_code=$?
        echo "❌ Command failed with exit code: $exit_code" >> "$log_file"
    fi
    
    echo "" >> "$log_file"
    echo "=== Exit Code: $exit_code ===" >> "$log_file"
    echo "End Timestamp: $(date)" >> "$log_file"
    
    # Filter sensitive data
    cp "$log_file" "$filtered_log_file"
    filter_sensitive_data "$filtered_log_file" "$filtered_log_file"
    
    # Return both the exit code and the filtered log file to STDOUT for workflow capture
    echo "$exit_code:$filtered_log_file"
}

# Function to create build summary (enhanced)
create_build_summary() {
    local overall_status="$1"
    local summary_file="$LOG_DIR/build-summary-$TIMESTAMP.txt"
    
    echo "📋 Creating build summary..." >&2
    
    {
        echo "=== Build Summary ==="
        echo "Overall Status: $overall_status"
        echo "Timestamp: $(date)"
        echo "Build Timestamp: $TIMESTAMP"
        echo "Workflow Run ID: $WORKFLOW_RUN_ID"
        echo "Job Name: $JOB_NAME"
        echo "Repository: $GITHUB_REPOSITORY"
        echo "Branch: $GITHUB_REF_NAME"
        echo "Commit: $GITHUB_SHA"
        echo ""
        
        echo "=== Generated Files ==="
        ls -la "$LOG_DIR"/*.log "$LOG_DIR"/*.txt 2>/dev/null || echo "No log files found"
        echo ""
        
        echo "=== Log Files Description ==="
        echo "- system-info-*.txt: System environment and configuration"
        echo "- *-filtered.log: Command outputs with sensitive data removed"
        echo "- build-summary-*.txt: This summary file"
        echo ""
        
        echo "=== Security Notice ==="
        echo "All sensitive information (tokens, passwords, keys) has been filtered"
        echo "from these logs using pattern matching and replacement."
        echo ""
        
        if [[ "$overall_status" == "SUCCESS" ]]; then
            echo "✅ Build completed successfully"
        else
            echo "❌ Build failed - check individual command logs for details"
        fi
        
    } > "$summary_file"
    
    echo "✅ Build summary created" >&2
}

# Function to upload logs as artifacts (enhanced)
upload_logs_artifact() {
    local artifact_name="$1"
    
    echo "📦 Uploading logs as artifact: $artifact_name" >&2
    
    # Create a compressed archive
    local archive_name="build-logs-${TIMESTAMP}.tar.gz"
    tar -czf "$archive_name" -C "$LOG_DIR" .
    
    # Upload the archive (this will be handled by the workflow)
    # Note: These are GitHub Actions specific outputs, not standard script output
    echo "archive_path=$archive_name" >> $GITHUB_OUTPUT
    echo "artifact_name=$artifact_name" >> $GITHUB_OUTPUT
    
    echo "✅ Logs archived: $archive_name" >&2
}

# Main execution based on parameters
case "${1:-help}" in
    "collect-system")
        collect_system_info
        ;;
    "execute")
        shift
        execute_with_logging "$@"
        ;;
    "filter")
        filter_sensitive_data "$2" "$3"
        ;;
    "summary")
        create_build_summary "$2"
        ;;
    "upload")
        upload_logs_artifact "$2"
        ;;
    "help"|*)
        echo "Usage: $0 {collect-system|execute|filter|summary|upload} [args...]" >&2
        echo "" >&2
        echo "Commands:" >&2
        echo "  collect-system           Collect system information" >&2
        echo "  execute <name> <command> Execute command with logging" >&2
        echo "  filter <input> <output>  Filter sensitive data from file" >&2
        echo "  summary <status>         Create build summary" >&2
        echo "  upload <artifact-name>   Prepare logs for artifact upload" >&2
        echo "" >&2
        echo "Environment Variables:" >&2
        echo "  BUILD_TIMESTAMP          Timestamp for consistent file naming" >&2
        exit 1
        ;;
esac