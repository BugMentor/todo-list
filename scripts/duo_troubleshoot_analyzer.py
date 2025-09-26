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
from typing import Any, Dict

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

    def analyze_junit_xml(self, path: str):
        if not os.path.exists(path):
            self.results["errors"].append(f"JUnit XML not found: {path}")
            return
        try:
            tree = ET.parse(path)
            root = tree.getroot()
            total = int(root.attrib.get("tests", 0))
            failures = int(root.attrib.get("failures", 0))
            errors = int(root.attrib.get("errors", 0))
            skipped = int(root.attrib.get("skipped", 0))
            passed = total - failures - errors - skipped

            failure_details = []
            for case in root.findall(".//testcase"):
                for fail in case.findall("failure"):
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

            self.results["status"] = (
                "failed" if failures > 0 or errors > 0 else "passed"
            )
            self.results["summary"] = (
                f"{failures} failures, {errors} errors"
                if failures + errors > 0
                else f"All {total} tests passed"
            )
            if skipped > 0:
                self.results["warnings"].append(f"{skipped} tests skipped")
                self.results["recommendations"].append("Review skipped tests")

        except Exception as e:
            self.results["errors"].append(f"Error parsing JUnit XML: {str(e)}")

    def analyze_security_report(self, path: str):
        if not os.path.exists(path):
            self.results["warnings"].append(f"Security report not found: {path}")
            return
        try:
            with open(path, "r") as f:
                try:
                    data = json.load(f)
                except json.JSONDecodeError:
                    content = f.read()
                    self.results["security_scan"]["raw_content"] = content[:1000]
                    return

            vulns = {}
            if "metadata" in data and "vulnerabilities" in data["metadata"]:
                vulns = data["metadata"]["vulnerabilities"]
            elif "vulnerabilities" in data:
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

            # Recommendations
            if vulns.get("critical", 0) > 0:
                self.results["status"] = "failed"
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

        except Exception as e:
            self.results["errors"].append(f"Error analyzing security report: {str(e)}")

    def analyze_server_log(self, path: str):
        if not os.path.exists(path):
            self.results["warnings"].append(f"Server log not found: {path}")
            return
        errors_found = []
        try:
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
                self.results["server_log_errors"] = errors_found[:10]
                self.results["recommendations"].append("Check server logs for errors")
        except Exception as e:
            self.results["errors"].append(f"Error analyzing server log: {str(e)}")

    def analyze_ci_log(self, content: str):
        if not content:
            self.results["warnings"].append("No CI log content")
            return
        try:
            if re.search(r"timeout.*?(\d+)", content, re.IGNORECASE):
                self.results["warnings"].append("Possible timeout detected")
                self.results["recommendations"].append("Increase job timeout")
            if re.search(
                r"(out of memory|memory limit exceeded)", content, re.IGNORECASE
            ):
                self.results["warnings"].append("Memory limit exceeded")
                self.results["recommendations"].append("Increase memory allocation")
            duration_match = re.search(r"Duration: (\d+\.\d+) seconds", content)
            if duration_match:
                self.results["performance_metrics"]["duration"] = float(
                    duration_match.group(1)
                )
        except Exception as e:
            self.results["errors"].append(f"Error analyzing CI log: {str(e)}")

    def add_test_duration(self, duration: str):
        if duration:
            self.results["performance_metrics"]["test_duration"] = duration

    def finalize(self):
        if not self.results["recommendations"]:
            if self.results["status"] == "passed":
                self.results["recommendations"].extend(
                    ["Add more test coverage", "Schedule regular security scans"]
                )
            else:
                self.results["recommendations"].append(
                    "Fix failing tests before merging"
                )
        self.results["recommendations"] = list(set(self.results["recommendations"]))
        self.results["analysis_timestamp"] = datetime.utcnow().isoformat() + "Z"


def parse_args():
    parser = argparse.ArgumentParser(description="Analyze CI/CD pipeline artifacts")
    parser.add_argument("--playwright-html-report-path")
    parser.add_argument("--junit-xml-report-path")
    parser.add_argument("--security-scan-report-path")
    parser.add_argument("--server-log-path")
    parser.add_argument("--gitlab-ci-log-placeholder")
    parser.add_argument("--test-duration")
    parser.add_argument("--output-file")
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    if args.verbose:
        logger.setLevel(logging.DEBUG)

    analyzer = PipelineAnalyzer()

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

    analyzer.finalize()
    results = analyzer.results

    if args.output_file:
        with open(args.output_file, "w") as f:
            json.dump(results, f, indent=2)
        logger.info(f"Results written to {args.output_file}")
    else:
        print(json.dumps(results, indent=2))


if __name__ == "__main__":
    sys.exit(main())
