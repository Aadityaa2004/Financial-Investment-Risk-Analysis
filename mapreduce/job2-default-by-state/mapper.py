#!/usr/bin/env python3
"""
Job 2 Mapper — Default Rate by US State

Reads LendingClub CSV rows from stdin and emits:
    <state>\t1:default
    <state>\t1:paid

State is the two-letter borrower address state (addr_state column).

Sample output:
  CA\t1:paid
  TX\t1:default
  NY\t1:paid
"""

import csv
import io
import sys

OLD_COL_LOAN_AMNT = 0
OLD_COL_ADDR_STATE = 21
OLD_COL_LOAN_STATUS = 14

NEW_COL_LOAN_AMNT = 2
NEW_COL_ADDR_STATE = 23
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

US_STATES = frozenset({
    'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA',
    'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD',
    'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ',
    'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'SC',
    'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY',
    'DC',
})


def main() -> None:
    text_stream = io.TextIOWrapper(sys.stdin.buffer, encoding='utf-8-sig', errors='replace')
    reader = csv.reader(text_stream)
    counters = {
        'header': 0,
        'short_rows': 0,
        'invalid_state': 0,
        'unknown_status': 0,
        'emitted': 0,
        'errors': 0,
    }

    for line_num, row in enumerate(reader, start=1):
        try:
            if len(row) <= NEW_COL_ADDR_STATE:
                counters['short_rows'] += 1
                continue

            old_status = row[OLD_COL_LOAN_STATUS].strip()
            new_status = row[NEW_COL_LOAN_STATUS].strip()

            if old_status in DEFAULT_STATUSES or old_status in PAID_STATUSES:
                col_loan_amnt, col_addr_state, col_loan_status = OLD_COL_LOAN_AMNT, OLD_COL_ADDR_STATE, OLD_COL_LOAN_STATUS
            else:
                col_loan_amnt, col_addr_state, col_loan_status = NEW_COL_LOAN_AMNT, NEW_COL_ADDR_STATE, NEW_COL_LOAN_STATUS

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

            state = row[col_addr_state].strip().upper()
            if state not in US_STATES:
                counters['invalid_state'] += 1
                continue

            print(f"{state}\t1:{classification}")
            counters['emitted'] += 1

        except Exception as exc:
            counters['errors'] += 1
            sys.stderr.write(f"SKIP line {line_num}: {exc}\n")

    sys.stderr.write(f"reporter:counter:Job2Mapper,HeaderRows,{counters['header']}\n")
    sys.stderr.write(f"reporter:counter:Job2Mapper,ShortRows,{counters['short_rows']}\n")
    sys.stderr.write(f"reporter:counter:Job2Mapper,InvalidState,{counters['invalid_state']}\n")
    sys.stderr.write(f"reporter:counter:Job2Mapper,UnknownStatus,{counters['unknown_status']}\n")
    sys.stderr.write(f"reporter:counter:Job2Mapper,EmittedRows,{counters['emitted']}\n")
    sys.stderr.write(f"reporter:counter:Job2Mapper,Errors,{counters['errors']}\n")


if __name__ == '__main__':
    main()
