#!/usr/bin/env bats

# Tests for scripts/detect-changes.sh
# Each test creates a temporary git repo, commits files, and verifies
# that detect-changes.sh correctly classifies the changed files.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"

setup() {
  # Create a temporary directory for each test
  TEST_REPO="$(mktemp -d)"
  cd "$TEST_REPO"

  # Initialize a git repo with an initial commit
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p src/data src/components
  echo "init" > README.md
  git add -A
  git commit -q -m "initial commit"
}

teardown() {
  rm -rf "$TEST_REPO"
}

@test "detects services changes from data/services.ts" {
  cd "$TEST_REPO"

  # Create and commit a services file
  echo 'export const services = [];' > src/data/services.ts
  git add -A
  git commit -q -m "add services"

  # Modify it so HEAD~1..HEAD shows the change
  echo 'export const services = [{ id: 1 }];' > src/data/services.ts
  git add -A
  git commit -q -m "update services"

  # Run the detect-changes script
  run bash "$SCRIPT_DIR/detect-changes.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"services"* ]]
}

@test "detects form changes from components with Form in name" {
  cd "$TEST_REPO"

  # Create and commit a form component
  echo 'export default function ApplicationForm() {}' > src/components/ApplicationForm.tsx
  git add -A
  git commit -q -m "add form component"

  # Modify it
  echo 'export default function ApplicationForm() { return null; }' > src/components/ApplicationForm.tsx
  git add -A
  git commit -q -m "update form component"

  # Run the detect-changes script
  run bash "$SCRIPT_DIR/detect-changes.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"forms"* ]]
}

@test "returns empty for no changes" {
  cd "$TEST_REPO"

  # Create an empty commit so HEAD~1..HEAD has no changed files
  git commit -q --allow-empty -m "empty commit"

  run bash "$SCRIPT_DIR/detect-changes.sh"
  [ "$status" -eq 0 ]

  # With no changed files, CHANGES stays empty; after dedup it becomes
  # whitespace-only. The script's regex doesn't match pure whitespace
  # as "cosmetic", so the output is effectively blank (no change types).
  trimmed="$(echo "$output" | xargs)"
  [ -z "$trimmed" ]
}
