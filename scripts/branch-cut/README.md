# Branch Cut Script

## What is Branch Cut?

Branch cut is the process of preparing a new project version. It automatically updates version numbers across all necessary files and prepares release branches.

## What does this script do?

The script automates two main tasks:

### 1. Version update on `main`
- Increments the version number (example: 4.21 → 4.22)
- Updates all version references in the code
- Renames Tekton pipeline files with the new version

### 2. Release branch preparation
- Creates a branch from `release-X.Y` 
- Updates references from `main` to `release-X.Y` in configuration files

## Prerequisites

**Important**: The `release-X.Y` branch must exist before executing the branch cut.

Example: If you're doing branch cut from 4.21.0, the `release-4.21` branch must exist.

## Important Notes

**The script never pushes changes to remote repositories**

The script only creates local branches and commits. You have full control over:
- When to push branches to remote
- Which branches to push
- Whether to create pull requests

This gives you the opportunity to review all changes before they are published.

## Basic usage

```bash
make branch-cut-with-git CURRENT_VERSION=4.21.0
```

This command will create two branches:
- `branch-cut-to-4.22` → for PR to `main`
- `prepare-release-4.21` → for PR to `release-4.21`

## Complete steps

### Option 1: With automatic git workflow (recommended)

```bash
# 1. Execute branch cut (creates local branches and commits)
make branch-cut-with-git CURRENT_VERSION=4.21.0

# 2. Verify changes (script never pushes, review first!)
git log
git diff HEAD~1

# 3. Push branches manually when ready
git push origin branch-cut-to-4.22
git push origin prepare-release-4.21

# 4. Create PRs from GitHub/GitLab interface
```

### Option 2: Manual (without automatic git)

```bash
# 1. Execute branch cut (only modifies files)
make branch-cut CURRENT_VERSION=4.21.0

# 2. Review changes manually
git status
git diff

# 3. Create branches and commits yourself
```

## Optional variables

| Variable | Description | Example |
|----------|-------------|---------|
| `CURRENT_VERSION` | **Required**. Current version | `4.21.0` |
| `EXCLUDE` | Exclude files/directories/extensions | `"docs/,.png,.gz"` |
| `EXCLUDE_VARS` | Exclude variable assignments from version replacement | `"RUNTIME_IMAGE,OPM_IMAGE"` |
| `CHECK_UNCOMMITTED` | Check for uncommitted changes | `false` |

**Note about EXCLUDE_VARS**: When you specify variables with `EXCLUDE_VARS`, any line containing these variable assignments (e.g., `RUNTIME_IMAGE=`) will be skipped during version replacement. This is useful when you want to prevent version numbers in specific variables from being updated (e.g., when they reference external images that should maintain their own versioning).

For example, if a file contains:
```
VERSION=4.21.0
RUNTIME_IMAGE=registry.io/base:4.21
OPM_IMAGE=registry.io/opm:4.21
```

And you run:
```bash
make branch-cut CURRENT_VERSION=4.21.0 EXCLUDE_VARS="RUNTIME_IMAGE,OPM_IMAGE"
```

The result will be:
```
VERSION=4.22.0
RUNTIME_IMAGE=registry.io/base:4.21   # <- Not changed
OPM_IMAGE=registry.io/opm:4.21         # <- Not changed
```

### Example with exclusions

```bash
# Exclude specific files and directories
make branch-cut-with-git CURRENT_VERSION=4.21.0 EXCLUDE="docs/,README.md,.png"

# Exclude specific variables from version replacement
make branch-cut-with-git CURRENT_VERSION=4.21.0 EXCLUDE_VARS="RUNTIME_IMAGE,OPM_IMAGE"

# Combine both types of exclusions
make branch-cut-with-git CURRENT_VERSION=4.21.0 \
  EXCLUDE="docs/,.png" \
  EXCLUDE_VARS="RUNTIME_IMAGE,OPM_IMAGE"
```

## Complete workflow example

```bash
# Step 1: Ensure the release branch exists
git fetch origin
git branch -r | grep release-4.21  # Should appear

# Step 2: Execute branch cut (creates LOCAL branches only, no push)
make branch-cut-with-git CURRENT_VERSION=4.21.0

# Step 3: Review the changes before pushing
git log --all --oneline --graph -10
git show branch-cut-to-4.22
git show prepare-release-4.21

# Step 4: Push the created branches when ready
git push origin branch-cut-to-4.22
git push origin prepare-release-4.21

# Step 5: Create PRs
# - PR 1: branch-cut-to-4.22 → main
# - PR 2: prepare-release-4.21 → release-4.21
```

## Expected result

After executing the script, you'll see:

```
==========================================
Step 1: Version bump on main branch
==========================================
Version bump completed: 4.21 -> 4.22

==========================================
Step 2: Prepare release branch (release-4.21)
==========================================
Release branch preparation completed on 'prepare-release-4.21'.

==========================================
Branch cut completed!
==========================================

Next steps:
  1. Review changes and push the branches
  2. Create PRs for both branches
```

## Troubleshooting

### Error: "Release branch does not exist"

**Problem**: The release branch doesn't exist yet.

**Solution**: 
```bash
# Check if it exists
git fetch origin
git branch -r | grep release-4.21

# If it doesn't exist, create it first or wait for it to be created
```

### Error: "You have uncommitted changes"

**Problem**: You have uncommitted changes in your repository.

**Solution**: 
```bash
# Option 1: Commit the changes
git add -A
git commit -m "WIP"

# Option 2: Stash them
git stash

# Option 3: Ignore the check (not recommended)
make branch-cut-with-git CURRENT_VERSION=4.21.0 CHECK_UNCOMMITTED=false
```

### Error: "Branch already exists"

**Problem**: One of the branches already exists from a previous branch cut.

**Solution**:
```bash
# Delete the local branch
git branch -D branch-cut-to-4.22

# Run again
make branch-cut-with-git CURRENT_VERSION=4.21.0
```

## Important: Tekton Pipeline Configuration

### For Dependent Repositories

If your repository uses this branch cut automation and has Tekton pipelines, you **should** add a filter to prevent pipelines from running on branch cut commits.

### Why This Is Necessary

Branch cut commits are tagged with `[BRANCH-CUT]` in their title and should not trigger CI/CD pipelines because:

1. They modify pipeline definition files themselves
2. They change version numbers across the entire codebase
3. They are intended for manual PR review, not automated validation
4. Running pipelines during branch cut causes unnecessary failures

### Required Filter

Add this CEL expression to your Tekton pipeline interceptors in `.tekton/*.yaml` files:

```yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  annotations:
    pipelinesascode.tekton.dev/on-cel-expression: |
      event == "pull_request/push" &&
      target_branch == "main" &&
                !event_title.contains("[BRANCH-CUT]") &&
```

This ensures that any PR or commit with a title that contains `[BRANCH-CUT]` will not trigger the pipeline, while all other workflows remain unchanged.

## Help

To see all available options:

```bash
make help
```

Or check the script usage directly:

```bash
./konflux-branch-cut.sh --help
```

## Compatibility

- Linux (Fedora, Ubuntu, etc.)  
- macOS

The script automatically detects the operating system and adjusts commands accordingly.
