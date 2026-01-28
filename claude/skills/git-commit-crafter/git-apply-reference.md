# Git Apply Reference

When applying `*.local.patch` files for recovery, follow these guidelines.

## Basic Usage

```bash
# Always verify first before applying
git apply --check patch_file.patch

# Apply with verbose output for debugging
git apply -v patch_file.patch
```

## Essential Flags

- **`-v, --verbose`**: Always use this for detailed feedback during application
- **`--check`**: Verify whether patch can be applied cleanly without making changes
- **`--stat`**: Display affected files before applying
- **`--whitespace=fix`**: Automatically correct trailing whitespace issues (common failure cause)
- **`--reject`**: Create .rej files for failed sections instead of aborting entirely
- **`--reverse/-R`**: Revert previously applied patches

## Troubleshooting Failed Applies

**Common Issues**:

1. **Trailing Whitespace**: Patches may fail due to whitespace differences
   ```bash
   git apply --whitespace=fix -v patch_file.patch
   ```

2. **Partial Failures**: When some hunks fail, use `--reject` to apply what works
   ```bash
   git apply --reject -v patch_file.patch
   # Manually resolve conflicts in generated .rej files
   ```

3. **Context Mismatch**: If patch was created from different base, try with more context
   ```bash
   git apply --ignore-whitespace -v patch_file.patch
   ```

4. **Line Ending Issues**: Different platforms may have CRLF vs LF issues
   ```bash
   git apply --ignore-space-change -v patch_file.patch
   ```

## Workflow Recommendation

```bash
# 1. Always check first
git apply --check patch_file.patch

# 2. If check passes, apply with verbose output
git apply -v patch_file.patch

# 3. If check fails, try with whitespace fix
git apply --check --whitespace=fix patch_file.patch
git apply -v --whitespace=fix patch_file.patch

# 4. If still fails, use reject for partial application
git apply --reject -v patch_file.patch
# Then manually fix .rej files
```

## Git Apply vs Git Am

- **`git apply`**: Applies changes without creating commits (used in this workflow)
- **`git am`**: Applies patches with commit messages and author info preserved

**ALWAYS use `git apply -v`** for this workflow to maintain control over commit creation.
