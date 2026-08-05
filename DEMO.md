# Demo runbook — presenter script

**Target: 10–12 minutes of walkthrough, leaving 8–10 minutes for questions.**

The structure leads with the security gate *failing*, because that is the strongest material and
the thing most submissions cannot show. The happy path comes second.

---

## T-15 min — pre-flight (not part of the demo)

```bash
cd ~/Documents/Assessments/Harness-FDE_ImplementationEngineer/harness-fde-app

kubectl get nodes                              # 3 nodes Ready
kubectl -n harness-delegate-ng get pods        # 1/1 Running
./scripts/envs.sh                              # all three ok, same version
```

Then confirm in the Harness UI that the delegate reads **Connected** — a Running pod that has lost
registration looks healthy from `kubectl` and fails every deployment.

**If anything is red, fix it now. Never debug live.**

### Tabs to have open, in this order

| # | Tab |
|---|---|
| 1 | Harness — last **green** execution (all 9 stages) |
| 2 | Harness — the **gate-failure** execution |
| 3 | Harness — the **rollback** execution |
| 4 | GitHub — `harness-fde-app` PR #1 (red `sto` check) |
| 5 | GitHub — `harness-fde-gitops` → Pull requests → Closed |
| 6 | Docker Hub — tags page |

### Terminals

Two, side by side, large font, in the app repo directory. Clear both.

---

## Segment 1 — Frame it (1 min)

Show the architecture diagram in the README or the report.

> "The flow is: a commit to main gets built once, scanned, and then promoted dev → staging → prod
> by pull request. Any CRITICAL vulnerability stops it before anything deploys.
>
> The constraint that shaped the architecture is that Harness's hosted runners can't reach a
> Kubernetes cluster running on my laptop. So rather than expose the cluster, CI and scanning run
> in Harness Cloud, and a delegate inside the kind cluster does the deploying — it polls Harness
> outbound over 443, so there's no inbound firewall rule and no tunnel."

**Do not** spend more than a minute here. Get to the working system.

---

## Segment 2 — The security gate, failure first (3 min)

**Tab 4 — PR #1.**

Point at the two checks:

> "This pull request downgrades the base image to one carrying a CRITICAL CVE. CI passes — the
> image builds fine, vulnerable isn't the same as broken. STO fails."

**Tab 2 — the gate-failure execution.** Open the Container Scan log, then the Security Gate step.

> "The gate is one line: `trivy image --severity CRITICAL --exit-code 1`. Non-zero exit fails the
> step, which fails the stage, which stops the pipeline."

Now point at the greyed-out stages:

> "And notice everything after STO is skipped — promotion and all three deploys. Pull requests
> never deploy here. The GitOps repo is the source of truth for what's running, so only merged
> code changes it. If two open PRs could both write the image tag, they'd race and nobody could
> say what's actually in production."

Back to **Tab 4**, scroll to the merge button:

> "And `harness_fde_cicd-sto` is a required status check under branch protection, so GitHub refuses
> the merge rather than just reporting it. One caveat I'd flag: `enforce_admins` is off, so as the
> repo owner I can still bypass it — that's deliberate so a one-person demo can't lock itself out.
> In a team it would be on."

Say the caveat yourself rather than waiting to be caught on it. Volunteering the limit of your own
control is more convincing than claiming an absolute.

### Then the part worth telling

> "The gate also caught something I didn't plant. The very first run failed on CVE-2026-59873 —
> CRITICAL, in `tar`, inside the npm that ships with `node:22-alpine`. My own dependencies were
> clean, and npm is never executed at runtime.
>
> I could have suppressed it with a `.trivyignore`. Instead I removed npm from the runtime image
> entirely — it's now plain Alpine with just the node binary copied in. That took the image from
> 234 MB to 196 and removed the whole class of finding rather than silencing one."

**If asked about distroless** — have this ready, it's a strong answer:

> "I tried it. It cleared that CVE but introduced a CRITICAL in libssl3, and it has no `/bin/sleep`,
> which would have silently broken my preStop hook. So it would have traded one CVE for another
> and quietly broken zero-downtime deploys."

---

## Segment 3 — Promotion (2 min)

**Terminal 1:**

```bash
./scripts/envs.sh
```

> "Same image tag in all three environments, different environment label. It was built and scanned
> exactly once — promotion never rebuilds."

**Tab 5 — merged promotion PRs.** Open one, go to Files changed.

> "This is a promotion: one line, the image tag, in one file. Environments are directories on a
> single branch, not long-lived branches — so a promotion physically can't smuggle a config change
> along with it. And every promotion is a reviewable, revertible commit."

---

## Segment 4 — Live rolling deploy (3 min)

**Terminal 1:**
```bash
kubectl get pods -n dev -w
```

**Terminal 2:**
```bash
./scripts/probe.sh 30080
```

Trigger a run (or replay a recording if time is tight). While CI builds:

> "maxUnavailable is 0 and maxSurge is 1 — the new pod has to pass its readiness probe before any
> old pod is touched."

When the rollout starts, point at Terminal 2:

> "Both versions are served for about fifteen seconds while the new pod comes up and the old one
> drains — that's the rolling update happening. Failure count stays at zero."

Ctrl-C Terminal 2 to show the tally.

> "I measured this rather than assuming it. Graceful SIGTERM alone wasn't enough — I was dropping
> 6 requests in 6,400, because Kubernetes removes the endpoint and sends SIGTERM at the same time,
> so kube-proxy still routes to a pod that's already draining. Adding a preStop sleep took it to
> 1 in 8,795, and the last run was 3,295 with zero."

---

## Segment 5 — Rollback (2 min)

**Use Tab 3, the captured execution.** Do not run this live — it takes ~7 minutes.

> "I forced a failure by pointing dev at an image tag that doesn't exist.
>
> The important thing is what Kubernetes does on its own: nothing. `progressDeadlineSeconds` fires,
> sets a status condition, and stops. No automatic rollback. The Deployment sits there permanently
> — available, serving old pods, unable to progress. It would stay like that forever.
>
> So the pipeline owns it: two retries with backoff, then StageRollback, then K8sRollingRollback.
> Throughout the whole failure the serving pods were never touched — 145 minutes old, zero
> restarts."

**If they ask about the release/revision numbers in the log:**

> "Two counters. Harness has its own release number in a ConfigMap in the namespace; Kubernetes has
> a Deployment revision. Harness finds its last successful release and translates it to the
> Kubernetes revision that produced it. And `rollout undo` replays that template as a *new*
> revision — so rollback moves forward in numbering while moving backward in content."

---

## Segment 6 — Close (1 min)

> "Everything mandatory is there, plus all five bonuses.
>
> The thing I'd change first is that rollback restores the previous Harness release but doesn't
> revert the GitOps repo — so after a rollback, Git and the cluster disagree, and the next sync
> would re-apply the bad tag. Rollback should itself be a revert commit.
>
> The other honest one: 'fail on any CRITICAL' is what was asked for and I implemented it
> literally, but it's brittle. On the day I built this, both candidate base images shipped a
> CRITICAL. In production I'd keep the gate and add a documented, time-boxed exception process —
> otherwise teams route around it."

---

# Question bank

## Architecture

**Why a delegate rather than giving Harness cluster credentials?**
Hosted runners can't reach a laptop cluster at all — it's behind NAT. The delegate polls outbound
over 443, so no inbound rules and no tunnel. It also means the post-deploy health check can use
in-cluster DNS (`harness-demo-app.dev.svc.cluster.local`), which hosted CI could never resolve.

**Why split CI and CD across two execution environments?**
Each side goes where it can reach what it needs. CI and scanning need the internet — registry,
Trivy's DB, GitHub's API. CD needs the Kubernetes API and cluster DNS.

**Why two repositories?**
The GitOps bonus asks for manifests in a separate repo updated via PR. It also separates
"what the code is" from "what is deployed where" — the app repo's history is features, the GitOps
repo's history is a deployment audit log.

**Why directories per environment instead of branches?**
Branch-per-environment turns promotion into a merge between long-lived branches, which drifts and
tangles config changes with promotions. With overlays, `diff -r overlays/dev overlays/prod` shows
every difference instantly and a promotion is provably one line.

## Security

**What exactly happens on a CRITICAL?**
`trivy image --severity CRITICAL --exit-code 1`. Non-zero exit fails the step → stage → pipeline.
Nothing promotes, nothing deploys.

**Why is the gate a separate step from the scan?**
So the execution graph shows unambiguously which step enforces. The cost is a redundant scan —
better would be one scan to JSON and `trivy convert` twice, which is also more correct, since two
independent scans could disagree if the vuln DB updates between them.

**Is CRITICAL-only the right threshold?**
No, and I can prove it: `alpine:3.16` has two HIGH findings and sails straight through. I found that
out because my first attempt at a vulnerable PR used it and the gate passed. It's what the
assignment specified, and in production I'd gate on HIGH with an exception process.

**Why no `--ignore-unfixed`?**
The requirement says fail on *any* CRITICAL, so it's literal. I'd add it in production — an
unfixable CRITICAL otherwise blocks you with no remediation path.

**Why not the Harness STO module?**
Not available on the free tier — the module page offers only "Trial – Coming soon" and Contact
Sales. I kept a stage named STO so the topology still reads CI → STO → CD, and implemented it with
Trivy and Semgrep. Arguably better for review: the failure condition is one auditable line in Git
rather than a UI toggle.

**Does the red check actually block a merge?**
Yes, now — `harness_fde_cicd-sto` is a required status check via branch protection. It didn't
initially, and that's worth saying: scanning happens in the pipeline, but *enforcement* is
repository policy. `enforce_admins` is off so a solo demo isn't locked out; a team would turn it on.

**Where does SAST fit?**
Semgrep OSS with the JavaScript, Node and OWASP Top Ten rulesets. Worth noting its limits — in
testing it caught an `eval` injection but missed a command injection via string concatenation.
SAST is a net with holes, which is why it sits alongside container scanning rather than replacing it.

## Deployment

**How do you know the deployment actually worked?**
The health check asserts HTTP 200 **and** that the response `version` equals the deployed commit
SHA. A plain 200 would also come back from the previous release, so a failed rollout would pass
unnoticed.

**Why `ScheduleAnyway` on topology spread?**
With 2 replicas on 2 workers, the surge pod during a rollout makes a 2/1 split unavoidable.
`DoNotSchedule` would leave it Pending and deadlock the rollout permanently.

**What happens if the deploy hangs rather than fails?**
That's a case I got wrong initially. A step that runs out of time *expires* rather than errors, and
`AllErrors` doesn't cover expiry — so the pipeline ended EXPIRED with no rollback. `Timeout` has to
be its own failure-strategy entry.

**Why multi-arch images?**
Harness Cloud runners are amd64; kind on Apple Silicon is arm64. A single-platform image fails at
*pull* time with `no match for platform in manifest`. The dependency stage builds on the native
platform and the runtime stage has no RUN at all, so cross-building needs no emulation.

## Process

**Why don't pull requests deploy?**
The GitOps repo is the source of truth for what's deployed, so only merged code should change it.
Two open PRs would race over the same tag. Per-PR environments are a fine pattern, but they belong
in an ephemeral `pr-N` namespace, not in dev — dev is what staging and prod get promoted from.

**Is auto-merging your own PR really GitOps?**
For dev, yes — auto-promotion with a full audit trail in Git. Staging and prod set `autoMerge` to
false, and production is gated by a Harness approval before its promotion even runs. The template
exposes it as a typed input, so it's a one-value change.

**How would you scale this to 20 services?**
The stage template already generalises the promotion logic. I'd add a pipeline template, move the
Harness entities to Git Experience so they're PR-reviewed, and template the Kustomize base as well.

**What would you do differently with more time?**
Cosign signing with admission-time verification, NetworkPolicies between namespaces, rollback as a
revert commit, ephemeral PR environments, and pushing PR builds to a quarantine registry rather
than the release one.

---

# If something breaks live

| Symptom | Response |
|---|---|
| Delegate disconnected | `kubectl -n harness-delegate-ng get pods` — it self-recovers in a minute. Explain the outbound-polling model while it does |
| Pipeline fails on a scan | That's the gate working. Walk the log; it's a better demo than a green run |
| NodePort not answering | `kubectl port-forward -n dev svc/harness-demo-app 8080:80` |
| A stage fails unexpectedly | Keep going. Read the log out loud and reason about it |

**Composure beats a perfect run.** Reasoning through a real failure on camera demonstrates more
than a rehearsed happy path.
