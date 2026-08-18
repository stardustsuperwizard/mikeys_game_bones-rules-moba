## Merge Policy

This repository uses **squash merging** for pull requests.

Each GitHub issue should represent one logical unit of work. Automated agents should:

1. Create or use a branch based on the current `main` branch.
2. Make any number of intermediate commits needed to complete the issue.
3. Open a pull request linked to the issue.
4. Allow CI and review feedback to complete before merging.
5. Squash the pull request into a single commit when merging.
6. Delete the feature branch after merge.

The intended repository history is:

**one issue → one pull request → one commit on `main`**

Do not create dependent or stacked pull requests unless explicitly required. New work should normally begin from the latest `main`.
