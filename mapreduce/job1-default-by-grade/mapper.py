#!/usr/bin/env python3
"""
Job 1 Mapper — Default Rate by Loan Grade

Reads LendingClub CSV rows from stdin and emits:
    <grade>\t1:default   (if loan_status is Charged Off or Default)
    <grade>\t1:paid      (if loan_status is Fully Paid)

Rows with missing grade or unrecognised status are skipped (logged to stderr).

Sample input line (tab-truncated for readability):
  10000,36 months,11.44%,329.48,B,B4,...,Fully Paid,...,CA,...

Sample output:
  B\t1:paid
  C\t1:default
"""

import sys
import csv

# LendingClub accepted_2007_to_2018Q4.csv column indices (0-based)
# These indices match the public Kaggle dataset header row.
COL_LOAN_AMNT = 0
COL_GRADE = 6
COL_LOAN_STATUS = 14

VALID_GRADES = {'A', 'B', 'C', 'D', 'E', 'F', 'G'}
DEFAULT_STATUSES = {'Charged Off', 'Default', 'Does not meet the credit policy. Status:Charged Off'}
PAID_STATUSES = {'Fully Paid', 'Does not meet the credit policy. Status:Fully Paid'}


def classify_status(status: str) -> str | None:
    """Return 'default', 'paid', or None if status is unrecognised."""
    s = status.strip()
    if s in DEFAULT_STATUSES:
        return 'default'
    if s in PAID_STATUSES:
        return 'paid'
    return None


def main() -> None:
    reader = csv.reader(sys.stdin)
    for line_num, row in enumerate(reader):
        try:
            # Skip header row identified by the literal column name
            if row[COL_LOAN_AMNT].strip() == 'loan_amnt' or row[COL_LOAN_AMNT].strip() == 'id':
                continue

            grade = row[COL_GRADE].strip().upper()
            if grade not in VALID_GRADES:
                sys.stderr.write(f"SKIP line {line_num}: invalid grade '{grade}'\n")
                continue

            loan_status = row[COL_LOAN_STATUS].strip()
            classification = classify_status(loan_status)
            if classification is None:
                # Skip in-progress loans (Current, Late, In Grace Period, etc.)
                continue

            print(f"{grade}\t1:{classification}")

        except IndexError:
            sys.stderr.write(f"SKIP line {line_num}: too few columns ({len(row)} cols)\n")
        except Exception as exc:
            sys.stderr.write(f"SKIP line {line_num}: unexpected error — {exc}\n")


if __name__ == '__main__':
    main()
