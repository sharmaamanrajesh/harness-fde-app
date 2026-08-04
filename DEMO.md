# Demo runbook

Target: **10–12 minutes**, leaving time for questions. Rehearse once end to end before the call.

---

## Before the call (15 minutes)

```bash
# 1. Cluster is up and all three environments are healthy
kubectl get nodes
for ns in dev staging prod; do
  port=$([ $ns = dev ] && echo 30080 || { [ $ns = staging ] && echo 30081 || echo 30082; })
  printf "%-8s " "$ns"; curl -s localhost:$port/health; echo
done

# 2. Delegate is connected
kubectl -n harness-delegate-ng get pods
```

Also confirm in the Harness UI that the delegate shows **Connected** — a Running pod that has
lost registration looks fine from `kubectl` and fails every deployment.

**Tabs to have open:**

1. Harness pipeline — last green execution
2. Harness — the gate-failure execution
3. GitHub — `harness-fde-app` PR #1 (red `sto` check)
4. GitHub — `harness-fde-gitops` merged promotion PRs
5. Docker Hub tags page
6. Two terminals

**If anything is broken, fix it now.** Do not debug live.

---

## Running order

### 1. Frame it (60s)

> "A commit to main is built and scanned once, then promoted dev → staging → prod by pull
> request. Any CRITICAL vulnerability stops it before anything deploys. The interesting
> constraint was that Harness's hosted runners can't reach a cluster on my laptop — so CI and
> scanning run in Harness Cloud, and a delegate inside the kind cluster does the deploying,
> polling outbound over 443."

Show the architecture diagram in the README.

### 2. The security gate — lead with this (3 min)

The strongest material. Show the **failure** first.

Open PR #1 on GitHub:

- `harness_fde_cicd-ci` green, `harness_fde_cicd-sto` **red**
- Open the Harness execution: Container Scan lists `CVE-2022-37434`, Security Gate fails
- Point at the **skipped** promote and deploy stages

> "Scans run on every PR. Promotion and deployment are skipped, because the GitOps repo is the
> source of truth for what's deployed and only merged code should change it."

Then the real find:

> "The gate caught something I didn't plant. The first run failed on CVE-2026-59873 — CRITICAL,
> in `tar`, inside npm bundled into `node:22-alpine`. My dependencies were clean; npm is never
> executed at runtime. I could have suppressed it. Instead I removed npm from the runtime image
> entirely — plain Alpine with just the node binary copied in. 234 MB down to 196."

If asked about distroless:

> "I tried it. It cleared that CVE but introduced a CRITICAL in libssl3, and it has no
> `/bin/sleep`, which would have silently broken my preStop hook."

### 3. Promotion (2 min)

```bash
for ns in dev staging prod; do
  port=$([ $ns = dev ] && echo 30080 || { [ $ns = staging ] && echo 30081 || echo 30082; })
  curl -s localhost:$port/health; echo
done
```

> "Same version everywhere, different environment. Built and scanned once — promotion never
> rebuilds."

Show a merged promotion PR in the GitOps repo:

> "That's a promotion: one line, `newTag`. Environments are directories on one branch, not
> branches — so promotion can't smuggle config drift along with it."

### 4. Live rolling deploy (3 min)

Terminal 1:

```bash
kubectl get pods -n dev -w
```

Terminal 2:

```bash
while true; do curl -s -D- -o /dev/null -m 2 localhost:30080/health | grep -i x-app-version; sleep 1; done
```

Make a trivial commit, push, and run the pipeline (or let the trigger fire). While it builds:

> "maxUnavailable is 0 and maxSurge is 1 — the new pod has to pass its readiness probe before an
> old one is touched."

When the rollout starts, point at terminal 2 flipping to the new SHA with no failed requests.

> "I measured this. Graceful SIGTERM alone wasn't enough — 6 dropped requests in 6,409, because
> Kubernetes removes the endpoint and sends SIGTERM at the same time. Adding a preStop sleep
> took it to 1 in 8,795."

### 5. Rollback (2 min)

Use the captured execution rather than running it live — it takes ~20 minutes.

> "I forced a failure by pointing at a tag that doesn't exist. Worth knowing: Kubernetes does
> nothing here. `progressDeadlineSeconds` sets a status condition and that's it — no auto
> rollback. The Deployment stays wedged indefinitely. So the pipeline owns it: two retries with
> backoff, then StageRollback. Throughout, the old pods were untouched — 21 hours old, zero
> restarts."

### 6. Close (60s)

> "All the mandatory requirements plus all five bonuses. The thing I'd change first: rollback
> restores the Harness release but doesn't revert the GitOps repo, so Git and the cluster diverge
> after a rollback. Rollback should itself be a revert commit."

---

## Questions to expect

**"Why a delegate?"**
Hosted runners can't reach a laptop cluster. The delegate polls outbound over 443 — no inbound
firewall rules. It also lets the health check use in-cluster DNS.

**"What happens on a CRITICAL?"**
`trivy image --severity CRITICAL --exit-code 1`. Non-zero fails the step, the stage, the pipeline.
Nothing promotes, nothing deploys.

**"Is failing on any CRITICAL right?"**
It's what the assignment asked for, and it's brittle. Both candidate base images shipped a
CRITICAL the day I built this. In production I'd keep the gate plus a documented, time-boxed
exception process. It's also narrow — `alpine:3.16` has two HIGH findings and passes untouched.

**"Would the red check actually block a merge?"**
Not by itself. That needs branch protection with required status checks — repo policy, not
pipeline config.

**"Why not deploy PRs?"**
Two open PRs would race over the same tag. Per-PR environments are fine, but in an ephemeral
`pr-N` namespace, not in `dev`.

**"How do you know the deploy worked?"**
The health check asserts the response `version` equals the deployed commit SHA, not just HTTP 200
— otherwise the previous release would pass.

**"Why multi-arch?"**
Harness Cloud is amd64, kind on Apple Silicon is arm64. A single-platform image fails at pull with
`no match for platform in manifest`.

---

## If something breaks live

- **Delegate disconnected** → show the captured execution instead; explain the outbound-polling model
- **Pipeline fails on a scan** → that's the gate working; walk the log
- **NodePort not answering** → `kubectl port-forward -n dev svc/harness-demo-app 8080:80`

Say what happened and move on. Composure reads better than a perfect run.
