# psvc

## Purpose

`psvc` manages local printing/scanning services, diagnoses CUPS/IPP printer connectivity, and prints files with explicit per-job options.

It is designed for the Brother DCP-T720DW setup, but most commands are generic CUPS helpers.

## Public Command

`psvc` is exposed through the Stow-friendly public command layer:

```text
scripts/bin/psvc -> ../printing/psvc/psvc
```

After `stow .` and a shell reload, run it as:

```bash
psvc --help
```

## Service Commands

Use direct commands instead of the interactive menu:

```bash
psvc status
psvc start
psvc stop
psvc restart
```

Scanner units can be included when available:

```bash
psvc status --include-saned
```

The legacy service menu is still available explicitly:

```bash
psvc --menu
```

## Doctor

Run read-only printer diagnostics:

```bash
psvc doctor --queue brother_t720dw
```

By default, transient network probe failures are warnings, not hard failures. This avoids false failures when a Wi-Fi printer is asleep or slow to answer.

Use strict mode when network probe failures should return non-zero:

```bash
psvc doctor --queue brother_t720dw --strict-network
```

The doctor checks:

- CUPS and Avahi service/socket state
- CUPS queue status
- pending/incomplete jobs
- configured printer URI
- IPP port reachability
- ping response
- IPP/Avahi discovery
- recent CUPS/Avahi warnings

## Print

Print with per-job options without changing saved printer defaults:

```bash
psvc print --preset 2up-short-edge document.pdf
```

Preview the generated `lp` command without printing:

```bash
psvc print --dry-run --preset 2up-short-edge document.pdf
```

Interactive mode:

```bash
psvc print
```

## Print Presets

Available presets:

- `2up-short-edge`: Letter, 2 pages per side, left-to-right layout, short-edge duplex, fit to page
- `1up-one-sided`: Letter, 1 page per side, one-sided, fit to page
- `1up-long-edge`: Letter, 1 page per side, long-edge duplex, fit to page
- `custom`: prompt for paper size, pages per side, layout, duplex mode, and fit-to-page

The `2up-short-edge` preset generates the equivalent of:

```bash
lp -d brother_t720dw \
  -o media=Letter \
  -o number-up=2 \
  -o number-up-layout=lrtb \
  -o sides=two-sided-short-edge \
  -o Duplex=DuplexTumble \
  -o fit-to-page \
  document.pdf
```

## Internal Files

These files are internal to the `psvc` tool directory:

```text
psvc          # public dispatcher
psvc-doctor   # internal doctor implementation
psvc-print    # internal print implementation
psvc-lib      # shared Bash helpers
```

Only `psvc` is exposed in `scripts/bin`. Do not add public symlinks for `psvc-doctor` or `psvc-print`; use `psvc doctor` and `psvc print`.

## Dependencies

Core service commands require:

```text
systemctl
```

Doctor and print functionality use CUPS/network tools when available:

```text
lp
lpstat
lpq
nc
ping
ippfind
avahi-browse
journalctl
```

Missing optional diagnostic tools are reported as warnings.

## Tests

Run the tool-specific tests from this directory:

```bash
bash tests/test-doctor.sh
bash tests/test-print.sh
bash tests/test-service.sh
```

From the repository root:

```bash
bash scripts/printing/psvc/tests/test-doctor.sh
bash scripts/printing/psvc/tests/test-print.sh
bash scripts/printing/psvc/tests/test-service.sh
```

The repository-level structure test also validates that `psvc` has this README and that only public commands are linked under `scripts/bin`:

```bash
bash scripts/tests/test-script-structure.sh
```

## Maintenance Notes

- Keep `psvc` as the public dispatcher.
- Keep helper behavior in `psvc-doctor` and `psvc-print` to avoid growing the dispatcher.
- Put shared logic in `psvc-lib` instead of duplicating parsing, queue, or command helpers.
- Do not use `lpoptions` for print presets; `psvc print` must not persist printer defaults.
