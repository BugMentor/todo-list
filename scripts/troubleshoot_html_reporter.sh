#!/bin/bash
# Troubleshooting HTML Report Generator
# This script generates an HTML report with troubleshooting information from CI/CD pipeline

set -e

# Parse arguments
PLAYWRIGHT_REPORTS_DIR="$1"
# CI_PROJECT_DIR is not used, so we'll skip it
PIPELINE_ID="$3"
BRANCH="$4"
ENVIRONMENT="$5"
COVERAGE_DIR="$6"
SECURITY_REPORT_FILE="$7"
# SAST_REPORT_FILE is not used, so we'll skip it
TEST_DURATION="$9"
ANALYSIS_RESULTS_FILE="${10}"

# Output file
OUTPUT_FILE="troubleshooting-report.html"

# Get system info
NODE_VERSION=$(node -v 2>/dev/null || echo "Node.js not found")
NPM_VERSION=$(npm -v 2>/dev/null || echo "NPM not found")
OS_INFO=$(uname -a 2>/dev/null || echo "OS info not available")

# Get disk space info
DISK_SPACE=$(df -h 2>/dev/null || echo "Disk space info not available")

# Initialize test result variables
TOTAL_TESTS="0"
FAILURES="0"
ERRORS="0"
SKIPPED="0"
PASSED="0"

# Check if test results exist
if [ -d "$PLAYWRIGHT_REPORTS_DIR" ] && [ -f "$PLAYWRIGHT_REPORTS_DIR/junit.xml" ]; then
    echo "Found JUnit XML report at $PLAYWRIGHT_REPORTS_DIR/junit.xml"
    
    # Try to extract test counts from junit.xml
    if command -v xmllint >/dev/null 2>&1; then
        # Try to handle both testsuites and single testsuite root elements
        ROOT_ELEMENT=$(xmllint --xpath "local-name(/*)" "$PLAYWRIGHT_REPORTS_DIR/junit.xml" 2>/dev/null || echo "unknown")
        
        if [ "$ROOT_ELEMENT" = "testsuites" ]; then
            TOTAL_TESTS=$(xmllint --xpath "sum(/testsuites/testsuite/@tests)" "$PLAYWRIGHT_REPORTS_DIR/junit.xml" 2>/dev/null || echo "0")
            FAILURES=$(xmllint --xpath "sum(/testsuites/testsuite/@failures)" "$PLAYWRIGHT_REPORTS_DIR/junit.xml" 2>/dev/null || echo "0")
            ERRORS=$(xmllint --xpath "sum(/testsuites/testsuite/@errors)" "$PLAYWRIGHT_REPORTS_DIR/junit.xml" 2>/dev/null || echo "0")
            SKIPPED=$(xmllint --xpath "sum(/testsuites/testsuite/@skipped)" "$PLAYWRIGHT_REPORTS_DIR/junit.xml" 2>/dev/null || echo "0")
        else
            TOTAL_TESTS=$(xmllint --xpath "string(/testsuite/@tests)" "$PLAYWRIGHT_REPORTS_DIR/junit.xml" 2>/dev/null || echo "0")
            FAILURES=$(xmllint --xpath "string(/testsuite/@failures)" "$PLAYWRIGHT_REPORTS_DIR/junit.xml" 2>/dev/null || echo "0")
            ERRORS=$(xmllint --xpath "string(/testsuite/@errors)" "$PLAYWRIGHT_REPORTS_DIR/junit.xml" 2>/dev/null || echo "0")
            SKIPPED=$(xmllint --xpath "string(/testsuite/@skipped)" "$PLAYWRIGHT_REPORTS_DIR/junit.xml" 2>/dev/null || echo "0")
        fi
    else
        # Fallback if xmllint is not available
        TOTAL_TESTS=$(grep -o 'tests="[0-9]*"' "$PLAYWRIGHT_REPORTS_DIR/junit.xml" | head -1 | grep -o '[0-9]*' || echo "0")
        FAILURES=$(grep -o 'failures="[0-9]*"' "$PLAYWRIGHT_REPORTS_DIR/junit.xml" | head -1 | grep -o '[0-9]*' || echo "0")
        ERRORS=$(grep -o 'errors="[0-9]*"' "$PLAYWRIGHT_REPORTS_DIR/junit.xml" | head -1 | grep -o '[0-9]*' || echo "0")
        SKIPPED=$(grep -o 'skipped="[0-9]*"' "$PLAYWRIGHT_REPORTS_DIR/junit.xml" | head -1 | grep -o '[0-9]*' || echo "0")
    fi
    
    # Calculate passed tests
    PASSED=$((TOTAL_TESTS - FAILURES - ERRORS - SKIPPED))
    
    echo "Test results: Total=$TOTAL_TESTS, Passed=$PASSED, Failed=$FAILURES, Errors=$ERRORS, Skipped=$SKIPPED"
else
    echo "No JUnit XML report found at $PLAYWRIGHT_REPORTS_DIR/junit.xml"
fi

# Check coverage directory
COVERAGE_STATUS="No coverage information available"
if [ -d "$COVERAGE_DIR" ]; then
    if [ -n "$(ls -A "$COVERAGE_DIR" 2>/dev/null)" ]; then
        COVERAGE_STATUS="Coverage report available"
        echo "Found coverage data in $COVERAGE_DIR"
    else
        COVERAGE_STATUS="Coverage directory exists but is empty"
        echo "Coverage directory is empty"
    fi
else
    COVERAGE_STATUS="No coverage directory found at: $COVERAGE_DIR"
    echo "Coverage directory not found"
fi

# Get security vulnerabilities if available
SECURITY_VULNS="No security scan results available"
if [ -f "$SECURITY_REPORT_FILE" ]; then
    if command -v jq >/dev/null 2>&1; then
        SECURITY_VULNS=$(jq -r '.metadata.vulnerabilities | to_entries[] | "\(.key): \(.value)"' "$SECURITY_REPORT_FILE" 2>/dev/null || echo "No vulnerabilities found or invalid format")
    else
        SECURITY_VULNS="Security report exists but jq is not available to parse it"
    fi
fi

# Get recommendations from analysis results
DUO_RECOMMENDATIONS="No recommendations available"
if [ -f "$ANALYSIS_RESULTS_FILE" ]; then
    if command -v jq >/dev/null 2>&1; then
        DUO_RECOMMENDATIONS=$(jq -r '.recommendations[]' "$ANALYSIS_RESULTS_FILE" 2>/dev/null | sed 's/^/- /' || echo "No recommendations found in analysis results.")
    else
        DUO_RECOMMENDATIONS="Analysis results exist but jq is not available to parse them"
    fi
fi

# Generate HTML report - using EOF with no variable expansion in the HTML
cat > "$OUTPUT_FILE" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pipeline Troubleshooting Report</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, 'Open Sans', 'Helvetica Neue', sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        h1, h2, h3 {
            color: #2e3440;
        }
        .card {
            background-color: #fff;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 20px;
            padding: 20px;
        }
        .header {
            background-color: #5e81ac;
            color: white;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
        }
        .status {
            font-size: 18px;
            font-weight: bold;
            padding: 10px;
            border-radius: 4px;
            display: inline-block;
        }
        .status-success {
            background-color: #a3be8c;
            color: #2e3440;
        }
        .status-warning {
            background-color: #ebcb8b;
            color: #2e3440;
        }
        .status-error {
            background-color: #bf616a;
            color: white;
        }
        .metrics {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
        }
        .metric-card {
            flex: 1;
            min-width: 200px;
            background-color: #eceff4;
            padding: 15px;
            border-radius: 4px;
        }
        .metric-value {
            font-size: 24px;
            font-weight: bold;
            margin: 10px 0;
        }
        pre {
            background-color: #eceff4;
            padding: 10px;
            border-radius: 4px;
            overflow-x: auto;
        }
        .recommendations {
            background-color: #d8dee9;
            padding: 15px;
            border-radius: 4px;
            margin-top: 20px;
        }
        .links {
            margin-top: 20px;
        }
        .links a {
            display: inline-block;
            margin-right: 15px;
            color: #5e81ac;
            text-decoration: none;
        }
        .links a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>Pipeline Troubleshooting Report</h1>
        <p>Branch: BRANCH_PLACEHOLDER | Pipeline: PIPELINE_PLACEHOLDER | Environment: ENV_PLACEHOLDER</p>
        <div class="status STATUS_CLASS_PLACEHOLDER">
            Status: STATUS_TEXT_PLACEHOLDER
        </div>
    </div>

    <div class="card">
        <h2>Test Results</h2>
        <div class="metrics">
            <div class="metric-card">
                <h3>Total</h3>
                <div class="metric-value">TOTAL_TESTS_PLACEHOLDER</div>
            </div>
            <div class="metric-card">
                <h3>Passed</h3>
                <div class="metric-value">PASSED_TESTS_PLACEHOLDER</div>
            </div>
            <div class="metric-card">
                <h3>Failed</h3>
                <div class="metric-value">FAILED_TESTS_PLACEHOLDER</div>
            </div>
            <div class="metric-card">
                <h3>Errors</h3>
                <div class="metric-value">ERROR_TESTS_PLACEHOLDER</div>
            </div>
            <div class="metric-card">
                <h3>Skipped</h3>
                <div class="metric-value">SKIPPED_TESTS_PLACEHOLDER</div>
            </div>
        </div>

        <h3>Coverage</h3>
        <p>COVERAGE_STATUS_PLACEHOLDER</p>

        <h3>Test Duration</h3>
        <p>TEST_DURATION_PLACEHOLDER seconds</p>
    </div>

    <div class="card">
        <h2>Security Scan</h2>
        <pre>SECURITY_VULNS_PLACEHOLDER</pre>
    </div>

    <div class="card">
        <h2>System Information</h2>
        <p><strong>Node.js:</strong> NODE_VERSION_PLACEHOLDER</p>
        <p><strong>NPM:</strong> NPM_VERSION_PLACEHOLDER</p>
        <p><strong>OS:</strong> OS_INFO_PLACEHOLDER</p>
        <p><strong>Disk Space:</strong></p>
        <pre>DISK_SPACE_PLACEHOLDER</pre>
    </div>

    <div class="card">
        <h2>Recommendations from Duo</h2>
        <div class="recommendations">
            <pre>DUO_RECOMMENDATIONS_PLACEHOLDER</pre>
        </div>
    </div>

    <div class="links">
        <a href="../PLAYWRIGHT_DIR_PLACEHOLDER/index.html" target="_blank">View Playwright Report</a>
        COVERAGE_LINK_PLACEHOLDER
    </div>
</body>
</html>
EOF

# Now replace the placeholders with actual values
# This avoids shellcheck issues with the heredoc
sed -i "s|BRANCH_PLACEHOLDER|$BRANCH|g" "$OUTPUT_FILE"
sed -i "s|PIPELINE_PLACEHOLDER|$PIPELINE_ID|g" "$OUTPUT_FILE"
sed -i "s|ENV_PLACEHOLDER|$ENVIRONMENT|g" "$OUTPUT_FILE"

# Set status class and text
if [ "$FAILURES" -eq "0" ] && [ "$ERRORS" -eq "0" ]; then
    sed -i "s|STATUS_CLASS_PLACEHOLDER|status-success|g" "$OUTPUT_FILE"
    sed -i "s|STATUS_TEXT_PLACEHOLDER|PASSED|g" "$OUTPUT_FILE"
else
    sed -i "s|STATUS_CLASS_PLACEHOLDER|status-error|g" "$OUTPUT_FILE"
    sed -i "s|STATUS_TEXT_PLACEHOLDER|FAILED|g" "$OUTPUT_FILE"
fi

# Replace test metrics
sed -i "s|TOTAL_TESTS_PLACEHOLDER|$TOTAL_TESTS|g" "$OUTPUT_FILE"
sed -i "s|PASSED_TESTS_PLACEHOLDER|$PASSED|g" "$OUTPUT_FILE"
sed -i "s|FAILED_TESTS_PLACEHOLDER|$FAILURES|g" "$OUTPUT_FILE"
sed -i "s|ERROR_TESTS_PLACEHOLDER|$ERRORS|g" "$OUTPUT_FILE"
sed -i "s|SKIPPED_TESTS_PLACEHOLDER|$SKIPPED|g" "$OUTPUT_FILE"

# Replace other placeholders
sed -i "s|COVERAGE_STATUS_PLACEHOLDER|$COVERAGE_STATUS|g" "$OUTPUT_FILE"
sed -i "s|TEST_DURATION_PLACEHOLDER|$TEST_DURATION|g" "$OUTPUT_FILE"
sed -i "s|SECURITY_VULNS_PLACEHOLDER|$SECURITY_VULNS|g" "$OUTPUT_FILE"
sed -i "s|NODE_VERSION_PLACEHOLDER|$NODE_VERSION|g" "$OUTPUT_FILE"
sed -i "s|NPM_VERSION_PLACEHOLDER|$NPM_VERSION|g" "$OUTPUT_FILE"
sed -i "s|OS_INFO_PLACEHOLDER|$OS_INFO|g" "$OUTPUT_FILE"
sed -i "s|DISK_SPACE_PLACEHOLDER|$DISK_SPACE|g" "$OUTPUT_FILE"
sed -i "s|DUO_RECOMMENDATIONS_PLACEHOLDER|$DUO_RECOMMENDATIONS|g" "$OUTPUT_FILE"
sed -i "s|PLAYWRIGHT_DIR_PLACEHOLDER|$PLAYWRIGHT_REPORTS_DIR|g" "$OUTPUT_FILE"

# Add coverage link if directory exists
if [ -d "$COVERAGE_DIR" ]; then
    COVERAGE_LINK="<a href=\"../$COVERAGE_DIR/index.html\" target=\"_blank\">View Coverage Report</a>"
    sed -i "s|COVERAGE_LINK_PLACEHOLDER|$COVERAGE_LINK|g" "$OUTPUT_FILE"
else
    sed -i "s|COVERAGE_LINK_PLACEHOLDER||g" "$OUTPUT_FILE"
fi

echo "Troubleshooting report generated at $OUTPUT_FILE"
