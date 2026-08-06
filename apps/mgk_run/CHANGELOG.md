# Changelog

All notable changes to Runio are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial repository scaffold: open-source governance, product specification,
  architecture documentation, roadmap, and Architecture Decision Records.
- AGPL-3.0 license and DCO-based contribution model.
- Flutter iOS app scaffold with a strict analyzer and CI (Phase A, step 1).
- Units domain (`Distance`, `Pace`, `Duration` formatting): metric storage with
  display-time km/mi conversion.
- Recording domain: the `RunPoint` model and the `RunRecorder` interface.
- Local Drift database (offline-first): `runs`, `run_points`, and `run_splits`
  tables with a tested persistence layer.

See [docs/roadmap.md](docs/roadmap.md) for what's next.
