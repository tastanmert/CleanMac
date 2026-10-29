# Contributing to CleanMac

Thanks for helping make CleanMac better. Bug reports, new cleanup rules, translations and UI polish are all welcome.

## Ground rules

CleanMac's promise is that it never breaks anything. Every change has to keep these rules:

- **Nothing is deleted for good.** Files are moved to the Trash; tool caches are cleared only with the tool's own command.
- **Every path is checked by `SafetyGuard` right before it is moved.** A new location needs a new policy and a test.
- **"Review" items are never selected automatically**, and caches of apps that are open are listed but not selected.
- **No system alerts or sheets** in the UI: use the in-window glass dialogs (`glassConfirm`, `AppModel.panel`).

## Development

```bash
swift test               # the whole suite runs in under a second
swift run CleanMac       # run from source
./scripts/build-app.sh   # build and install /Applications/CleanMac.app
./scripts/make-dmg.sh    # build/CleanMac.dmg
```

Requirements: macOS 15 or later, Xcode 16 or later (Swift 6).

1. Fork the repository and create a branch.
2. Make your change with tests (`Tests/CleanMacCoreTests`, Swift Testing).
3. Run `swift test` and, for UI changes, check the screen in the app.
4. Open a pull request describing what changes for the user.

## Contributor License Agreement

CleanMac is released under the GNU GPL v3.0. To keep the project able to evolve (for example, to offer it under other terms in the future), the maintainer needs the right to relicense contributions.

By submitting a pull request, you agree that:

1. You wrote the contribution, or have the right to submit it.
2. You license your contribution to the project under the GPL-3.0, **and** you grant Mert Taştan a perpetual, worldwide, non-exclusive, royalty-free, irrevocable license to use, modify, sublicense and relicense it under any terms, including proprietary ones.
3. You keep the copyright of your contribution.

## Name and icon

The CleanMac name and app icon are not covered by the GPL. Forks are welcome, but please publish them under a different name and icon so users are not confused about which app they are installing.
