#!/bin/bash

# Log Collector and Sensitive Data Filter
# This script collects build logs and filters sensitive information

set -euo pipefail

# Configuration
LOG_DIR="build-logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
WORKFLOW_RUN_ID="${GITHUB_RUN_ID:-unknown}"
JOB_NAME="${GITHUB_JOB:-unknown}"
STEP_NAME="${GITHUB_STEP:-unknown}"

# Create log directory
mkdir -p "$LOG_DIR"

# Sensitive data patterns to filter
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

# Replacement patterns
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

# Function to filter sensitive data
filter_sensitive_data() {
    local input_file="$1"
    local output_file="$2"
    
    echo "🔒 Filtering sensitive data from $input_file..."
    
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
    
    echo "✅ Sensitive data filtered"
}

# Function to collect system information
collect_system_info() {
    local info_file="$LOG_DIR/system-info-$TIMESTAMP.txt"
    
    echo "📊 Collecting system information..."
    
    {
        echo "=== Build System Information ==="
        echo "Timestamp: $(date)"
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
    
    echo "✅ System information collected"
}

# Function to start log collection for a command
start_command_log() {
    local command_name="$1"
    local log_file="$LOG_DIR/${command_name}-${TIMESTAMP}.log"
    
    echo "📝 Starting log collection for: $command_name"
    echo "=== Command: $command_name ===" > "$log_file"
    echo "Timestamp: $(date)" >> "$log_file"
    echo "Working Directory: $(pwd)" >> "$log_file"
    echo "" >> "$log_file"
    
    # Return the log file path
    echo "$log_file"
}

# Function to execute command with logging
execute_with_logging() {
    local command_name="$1"
    shift
    local command="$@"
    
    local log_file="$LOG_DIR/${command_name}-${TIMESTAMP}.log"
    local filtered_log_file="$LOG_DIR/${command_name}-${TIMESTAMP}-filtered.log"
    
    echo "🚀 Executing: $command"
    echo "=== Command: $command ===" > "$log_file"
    echo "Timestamp: $(date)" >> "$log_file"
    echo "Working Directory: $(pwd)" >> "$log_file"
    echo "Environment:" >> "$log_file"
    env | grep -E -v "(TOKEN|SECRET|KEY|PASSWORD|JKS|CACHIX)" | sort >> "$log_file"
    echo "" >> "$log_file"
    echo "=== Output ===" >> "$log_file"
    
    # Execute command and capture output
    local exit_code=0
    if eval "$command" >> "$log_file" 2>&1; then
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
    filter_sensitive_data "$log_file" "$filtered_log_file"
    
    # Return both the exit code and the filtered log file
    echo "$exit_code:$filtered_log_file"
}

# Function to create build summary
create_build_summary() {
    local overall_status="$1"
    local summary_file="$LOG_DIR/build-summary-$TIMESTAMP.txt"
    
    echo "📋 Creating build summary..."
    
    {
        echo "=== Build Summary ==="
        echo "Overall Status: $overall_status"
        echo "Timestamp: $(date)"
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
    
    echo "✅ Build summary created"
}

# Function to upload logs as artifacts
upload_logs_artifact() {
    local artifact_name="$1"
    
    echo "📦 Uploading logs as artifact: $artifact_name"
    
    # Create a compressed archive
    local archive_name="build-logs-${TIMESTAMP}.tar.gz"
    tar -czf "$archive_name" -C "$LOG_DIR" .
    
    # Upload the archive (this will be handled by the workflow)
    echo "archive_path=$archive_name" >> $GITHUB_OUTPUT
    echo "artifact_name=$artifact_name" >> $GITHUB_OUTPUT
    
    echo "✅ Logs archived: $archive_name"
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
        echo "Usage: $0 {collect-system|execute|filter|summary|upload} [args...]"
        echo ""
        echo "Commands:"
        echo "  collect-system           Collect system information"
        echo "  execute <name> <command> Execute command with logging"
        echo "  filter <input> <output>  Filter sensitive data from file"
        echo "  summary <status>         Create build summary"
        echo "  upload <artifact-name>   Prepare logs for artifact upload"
        exit 1
        ;;
esac