#!/bin/bash
# This runs only for dev

# rustup target add x86_64-pc-windows-gnu aarch64-pc-windows-gnullvm
# rustup target add x86_64-unknown-linux-gnu aarch64-unknown-linux-musl
# rustup target add x86_64-apple-darwin aarch64-apple-darwin

# Should be in this format
# metrics-linux-v2.1.2-x86_64
# metrics-linux-v2.1.2-aarch64
# metrics-macos-v2.1.2-x86_64
# metrics-macos-v2.1.2-aarch64
# metrics-windows-v2.1.2-x86_64.exe
# metrics-windows-v2.1.2-aarch64.exe
set -e

# Initialize action flags
DO_BUILD=false
DO_VERSION=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--build)
      DO_BUILD=true
      shift
      ;;
    -v|--versioning)
      DO_VERSION=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [-b|--build] [-v|--versioning]"
      exit 1
      ;;
  esac
done

# Default behavior: if no flags are provided, do both
if [ "$DO_BUILD" = false ] && [ "$DO_VERSION" = false ]; then
  DO_BUILD=true
  DO_VERSION=true
fi

if [ "$DO_BUILD" = true ]; then
  echo "Starting build process..."
  VERSION=$(sed -nE '/^\[package\]/,/^\[.*\]/ { s/^version = "(.*)"/\1/p; /^version =/q }' "$PWD/metrics/Cargo.toml")
	VERSION="v$VERSION"
  echo "Detected metrics version: $VERSION"
  # With gpu feature on x86_64 Linux
	echo "Building for x86_64-unknown-linux-gnu"
  cargo build --release --target x86_64-unknown-linux-gnu --features gpu
  rm -f "$PWD/assets/bin/metrics-linux-$VERSION-x86_64"
  cp "$PWD/target/x86_64-unknown-linux-gnu/release/metrics" "$PWD/assets/bin/metrics-linux-$VERSION-x86_64"
	echo "Build completed for x86_64-unknown-linux-gnu"

  # Keep musl for aarch64 Linux, no gpu
	echo "Building for aarch64-unknown-linux-musl"
  cargo build --release --target aarch64-unknown-linux-musl
  rm -f "$PWD/assets/bin/metrics-linux-$VERSION-aarch64"
  cp "$PWD/target/aarch64-unknown-linux-musl/release/metrics" "$PWD/assets/bin/metrics-linux-$VERSION-aarch64"
	echo "Build completed for aarch64-unknown-linux-musl"

  # Windows with gpu feature on x86_64 & build with cross
	# echo "Building for x86_64-pc-windows-gnu"
 #  cross build --release --target x86_64-pc-windows-gnu --features gpu
 #  rm -f "$PWD/assets/bin/metrics-windows-$VERSION-x86_64.exe"
 #  cp "$PWD/target/x86_64-pc-windows-gnu/release/metrics.exe" "$PWD/assets/bin/metrics-windows-$VERSION-x86_64.exe"
	# echo "Build completed for x86_64-pc-windows-gnu"
fi

if [ "$DO_VERSION" = true ]; then
  echo "Starting versioning process..."
  LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
  if [ -z "$LATEST_TAG" ]; then
    echo "Error: No git tags found in this repository."
    exit 1
  fi
  VERSION=$(echo "$LATEST_TAG" | sed 's/^v//')
  sed -i "s/^version:.*/version: $VERSION/" pubspec.yaml
  echo "Successfully updated 'pubspec.yaml' version to $VERSION"

  cd "$PWD/metrics" || exit 1
  sed -i "s/^version = \".*\"/version = \"$VERSION\"/" Cargo.toml
  echo "Successfully updated 'Cargo.toml' version to $VERSION"
fi


