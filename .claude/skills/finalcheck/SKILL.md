---
name: finalcheck
description: Use for the final pre-merge pass on the current OpenHiker PR. Review it, fix everything the review found, then drive GitHub CI to green.
disable-model-invocation: false
allowed-tools: Read, Edit, Bash(git *), Bash(gh *), Bash(xcodebuild *), Bash(xcrun *), Bash(./gradlew *), Bash(cd OpenHikerAndroid *), Bash(set -o pipefail*), Bash(actionlint *)
---
Run these steps in order on the PR for the current branch. First run `pwd && git branch --show-current &&
git worktree list`. If the branch is checked out in another worktree, `cd` into it. Then find the PR with
`gh pr view --json number,url,headRefOid`. If there is none, stop and tell me.

1. **Review.** Invoke the `pr-review-toolkit:review-pr` skill via the Skill tool and let it finish.
2. **Fix.** First merge `origin/main` into the branch (`git fetch origin && git merge origin/main`) and
   resolve any conflicts. Then work through the review's findings one by one:
   - Fix each one now if that is manageable in this session. Otherwise, lodge it as a GitHub issue.
   - Run the gates for every platform you touched (commands in `.claude/skills/nextsession/SKILL.md`, step
     1). A change in `Shared/` needs the iOS tests plus the watchOS and macOS builds. A new `.swift` file
     must be in `project.pbxproj` (see CLAUDE.md).
   - Re-read the changes against `docs/llm/general_golden_rules.md`. If a feature changed on one platform,
     check that the `docs/TODO/<platform>/` files for the other platforms are up to date.
   - Update HANDOVER.md only if the fixes change what it says. Then commit and push into the PR.
   - Confirm the push landed: `git fetch origin && git status -sb` must show no `ahead`, and the PR's
     `headRefOid` must equal `git rev-parse HEAD`.
   - A deferred item gets no closing keyword before its number ("Deferred: #N", never "not fixed: #N"),
     in commits and in the PR body alike.
3. **Drive CI to green.** Loop:
   - Watch the checks for the pushed head commit with `gh pr checks --watch` (not `--fail-fast`: the
     known-red `Swift` check below would end the watch before the iOS check finishes). Checks can take a
     minute to register, so wait if it reports none yet. `codeql.yml` is disabled for inactivity
     (`gh workflow list --all`) and runs on nothing until someone re-enables it.
   - **Known red, not your fault:** the `Swift` workflow (`swift.yml`) runs `swift build` but the repo has no
     `Package.swift`, so it has failed on every run (see HANDOVER.md). Ignore it until it is fixed or
     removed. Never treat any other failure this way.
   - All other checks green → done. Report the PR URL and the final check list.
   - A check failed → read the cause: `gh run list --branch "$(git branch --show-current)" --limit 5`, then
     `gh run view <run-id> --log-failed`. Reproduce it locally with the command the failing job runs (see
     `.github/workflows/`):
     - `iOS starter workflow` (`ios.yml`) → `xcodebuild build-for-testing` then `test-without-building`,
       scheme `OpenHiker`, on an iPhone simulator. Locally:
       `xcodebuild test -project OpenHiker.xcodeproj -scheme OpenHiker -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0'`
     - CodeQL → read the alert (`gh api repos/hherb/OpenHiker/code-scanning/alerts`) and fix the code.
     - A workflow file changed → `actionlint`.

     Judge each command by its **exit code**, never by filtered output: `cmd | tail` reports `tail`'s
     status, so use `set -o pipefail`. Fix the root cause, using TDD where it is a code bug. Confirm the fix
     passes locally, commit with a message naming the CI failure, push, and loop again.
   - **CI-only failures.** CI runs on `macos-latest`, whose Xcode and simulators may differ from the local
     ones. Compare `xcodebuild -version` and the simulator the job picked (in its log) before guessing.
   - **A job CANCELLED with no log** hit its timeout or lost its runner. Look for a hang before you call it
     a flake.
   - If the failure is not caused by the code (runner or infra outage, network flake, missing secret), rerun
     once with `gh run rerun <run-id> --failed`. If it fails the same way again, stop and report rather than
     changing code to work around it.
   - Never "fix" CI by skipping or deleting tests (`XCTSkip`, `@Ignore`), by weakening workflow config, or by
     adding a `paths:` filter to any job, without my explicit permission. If the same failure survives three
     fix attempts, stop and report what you tried.
4. **Not covered by CI.** Run these locally if the PR needs them, and include the results in the report:
   - Android: no CI job runs it. `cd OpenHikerAndroid && ./gradlew test` (add `--rerun-tasks` if the result
     looks stale).
   - watchOS and macOS: CI builds only the iOS scheme. Run the watchOS and macOS build commands from
     `.claude/skills/nextsession/SKILL.md` for any change under `OpenHiker watchOS/`, `OpenHiker macOS/` or
     `Shared/`.
   - Device-only behaviour (WatchConnectivity, HealthKit, MultipeerConnectivity, background GPS) cannot be
     tested in CI or the simulator. List what needs a manual check on real hardware.
