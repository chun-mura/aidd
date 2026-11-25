"""Print the total of the amounts given on the command line."""
import sys

from app.report import fmt_total


def main(argv: list) -> int:
    amounts = [float(a) for a in argv]
    print(fmt_total(amounts))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
