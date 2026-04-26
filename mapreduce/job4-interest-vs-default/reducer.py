#!/usr/bin/env python3
"""
Job 4 Reducer — Average Interest Rate vs Default Rate by Loan Grade

Reads sorted mapper output and emits one TSV line per grade:
    <grade>\t<total_loans>\t<avg_interest_rate>\t<default_rate_pct>

This surfaces the risk-return tradeoff: higher-grade (riskier) loans
charge higher interest rates but also have higher default rates.

Sample output:
  A\t168284\t7.26\t5.12
  B\t302158\t11.49\t11.38
  C\t264781\t15.62\t16.87
  D\t118453\t19.89\t24.31
  E\t42376\t24.07\t30.14
  F\t11124\t28.12\t36.48
  G\t2890\t29.98\t41.22
"""

import sys


def emit(grade: str, total: int, interest_sum: float, defaults: int) -> None:
    if total == 0:
        return
    avg_rate = round(interest_sum / total, 2)
    default_rate = round((defaults / total) * 100, 2)
    print(f"{grade}\t{total}\t{avg_rate}\t{default_rate}")


def main() -> None:
    current_grade: str | None = None
    total = 0
    interest_sum = 0.0
    defaults = 0

    for line in sys.stdin:
        line = line.rstrip('\n')
        try:
            parts = line.split('\t')
            if len(parts) != 2:
                continue

            grade, value = parts[0].strip(), parts[1].strip()

            if grade != current_grade:
                if current_grade is not None:
                    emit(current_grade, total, interest_sum, defaults)
                current_grade = grade
                total = 0
                interest_sum = 0.0
                defaults = 0

            value_type, value_data = value.split(':', 1)

            if value_type == 'interest':
                interest_sum += float(value_data)
                total += 1
            elif value_type == 'default':
                defaults += int(value_data)

        except Exception as exc:
            sys.stderr.write(f"SKIP reducer error: {exc} on '{line}'\n")

    if current_grade is not None:
        emit(current_grade, total, interest_sum, defaults)


if __name__ == '__main__':
    main()
