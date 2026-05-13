# Policy reference

**What goes in `.scalp/policy.json` and what each field does.**

> The policy is JSON — no YAML, no TOML, no DSL. If you know Go structs you know the schema. Every field has a default, so an empty file behaves the same as no file.

---

## Full schema

```json
{
  "$schema": ".scalp/policy.schema.json",
  "version": 1,
  "trust": {
    "mode": "audit-only",
    "min_score": 0,
    "require_hash": false
  },
  "packages": {
    "allow": [],
    "deny": []
  },
  "transitive": {
    "max_depth": 0
  },
  "enforcement": {
    "on_violation": "warn",
    "default_mode": "passthrough"
  }
}
```

All values above are the defaults. If you create `.scalp/policy.json` with only `{"version": 1}`, it behaves exactly like no file.

JSON Schema at `.scalp/policy.schema.json` — VS Code and other editors pick it up from the `$schema` field for autocomplete and validation.

---

## `version`

```
Required: yes
Value: 1 (currently the only version)
```

Always set `"version": 1`. If omitted, defaults to 1. Future versions will define migration paths.

---

## `trust`

Controls which packages are allowed and how trust scoring works.

### `trust.mode`

| Value | Behavior |
|-------|----------|
| `audit-only` (default) | Log everything. Never blocks based on trust rules. |
| `allowlist` | Only packages matching entries in `packages.allow` are permitted. |
| `denylist` | Packages matching entries in `packages.deny` are blocked. Everything else is allowed. |

Allowlist example:

```json
{
  "trust": { "mode": "allowlist" },
  "packages": {
    "allow": [
      { "name": "lodash" },
      { "pattern": "@scope/*" }
    ]
  }
}
```

Only `lodash` and packages under `@scope/` will pass. Everything else triggers a violation.

### `trust.min_score`

```
Type: integer (0–80)
Default: 0 (disabled)
```

Minimum trust score. Every dependency gets a score from 0 to 80. If the score is below `min_score`, it's a violation.

Score factors:

| Factor | Max | Source |
|--------|-----|--------|
| Hash verified | 30 | `.scalp/lockfile.json` |
| Version >= 1.0.0 | 15 | Package version |
| Weekly downloads | 20 | `api.npmjs.org` (cached) |
| No active CVEs | 15 | `npm audit --json` (cached) |

See `docs/trust-score.md` for the full mechanics, including how offline/unknown data is handled (half points instead of zero).

Set to 0 to disable trust scoring entirely — useful during migration or if you don't want numeric risk.

### `trust.require_hash`

```
Type: boolean
Default: false
```

When true, any package without a lockfile integrity entry is an **automatic violation** — even if its total score would pass `min_score`. This is the "supply chain minimum" switch.

If a package was installed outside SCAL-P's guarded flow (or tampered with after), you know immediately. No grace period for missing hashes.

With `min_score` and `require_hash` both on:

| Package state | Result |
|--------------|--------|
| Missing hash | Violation (`hash_required`) |
| Has hash, score 30/50 | Violation (`trust_score_too_low`) |
| Has hash, score 65/50 | Passes |

---

## `packages`

### `packages.allow`

```
Type: array of PackageRule
Default: []
```

Used in `allowlist` mode only. Each entry must have at least `name` or `pattern`.

### `packages.deny`

```
Type: array of PackageRule
Default: []
```

Used in `denylist` mode. Same structure as `allow`.

### PackageRule

| Field | Type | Required | Behavior |
|-------|------|----------|----------|
| `name` | string | yes* | Exact package name: `"lodash"`, `"@scope/name"` |
| `pattern` | string | yes* | Glob pattern: see below |
| `versions` | string | no | Semver constraint: `"^4.0.0"`, `">=1.0.0"` |
| `checksum` | string | no | Expected integrity hash: `"sha512-..."` |

\* One of `name` or `pattern` is required. Both can be present.

Pattern matching rules:

| Pattern | Matches |
|---------|---------|
| `*` | Everything |
| `prefix*` | `prefix-anything` |
| `*suffix` | `anything-suffix` |
| `*substr*` | `anything-substr-anything` |
| `@scope/*` | All packages under `@scope/` |

Examples:

```json
{
  "packages": {
    "deny": [
      { "name": "malicious-pkg" },
      { "pattern": "*-free" },
      { "name": "old-lib", "versions": "<2.0.0" },
      { "pattern": "@evil-scope/*" }
    ]
  }
}
```

---

## `transitive`

### `transitive.max_depth`

```
Type: integer (>= 0)
Default: 0 (no limit)
```

Maximum nesting depth for transitive dependencies. Depth 0 = root package. Depth 1 = direct dependency. Depth 2 = dependency of a dependency.

If `max_depth = 2` and a package is found at depth 3, it's a violation.

```json
{ "transitive": { "max_depth": 5 } }
```

This is a heuristic — deep trees are harder to audit and more likely to hide malicious packages.

---

## `enforcement`

Controls what happens when a violation is detected.

### `enforcement.on_violation`

| Value | Behavior |
|-------|----------|
| `warn` (default) | Print violations to stderr. Continue with exit 0. |
| `block` | Print violations. Exit 1. Install is skipped in guarded mode. |
| `log` | Silently log to `.scalp/audit.log`. Continue. |

`--ci` overrides this to `block` regardless of policy. That's the whole point of CI mode — exit 1 on any violation.

### `enforcement.default_mode`

| Value | Behavior |
|-------|----------|
| `passthrough` (default) | Run without evaluation. Sync lockfile after install. |
| `guarded` | Always enforce policy before install, even without `--guarded` flag. |

Use `guarded` if you never want unguarded installs. Use `passthrough` (the default) to let each run decide with `--guarded`.

---

## Examples

### Minimal — trust scoring only, warn on violation

```json
{
  "version": 1,
  "trust": { "min_score": 60 },
  "enforcement": { "on_violation": "warn" }
}
```

### Locked down — allowlist, require hash, block

```json
{
  "version": 1,
  "trust": {
    "mode": "allowlist",
    "min_score": 60,
    "require_hash": true
  },
  "packages": {
    "allow": [
      { "name": "lodash", "versions": "^4.0.0" },
      { "name": "express", "versions": "^4.18.0" }
    ]
  },
  "transitive": { "max_depth": 5 },
  "enforcement": {
    "on_violation": "block",
    "default_mode": "guarded"
  }
}
```

### CI pipeline — denylist + trust

```json
{
  "version": 1,
  "trust": { "min_score": 50 },
  "packages": {
    "deny": [
      { "pattern": "*-free" },
      { "pattern": "*debug*" }
    ]
  },
  "enforcement": {
    "on_violation": "block",
    "default_mode": "passthrough"
  }
}
```
