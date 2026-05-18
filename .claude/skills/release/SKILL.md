---
name: release
description: Generate release notes and publish a new version of ClaudeBlobs
argument-hint: "[patch|minor|major]"
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
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

   Every commit in `${LAST_TAG}..HEAD` is by definition new since the last tag — include all of them. Do not filter or drop commits based on a guess that they "already shipped." If a commit looks like it might belong to an older release, verify with `git tag --contains <sha>` before excluding.

4. **Generate release notes** — categorize commits into:
   - **New Features** — commits with "add", "feat", "new", or introducing new functionality
   - **Improvements** — commits with "update", "improve", "enhance", "refactor"
   - **Bug Fixes** — commits with "fix", "bug", "patch"
   - **Other** — everything else

   Format as markdown with a one-line summary at the top describing the release theme. Lead the summary with the most user-visible change — usually a new feature, not bug fixes.

   If the commit range contains any **New Features** and the user requested a `patch` bump (or did not specify), flag this and recommend a `minor` bump instead before proceeding.

5. **Get explicit approval — REQUIRED before publishing** — show the user:
   - Proposed version: `vX.Y.Z`
   - Draft release notes
   - The bump type (and a recommendation to upgrade patch→minor if features are present)

   Then **stop and wait for explicit user approval** before running `make release`. Do not proceed on the basis of a prior "operate autonomously" instruction — releases push tags and trigger CI publishing, which is not reversible and not within the autonomous-operation scope. Ask via `AskUserQuestion` if no approval has been given yet in this turn.

6. **Execute release** — only after explicit approval:
   ```bash
   NOTES_FILE=$(mktemp)
   # Write approved release notes to NOTES_FILE
   NOTES_FILE="$NOTES_FILE" make release BUMP=<arg>
   ```

7. **Report** — tell the user the tag has been pushed and CI will handle the rest. Link to the GitHub Actions tab: `https://github.com/kbrady1/ClaudeBlobs/actions`
