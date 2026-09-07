# Python User Validation Script

## Purpose

This task processes user records from a comma-separated text file and validates each user's email address and numeric ID. Valid records are reported with an odd/even ID result; invalid records produce clear warnings without stopping the remaining input from being processed.

Expected input format:

```text
name, email, id
```

## Requirements

- Python 3
- [`dnspython`](https://www.dnspython.org/) for DNS MX lookups

Install the dependency:

```bash
python3 -m pip install dnspython
```

## How to run

Place the script and `users.txt` in the same directory, then run:

```bash
python3 <script-name>.py
```

## Validation performed

- Verifies that every row has the expected fields.
- Trims surrounding whitespace.
- Checks that required values are present.
- Validates basic email structure and the domain as an FQDN.
- Queries DNS for MX records only after the domain passes FQDN validation.
- Converts the ID to an integer and reports whether it is odd or even.
- Reports multiple independent errors for one user and continues with later records.

## Concepts practiced

File handling, loops, lists, `strip()`, `split()`, validation flags, `try`/`except`, `ValueError`, integer conversion, modulo, f-strings, control flow, FQDN validation, and DNS MX queries.

## Key notes

Validation follows dependency order: email presence → format → FQDN → MX lookup, and ID presence → integer conversion → parity. This prevents misleading DNS queries or arithmetic on invalid values.