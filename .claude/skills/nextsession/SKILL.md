---
name: nextsession
description: Use when starting or resuming a work session on the OpenHiker project, to load current project state and re-establish the coding rules and session workflow before doing any work.
disable-model-invocation: true
allowed-tools: Read, Edit, Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(gh issue *), Bash(gh pr *), Bash(gh run *), Bash(xcodebuild *), Bash(./gradlew *)
---

Read HANDOVER.md and follow its instructions. ROADMAP.md lists planned work not yet started. Ask me if you have any questions.

Our coding rules are in `docs/llm/general_golden_rules.md` (Swift and Kotlin). Read and follow them. Also follow
CLAUDE.md, especially the pbxproj rules for new Swift files and the `docs/TODO/<platform>/<feature>.md` rule
for feature parity. On top of those, follow this session workflow:

1. All tests for the platforms you touched must pass before you commit, unless I explicitly give permission
   otherwise. Run each command with `set -o pipefail` and judge it by its exit code.
   - iOS app and `Shared/` (XCTest target `OpenHikerTests`):
     `xcodebuild test -project OpenHiker.xcodeproj -scheme OpenHiker -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0'`
   - watchOS app (no test target, build only):
     `xcodebuild build -project OpenHiker.xcodeproj -scheme 'OpenHiker Watch App' -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm),OS=26.5'`
   - macOS app (build only):
     `xcodebuild build -project OpenHiker.xcodeproj -scheme 'OpenHiker macOS' -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
   - Android: `cd OpenHikerAndroid && ./gradlew test`
   - A change in `Shared/` is compiled into the iOS, watchOS and macOS targets, so build all three.
2. Before you start working, check that HANDOVER.md matches the current state (`git log`, `gh issue list`,
   `gh pr list`). If it does not, update it before you start.
3. Avoid technical debt. If you find an error, fix it when you can. Otherwise, lodge it as a GitHub issue.
4. When you are done, update HANDOVER.md to show the current state of development. Prune it to stay concise
   and under 500 lines if possible. Remove sections for slices that have landed, focus on what still needs
   doing, and briefly summarise what is done. Remove items from ROADMAP.md once they land. If you are not sure
   how to do this, ask me.
5. When the task is complete, work on a branch (never commit straight to `main`), commit all changes, push,
   and open a PR to `main`. Link the PR to the relevant GitHub issue if there is one. Give a clear description
   of the changes and any context reviewers need. If you are not sure how to do this, ask me.
