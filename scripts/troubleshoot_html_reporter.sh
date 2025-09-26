#!/bin/bash

set -e

# Arguments:
# $1: REPORTS_DIR (e.g., playwright-report)
# $2: CI_PROJECT_DIR
# $3: PIPELINE_ID
# $4: BRANCH
# $5: NODE_ENV
# $6: COVERAGE_DIR (optional, path to coverage reports)
# $7: SECURITY_REPORT_FILE (optional, path to npm audit --json output)

REPORTS_DIR=$1
CI_PROJECT_DIR=$2
PIPELINE_ID=$3
BRANCH=$4
NODE_ENV=$5
COVERAGE_DIR=${6:-}          # Optional argument, default to empty string
SECURITY_REPORT_FILE=${7:-}  # Optional argument, default to empty string

echo "Starting enhanced troubleshooting HTML report generation..."

REPORT_FILE="troubleshooting-report.html"
JUNIT_XML_PATH="${REPORTS_DIR}/junit.xml" # Assuming Playwright outputs to this single file

# --- HTML Header ---
cat > "$REPORT_FILE" <<EOF
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Pipeline Troubleshooting Report</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; background: #f9f9f9; color: #333; }
    h1, h2, h3, h4 { color: #222; }
    pre { background: #eee; padding: 10px; border-radius: 6px; overflow-x: auto; }
    code { font-family: monospace; }
    table { border-collapse: collapse; width: 100%; margin: 10px 0; }
    th, td { border: 1px solid #ccc; padding: 6px 10px; text-align: left; }
    th { background: #f0f0f0; }
    ul { margin: 0; padding-left: 20px; }
    .ok { color: green; font-weight: bold; }
    .fail { color: red; font-weight: bold; }
    .warn { color: orange; font-weight: bold; }
  </style>
</head>
<body>
<h1>Pipeline Troubleshooting Report</h1>
<h2>Pipeline ID: $PIPELINE_ID</h2>
<p><b>Date:</b> $(date)<br>
<b>Branch:</b> $BRANCH<br>
<b>Environment:</b> $NODE_ENV</p>
EOF

# --- System Info ---
{
    echo "<h2>System Information</h2><ul>"
    echo "<li>Node Version: $(node -v)</li>"
    echo "<li>NPM Version: $(npm -v)</li>"
    echo "<li>OS: $(uname -a)</li>"
    echo "</ul>"
} >> "$REPORT_FILE"

# --- Env Vars ---
{
    echo "<h2>Environment Variables</h2><ul>"
    echo "<li>REPORTS_DIR: $REPORTS_DIR</li>"
    echo "<li>NODE_ENV: $NODE_ENV</li>"
    [ -n "$METADATA_URL" ] && echo "<li>METADATA_URL: $METADATA_URL</li>"
    [ -n "$API_BASE_URL" ] && echo "<li>API_BASE_URL: $API_BASE_URL</li>"
    echo "</ul>"
} >> "$REPORT_FILE"

# --- Test Results ---
echo "<h2>Test Results Summary</h2>" >> "$REPORT_FILE"

# Function to extract test summary from a single JUnit XML file
extract_junit_summary() {
    local xml_file=$1
    local name=$2
    
    if [ -f "$xml_file" ]; then
        local total_tests=0 total_failures=0 total_errors=0 total_skipped=0
        
        # FIX 1: Improved test counting logic to avoid duplication
        if grep -q '<testsuites>' "$xml_file"; then
            # If there's a testsuites container element, use those totals
            total_tests=$(grep -oP '<testsuites[^>]*tests="\K[^"]+' "$xml_file" || echo 0)
            total_failures=$(grep -oP '<testsuites[^>]*failures="\K[^"]+' "$xml_file" || echo 0)
            total_errors=$(grep -oP '<testsuites[^>]*errors="\K[^"]+' "$xml_file" || echo 0)
            total_skipped=$(grep -oP '<testsuites[^>]*skipped="\K[^"]+' "$xml_file" || echo 0)
        else
            # Count only top-level testsuite elements
            while IFS= read -r line; do
                total_tests=$((total_tests + $(echo "$line" | grep -oP 'tests="\K[^"]+' || echo 0)))
                total_failures=$((total_failures + $(echo "$line" | grep -oP 'failures="\K[^"]+' || echo 0)))
                total_errors=$((total_errors + $(echo "$line" | grep -oP 'errors="\K[^"]+' || echo 0)))
                total_skipped=$((total_skipped + $(echo "$line" | grep -oP 'skipped="\K[^"]+' || echo 0)))
            done < <(grep -oP '<testsuite[^>]*>' "$xml_file" | grep -v '<testsuite.*<testsuite')
        fi
        
        local passed=$((total_tests - total_failures - total_errors - total_skipped))
        
        {
            echo "<h3>$name Tests</h3><ul>"
            echo "<li><b>Total:</b> $total_tests</li>"
            echo "<li><b>Passed:</b> $passed</li>"
            echo "<li><b>Failed:</b> $total_failures</li>"
            echo "<li><b>Errors:</b> $total_errors</li>"
            echo "<li><b>Skipped:</b> $total_skipped</li></ul>"
        } >> "$REPORT_FILE"
        
        if [ "$total_failures" -gt 0 ] || [ "$total_errors" -gt 0 ]; then
            echo "<h4>Failed Tests (up to 10):</h4><ul>" >> "$REPORT_FILE"
            grep -E -A 3 '<(failure|error)' "$xml_file" | \
            grep -oP '(?<=<(failure|error) message=")[^"]*(?=")' | \
            head -10 | \
            sed 's/&quot;/"/g; s/</</g; s/>/>/g; s/&amp;/&/g' | \
            sed 's/^/<li>/' | sed 's/$/<\/li>/' >> "$REPORT_FILE"
            echo "</ul>" >> "$REPORT_FILE"
        fi
    else
        echo "<h3>$name Tests</h3><p>No results found at <code>$xml_file</code>.</p>" >> "$REPORT_FILE"
    fi
}

# Call the function for Playwright
extract_junit_summary "$JUNIT_XML_PATH" "Playwright E2E"

# --- HTML Reports ---
# FIX 2: Corrected link to Playwright HTML report
{
    echo "<h2>HTML Reports</h2><ul>"
    if [ -d "$REPORTS_DIR" ] && [ -f "$REPORTS_DIR/index.html" ]; then
        # Use correct relative path for the link and add target="_blank"
        echo "<li>Playwright HTML Report: <a href=\"$REPORTS_DIR/index.html\" target=\"_blank\">index.html</a></li>"
    else
        echo "<li>No Playwright HTML reports found.</li>"
    fi
    echo "</ul>"
} >> "$REPORT_FILE"

# --- Coverage ---
{
    echo "<h2>Coverage Reports</h2>"
    if [ -n "$COVERAGE_DIR" ] && [ -d "$COVERAGE_DIR" ] && [ -f "$COVERAGE_DIR/lcov-report/index.html" ]; then
        echo "<p>Coverage report available: <a href=\"$COVERAGE_DIR/lcov-report/index.html\" target=\"_blank\">index.html</a></p>"
        if [ -f "$COVERAGE_DIR/coverage-summary.json" ] && command -v jq &>/dev/null; then
            coverage_pct=$(jq -r '.total.lines.pct' "$COVERAGE_DIR/coverage-summary.json" 2>/dev/null || echo "N/A")
            echo "<p>Overall coverage: <b>$coverage_pct%</b></p>"
        fi
    else
        echo "<p>No coverage reports found.</p>"
    fi
} >> "$REPORT_FILE"

# --- Security ---
# FIX 3: Improved security scan report handling
if [ -n "$SECURITY_REPORT_FILE" ] && [ -f "$SECURITY_REPORT_FILE" ]; then
    echo "<h2>Security Scan</h2>" >> "$REPORT_FILE"
    if command -v jq &>/dev/null; then
        # Check JSON structure and handle different formats
        if jq -e '.metadata.vulnerabilities' "$SECURITY_REPORT_FILE" >/dev/null 2>&1; then
            # Expected structure
            echo "<h3>Vulnerabilities Summary</h3>" >> "$REPORT_FILE"
            echo "<ul>" >> "$REPORT_FILE"
            echo "<li><b>Critical:</b> $(jq -r '.metadata.vulnerabilities.critical // 0' "$SECURITY_REPORT_FILE")</li>" >> "$REPORT_FILE"
            echo "<li><b>High:</b> $(jq -r '.metadata.vulnerabilities.high // 0' "$SECURITY_REPORT_FILE")</li>" >> "$REPORT_FILE"
            echo "<li><b>Moderate:</b> $(jq -r '.metadata.vulnerabilities.moderate // 0' "$SECURITY_REPORT_FILE")</li>" >> "$REPORT_FILE"
            echo "<li><b>Low:</b> $(jq -r '.metadata.vulnerabilities.low // 0' "$SECURITY_REPORT_FILE")</li>" >> "$REPORT_FILE"
            echo "<li><b>Info:</b> $(jq -r '.metadata.vulnerabilities.info // 0' "$SECURITY_REPORT_FILE")</li>" >> "$REPORT_FILE"
            echo "</ul>" >> "$REPORT_FILE"
            elif jq -e '.vulnerabilities' "$SECURITY_REPORT_FILE" >/dev/null 2>&1; then
            # Alternative structure
            echo "<h3>Vulnerabilities Found</h3>" >> "$REPORT_FILE"
            vuln_count=$(jq '.vulnerabilities | length' "$SECURITY_REPORT_FILE")
            echo "<p>Total vulnerabilities: $vuln_count</p>" >> "$REPORT_FILE"
            
            if [ "$vuln_count" -gt 0 ]; then
                echo "<table>" >> "$REPORT_FILE"
                echo "<tr><th>Severity</th><th>Count</th></tr>" >> "$REPORT_FILE"
                jq -r '.vulnerabilities | group_by(.severity) | map({severity: .[0].severity, count: length}) | .[] | "<tr><td>\(.severity)</td><td>\(.count)</td></tr>"' "$SECURITY_REPORT_FILE" >> "$REPORT_FILE"
                echo "</table>" >> "$REPORT_FILE"
            fi
        else
            # Unknown structure - show raw JSON
            echo "<p>Security report structure is different than expected. Raw content:</p>" >> "$REPORT_FILE"
            echo "<pre>" >> "$REPORT_FILE"
            jq '.' "$SECURITY_REPORT_FILE" >> "$REPORT_FILE" || cat "$SECURITY_REPORT_FILE" >> "$REPORT_FILE"
            echo "</pre>" >> "$REPORT_FILE"
        fi
    else
        echo "<p>jq not found. Raw security report content:</p>" >> "$REPORT_FILE"
        echo "<pre>" >> "$REPORT_FILE"
        cat "$SECURITY_REPORT_FILE" >> "$REPORT_FILE"
        echo "</pre>" >> "$REPORT_FILE"
    fi
else
    echo "<h2>Security Scan</h2><p>No security report file provided or found.</p>" >> "$REPORT_FILE"
fi

# --- Connectivity ---
if [ -n "$METADATA_URL" ] || [ -n "$API_BASE_URL" ]; then
    echo "<h2>Network Connectivity</h2><ul>" >> "$REPORT_FILE"
    for u in "$METADATA_URL" "$API_BASE_URL"; do
        if [ -n "$u" ]; then
            if curl -s --head --max-time 5 "$u" >/dev/null; then
                echo "<li>$u: <span class='ok'>OK</span></li>" >> "$REPORT_FILE"
            else
                echo "<li>$u: <span class='fail'>FAIL</span></li>" >> "$REPORT_FILE"
            fi
        fi
    done
    echo "</ul>" >> "$REPORT_FILE"
fi

# --- Disk Space ---
echo "<h2>Disk Space</h2><pre>" >> "$REPORT_FILE"
df -h | grep -v tmpfs >> "$REPORT_FILE"
echo "</pre>" >> "$REPORT_FILE"

# --- All HTML files ---
echo "<h2>All HTML Files (Excluding node_modules)</h2><pre>" >> "$REPORT_FILE"
find "$CI_PROJECT_DIR" -type d -name node_modules -prune -o -name "*.html" -print | sort >> "$REPORT_FILE"
echo "</pre>" >> "$REPORT_FILE"

# --- Recommendations ---
{
    echo "<h2>Recommendations</h2><ul>"
    total_failures_from_junit=0
    if [ -f "$JUNIT_XML_PATH" ]; then
        # FIX: Use the same improved test counting logic for recommendations
        if grep -q '<testsuites>' "$JUNIT_XML_PATH"; then
            total_failures_from_junit=$(grep -oP '<testsuites[^>]*failures="\K[^"]+' "$JUNIT_XML_PATH" || echo 0)
        else
            total_failures_from_junit=$(grep -oP '<testsuite[^>]*failures="\K[^"]+' "$JUNIT_XML_PATH" | awk '{s+=$1} END{print s}')
        fi
    fi
    
    if [ "${total_failures_from_junit:-0}" -gt 0 ]; then
        echo "<li>⚠️ ${total_failures_from_junit} failed tests found. Review the 'Test Results Summary' and Playwright HTML report.</li>"
    else
        echo "<li>✅ All tests passing.</li>"
    fi
    
    # FIX: Improved security recommendations with better error handling
    if [ -n "$SECURITY_REPORT_FILE" ] && [ -f "$SECURITY_REPORT_FILE" ] && command -v jq &>/dev/null; then
        if jq -e '.metadata.vulnerabilities' "$SECURITY_REPORT_FILE" >/dev/null 2>&1; then
            high_critical_vulns=$(jq -r '(.metadata.vulnerabilities.high // 0) + (.metadata.vulnerabilities.critical // 0)' "$SECURITY_REPORT_FILE" 2>/dev/null || echo 0)
            if [ "$high_critical_vulns" -gt 0 ]; then
                echo "<li>🚨 Found <b>$high_critical_vulns high/critical</b> security vulnerabilities. Address these urgently.</li>"
            else
                total_vulns=$(jq -r '(.metadata.vulnerabilities.info // 0) + (.metadata.vulnerabilities.low // 0) + (.metadata.vulnerabilities.moderate // 0)' "$SECURITY_REPORT_FILE" 2>/dev/null || echo 0)
                if [ "$total_vulns" -gt 0 ]; then
                    echo "<li>⚠️ Found <b>$total_vulns low/moderate</b> security vulnerabilities. Consider addressing them.</li>"
                else
                    echo "<li>✅ No significant security vulnerabilities detected.</li>"
                fi
            fi
            elif jq -e '.vulnerabilities' "$SECURITY_REPORT_FILE" >/dev/null 2>&1; then
            # Alternative structure
            high_sev_count=$(jq -r '[.vulnerabilities[] | select(.severity == "high" or .severity == "critical")] | length' "$SECURITY_REPORT_FILE" 2>/dev/null || echo 0)
            if [ "$high_sev_count" -gt 0 ]; then
                echo "<li>🚨 Found <b>$high_sev_count high/critical</b> security vulnerabilities. Address these urgently.</li>"
            else
                echo "<li>✅ No high/critical security vulnerabilities detected.</li>"
            fi
        else
            echo "<li>ℹ️ Security scan completed but format is not recognized. Review the raw output.</li>"
        fi
    else
        echo "<li>ℹ️ No security scan report was provided. Consider adding security scanning to your pipeline.</li>"
    fi
    
    echo "<li>📊 Keep monitoring coverage regularly.</li></ul>"
} >> "$REPORT_FILE"

# --- Close HTML ---
echo "</body></html>" >> "$REPORT_FILE"

echo "✅ HTML troubleshooting report generated at $REPORT_FILE"
