# Security Policy

## Reporting a Vulnerability

Please report suspected security vulnerabilities privately through the
repository's GitHub **Security** tab using **Report a vulnerability**. Do not
publish exploit details in an issue or pull request before a fix is available.
If private vulnerability reporting is not enabled for the repository, contact
the maintainer privately through their GitHub profile instead of posting
reproduction details publicly.

Include the affected file or project profile, steps to reproduce, expected and
actual behavior, and any relevant logs. Do not include private keys, passwords,
USB serial identifiers, or other personal data.

## Scope

This is an educational CPU/FPGA project. The UART bootloader, DDR loader,
experimental cache/throughput profiles, and third-party DoomGeneric port have
different maturity levels; none should be assumed to provide production-grade
security. Report issues involving unsafe memory access, image validation,
privilege enforcement, DMA/cache ordering, or build/release artifacts through
the private channel above.

Please allow time for investigation and a coordinated fix before public
disclosure. There is currently no guaranteed response-time or support SLA.
