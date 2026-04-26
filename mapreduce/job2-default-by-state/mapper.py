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

import sys
import csv

COL_LOAN_AMNT = 0
COL_ADDR_STATE = 21
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

US_STATES = frozenset({
    'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA',
    'HI', 'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD',
    'MA', 'MI', 'MN', 'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ',
    'NM', 'NY', 'NC', 'ND', 'OH', 'OK', 'OR', 'PA', 'RI', 'SC',
    'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV', 'WI', 'WY',
    'DC',
})


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

            state = row[COL_ADDR_STATE].strip().upper()
            if state not in US_STATES:
                sys.stderr.write(f"SKIP line {line_num}: invalid state '{state}'\n")
                continue

            print(f"{state}\t1:{classification}")

        except IndexError:
            sys.stderr.write(f"SKIP line {line_num}: too few columns ({len(row)})\n")
        except Exception as exc:
            sys.stderr.write(f"SKIP line {line_num}: {exc}\n")


if __name__ == '__main__':
    main()
