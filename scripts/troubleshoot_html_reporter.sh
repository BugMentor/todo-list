#!/bin/bash
# Troubleshooting HTML Report Generator
# This script generates an HTML report with troubleshooting information from CI/CD pipeline

set -e

# Parse arguments
PLAYWRIGHT_REPORTS_DIR="$1"
CI_PROJECT_DIR="$2"
PIPELINE_ID="$3"
BRANCH="$4"
ENVIRONMENT="$5"
COVERAGE_DIR="$6"
SECURITY_REPORT_FILE="$7"
# Unused but needed for positional parameters
: "$8" # SAST_REPORT_FILE - using : as a no-op to avoid shellcheck warning
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

# Check if test results exist
if [ -d "$PLAYWRIGHT_REPORTS_DIR" ] && [ -f "$PLAYWRIGHT_REPORTS_DIR/junit.xml" ]; then
    # Try to extract test counts from junit.xml
    if command -v xmllint >/dev/null 2>&1; then
        TOTAL_TESTS=$(xmllint --xpath "string(/testsuites/@tests)" "$PLAYWRIGHT_REPORTS_DIR/junit.xml" 2>/dev/null || echo "0")
        FAILURES=$(xmllint --xpath "string(/testsuites/@failures)" "$PLAYWRIGHT_REPORTS_DIR/junit.xml" 2>/dev/null || echo "0")
        ERRORS=$(xmllint --xpath "string(/testsuites/@errors)" "$PLAYWRIGHT_REPORTS_DIR/junit.xml" 2>/dev/null || echo "0")
        SKIPPED=$(xmllint --xpath "string(/testsuites/@skipped)" "$PLAYWRIGHT_REPORTS_DIR/junit.xml" 2>/dev/null || echo "0")
    else
        # Fallback if xmllint is not available
        TOTAL_TESTS=$(grep -o 'tests="[0-9]*"' "$PLAYWRIGHT_REPORTS_DIR/junit.xml" | head -1 | grep -o '[0-9]*' || echo "0")
        FAILURES=$(grep -o 'failures="[0-9]*"' "$PLAYWRIGHT_REPORTS_DIR/junit.xml" | head -1 | grep -o '[0-9]*' || echo "0")
        ERRORS=$(grep -o 'errors="[0-9]*"' "$PLAYWRIGHT_REPORTS_DIR/junit.xml" | head -1 | grep -o '[0-9]*' || echo "0")
        SKIPPED=$(grep -o 'skipped="[0-9]*"' "$PLAYWRIGHT_REPORTS_DIR/junit.xml" | head -1 | grep -o '[0-9]*' || echo "0")
    fi
    PASSED=$((TOTAL_TESTS - FAILURES - ERRORS - SKIPPED))
else
    TOTAL_TESTS="0"
    PASSED="0"
    FAILURES="0"
    ERRORS="0"
    SKIPPED="0"
fi

# Format test duration
if [[ "$TEST_DURATION" =~ ^[0-9]+$ ]]; then
    # If it's a number of seconds, format it nicely
    TEST_DURATION_FORMATTED="$TEST_DURATION seconds"
else
    # Otherwise use as-is
    TEST_DURATION_FORMATTED="$TEST_DURATION"
fi

# Check for security vulnerabilities
if [ -f "$SECURITY_REPORT_FILE" ]; then
    if command -v jq >/dev/null 2>&1; then
        # Try to extract vulnerability counts using jq
        CRITICAL=$(jq -r '.metadata.vulnerabilities.critical // 0' "$SECURITY_REPORT_FILE" 2>/dev/null || echo "0")
        HIGH=$(jq -r '.metadata.vulnerabilities.high // 0' "$SECURITY_REPORT_FILE" 2>/dev/null || echo "0")
        MEDIUM=$(jq -r '.metadata.vulnerabilities.moderate // 0' "$SECURITY_REPORT_FILE" 2>/dev/null || echo "0")
        LOW=$(jq -r '.metadata.vulnerabilities.low // 0' "$SECURITY_REPORT_FILE" 2>/dev/null || echo "0")
        SECURITY_INFO="Critical: $CRITICAL, High: $HIGH, Medium: $MEDIUM, Low: $LOW"
    else
        SECURITY_INFO="Security report exists but 'jq' is not available to parse it."
    fi
else
    SECURITY_INFO="No security report found at: $SECURITY_REPORT_FILE"
fi

# Check for analysis results
if [ -f "$ANALYSIS_RESULTS_FILE" ]; then
    if command -v jq >/dev/null 2>&1; then
        # Extract recommendations from analysis results
        DUO_RECOMMENDATIONS=$(jq -r '.recommendations[]' "$ANALYSIS_RESULTS_FILE" 2>/dev/null | sed 's/^/- /' || echo "No recommendations found in analysis results.")
    else
        DUO_RECOMMENDATIONS="Analysis results exist but 'jq' is not available to parse them."
    fi
else
    DUO_RECOMMENDATIONS="No analysis results found at: $ANALYSIS_RESULTS_FILE"
fi

# Check for code coverage
if [ -d "$COVERAGE_DIR" ]; then
    if [ -f "$COVERAGE_DIR/coverage-summary.json" ]; then
        if command -v jq >/dev/null 2>&1; then
            LINES_PCT=$(jq -r '.total.lines.pct' "$COVERAGE_DIR/coverage-summary.json" 2>/dev/null || echo "N/A")
            STATEMENTS_PCT=$(jq -r '.total.statements.pct' "$COVERAGE_DIR/coverage-summary.json" 2>/dev/null || echo "N/A")
            FUNCTIONS_PCT=$(jq -r '.total.functions.pct' "$COVERAGE_DIR/coverage-summary.json" 2>/dev/null || echo "N/A")
            BRANCHES_PCT=$(jq -r '.total.branches.pct' "$COVERAGE_DIR/coverage-summary.json" 2>/dev/null || echo "N/A")
            COVERAGE_INFO="Lines: ${LINES_PCT}%, Statements: ${STATEMENTS_PCT}%, Functions: ${FUNCTIONS_PCT}%, Branches: ${BRANCHES_PCT}%"
        else
            COVERAGE_INFO="Coverage report exists but 'jq' is not available to parse it."
        fi
    else
        COVERAGE_INFO="No coverage summary found in coverage directory."
    fi
else
    COVERAGE_INFO="No coverage directory found at: $COVERAGE_DIR"
fi

# Generate timestamp
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%SZ")

# Create HTML report
cat > "$OUTPUT_FILE" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GitLab Duo Troubleshooting Report</title>
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
            color: #2e2e2e;
        }
        h1 {
            border-bottom: 2px solid #fc6d26;
            padding-bottom: 10px;
        }
        .section {
            margin-bottom: 30px;
            padding: 20px;
            background-color: #f9f9f9;
            border-radius: 5px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .info-row {
            display: flex;
            margin-bottom: 10px;
        }
        .info-label {
            font-weight: bold;
            width: 200px;
        }
        .info-value {
            flex: 1;
        }
        .test-results {
            display: flex;
            justify-content: space-between;
            flex-wrap: wrap;
        }
        .test-metric {
            background-color: #fff;
            padding: 15px;
            border-radius: 5px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            margin-bottom: 10px;
            width: calc(20% - 10px);
            text-align: center;
        }
        .test-metric h3 {
            margin: 0;
            font-size: 14px;
            color: #666;
        }
        .test-metric .value {
            font-size: 24px;
            font-weight: bold;
            margin: 10px 0;
        }
        .passed { color: #1aaa55; }
        .failed { color: #db3b21; }
        .errors { color: #cc0033; }
        .skipped { color: #868686; }
        .total { color: #2e2e2e; }
        pre {
            background-color: #f1f1f1;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
            white-space: pre-wrap;
        }
        .recommendations {
            background-color: #fff;
            padding: 15px;
            border-radius: 5px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }
        .recommendations ul {
            margin: 0;
            padding-left: 20px;
        }
        .recommendations li {
            margin-bottom: 8px;
        }
        .footer {
            text-align: center;
            margin-top: 30px;
            font-size: 12px;
            color: #666;
        }
    </style>
</head>
<body>
    <h1>🔍 Duo Troubleshoot Report</h1>

    <div class="section">
        <h2>Pipeline info</h2>
        <div class="info-row">
            <div class="info-label">Pipeline ID:</div>
            <div class="info-value">$PIPELINE_ID</div>
        </div>
        <div class="info-row">
            <div class="info-label">Branch:</div>
            <div class="info-value">$BRANCH</div>
        </div>
        <div class="info-row">
            <div class="info-label">Environment:</div>
            <div class="info-value">$ENVIRONMENT</div>
        </div>
    </div>

    <div class="section">
        <h2>System</h2>
        <div class="info-row">
            <div class="info-label">Node:</div>
            <div class="info-value">$NODE_VERSION</div>
        </div>
        <div class="info-row">
            <div class="info-label">NPM:</div>
            <div class="info-value">$NPM_VERSION</div>
        </div>
        <div class="info-row">
            <div class="info-label">OS:</div>
            <div class="info-value">$OS_INFO</div>
        </div>
    </div>

    <div class="section">
        <h2>Test results</h2>
        <div class="test-results">
            <div class="test-metric">
                <h3>Total</h3>
                <div class="value total">$TOTAL_TESTS</div>
            </div>
            <div class="test-metric">
                <h3>Passed</h3>
                <div class="value passed">$PASSED</div>
            </div>
            <div class="test-metric">
                <h3>Failed</h3>
                <div class="value failed">$FAILURES</div>
            </div>
            <div class="test-metric">
                <h3>Errors</h3>
                <div class="value errors">$ERRORS</div>
            </div>
            <div class="test-metric">
                <h3>Skipped</h3>
                <div class="value skipped">$SKIPPED</div>
            </div>
        </div>
        <div class="info-row">
            <div class="info-label">Test run time:</div>
            <div class="info-value">$TEST_DURATION_FORMATTED</div>
        </div>
        <div class="info-row">
            <div class="info-label">Playwright report:</div>
            <div class="info-value">$PLAYWRIGHT_REPORTS_DIR/index.html</div>
        </div>
    </div>

    <div class="section">
        <h2>Coverage</h2>
        <pre>$COVERAGE_INFO</pre>
    </div>

    <div class="section">
        <h2>Security scan</h2>
        <pre>$SECURITY_INFO</pre>
    </div>

    <div class="section">
        <h2>Recommendations from Duo</h2>
        <div class="recommendations">
            <pre>$DUO_RECOMMENDATIONS</pre>
        </div>
    </div>

    <div class="section">
        <h2>Disk space</h2>
        <pre>$DISK_SPACE</pre>
    </div>

    <div class="footer">
        <p>Generated: $TIMESTAMP</p>
        <p>Report file: $CI_PROJECT_DIR/$OUTPUT_FILE</p>
    </div>
</body>
</html>
EOF

echo "Troubleshooting report generated: $OUTPUT_FILE"
