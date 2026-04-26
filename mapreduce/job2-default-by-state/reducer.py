#!/usr/bin/env python3
"""
Job 2 Reducer — Default Rate by US State

Reads sorted mapper output and emits one TSV line per state:
    <state>\t<total_loans>\t<total_defaults>\t<default_rate_pct>

Sample output:
  CA\t142300\t18400\t12.93
  TX\t89200\t11500\t12.89
  NY\t76100\t8900\t11.70
"""

import sys


def emit(state: str, total: int, defaults: int) -> None:
    if total == 0:
        return
    rate = round((defaults / total) * 100, 2)
    print(f"{state}\t{total}\t{defaults}\t{rate}")


def main() -> None:
    current_state: str | None = None
    total = 0
    defaults = 0

    for line in sys.stdin:
        line = line.rstrip('\n')
        try:
            parts = line.split('\t')
            if len(parts) != 2:
                continue

            state, value = parts[0].strip(), parts[1].strip()

            if state != current_state:
                if current_state is not None:
                    emit(current_state, total, defaults)
                current_state = state
                total = 0
                defaults = 0

            count_str, status = value.split(':')
            count = int(count_str)
            total += count
            if status == 'default':
                defaults += count

        except Exception as exc:
            sys.stderr.write(f"SKIP reducer error: {exc} on line: '{line}'\n")

    if current_state is not None:
        emit(current_state, total, defaults)


if __name__ == '__main__':
    main()
