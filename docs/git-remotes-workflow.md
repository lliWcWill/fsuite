# Git Remotes Workflow

This repo uses three remotes with different jobs. Do not assume `origin` is the upstream-facing remote.

## Remote map

- `upstream` = `lliWcWill/fsuite`
  - Canonical upstream project
- `fork` = `Cwilliams333/fsuite`
  - Public fork
  - Should stay aligned with `upstream`
- `origin` = `Cwilliams333/fsuite-private`
  - Private repo
  - May contain extra history that does not belong in `fork` or `upstream`, including `flog`

## Safe default workflow

1. Work locally on a feature branch.
2. Push the feature branch to `fork`.
3. Open a PR from that branch into `fork/master`.
4. Merge on `fork`.
5. Open an upstream PR from `fork` when the change should go to `lliWcWill/fsuite`.
6. Cherry-pick the needed commit(s) from `fork` into `origin` when the private repo should carry the same fix.

## Rules

- Always run `git remote -v` before pushing or creating a PR if there is any ambiguity.
- Do not treat `origin` as something that should be kept in lockstep with `fork`.
- Do not merge `fork` into `origin` just to sync branches.
- Do not rebase `origin` onto `fork` or `upstream`.
- Preserve private-only history in `origin`.
- Prefer cherry-picking from `fork` into `origin`.

## Why

`fork` is the integration point for upstream-facing work. `origin` is a private derivative with extra history that should not be flattened, rebased away, or accidentally published upstream.

## Memory anchors

- Memory ID `730`: canonical note for the fsuite git remotes and PR workflow
- Memory ID `731`: canonical note for this workflow document path

## Quick command examples

```bash
# Inspect remotes first
git remote -v

# Push feature work to the public fork
git push fork my-feature:my-feature

# After merge on fork, bring the same fix into the private repo
git checkout master
git cherry-pick <fork-merge-commit-or-feature-commit>
git push origin master
```
