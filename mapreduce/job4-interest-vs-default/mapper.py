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

import sys
import csv

COL_LOAN_AMNT = 0
COL_GRADE = 6
COL_INT_RATE = 4
COL_LOAN_STATUS = 14

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
    reader = csv.reader(sys.stdin)
    for line_num, row in enumerate(reader):
        try:
            if row[COL_LOAN_AMNT].strip() in ('loan_amnt', 'id', ''):
                continue

            loan_status = row[COL_LOAN_STATUS].strip()
            if loan_status not in DEFAULT_STATUSES and loan_status not in PAID_STATUSES:
                continue

            grade = row[COL_GRADE].strip().upper()
            if grade not in VALID_GRADES:
                sys.stderr.write(f"SKIP line {line_num}: invalid grade '{grade}'\n")
                continue

            int_rate_str = row[COL_INT_RATE].strip()
            if not int_rate_str:
                sys.stderr.write(f"SKIP line {line_num}: missing interest rate\n")
                continue

            int_rate = parse_rate(int_rate_str)

            print(f"{grade}\tinterest:{int_rate:.4f}")

            if loan_status in DEFAULT_STATUSES:
                print(f"{grade}\tdefault:1")

        except (ValueError, IndexError) as exc:
            sys.stderr.write(f"SKIP line {line_num}: {exc}\n")
        except Exception as exc:
            sys.stderr.write(f"SKIP line {line_num}: unexpected — {exc}\n")


if __name__ == '__main__':
    main()
