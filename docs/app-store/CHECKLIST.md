# Shipping skill-health: what only the owner can do

Everything else is built and in this repository. These steps need your Apple account, money or judgment.

## Both channels
1. Join the Apple Developer Program (Account › Membership).
2. Decide the app's name and reserve it in App Store Connect (see listing.md).
3. App icon: done. Resources/AppIcon.icns is drawn from a Phosphor Icons glyph (MIT License, see NOTICE) by Scripts/make_icon.swift.
4. Make the repository public, or host the plugin elsewhere: the plugin installs from github.com/mvoshell652/skill-health, and the sample library compares with its samples/ folder. While it's private, both work only for you.
5. Host privacy-policy.md at a public URL (GitHub Pages works) for App Store Connect and the app's support page.
6. Licence: done. Apache License 2.0 (LICENSE, NOTICE).

## Direct download (Developer ID)
7. Create a "Developer ID Application" certificate (Xcode › Settings › Accounts › Manage Certificates).
8. Store notarization credentials: `xcrun notarytool store-credentials skill-health --apple-id <email> --team-id <TEAMID>`.
9. Run `APP_IDENTITY="Developer ID Application: … (TEAMID)" Scripts/release.sh`. It signs, notarizes, staples and checks with spctl and stapler (the spec's M6 done-test).

## Mac App Store
10. In the developer portal: an App ID for com.mvoshell.skillhealth, an "Apple Distribution" and a "Mac Installer Distribution" certificate, and a Mac App Store provisioning profile.
11. Run Scripts/package_mas.sh with those (see its header), upload the .pkg with Transporter.
12. In App Store Connect: the listing (listing.md), App Privacy "Data Not Collected", screenshots from the sample library, and review-notes.md in Notes for Review. Expect one round of questions about reading ~/.claude.

## The plugin
13. Make the repository public before anyone else installs the plugin: `claude plugin marketplace add mvoshell652/skill-health` uses the person's own git credentials, so a private repository works only for you.
14. Every plugin change needs a version bump in plugin/.claude-plugin/plugin.json (Claude Code pins installs to that version), and the app's PluginHandshake.minimumVersion raised when the menu starts opening a command an older plugin lacks. After changing Sources/SkillHealthCore or Sources/skill-health, commit, then run Scripts/build_plugin_bin.sh and commit plugin/bin (a test fails until you do).
15. Third-party marketplaces don't auto-update by default; the README tells people how (`claude plugin update skill-health@skill-health`, or auto-update under /plugin › Marketplaces).
16. Merge go-public-prep with a merge commit, never a squash or a rebase, so the commit plugin/bin/BUILT_FROM names stays in history. Then tag the merge commit, which must carry the rebuilt binary and version 0.6.1 in plugin.json and version.env: `git tag -a v0.6.1 <main tip> -m "Skill Health 0.6.1" && git push origin v0.6.1`. The README's `#v0.6.1` pin names this tag, so it must exist before the README is public; tag again for every version bump. Check `claude plugin marketplace add 'mvoshell652/skill-health#v0.6.1'` in a scratch CLAUDE_CONFIG_DIR. Also publish a GitHub Release for the tag (`gh release create v0.6.1 --notes …`): the README and SECURITY.md say new versions are listed there.
17. In the repository settings, untick squash and rebase merging, then (rulesets need the repository to be public or GitHub Pro) add a ruleset on main: no force-push, no deletion, a pull request required, and a review from code owners, which is the only thing that makes .github/CODEOWNERS bind.
18. Turn on private vulnerability reporting, secret scanning and push protection: SECURITY.md sends reporters to the Security tab.
