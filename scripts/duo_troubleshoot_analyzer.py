#!/usr/bin/env python3
"""
GitLab CI/CD Pipeline Troubleshooter and Analyzer
Generates a JSON report from Playwright tests, security scans, server logs, and CI logs.
"""

import argparse
import json
import logging
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from datetime import datetime
from typing import Any, Dict, List, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("duo-troubleshoot")


class PipelineAnalyzer:
    def __init__(self):
        self.results: Dict[str, Any] = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "status": "unknown",
            "summary": "",
            "test_results": {},
            "security_scan": {},
            "performance_metrics": {},
            "errors": [],
            "warnings": [],
            "recommendations": [],
        }
        self.has_test_results = False
        self.has_security_results = False

    def analyze_junit_xml(self, path: str) -> bool:
        """Analyze JUnit XML test results and return whether analysis was successful."""
        if not os.path.exists(path):
            self.results["errors"].append(f"JUnit XML not found: {path}")
            return False

        try:
            tree = ET.parse(path)
            root = tree.getroot()

            # Handle both testsuites and testsuite root elements
            if root.tag == "testsuites":
                total = sum(
                    int(suite.attrib.get("tests", 0))
                    for suite in root.findall("./testsuite")
                )
                failures = sum(
                    int(suite.attrib.get("failures", 0))
                    for suite in root.findall("./testsuite")
                )
                errors = sum(
                    int(suite.attrib.get("errors", 0))
                    for suite in root.findall("./testsuite")
                )
                skipped = sum(
                    int(suite.attrib.get("skipped", 0))
                    for suite in root.findall("./testsuite")
                )
            else:  # Single testsuite as root
                total = int(root.attrib.get("tests", 0))
                failures = int(root.attrib.get("failures", 0))
                errors = int(root.attrib.get("errors", 0))
                skipped = int(root.attrib.get("skipped", 0))

            passed = total - failures - errors - skipped

            # If no tests were found, this is a problem
            if total == 0:
                self.results["errors"].append("No tests were executed")
                self.results["recommendations"].append(
                    "Check test discovery configuration"
                )
                return False

            failure_details = []
            for case in root.findall(".//testcase"):
                for fail in case.findall("failure") + case.findall("error"):
                    failure_details.append(
                        {
                            "test_name": case.get("name", "unknown"),
                            "class_name": case.get("classname", "unknown"),
                            "message": fail.get("message", ""),
                            "type": fail.get("type", ""),
                            "content": fail.text.strip() if fail.text else "",
                        }
                    )

            self.results["test_results"] = {
                "total": total,
                "passed": passed,
                "failed": failures,
                "errors": errors,
                "skipped": skipped,
                "pass_rate": round(passed / total * 100, 2) if total > 0 else 0,
                "failure_details": failure_details,
            }

            # Set overall status based on test results
            if failures > 0 or errors > 0:
                self.results["status"] = "failed"
                self.results["summary"] = (
                    f"{failures} failures, {errors} errors out of {total} tests"
                )
            else:
                self.results["status"] = "passed"
                self.results["summary"] = f"All {total} tests passed"

            # Add recommendations based on test results
            if failures > 0 or errors > 0:
                self.results["recommendations"].append(
                    "Fix failing tests before merging"
                )

            if skipped > 0:
                self.results["warnings"].append(f"{skipped} tests skipped")
                self.results["recommendations"].append("Review skipped tests")

            self.has_test_results = True
            return True

        except Exception as e:
            self.results["errors"].append(f"Error parsing JUnit XML: {str(e)}")
            logger.exception("Error parsing JUnit XML")
            return False

    def analyze_security_report(self, path: str) -> bool:
        """Analyze security scan report and return whether analysis was successful."""
        if not os.path.exists(path):
            self.results["warnings"].append(f"Security report not found: {path}")
            return False

        try:
            with open(path, "r") as f:
                try:
                    data = json.load(f)
                except json.JSONDecodeError:
                    # Handle non-JSON security reports
                    content = f.read()
                    self.results["security_scan"]["raw_content"] = content[:1000]
                    if "No vulnerabilities found" in content:
                        self.results["security_scan"]["vulnerability_counts"] = {}
                        self.results["security_scan"]["total_vulnerabilities"] = 0
                        self.has_security_results = True
                        return True
                    return False

            # Extract vulnerability counts from different JSON formats
            vulns = {}
            if "metadata" in data and "vulnerabilities" in data["metadata"]:
                vulns = data["metadata"]["vulnerabilities"]
            elif "vulnerabilities" in data:
                if isinstance(data["vulnerabilities"], list):
                    vulns = dict(
                        Counter(
                            [
                                v.get("severity", "unknown")
                                for v in data["vulnerabilities"]
                            ]
                        )
                    )
                elif isinstance(data["vulnerabilities"], dict):
                    vulns = dict(
                        Counter(
                            [
                                v.get("severity", "unknown")
                                for v in data["vulnerabilities"].values()
                            ]
                        )
                    )

            self.results["security_scan"]["vulnerability_counts"] = vulns
            self.results["security_scan"]["total_vulnerabilities"] = (
                sum(vulns.values()) if vulns else 0
            )

            # Add recommendations based on security findings
            if vulns.get("critical", 0) > 0:
                self.results["errors"].append(
                    f"Critical vulnerabilities: {vulns['critical']}"
                )
                self.results["recommendations"].append(
                    "Fix critical vulnerabilities immediately"
                )

            if vulns.get("high", 0) > 0:
                self.results["warnings"].append(
                    f"High severity vulnerabilities: {vulns['high']}"
                )
                self.results["recommendations"].append(
                    "Address high severity vulnerabilities soon"
                )

            self.has_security_results = True
            return True

        except Exception as e:
            self.results["errors"].append(f"Error analyzing security report: {str(e)}")
            logger.exception("Error analyzing security report")
            return False

    def analyze_server_log(self, path: str) -> bool:
        """Analyze server logs for errors and return whether analysis was successful."""
        if not os.path.exists(path):
            self.results["warnings"].append(f"Server log not found: {path}")
            return False

        try:
            errors_found = []
            pattern = re.compile(
                r"(Error:|Exception:|Failed to|fatal:|\[ERROR\])", re.IGNORECASE
            )

            with open(path, "r") as f:
                for i, line in enumerate(f, 1):
                    if pattern.search(line):
                        errors_found.append({"line": i, "content": line.strip()})

            if errors_found:
                self.results["warnings"].append(
                    f"{len(errors_found)} server log errors"
                )
                self.results["server_log_errors"] = errors_found[
                    :10
                ]  # Limit to first 10 errors
                self.results["recommendations"].append("Check server logs for errors")

            return True

        except Exception as e:
            self.results["errors"].append(f"Error analyzing server log: {str(e)}")
            logger.exception("Error analyzing server log")
            return False

    def analyze_ci_log(self, content: str) -> bool:
        """Analyze CI log content for common issues and return whether analysis was successful."""
        if not content:
            self.results["warnings"].append("No CI log content provided")
            return False

        try:
            # Check for common CI issues
            if re.search(r"timeout.*?(\d+)", content, re.IGNORECASE):
                self.results["warnings"].append("Possible timeout detected in CI job")
                self.results["recommendations"].append(
                    "Increase job timeout or optimize tests"
                )

            if re.search(
                r"(out of memory|memory limit exceeded)", content, re.IGNORECASE
            ):
                self.results["warnings"].append("Memory limit exceeded in CI job")
                self.results["recommendations"].append(
                    "Increase memory allocation for CI job"
                )

            # Extract performance metrics if available
            duration_match = re.search(r"Duration: (\d+\.\d+) seconds", content)
            if duration_match:
                self.results["performance_metrics"]["duration"] = float(
                    duration_match.group(1)
                )

            # Check for coverage issues
            if re.search(
                r"(No coverage directory found|Coverage directory not found)",
                content,
                re.IGNORECASE,
            ):
                self.results["warnings"].append("Coverage directory not found")
                self.results["recommendations"].append(
                    "Configure code coverage collection in your tests"
                )

            return True

        except Exception as e:
            self.results["errors"].append(f"Error analyzing CI log: {str(e)}")
            logger.exception("Error analyzing CI log")
            return False

    def add_test_duration(self, duration: Optional[str]) -> None:
        """Add test duration to performance metrics if available."""
        if duration and duration.isdigit():
            self.results["performance_metrics"]["test_duration"] = int(duration)

    def check_coverage_dir(self, path: str) -> None:
        """Check if coverage directory exists and has content."""
        if not os.path.exists(path):
            self.results["warnings"].append("Coverage directory not found")
            self.results["recommendations"].append(
                "Configure code coverage collection in your tests"
            )
        elif not os.listdir(path):
            self.results["warnings"].append("Coverage directory is empty")
            self.results["recommendations"].append(
                "Verify code coverage is properly configured"
            )

    def finalize(self) -> None:
        """Finalize analysis results and add appropriate recommendations."""
        # Deduplicate recommendations and warnings
        self.results["recommendations"] = list(set(self.results["recommendations"]))
        self.results["warnings"] = list(set(self.results["warnings"]))

        # Add general recommendations if none exist
        if not self.results["recommendations"]:
            if self.has_test_results:
                if self.results["status"] == "passed":
                    self.results["recommendations"].append(
                        "Consider adding more test coverage"
                    )
                    if not self.has_security_results:
                        self.results["recommendations"].append(
                            "Set up regular security scans"
                        )
            else:
                self.results["recommendations"].append(
                    "Set up automated tests for your project"
                )

        # Add timestamp for when analysis was completed
        self.results["analysis_timestamp"] = datetime.utcnow().isoformat() + "Z"


def parse_args():
    parser = argparse.ArgumentParser(description="Analyze CI/CD pipeline artifacts")
    parser.add_argument(
        "--playwright-html-report-path", help="Path to Playwright HTML report directory"
    )
    parser.add_argument("--junit-xml-report-path", help="Path to JUnit XML report file")
    parser.add_argument(
        "--security-scan-report-path", help="Path to security scan report file"
    )
    parser.add_argument("--server-log-path", help="Path to server log file")
    parser.add_argument(
        "--gitlab-ci-log-placeholder", help="GitLab CI log content or placeholder"
    )
    parser.add_argument("--test-duration", help="Test duration in seconds")
    parser.add_argument("--coverage-dir", help="Path to coverage directory")
    parser.add_argument("--output-file", help="Path to output JSON file")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose logging")
    return parser.parse_args()


def main():
    args = parse_args()
    if args.verbose:
        logger.setLevel(logging.DEBUG)

    analyzer = PipelineAnalyzer()

    # Analyze available artifacts
    if args.junit_xml_report_path:
        analyzer.analyze_junit_xml(args.junit_xml_report_path)

    if args.security_scan_report_path:
        analyzer.analyze_security_report(args.security_scan_report_path)

    if args.server_log_path:
        analyzer.analyze_server_log(args.server_log_path)

    if args.gitlab_ci_log_placeholder:
        analyzer.analyze_ci_log(args.gitlab_ci_log_placeholder)

    if args.test_duration:
        analyzer.add_test_duration(args.test_duration)

    if args.coverage_dir:
        analyzer.check_coverage_dir(args.coverage_dir)

    # Finalize analysis and generate recommendations
    analyzer.finalize()
    results = analyzer.results

    # Output results
    if args.output_file:
        with open(args.output_file, "w") as f:
            json.dump(results, f, indent=2)
        logger.info(f"Results written to {args.output_file}")
    else:
        print(json.dumps(results, indent=2))


if __name__ == "__main__":
    sys.exit(main())
