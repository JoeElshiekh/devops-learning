# Bash User Validation Script

## Purpose

This task implements the user-file validation exercise in Bash. It reads comma-separated user records, validates email and ID values, reports useful warnings, and prints whether each valid ID is odd or even.

Expected input format:

```text
name, email, id
```

## Requirements

- Bash
- `dig` for DNS MX lookups (provided by `dnsutils` on Ubuntu/Debian)
- `xargs` for trimming input values

Install the DNS utility on Ubuntu/Debian:

```bash
sudo apt update
sudo apt install dnsutils
```

## How to run

Place the script and `users.txt` in the same directory, make the script executable, and run it:

```bash
chmod +x <script-name>.sh
./<script-name>.sh
```

## Validation performed

- Reads fields with `IFS=','` and `read -r`.
- Trims surrounding whitespace.
- Checks required fields and basic email structure.
- Validates each FQDN label.
- Runs `dig +short MX` only for a structurally valid domain.
- Accepts IDs containing digits only and calculates odd/even parity.
- Uses validation flags to report independent problems before continuing.

## Concepts practiced

Shebangs, `while` loops, `IFS`, input redirection, variables, command substitution, pipes, `[[ ... ]]`, `-z`, `-n`, regular expressions, arrays, arithmetic expressions, `continue`, validation flags, and DNS queries with `dig`.

## Key notes

Dependent checks are skipped when their prerequisites fail. An invalid FQDN does not trigger an MX query, and a nonnumeric ID is never used in an arithmetic expression.