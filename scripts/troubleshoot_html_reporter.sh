#!/bin/bash
set -euo pipefail

# --- Arguments ---
REPORTS_DIR="${1:-}"
CI_PROJECT_DIR="${2:-}"
PIPELINE_ID="${3:-}"
BRANCH="${4:-}"
NODE_ENV="${5:-}"
COVERAGE_DIR="${6:-}"
SECURITY_REPORT_FILE="${7:-}"
SAST_REPORT_FILE="${8:-}"

# --- Output file ---
REPORT_FILE="${CI_PROJECT_DIR}/troubleshooting-report.html"
JUNIT_XML="${REPORTS_DIR}/junit.xml"

# --- Helper functions ---
function log_info() {
    echo "[INFO] $1"
}

function log_error() {
    echo "[ERROR] $1" >&2
}

function parse_junit_results() {
    local xml_file="$1"
    local results=()
    local total=0
    local failures=0
    local errors=0
    local skipped=0
    local passed=0
    
    if [ ! -f "$xml_file" ]; then
        log_error "JUnit XML file not found: $xml_file"
        results=(0 0 0 0 0)
        echo "${results[@]}"
        return
    fi
    
    total=$(grep -oP '<testsuites[^>]*tests="\K[^"]+' "$xml_file" 2>/dev/null || echo 0)
    failures=$(grep -oP '<testsuites[^>]*failures="\K[^"]+' "$xml_file" 2>/dev/null || echo 0)
    errors=$(grep -oP '<testsuites[^>]*errors="\K[^"]+' "$xml_file" 2>/dev/null || echo 0)
    skipped=$(grep -oP '<testsuites[^>]*skipped="\K[^"]+' "$xml_file" 2>/dev/null || echo 0)
    passed=$((total - failures - errors - skipped))
    
    results=("$total" "$passed" "$failures" "$errors" "$skipped")
    echo "${results[@]}"
}

function parse_security_report() {
    local report_file="$1"
    local summary="No security report provided."
    local findings="No vulnerabilities found."
    local critical=0
    local high=0
    local moderate=0
    local low=0
    local total=0
    
    if [ ! -f "$report_file" ] || [ ! -s "$report_file" ]; then
        echo "$summary" "$findings"
        return
    fi
    
    summary="Security report file found at: $report_file"
    
    if ! jq -e '.' "$report_file" >/dev/null 2>&1; then
        findings="Invalid JSON format in security report."
        echo "$summary" "$findings"
        return
    fi
    
    # Format the security findings for better readability
    if jq -e '.metadata.vulnerabilities' "$report_file" >/dev/null 2>&1; then
        critical=$(jq -r '.metadata.vulnerabilities.critical // 0' "$report_file")
        high=$(jq -r '.metadata.vulnerabilities.high // 0' "$report_file")
        moderate=$(jq -r '.metadata.vulnerabilities.moderate // 0' "$report_file")
        low=$(jq -r '.metadata.vulnerabilities.low // 0' "$report_file")
        total=$(jq -r '.metadata.vulnerabilities.total // 0' "$report_file")
        
        findings="{\n"
        findings+="  \"auditReportVersion\": $(jq -r '.auditReportVersion // 2' "$report_file"),\n"
        findings+="  \"vulnerabilities\": $(jq -r '.vulnerabilities // {}' "$report_file"),\n"
        findings+="  \"metadata\": {\n"
        findings+="    \"vulnerabilities\": {\n"
        findings+="      \"info\": 0,\n"
        findings+="      \"low\": $low,\n"
        findings+="      \"moderate\": $moderate,\n"
        findings+="      \"high\": $high,\n"
        findings+="      \"critical\": $critical,\n"
        findings+="      \"total\": $total\n"
        findings+="    },\n"
        findings+="    \"dependencies\": $(jq -r '.metadata.dependencies // {}' "$report_file")\n"
        findings+="  }\n"
        findings+="}"
    else
        findings=$(jq -r '.' "$report_file")
    fi
    
    echo "$summary" "$findings"
}

function parse_sast_report() {
    local report_file="$1"
    local summary="No SAST report provided."
    local findings="No vulnerabilities found."
    local vuln_count=0
    
    if [ ! -f "$report_file" ] || [ ! -s "$report_file" ]; then
        echo "$summary" "$findings"
        return
    fi
    
    summary="SAST report file found at: $report_file"
    
    if ! jq -e '.' "$report_file" >/dev/null 2>&1; then
        findings="Invalid JSON format in SAST report."
        echo "$summary" "$findings"
        return
    fi
    
    # Check if vulnerabilities exist and format them
    if jq -e '.vulnerabilities' "$report_file" >/dev/null 2>&1; then
        vuln_count=$(jq '.vulnerabilities | length' "$report_file")
        
        if [ "$vuln_count" -gt 0 ]; then
            findings=$(jq -r '
        .vulnerabilities |
        sort_by(.severity) | reverse |
        .[0:5] |
        map("- **" + (.name // "Unnamed vulnerability") + "**: " +
            "Severity: " + (.severity // "unknown") + ", " +
            "Location: " + (.location.file // "unknown") + ":" + ((.location.start_line|tostring) // "unknown") + ", " +
            "Description: " + (.description // "No description")) |
        join("\n")
            ' "$report_file" 2>/dev/null || echo "Error parsing SAST vulnerabilities")
        else
            findings="No vulnerabilities found in SAST report."
        fi
    else
        findings="No vulnerabilities section found in SAST report."
    fi
    
    echo "$summary" "$findings"
}

# --- Main execution ---
log_info "Generating troubleshooting report..."

# Parse test results
read -r TOTAL_TESTS PASSED_TESTS FAILED_TESTS ERROR_TESTS SKIPPED_TESTS < <(parse_junit_results "$JUNIT_XML")
log_info "Test results: Total=$TOTAL_TESTS, Passed=$PASSED_TESTS, Failed=$FAILED_TESTS, Errors=$ERROR_TESTS, Skipped=$SKIPPED_TESTS"

# System information
NODE_VERSION=$(node -v 2>/dev/null || echo "Not installed")
NPM_VERSION=$(npm -v 2>/dev/null || echo "Not installed")
OS_INFO=$(uname -a 2>/dev/null || echo "Unknown")

# Environment variables
ENV_VARS=("REPORTS_DIR" "NODE_ENV")

# Coverage reports
COVERAGE_REPORTS=""
if [ -n "$COVERAGE_DIR" ] && [ -d "$COVERAGE_DIR" ]; then
    COVERAGE_REPORTS=$(find "$COVERAGE_DIR" -name "*.html" -type f | sort || true)
fi

# Security scan
read -r SECURITY_SUMMARY SECURITY_FINDINGS < <(parse_security_report "$SECURITY_REPORT_FILE")

# SAST scan
read -r SAST_SUMMARY SAST_FINDINGS < <(parse_sast_report "$SAST_REPORT_FILE")

# Disk space
DISK_SPACE=$(df -h | grep -v "tmpfs" || echo "Unable to retrieve disk space info")

# --- Generate HTML Report ---
log_info "Creating HTML report at $REPORT_FILE"

cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Pipeline Troubleshooting Report</title>
<style>
:root{--primary-color:#1f76c2;--secondary-color:#4a9de7;--success-color:#28a745;--warning-color:#ffc107;--danger-color:#dc3545;--info-color:#17a2b8;--light-color:#f8f9fa;--dark-color:#343a40;--border-color:#dee2e6;--text-color:#333;--background-color:#f9f9f9;--card-background:#ffffff}
body{font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;margin:0;padding:0;background:var(--background-color);color:var(--text-color);line-height:1.6}
.container{max-width:1200px;margin:0 auto;padding:20px}
header{background:linear-gradient(135deg,var(--primary-color),var(--secondary-color));color:white;padding:20px;border-radius:8px 8px 0 0;margin-bottom:20px;box-shadow:0 4px 6px rgba(0,0,0,0.1)}
h1{margin:0;font-size:28px;font-weight:600}
.pipeline-info{background-color:var(--card-background);border-radius:8px;padding:15px;margin-bottom:20px;box-shadow:0 2px 4px rgba(0,0,0,0.05);border-left:5px solid var(--primary-color)}
.section{background-color:var(--card-background);border-radius:8px;padding:20px;margin-bottom:20px;box-shadow:0 2px 4px rgba(0,0,0,0.05)}
h2{color:var(--primary-color);border-bottom:2px solid var(--border-color);padding-bottom:10px;margin-top:0;font-size:22px}
ul{margin:0;padding-left:20px}
li{margin-bottom:5px}
pre{background:#f0f0f0;padding:15px;border-radius:6px;overflow-x:auto;border:1px solid var(--border-color);font-family:'Courier New',Courier,monospace;font-size:14px}
.stats{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:15px}
.stat-card{flex:1;min-width:120px;background-color:var(--light-color);border-radius:8px;padding:15px;text-align:center;box-shadow:0 2px 4px rgba(0,0,0,0.05)}
.stat-card .number{font-size:24px;font-weight:bold;margin-bottom:5px}
.stat-card.total{border-top:3px solid var(--dark-color)}
.stat-card.passed{border-top:3px solid var(--success-color)}
.stat-card.failed{border-top:3px solid var(--danger-color)}
.stat-card.errors{border-top:3px solid var(--warning-color)}
.stat-card.skipped{border-top:3px solid var(--info-color)}
.footer{text-align:center;margin-top:30px;padding:15px;color:#666;font-size:14px;border-top:1px solid var(--border-color)}
</style>
</head>
<body>
<div class="container">
<header><h1>Pipeline Troubleshooting Report</h1></header>

<div class="pipeline-info">
<h2>Pipeline Information</h2>
<p><strong>Pipeline ID:</strong> ${PIPELINE_ID}</p>
<p><strong>Date:</strong> $(date)</p>
<p><strong>Branch:</strong> ${BRANCH}</p>
<p><strong>Environment:</strong> ${NODE_ENV}</p>
</div>

<div class="section">
<h2>System Information</h2>
<ul>
<li><strong>Node Version:</strong> ${NODE_VERSION}</li>
<li><strong>NPM Version:</strong> ${NPM_VERSION}</li>
<li><strong>OS:</strong> ${OS_INFO}</li>
</ul>
</div>

<div class="section">
<h2>Environment Variables</h2>
<ul>
EOF

for var in "${ENV_VARS[@]}"; do
    if [ -n "${!var:-}" ]; then
        echo "<li><strong>${var}:</strong> ${!var}</li>" >> "$REPORT_FILE"
    fi
done

cat >> "$REPORT_FILE" <<EOF
</ul>
</div>

<div class="section">
<h2>Test Results</h2>
<div class="stats">
<div class="stat-card total"><div class="number">${TOTAL_TESTS}</div><div class="label">Total</div></div>
<div class="stat-card passed"><div class="number">${PASSED_TESTS}</div><div class="label">Passed</div></div>
<div class="stat-card failed"><div class="number">${FAILED_TESTS}</div><div class="label">Failed</div></div>
<div class="stat-card errors"><div class="number">${ERROR_TESTS}</div><div class="label">Errors</div></div>
<div class="stat-card skipped"><div class="number">${SKIPPED_TESTS}</div><div class="label">Skipped</div></div>
</div>
</div>

<div class="section">
<h2>Coverage Reports</h2>
<ul>
EOF

if [ -n "$COVERAGE_REPORTS" ]; then
    for f in $COVERAGE_REPORTS; do
        echo "<li><a href=\"$f\">$f</a></li>" >> "$REPORT_FILE"
    done
else
    echo "<li>No coverage reports found</li>" >> "$REPORT_FILE"
fi

cat >> "$REPORT_FILE" <<EOF
</ul>
</div>

<div class="section">
<h2>Security Scan</h2>
<p>${SECURITY_SUMMARY}</p>
<pre>${SECURITY_FINDINGS}</pre>
</div>

<div class="section">
<h2>SAST Scan</h2>
<p>${SAST_SUMMARY}</p>
<pre>${SAST_FINDINGS}</pre>
</div>

<div class="section">
<h2>Disk Space</h2>
<pre>${DISK_SPACE}</pre>
</div>

<div class="footer">
<p>Generated on $(date)</p>
</div>
</div>
</body>
</html>
EOF

log_info "Enhanced troubleshooting report generated at: $REPORT_FILE"
