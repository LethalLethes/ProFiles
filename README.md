# ProFiles

A standalone SwiftUI iOS app starter with three clearly separated areas:

- **Airlift Explorer** — a placeholder for displaying only files that a supported Airlift operation can actually expose.
- **AFC Explorer** — a placeholder for browsing the paired AFC service namespace when a real AFC implementation is connected.
- **CoreMedia Lab** — a diagnostic information screen. A CoreMedia test does not imply filesystem access.

## Important scope

This starter does not include exploit code, sandbox-escape logic, root access, or arbitrary system-file browsing. It does not claim that `/usr`, `/System`, or other protected locations are readable. Each module must be connected only to a documented, tested API and should display its actual errors and capabilities.

## Build

1. Install Xcode and XcodeGen on macOS.
2. Run `xcodegen generate`.
3. Open `ProFiles.xcodeproj` in Xcode.
4. Select your signing team and build for your own device.

The GitHub Actions workflow builds an unsigned IPA artifact. Signing requires a matching Apple Distribution/Development certificate and provisioning profile; the bundle identifier is `com.procreations.profiles`.

## GitHub Actions

Push the repository to GitHub. The workflow in `.github/workflows/build.yml` runs on pushes and can also be started manually from the Actions tab.
