# Contributing

Thanks for considering a contribution — all sizes are welcome, from a typo fix to a new feature.

## Getting set up

```bash
git clone https://github.com/Jrpixel666/Lame.git
cd Lame
flutter pub get
```

For Android specifically, see [Local Android Development](README.md#local-android-development) in
the README, or just run:

```bash
scripts/check_android_dev_env.sh
scripts/setup_android_dev.sh
```

## Before opening a PR

```bash
flutter analyze
flutter test
```

Both of these also run in CI on every pull request — fixing them locally first saves a round trip.

## Workflow

```bash
git checkout -b fix/short-description
# make your changes
git commit -m "fix: short description"
git push origin fix/short-description
# open a PR against main
```

- Keep PRs focused — one fix or feature per PR is easier to review than several bundled together.
- If you're changing behavior a user would notice, say so in the PR description.
- If you're adding a dependency, say why in the PR description — this project tries to keep its
  dependency surface small, especially for a mobile-first local-inference app.

## Dependencies

Dependabot opens weekly PRs for pub, Gradle, and GitHub Actions updates — review and merge those
rather than bumping versions by hand where possible.

One exception worth knowing about: `flutter_markdown` (used to render AI responses) was marked
**discontinued** on pub.dev by the Flutter team. It still works and we're pinned to its latest
published version, but if you're picking up new markdown work, consider whether a community fork
or an alternative package should replace it first.

## Reporting bugs / requesting features

Use the issue templates — they'll prompt for the platform, steps to reproduce, and anything else
that speeds up triage. See [SECURITY.md](SECURITY.md) instead if what you found is a security
issue.
