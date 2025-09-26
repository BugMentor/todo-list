#!/usr/bin/env python3
"""
GitLab CI/CD Pipeline Troubleshooter and Analyzer

This script analyzes various artifacts from a CI/CD pipeline run including:
- Playwright test results (HTML and JUnit XML reports)
- Security scan reports
- Server logs
- CI/CD pipeline logs

It generates a structured JSON output with insights, recommendations, and metrics.
"""

import argparse
import json
import logging
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict, Counter
from datetime import datetime
from typing import Dict, List, Any, Optional, Tuple

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("duo-troubleshoot")


class PipelineAnalyzer:
    """Analyzes CI/CD pipeline artifacts and generates insights."""

    def __init__(self):
        self.results = {
            "timestamp": datetime.now().isoformat(),
            "status": "unknown",
            "summary": "",
            "test_results": {},
            "security_scan": {},
            "performance_metrics": {},
            "errors": [],
            "warnings": [],
            "recommendations": [],
        }

    def analyze_junit_xml(self, junit_path: str) -> None:
        """Parse JUnit XML report and extract test metrics."""
        if not os.path.exists(junit_path):
            self.results["errors"].append(f"JUnit XML file not found: {junit_path}")
            return

        try:
            tree = ET.parse(junit_path)
            root = tree.getroot()

            # Extract test suite metrics
            total_tests = int(root.get("tests", 0))
            failures = int(root.get("failures", 0))
            errors = int(root.get("errors", 0))
            skipped = int(root.get("skipped", 0))
            passed = total_tests - failures - errors - skipped

            self.results["test_results"] = {
                "total": total_tests,
                "passed": passed,
                "failed": failures,
                "errors": errors,
                "skipped": skipped,
                "pass_rate": (
                    round(passed / total_tests * 100, 2) if total_tests > 0 else 0
                ),
            }

            # Extract failure details
            failure_details = []
            for test_case in root.findall(".//testcase"):
                for failure in test_case.findall("./failure"):
                    failure_details.append(
                        {
                            "test_name": test_case.get("name", "Unknown"),
                            "class_name": test_case.get("classname", "Unknown"),
                            "message": failure.get("message", "No message"),
                            "type": failure.get("type", "Unknown"),
                            "content": failure.text.strip() if failure.text else "",
                        }
                    )

            if failure_details:
                self.results["test_results"]["failures"] = failure_details

            # Set overall status based on test results
            if failures > 0 or errors > 0:
                self.results["status"] = "failed"
                self.results["summary"] = (
                    f"Tests failed: {failures} failures, {errors} errors"
                )
            else:
                self.results["status"] = "passed"
                self.results["summary"] = f"All {total_tests} tests passed"

            # Add recommendations based on test results
            if skipped > 0:
                self.results["warnings"].append(f"{skipped} tests were skipped")
                self.results["recommendations"].append(
                    "Review skipped tests to ensure they're not critical"
                )

        except Exception as e:
            self.results["errors"].append(f"Error parsing JUnit XML: {str(e)}")

    def analyze_security_report(self, security_report_path: str) -> None:
        """Parse security scan report and extract vulnerability metrics."""
        if not os.path.exists(security_report_path):
            self.results["warnings"].append(
                f"Security report not found: {security_report_path}"
            )
            return

        try:
            with open(security_report_path, "r") as f:
                try:
                    security_data = json.load(f)

                    # Extract vulnerability counts
                    vuln_counts = {}
                    if (
                        "metadata" in security_data
                        and "vulnerabilities" in security_data["metadata"]
                    ):
                        vuln_counts = security_data["metadata"]["vulnerabilities"]
                    elif "vulnerabilities" in security_data:
                        # Count vulnerabilities by severity
                        severities = [
                            v.get("severity", "unknown")
                            for v in security_data["vulnerabilities"]
                        ]
                        vuln_counts = dict(Counter(severities))

                    self.results["security_scan"] = {
                        "vulnerability_counts": vuln_counts,
                        "total_vulnerabilities": (
                            sum(vuln_counts.values()) if vuln_counts else 0
                        ),
                    }

                    # Add top vulnerabilities if present
                    if (
                        "vulnerabilities" in security_data
                        and security_data["vulnerabilities"]
                    ):
                        top_vulns = []
                        for name, vuln in security_data["vulnerabilities"].items():
                            if isinstance(vuln, dict):
                                top_vulns.append(
                                    {
                                        "name": name,
                                        "severity": vuln.get("severity", "unknown"),
                                        "description": vuln.get(
                                            "description", "No description"
                                        ),
                                    }
                                )

                        if top_vulns:
                            # Sort by severity and take top 5
                            severity_order = {
                                "critical": 0,
                                "high": 1,
                                "moderate": 2,
                                "low": 3,
                                "info": 4,
                                "unknown": 5,
                            }
                            top_vulns.sort(
                                key=lambda x: severity_order.get(
                                    x["severity"].lower(), 999
                                )
                            )
                            self.results["security_scan"]["top_vulnerabilities"] = (
                                top_vulns[:5]
                            )

                    # Add recommendations based on security findings
                    critical_count = vuln_counts.get("critical", 0)
                    high_count = vuln_counts.get("high", 0)

                    if critical_count > 0:
                        self.results["status"] = "failed"
                        self.results["errors"].append(
                            f"Found {critical_count} critical security vulnerabilities"
                        )
                        self.results["recommendations"].append(
                            "Address critical security vulnerabilities immediately"
                        )

                    if high_count > 0:
                        self.results["warnings"].append(
                            f"Found {high_count} high severity security vulnerabilities"
                        )
                        self.results["recommendations"].append(
                            "Plan to address high severity vulnerabilities soon"
                        )

                except json.JSONDecodeError:
                    # Handle non-JSON security reports
                    with open(security_report_path, "r") as f:
                        content = f.read()

                    self.results["security_scan"] = {
                        "raw_content": content[:1000]  # Limit to first 1000 chars
                    }

                    # Try to extract vulnerability counts using regex
                    critical_match = re.search(
                        r"critical.*?(\d+)", content, re.IGNORECASE
                    )
                    high_match = re.search(r"high.*?(\d+)", content, re.IGNORECASE)

                    if critical_match or high_match:
                        vuln_counts = {}
                        if critical_match:
                            vuln_counts["critical"] = int(critical_match.group(1))
                        if high_match:
                            vuln_counts["high"] = int(high_match.group(1))

                        self.results["security_scan"][
                            "vulnerability_counts"
                        ] = vuln_counts

        except Exception as e:
            self.results["errors"].append(f"Error analyzing security report: {str(e)}")

    def analyze_server_log(self, log_path: str) -> None:
        """Analyze server logs for errors and performance issues."""
        if not os.path.exists(log_path):
            self.results["warnings"].append(f"Server log not found: {log_path}")
            return

        try:
            error_patterns = [
                r"Error:",
                r"Exception:",
                r"Failed to",
                r"fatal:",
                r"\[ERROR\]",
            ]

            error_regex = re.compile("|".join(error_patterns), re.IGNORECASE)
            errors_found = []

            with open(log_path, "r") as f:
                for line_num, line in enumerate(f, 1):
                    if error_regex.search(line):
                        errors_found.append({"line": line_num, "content": line.strip()})

            if errors_found:
                self.results["warnings"].append(
                    f"Found {len(errors_found)} errors in server logs"
                )
                self.results["server_log_errors"] = errors_found[:10]  # Limit to top 10

                # Add recommendations
                self.results["recommendations"].append(
                    "Review server logs for application errors"
                )

        except Exception as e:
            self.results["errors"].append(f"Error analyzing server log: {str(e)}")

    def analyze_ci_log(self, log_content: str) -> None:
        """Analyze CI log content for build issues."""
        if not log_content:
            self.results["warnings"].append("No CI log content provided")
            return

        try:
            # Look for common CI issues
            timeout_match = re.search(r"timeout.*?(\d+)", log_content, re.IGNORECASE)
            if timeout_match:
                self.results["warnings"].append(
                    f"Possible timeout issue detected in CI log"
                )
                self.results["recommendations"].append(
                    "Consider increasing job timeout limits"
                )

            memory_match = re.search(
                r"(out of memory|memory limit exceeded)", log_content, re.IGNORECASE
            )
            if memory_match:
                self.results["warnings"].append("Memory limit exceeded in CI job")
                self.results["recommendations"].append(
                    "Increase memory allocation for CI jobs"
                )

            # Extract performance metrics if available
            duration_match = re.search(r"Duration: (\d+\.\d+) seconds", log_content)
            if duration_match:
                self.results["performance_metrics"]["duration"] = float(
                    duration_match.group(1)
                )

        except Exception as e:
            self.results["errors"].append(f"Error analyzing CI log: {str(e)}")

    def generate_final_recommendations(self) -> None:
        """Generate final recommendations based on all analysis results."""
        # Add general recommendations if none exist
        if not self.results["recommendations"]:
            if self.results["status"] == "passed":
                self.results["recommendations"].append(
                    "Consider adding more test coverage"
                )
                self.results["recommendations"].append(
                    "Set up regular security scanning"
                )
            elif self.results["status"] == "failed":
                self.results["recommendations"].append(
                    "Fix failing tests before merging"
                )

        # Add timestamp to recommendations
        self.results["analysis_timestamp"] = datetime.now().isoformat()

        # Deduplicate recommendations
        if self.results["recommendations"]:
            self.results["recommendations"] = list(set(self.results["recommendations"]))

    def get_results(self) -> Dict[str, Any]:
        """Return the analysis results."""
        self.generate_final_recommendations()
        return self.results


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Analyze CI/CD pipeline results")

    parser.add_argument(
        "--gitlab-ci-log-placeholder", help="Placeholder for GitLab CI log content"
    )
    parser.add_argument(
        "--playwright-html-report-path", help="Path to Playwright HTML report directory"
    )
    parser.add_argument("--junit-xml-report-path", help="Path to JUnit XML report file")
    parser.add_argument(
        "--security-scan-report-path", help="Path to security scan report file"
    )
    parser.add_argument("--server-log-path", help="Path to server log file")
    parser.add_argument(
        "--output-file", help="Path to output JSON file (default: stdout)"
    )
    parser.add_argument("--verbose", action="store_true", help="Enable verbose logging")

    return parser.parse_args()


def main() -> int:
    """Main entry point for the script."""
    args = parse_args()

    if args.verbose:
        logger.setLevel(logging.DEBUG)

    analyzer = PipelineAnalyzer()

    # Analyze JUnit XML report
    if args.junit_xml_report_path:
        logger.info(f"Analyzing JUnit XML report: {args.junit_xml_report_path}")
        analyzer.analyze_junit_xml(args.junit_xml_report_path)

    # Analyze security scan report
    if args.security_scan_report_path:
        logger.info(f"Analyzing security scan report: {args.security_scan_report_path}")
        analyzer.analyze_security_report(args.security_scan_report_path)

    # Analyze server log
    if args.server_log_path:
        logger.info(f"Analyzing server log: {args.server_log_path}")
        analyzer.analyze_server_log(args.server_log_path)

    # Analyze CI log
    if args.gitlab_ci_log_placeholder:
        logger.info("Analyzing CI log content")
        analyzer.analyze_ci_log(args.gitlab_ci_log_placeholder)

    # Get analysis results
    results = analyzer.get_results()

    # Output results
    if args.output_file:
        with open(args.output_file, "w") as f:
            json.dump(results, f, indent=2)
        logger.info(f"Results written to {args.output_file}")
    else:
        print(json.dumps(results, indent=2))

    return 0


if __name__ == "__main__":
    sys.exit(main())
