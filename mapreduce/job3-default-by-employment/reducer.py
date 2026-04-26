#!/usr/bin/env python3
"""
Job 3 Reducer — Default Rate by Employment Length

Reads sorted mapper output and emits one TSV line per employment bucket:
    <emp_bucket>\t<total_loans>\t<total_defaults>\t<default_rate_pct>

Sample output:
  < 1 year\t45200\t7800\t17.26
  1-2 years\t82100\t11200\t13.64
  3-5 years\t198400\t24300\t12.25
  6-9 years\t175300\t18900\t10.78
  10+ years\t412600\t41800\t10.13
"""

import sys


def emit(bucket: str, total: int, defaults: int) -> None:
    if total == 0:
        return
    rate = round((defaults / total) * 100, 2)
    print(f"{bucket}\t{total}\t{defaults}\t{rate}")


def main() -> None:
    current_bucket: str | None = None
    total = 0
    defaults = 0

    for line in sys.stdin:
        line = line.rstrip('\n')
        try:
            parts = line.split('\t')
            if len(parts) != 2:
                continue

            bucket, value = parts[0].strip(), parts[1].strip()

            if bucket != current_bucket:
                if current_bucket is not None:
                    emit(current_bucket, total, defaults)
                current_bucket = bucket
                total = 0
                defaults = 0

            count_str, status = value.split(':')
            count = int(count_str)
            total += count
            if status == 'default':
                defaults += count

        except Exception as exc:
            sys.stderr.write(f"SKIP reducer error: {exc} on '{line}'\n")

    if current_bucket is not None:
        emit(current_bucket, total, defaults)


if __name__ == '__main__':
    main()
