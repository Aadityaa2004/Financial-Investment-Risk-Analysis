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

import csv
import io
import sys

# sample_loans.csv layout
OLD_COL_LOAN_AMNT = 0
OLD_COL_GRADE = 6
OLD_COL_LOAN_STATUS = 14

# accepted_2007_to_2018Q4 full layout
NEW_COL_LOAN_AMNT = 2
NEW_COL_GRADE = 8
NEW_COL_LOAN_STATUS = 16

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


def resolve_indices(row: list[str]) -> tuple[int, int, int]:
    if len(row) <= NEW_COL_LOAN_STATUS:
        return OLD_COL_LOAN_AMNT, OLD_COL_GRADE, OLD_COL_LOAN_STATUS

    old_status = classify_status(row[OLD_COL_LOAN_STATUS].strip()) is not None
    new_status = classify_status(row[NEW_COL_LOAN_STATUS].strip()) is not None
    old_grade = row[OLD_COL_GRADE].strip().upper() in VALID_GRADES
    new_grade = row[NEW_COL_GRADE].strip().upper() in VALID_GRADES

    if old_status and old_grade:
        return OLD_COL_LOAN_AMNT, OLD_COL_GRADE, OLD_COL_LOAN_STATUS
    if new_status and new_grade:
        return NEW_COL_LOAN_AMNT, NEW_COL_GRADE, NEW_COL_LOAN_STATUS

    # Fallback to full Kaggle layout.
    return NEW_COL_LOAN_AMNT, NEW_COL_GRADE, NEW_COL_LOAN_STATUS


def main() -> None:
    text_stream = io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8-sig', errors='replace')
    reader = csv.reader(text_stream)
    counters = {
        'header': 0,
        'short_rows': 0,
        'invalid_grade': 0,
        'unknown_status': 0,
        'emitted': 0,
        'errors': 0,
    }

    for line_num, row in enumerate(reader, start=1):
        try:
            col_loan_amnt, col_grade, col_loan_status = resolve_indices(row)
            if len(row) <= col_loan_status:
                counters['short_rows'] += 1
                continue

            # Skip header row identified by the literal column name
            if row[col_loan_amnt].strip() == 'loan_amnt' or row[col_loan_amnt].strip() == 'id':
                counters['header'] += 1
                continue

            grade = row[col_grade].strip().upper()
            if grade not in VALID_GRADES:
                counters['invalid_grade'] += 1
                continue

            loan_status = row[col_loan_status].strip()
            classification = classify_status(loan_status)
            if classification is None:
                # Skip in-progress loans (Current, Late, In Grace Period, etc.)
                counters['unknown_status'] += 1
                continue

            print(f"{grade}\t1:{classification}")
            counters['emitted'] += 1

        except Exception as exc:
            counters['errors'] += 1
            sys.stderr.write(f"SKIP line {line_num}: unexpected error - {exc}\n")

    sys.stderr.write(f"reporter:counter:Job1Mapper,HeaderRows,{counters['header']}\n")
    sys.stderr.write(f"reporter:counter:Job1Mapper,ShortRows,{counters['short_rows']}\n")
    sys.stderr.write(f"reporter:counter:Job1Mapper,InvalidGrade,{counters['invalid_grade']}\n")
    sys.stderr.write(f"reporter:counter:Job1Mapper,UnknownStatus,{counters['unknown_status']}\n")
    sys.stderr.write(f"reporter:counter:Job1Mapper,EmittedRows,{counters['emitted']}\n")
    sys.stderr.write(f"reporter:counter:Job1Mapper,Errors,{counters['errors']}\n")


if __name__ == '__main__':
    main()
