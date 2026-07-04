#!/bin/bash
# This run on linux
# rustup target add x86_64-pc-windows-gnu aarch64-pc-windows-gnullvm
# rustup target add x86_64-unknown-linux-gnu aarch64-unknown-linux-musl
# rustup target add x86_64-apple-darwin aarch64-apple-darwin

# Should be in this format
# metrics-linux-x86_64
# metrics-linux-aarch64
# metrics-macos-x86_64
# metrics-macos-aarch64
# metrics-windows-x86_64.exe
# metrics-windows-aarch64.exe
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
  # With gpu feature on x86_64 Linux
  cargo build --release --target x86_64-unknown-linux-gnu --features gpu
  rm -f "$PWD/assets/bin/metrics-linux-x86_64"
  cp "$PWD/target/x86_64-unknown-linux-gnu/release/metrics" "$PWD/assets/bin/metrics-linux-x86_64"

  # Keep musl for aarch64 Linux, no gpu
  cargo build --release --target aarch64-unknown-linux-musl
  rm -f "$PWD/assets/bin/metrics-linux-aarch64"
  cp "$PWD/target/aarch64-unknown-linux-musl/release/metrics" "$PWD/assets/bin/metrics-linux-aarch64"

  # Windows with gpu feature on x86_64 & build with cross
  cross build --release --target x86_64-pc-windows-gnu --features gpu
  rm -f "$PWD/assets/bin/metrics-windows-x86_64.exe"
  cp "$PWD/target/x86_64-pc-windows-gnu/release/metrics.exe" "$PWD/assets/bin/metrics-windows-x86_64.exe"
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


