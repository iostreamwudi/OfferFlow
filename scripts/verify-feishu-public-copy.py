#!/usr/bin/env python3
"""Validate the 2026-11-17 public-view copy snapshot; not a live sync adapter.

The observed plain-text copy has 23 columns and unquoted embedded newlines.
This parser is restricted to that observed layout. It must not be used as a
general TSV parser: raw tabs in cells or changed column order are ambiguous.
"""
import argparse
import csv
import hashlib
import json
from datetime import datetime
from pathlib import Path
from urllib.parse import urlsplit


HEADERS = [
    "更新时间", "公司名称", "企业性质", "行业分类", "招聘岗位", "工作地点",
    "截止时间", "届次", "学历要求", "批次", "公告来源", "公告链接", "投递方式",
    "备注", "专业要求", "是否笔试", "字段 1", "字段 2", "专业要求 (1)",
    "是否笔试 (1)", "字段 1 (1)", "字段 2 (1)", "父记录",
]


def decode_observed_copy(text, expected_records):
    records, pending, tab_count = [], [], 0
    lines = text.split("\n")
    for index, line in enumerate(lines):
        physical_line = line + ("\n" if index < len(lines) - 1 else "")
        if not physical_line:
            continue
        pending.append(physical_line)
        tab_count += physical_line.count("\t")
        if tab_count > len(HEADERS) - 1:
            raise ValueError("Column overflow: layout changed or a cell contains raw tabs")
        if tab_count == len(HEADERS) - 1:
            record = "".join(pending)
            if record.endswith("\n"):
                record = record[:-1]
            records.append(record.split("\t"))
            pending, tab_count = [], 0
    if pending:
        raise ValueError("Incomplete final record or ambiguous boundary newline")
    if len(records) != expected_records:
        raise ValueError(f"Record count mismatch: {len(records)} != {expected_records}")
    rebuilt = "\n".join("\t".join(row) for row in records)
    if text not in (rebuilt, rebuilt + "\n"):
        raise ValueError("Reconstructed content does not match the original")
    # The observed first and final columns contain no embedded newlines. If
    # those boundary columns change, this format cannot determine row bounds.
    if any("\n" in row[0] or "\n" in row[-1] for row in records):
        raise ValueError("Ambiguous newline in a boundary column")
    return records


def single_http_url(value):
    value = value.strip()
    if not value or any(char.isspace() for char in value):
        return False
    try:
        parsed = urlsplit(value)
        return parsed.scheme in ("http", "https") and bool(parsed.hostname)
    except ValueError:
        return False


def valid_source_date(value):
    try:
        datetime.strptime(value.strip(), "%Y/%m/%d")
        return True
    except ValueError:
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--expected-records", type=int, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    raw = args.input.read_bytes()
    text = raw.decode("utf-8")
    if any(c in text for c in ("\u2028", "\u2029", "\v", "\f")):
        raise ValueError("Unverified line separator in this snapshot")
    rows = decode_observed_copy(text, args.expected_records)
    useful = [row for row in rows if row[1].strip() and row[4].strip()]
    nonempty = [tuple(row) for row in rows if any(cell.strip() for cell in row)]
    duplicate_count = len(nonempty) - len(set(nonempty))
    report = {
        "verificationDate": "2026-11-17",
        "method": "Public view Select All / Copy, pasted and saved through TextEdit UI",
        "scope": "Snapshot only; current shared view, not live or incremental sync",
        "sourceURL": "https://my.feishu.cn/base/ZBpybxIDfayhQssBHnYc9ZjEn7c?table=tblCNHUxBdaYvYvx&view=vewIPUzblP",
        "sourceDocumentTitle": "27届秋招+实习",
        "visibleViewTitle": "🎯26届网申总表2.0",
        "inputSHA256": hashlib.sha256(raw).hexdigest(),
        "bytes": len(raw),
        "sourceDisplayedRecords": args.expected_records,
        "parsedRecords": len(rows),
        "columnsPerRecord": len(HEADERS),
        "headersVisuallyVerified": HEADERS,
        "losslessRoundTrip": True,
        "blankRecords": len(rows) - len(nonempty),
        "recordsWithCompanyAndRecruitmentText": len(useful),
        "recordsMissingCompanyOrRecruitmentText": len(rows) - len(useful),
        "exactDuplicateNonemptyRecords": duplicate_count,
        "recordsWithEmbeddedNewlines": sum(any("\n" in c for c in r) for r in rows),
        "embeddedNewlines": sum(c.count("\n") for r in rows for c in r),
        "embeddedCarriageReturnsPreserved": text.count("\r"),
        "singleHTTPApplicationURLs": sum(single_http_url(r[12]) for r in rows),
        "nonemptyApplicationValuesNeedingInterpretation": sum(bool(r[12].strip()) and not single_http_url(r[12]) for r in rows),
        "emptyApplicationValues": sum(not r[12].strip() for r in rows),
        "parseableSourceDates": sum(valid_source_date(r[0]) for r in rows),
        "sourceRecordIdsObtained": 0,
        "fullJobDescriptionsVerified": 0,
        "limitations": [
            "Fixed observed schema only; raw tabs, reordered or hidden columns require a new validation.",
            "Application URL syntax is checked; destination availability and hiring status are not checked.",
            "Recruitment rows may aggregate multiple jobs; record count is not unique job count.",
            "No stable source record ID was obtained; content hashes are not source IDs.",
            "No automatic refresh, update/delete reconciliation or production importer is implemented.",
        ],
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    normalized = args.output_dir / "feishu-public-normalized.csv"
    with normalized.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(HEADERS)
        writer.writerows(rows)
    with normalized.open(encoding="utf-8-sig", newline="") as handle:
        reread = list(csv.reader(handle))
    if reread != [HEADERS, *rows]:
        raise ValueError("Normalized CSV failed round-trip verification")
    report["normalizedCSVRoundTrip"] = True
    (args.output_dir / "validation-report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items()
                      if key not in ("headersVisuallyVerified", "limitations")}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
