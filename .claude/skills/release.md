---
name: release
description: Generate release notes and publish a new version of ClaudeBlobs
user_invocable: true
---

# Release ClaudeBlobs

Create a new release with auto-generated release notes.

## Arguments

Optional first argument: `patch` (default), `minor`, or `major`.

## Process

1. **Pre-flight checks** — verify:
   - On `main` branch: `git rev-parse --abbrev-ref HEAD`
   - Clean working tree: `git diff --quiet && git diff --cached --quiet`
   - Tests pass: `swift test`

2. **Determine version** — read current version from `Resources/Info.plist` using `/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist`, then compute the next version based on the bump argument.

3. **Collect commits** — get all commits since the last tag:
   ```bash
   LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
   if [ -n "$LAST_TAG" ]; then
     git log --oneline "${LAST_TAG}..HEAD"
   else
     git log --oneline
   fi
   ```

4. **Generate release notes** — categorize commits into:
   - **New Features** — commits with "add", "feat", "new", or introducing new functionality
   - **Improvements** — commits with "update", "improve", "enhance", "refactor"
   - **Bug Fixes** — commits with "fix", "bug", "patch"
   - **Other** — everything else

   Format as markdown with a one-line summary at the top describing the release theme.

5. **Present to user** — show:
   - Proposed version: `vX.Y.Z`
   - Draft release notes
   - Ask for approval or edits

6. **Execute release** — on approval:
   ```bash
   NOTES_FILE=$(mktemp)
   # Write approved release notes to NOTES_FILE
   NOTES_FILE="$NOTES_FILE" make release BUMP=<arg>
   ```

7. **Report** — tell the user the tag has been pushed and CI will handle the rest. Link to the GitHub Actions tab: `https://github.com/kbrady1/ClaudeBlobs/actions`
