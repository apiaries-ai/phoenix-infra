# Runbook — repo invariants

## Known plan-level gaps (accepted 2026-05-01)
apiaries-trunk and easypawn-site run on the free private-repo plan
and cannot enable secret scanning, CodeQL default setup, or branch
protection on main. repo-audit emits warnings for those three
assertions on those two repos. Lift this section when the org
upgrades to GitHub Team and the assertions go fatal again.
