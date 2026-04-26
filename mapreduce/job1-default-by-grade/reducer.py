#!/usr/bin/env python3
"""
Job 1 Reducer — Default Rate by Loan Grade

Reads sorted mapper output from stdin:
    <grade>\t1:default
    <grade>\t1:paid

Emits one TSV line per grade:
    <grade>\t<total_loans>\t<total_defaults>\t<default_rate_pct>

Sample input (sorted by Hadoop):
  A\t1:paid
  A\t1:paid
  A\t1:default
  B\t1:default

Sample output:
  A\t3\t1\t33.33
  B\t1\t1\t100.00
"""

import sys


def emit(grade: str, total: int, defaults: int) -> None:
    if total == 0:
        return
    rate = round((defaults / total) * 100, 2)
    print(f"{grade}\t{total}\t{defaults}\t{rate}")


def main() -> None:
    current_grade: str | None = None
    total = 0
    defaults = 0

    for line in sys.stdin:
        line = line.rstrip('\n')
        try:
            parts = line.split('\t')
            if len(parts) != 2:
                sys.stderr.write(f"SKIP malformed reducer input: '{line}'\n")
                continue

            grade, value = parts[0].strip(), parts[1].strip()

            if grade != current_grade:
                if current_grade is not None:
                    emit(current_grade, total, defaults)
                current_grade = grade
                total = 0
                defaults = 0

            count_str, status = value.split(':')
            count = int(count_str)
            total += count
            if status == 'default':
                defaults += count

        except Exception as exc:
            sys.stderr.write(f"SKIP reducer error on '{line}': {exc}\n")

    if current_grade is not None:
        emit(current_grade, total, defaults)


if __name__ == '__main__':
    main()
