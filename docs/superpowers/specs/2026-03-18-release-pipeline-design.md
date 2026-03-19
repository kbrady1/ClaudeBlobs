# Release Pipeline Design

## Overview

Automated release pipeline for ClaudeBlobs: local versioning script, GitHub Actions CI for codesigning/notarization/DMG creation, Homebrew cask distribution, and a `/release` skill for generating release notes.

## Components

### 1. Local Release Script (`scripts/release.sh`)

Invoked via `make release BUMP=patch|minor|major`.

**Pre-flight checks:**
- Must be on `main` branch
- No uncommitted changes (clean working tree)
- `swift test` passes

**Version bump:**
- Reads current `CFBundleShortVersionString` from `Resources/Info.plist`
- Increments per `BUMP` argument (semver: major.minor.patch)
- Writes updated version to both `CFBundleVersion` and `CFBundleShortVersionString`

**Release:**
- Commits version bump: `"Release vX.Y.Z"`
- If `NOTES_FILE` env var is set, creates annotated tag `vX.Y.Z` with file contents as message
- Otherwise creates lightweight tag `vX.Y.Z`
- Pushes commit + tag to origin

### 2. GitHub Actions CI (`.github/workflows/release.yml`)

**Trigger:** Push of `v*` tag.

**Steps:**
1. Checkout repo at tag
2. `swift build -c release`
3. `make bundle` (creates .app)
4. Import Developer ID certificate from secrets into temporary keychain
5. Codesign the .app bundle (deep, runtime hardened) with Developer ID Application identity
6. Submit to Apple notary service via `xcrun notarytool submit --wait`
7. Staple notarization ticket: `xcrun stapler staple`
8. Create simple DMG via `hdiutil create` containing the .app → `ClaudeBlobs-X.Y.Z.dmg`
9. Create GitHub Release with DMG attached; release notes from tag annotation (if annotated) or commits since last tag
10. Clone `kbrady1/homebrew-tap`, update `Casks/claude-blobs.rb` with new version + SHA256, commit + push

**Secrets required:**

| Secret | Description |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_BASE64` | .p12 export of Developer ID Application cert, base64-encoded |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for the .p12 file |
| `APPLE_TEAM_ID` | 10-character Apple Developer team ID |
| `APPLE_ID` | Apple ID email for notarytool |
| `APPLE_ID_PASSWORD` | App-specific password for notarytool |
| `HOMEBREW_TAP_TOKEN` | GitHub PAT with repo scope for kbrady1/homebrew-tap |

### 3. Homebrew Tap (`kbrady1/homebrew-tap`)

Separate repo with a single cask formula:

**`Casks/claude-blobs.rb`:**
```ruby
cask "claude-blobs" do
  version "X.Y.Z"
  sha256 "..."

  url "https://github.com/kbrady1/ClaudeBlobs/releases/download/v#{version}/ClaudeBlobs-#{version}.dmg"
  name "ClaudeBlobs"
  desc "macOS menu bar app for monitoring Claude agent sessions"
  homepage "https://github.com/kbrady1/ClaudeBlobs"

  app "ClaudeBlobs.app"
end
```

**Install command:** `brew tap kbrady1/homebrew-tap && brew install --cask claude-blobs`

### 4. `/release` Skill (`.claude/skills/release.md`)

Takes optional arg: `patch` (default), `minor`, or `major`.

**Flow:**
1. Pre-flight: on main, clean tree, tests pass
2. Collect commits since last tag (`git log --oneline`)
3. Generate categorized release notes (features, fixes, improvements)
4. Show draft notes + proposed version to user
5. On approval: write notes to temp file, run `make release BUMP=<arg> NOTES_FILE=<path>`

## Makefile Addition

```makefile
release:
	@scripts/release.sh $(BUMP)
```

## File Changes Summary

| File | Action |
|---|---|
| `scripts/release.sh` | Create |
| `.github/workflows/release.yml` | Create |
| `.claude/skills/release.md` | Create |
| `Makefile` | Add `release` target |
| `Resources/Info.plist` | Modified at release time (version bump) |
