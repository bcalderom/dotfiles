# ssf

## Purpose

Interactive SSH launcher for hosts defined in `~/.ssh/config`.

## Usage

```bash
ssf
ssf --config ~/.ssh/config
ssf --collapsed
```

## Dependencies

Requires `ssh` and `fzf` for normal interactive use.

## Tests

```bash
bash tests/test-ssf.sh
```
