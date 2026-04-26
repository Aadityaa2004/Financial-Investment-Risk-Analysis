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

import sys
import csv

COL_LOAN_AMNT = 0
COL_EMP_LENGTH = 9
COL_LOAN_STATUS = 14

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
    reader = csv.reader(sys.stdin)
    for line_num, row in enumerate(reader):
        try:
            if row[COL_LOAN_AMNT].strip() in ('loan_amnt', 'id', ''):
                continue

            loan_status = row[COL_LOAN_STATUS].strip()
            if loan_status in DEFAULT_STATUSES:
                classification = 'default'
            elif loan_status in PAID_STATUSES:
                classification = 'paid'
            else:
                continue

            emp_raw = row[COL_EMP_LENGTH].strip()
            bucket = EMP_BUCKET_MAP.get(emp_raw)
            if bucket is None:
                # n/a or empty — skip
                continue

            print(f"{bucket}\t1:{classification}")

        except IndexError:
            sys.stderr.write(f"SKIP line {line_num}: too few columns ({len(row)})\n")
        except Exception as exc:
            sys.stderr.write(f"SKIP line {line_num}: {exc}\n")


if __name__ == '__main__':
    main()
