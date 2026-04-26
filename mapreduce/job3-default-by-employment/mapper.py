#!/usr/bin/env python3
"""
Job 3 Mapper — Default Rate by Employment Length

Reads LendingClub CSV rows and emits:
    <emp_bucket>\t1:default
    <emp_bucket>\t1:paid

Employment length is bucketed into 5 groups for cleaner analysis:
    "< 1 year"   → emp_length values: "< 1 year"
    "1-2 years"  → "1 year", "2 years"
    "3-5 years"  → "3 years", "4 years", "5 years"
    "6-9 years"  → "6 years", "7 years", "8 years", "9 years"
    "10+ years"  → "10+ years"

Sample output:
  3-5 years\t1:paid
  10+ years\t1:default
"""

import csv
import io
import sys

OLD_COL_LOAN_AMNT = 0
OLD_COL_EMP_LENGTH = 9
OLD_COL_LOAN_STATUS = 14

NEW_COL_LOAN_AMNT = 2
NEW_COL_EMP_LENGTH = 11
NEW_COL_LOAN_STATUS = 16

DEFAULT_STATUSES = frozenset({
    'Charged Off',
    'Default',
    'Does not meet the credit policy. Status:Charged Off',
})
PAID_STATUSES = frozenset({
    'Fully Paid',
    'Does not meet the credit policy. Status:Fully Paid',
})

EMP_BUCKET_MAP = {
    '< 1 year':   '< 1 year',
    '1 year':     '1-2 years',
    '2 years':    '1-2 years',
    '3 years':    '3-5 years',
    '4 years':    '3-5 years',
    '5 years':    '3-5 years',
    '6 years':    '6-9 years',
    '7 years':    '6-9 years',
    '8 years':    '6-9 years',
    '9 years':    '6-9 years',
    '10+ years':  '10+ years',
}


def main() -> None:
    text_stream = io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8-sig', errors='replace')
    reader = csv.reader(text_stream)
    counters = {
        'header': 0,
        'short_rows': 0,
        'missing_bucket': 0,
        'unknown_status': 0,
        'emitted': 0,
        'errors': 0,
    }

    for line_num, row in enumerate(reader, start=1):
        try:
            if len(row) <= NEW_COL_LOAN_STATUS:
                counters['short_rows'] += 1
                continue

            old_status = row[OLD_COL_LOAN_STATUS].strip()
            if old_status in DEFAULT_STATUSES or old_status in PAID_STATUSES:
                col_loan_amnt, col_emp_length, col_loan_status = OLD_COL_LOAN_AMNT, OLD_COL_EMP_LENGTH, OLD_COL_LOAN_STATUS
            else:
                col_loan_amnt, col_emp_length, col_loan_status = NEW_COL_LOAN_AMNT, NEW_COL_EMP_LENGTH, NEW_COL_LOAN_STATUS

            if row[col_loan_amnt].strip() in ('loan_amnt', 'id', ''):
                counters['header'] += 1
                continue

            loan_status = row[col_loan_status].strip()
            if loan_status in DEFAULT_STATUSES:
                classification = 'default'
            elif loan_status in PAID_STATUSES:
                classification = 'paid'
            else:
                counters['unknown_status'] += 1
                continue

            emp_raw = row[col_emp_length].strip()
            bucket = EMP_BUCKET_MAP.get(emp_raw)
            if bucket is None:
                # n/a or empty — skip
                counters['missing_bucket'] += 1
                continue

            print(f"{bucket}\t1:{classification}")
            counters['emitted'] += 1

        except Exception as exc:
            counters['errors'] += 1
            sys.stderr.write(f"SKIP line {line_num}: {exc}\n")

    sys.stderr.write(f"reporter:counter:Job3Mapper,HeaderRows,{counters['header']}\n")
    sys.stderr.write(f"reporter:counter:Job3Mapper,ShortRows,{counters['short_rows']}\n")
    sys.stderr.write(f"reporter:counter:Job3Mapper,MissingBucket,{counters['missing_bucket']}\n")
    sys.stderr.write(f"reporter:counter:Job3Mapper,UnknownStatus,{counters['unknown_status']}\n")
    sys.stderr.write(f"reporter:counter:Job3Mapper,EmittedRows,{counters['emitted']}\n")
    sys.stderr.write(f"reporter:counter:Job3Mapper,Errors,{counters['errors']}\n")


if __name__ == '__main__':
    main()
