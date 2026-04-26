#!/usr/bin/env python3
"""
Job 4 Mapper — Average Interest Rate vs Default Rate by Loan Grade

Emits two types of key-value pairs per row:
    <grade>\tinterest:<rate_float>   — for every valid row
    <grade>\tdefault:1               — only for defaulted loans

The reducer accumulates these to compute both avg interest rate and
default rate per grade in a single pass, surfacing the risk-return tradeoff.

Sample output:
  B\tinterest:13.56
  B\tdefault:1
  C\tinterest:16.02
"""

import csv
import io
import sys

OLD_COL_LOAN_AMNT = 0
OLD_COL_GRADE = 6
OLD_COL_INT_RATE = 4
OLD_COL_LOAN_STATUS = 14

NEW_COL_LOAN_AMNT = 2
NEW_COL_GRADE = 8
NEW_COL_INT_RATE = 6
NEW_COL_LOAN_STATUS = 16

VALID_GRADES = frozenset({'A', 'B', 'C', 'D', 'E', 'F', 'G'})
DEFAULT_STATUSES = frozenset({
    'Charged Off',
    'Default',
    'Does not meet the credit policy. Status:Charged Off',
})
PAID_STATUSES = frozenset({
    'Fully Paid',
    'Does not meet the credit policy. Status:Fully Paid',
})


def parse_rate(rate_str: str) -> float:
    """Parse '13.56%' or '13.56' into 13.56."""
    return float(rate_str.strip().rstrip('%'))


def main() -> None:
    text_stream = io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8-sig', errors='replace')
    reader = csv.reader(text_stream)
    counters = {
        'header': 0,
        'short_rows': 0,
        'invalid_grade': 0,
        'missing_rate': 0,
        'bad_rate': 0,
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
                col_loan_amnt, col_grade, col_int_rate, col_loan_status = (
                    OLD_COL_LOAN_AMNT,
                    OLD_COL_GRADE,
                    OLD_COL_INT_RATE,
                    OLD_COL_LOAN_STATUS,
                )
            else:
                col_loan_amnt, col_grade, col_int_rate, col_loan_status = (
                    NEW_COL_LOAN_AMNT,
                    NEW_COL_GRADE,
                    NEW_COL_INT_RATE,
                    NEW_COL_LOAN_STATUS,
                )

            if row[col_loan_amnt].strip() in ('loan_amnt', 'id', ''):
                counters['header'] += 1
                continue

            loan_status = row[col_loan_status].strip()
            if loan_status not in DEFAULT_STATUSES and loan_status not in PAID_STATUSES:
                counters['unknown_status'] += 1
                continue

            grade = row[col_grade].strip().upper()
            if grade not in VALID_GRADES:
                counters['invalid_grade'] += 1
                continue

            int_rate_str = row[col_int_rate].strip()
            if not int_rate_str:
                counters['missing_rate'] += 1
                continue

            try:
                int_rate = parse_rate(int_rate_str)
            except ValueError:
                counters['bad_rate'] += 1
                continue

            print(f"{grade}\tinterest:{int_rate:.4f}")
            counters['emitted'] += 1

            if loan_status in DEFAULT_STATUSES:
                print(f"{grade}\tdefault:1")

        except Exception as exc:
            counters['errors'] += 1
            sys.stderr.write(f"SKIP line {line_num}: unexpected - {exc}\n")

    sys.stderr.write(f"reporter:counter:Job4Mapper,HeaderRows,{counters['header']}\n")
    sys.stderr.write(f"reporter:counter:Job4Mapper,ShortRows,{counters['short_rows']}\n")
    sys.stderr.write(f"reporter:counter:Job4Mapper,InvalidGrade,{counters['invalid_grade']}\n")
    sys.stderr.write(f"reporter:counter:Job4Mapper,MissingRate,{counters['missing_rate']}\n")
    sys.stderr.write(f"reporter:counter:Job4Mapper,BadRate,{counters['bad_rate']}\n")
    sys.stderr.write(f"reporter:counter:Job4Mapper,UnknownStatus,{counters['unknown_status']}\n")
    sys.stderr.write(f"reporter:counter:Job4Mapper,EmittedRows,{counters['emitted']}\n")
    sys.stderr.write(f"reporter:counter:Job4Mapper,Errors,{counters['errors']}\n")


if __name__ == '__main__':
    main()
