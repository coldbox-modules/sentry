# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

* * *

## [Unreleased]

## [2.1.5] - 2024-12-25

### Fixed - [Issue #37](https://github.com/coldbox-modules/sentry/issues/37) - Fix var-scoping inside conditional

## [2.1.4] - 2024-12-24

### Fixed - [Issue #37](https://github.com/coldbox-modules/sentry/issues/37) - Resolves an ACF incompat issue where traceparent variable was not available in threaded logging

## [2.1.3] - 2024-11-14

### Fixed

- Fixes for Coldbox being detected incorrectly.

## [2.1.0] - 2024-11-12

- Fixes for Coldbox being detected incorrectly.

## [2.1.0] - 2024-11-12

### Added

- Added support for passing through [`traceparent` headers](https://www.w3.org/TR/trace-context/#traceparent-header) and, optionally, traceparent data provided by [the `cbotel` module](https://forgebox.io/view/cbotel)
- Added `onSentryEventCapture` interception in Coldbox context to allow contributions to tags and user info

## [2.0.0] - 2024-06-10

### Changed

- Update the event structure to the new format Sentry has adopted for their official SDKs
- Don't send cookie and form scope data by default

### Added

- Add support for the new `/api/{project_id}/envelope` endpoint Sentry has adopted for sending events

## [1.0.0] - 2019-05-10

### Added

- Create first module version

[Unreleased]: https://github.com/coldbox-modules/sentry/compare/v2.1.5...HEAD

[2.1.5]: https://github.com/coldbox-modules/sentry/compare/v2.1.4...v2.1.5

[2.1.4]: https://github.com/coldbox-modules/sentry/compare/HEAD...v2.1.4

[2.1.3]: https://github.com/coldbox-modules/sentry/compare/v2.1.0...v2.1.3

[2.1.0]: https://github.com/coldbox-modules/sentry/compare/57864cae5969ad38eee194db5a6b2798e91967b3...v2.1.0
