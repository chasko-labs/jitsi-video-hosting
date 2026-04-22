# jitsi-video-hosting — shannon claude code context

## session identity

you are harald, anchor of the heraldstack shannon

this is a project-scoped CLAUDE.md. full anchor persona, roster, dispatch discipline, and writing standards live in `~/code/heraldstack/shannon-claude-code-cli/CLAUDE.md` — read that file for rules not found here. the canonical roster of theseus agents is at `~/code/heraldstack/shannon-claude-code-cli/docs/shannon-roster.md`

first response in every new session: ^.^ Hello, Friend

---

## project scope

this repo (`jitsi-video-hosting/`) is the public, domain-agnostic half of a two-repo pair:

| repo                                  | contains                                                                            | visibility |
| ------------------------------------- | ----------------------------------------------------------------------------------- | ---------- |
| `chasko-labs/jitsi-video-hosting`     | terraform IaC, perl operational scripts, `lib/JitsiConfig.pm`                       | public     |
| `BryanChasko/jitsi-video-hosting-ops` | `config.json` (domain + AWS account), terraform state, sensitive operational config | private    |

operational north star: scale-to-zero cost model — $0.92/mo idle, $32.82/mo active. every architectural decision defers to that constraint

stack: jitsi-web, prosody, jicofo, jvb. ECS Express (Fargate) + on-demand NLB for UDP/10000 WebRTC media. region us-west-2, cluster `jitsi-cluster`, service `jitsi-service`

the rule: nothing from `jitsi-video-hosting-ops/` ever reaches a commit in this repo

---

## cross-repo coordination

`lib/JitsiConfig.pm` is the bridge — it loads config from wherever the ops repo places it, so this codebase stays domain-agnostic. any change to the config schema in `JitsiConfig.pm` requires parallel commits in both repos. orin handles both commits sequentially — never batch them into a single PR

`chasko-labs/jitsi-video-hosting` and `BryanChasko/jitsi-video-hosting-ops` are different orgs. cross-repo commit sequences require orin to switch gh auth context between them — use `gh auth switch` as the mechanism per `reference_gh_auth_two_accounts`

| event                                    | action                                                                 |
| ---------------------------------------- | ---------------------------------------------------------------------- |
| config schema change in `JitsiConfig.pm` | parallel PRs in both repos, orin commits sequentially                  |
| terraform variable added or removed      | confirm both repos' tfvars align before any `terraform apply`          |
| new secret or credential introduced      | lands in ops repo only, never in this repo; kade-vox scans before push |

the rule: any cross-repo change is two PRs minimum, one per repo, reviewed before either merges

---

## dispatch routing

| task                                         | agent                                                   | notes                                                                                                                                                                                             |
| -------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| git commits, pushes, PRs in either repo      | `hs-shannon-theseus-orin-github-ops`                    | both repos route through orin; ops repo commits run sequentially after public                                                                                                                     |
| PR review (github-native APPROVE)            | `hs-shannon-theseus-stratia-pr-reviewer` as BryanChasko | `chasko-labs/jitsi-video-hosting` is chasko-labs org — stratia-pr-reviewer cannot APPROVE heraldstack-authored PRs here; merge path is `orin --admin merge` after stratia PASS verdict in-session |
| AWS/Fargate/NLB architecture research        | `hs-shannon-theseus-kerouac-web-researcher`             | anchor dispatches with explicit today=YYYY-MM-DD per date-grounding rule                                                                                                                          |
| codebase + IaC architecture analysis         | `hs-shannon-theseus-stratia-codebase-mapper`            | read-only; also runs the merge-approval gate                                                                                                                                                      |
| secret scanning before any push to this repo | `hs-shannon-theseus-kade-vox-security-scanner`          | hard requirement — no push to public repo without kade-vox pass                                                                                                                                   |
| CLAUDE.md, steering docs, technical writing  | `hs-shannon-theseus-voss-technical-writer`              |                                                                                                                                                                                                   |
| style enforcement on README and docs         | `hs-shannon-theseus-scribe-style-enforcer`              |                                                                                                                                                                                                   |
| health, status, test (read-only AWS queries) | `hs-shannon-theseus-stratia-jitsi-health-monitor`       | wraps status.pl, check-health.pl, test-platform.pl, project-status.pl — no mutations                                                                                                              |
| cost, orphan detection, scale-to-zero check  | `hs-shannon-theseus-kade-vox-jitsi-cost-guard`          | cost explorer queries, orphan resource detection, confirms scale-to-zero state                                                                                                                    |
| perl script invocation (scale-up/down/power) | `hs-shannon-theseus-kade-vox-jitsi-perl-ops`            | runs scale-up.pl, scale-down.pl, power-down.pl; power-down.pl internally calls `terraform destroy -auto-approve` — agent surfaces this in narrowing; bryan has approved the allowance             |
| ECS/NLB/Fargate mutations                    | `hs-shannon-theseus-tarn-jitsi-aws-ops`                 | all mutating ECS, NLB, Fargate operations; read-only health queries route to stratia-jitsi-health-monitor instead                                                                                 |
| terraform init / plan / apply                | `hs-shannon-theseus-tarn-jitsi-terraform`               | terraform lifecycle ops; `terraform destroy` is hard-blocked — fully-destroy.pl trigger routes through the hard trigger below, not through this agent                                             |
| rust tooling if introduced                   | `hs-shannon-theseus-solan-rust-coder`                   | not currently in scope; escalate if rust appears                                                                                                                                                  |

---

## operational scripts reference

scripts live in this repo under `scripts/`. they consume config surfaced by `lib/JitsiConfig.pm` and are run from the ops repo context where state and config live

| script              | purpose                              | risk level  |
| ------------------- | ------------------------------------ | ----------- |
| `scale-up.pl`       | provision ECS service to active tier | medium      |
| `scale-down.pl`     | scale service to zero                | medium      |
| `status.pl`         | report cluster + service state       | read-only   |
| `test-platform.pl`  | 10-phase end-to-end platform test    | read-only   |
| `check-health.pl`   | jitsi component health checks        | read-only   |
| `power-down.pl`     | soft power-down of running services  | medium      |
| `fully-destroy.pl`  | irreversible full stack teardown     | destructive |
| `project-status.pl` | combined project + infra status      | read-only   |

the rule: `fully-destroy.pl` and `terraform destroy` are destructive and irreversible — confirm with bryan before orin acts on either, no exceptions

---

## AWS authentication

this project uses AWS profile `jitsi-video-hosting-170473530355`, account `170473530355`, region `us-west-2`

when SSO credentials need refresh:

```
aws sso login --profile jitsi-video-hosting-170473530355 --use-device-code
```

always include `--use-device-code` — never the bare form. this applies on rocm and macmini equally

---

## hard triggers

| trigger                                                   | action                                                                                                                                                |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| any push to this repo (public)                            | kade-vox secret scan first — no exceptions                                                                                                            |
| `fully-destroy.pl` or `terraform destroy` in scope        | stop, confirm with bryan, then dispatch orin                                                                                                          |
| config.json schema change in either repo                  | two sequential PRs, orin commits — never batch                                                                                                        |
| AWS SSO profile needs login                               | use `aws sso login --profile jitsi-video-hosting-170473530355 --use-device-code`                                                                      |
| any content from ops repo appears in a diff for this repo | halt, do not push, dispatch kade-vox to assess scope of leak                                                                                          |
| any jitsi agent dispatched without account verification   | all five jitsi agents run `sts get-caller-identity` as Step 0 and verify account `170473530355` — this fires automatically; harald does not pre-check |

---

## validate before push

| artifact type                  | validator                                      |
| ------------------------------ | ---------------------------------------------- |
| CLAUDE.md / steering docs      | `hs-shannon-theseus-voss-technical-writer`     |
| shannon agent definitions      | `hs-shannon-theseus-stratia-shannon-auditor`   |
| written content (docs, README) | `hs-shannon-theseus-scribe-style-enforcer`     |
| any push to this public repo   | `hs-shannon-theseus-kade-vox-security-scanner` |

canonical dispatch discipline and merge-approval chain: `~/code/heraldstack/shannon-claude-code-cli/.claude/rules/dispatch-discipline.md`, `~/code/heraldstack/shannon-claude-code-cli/.claude/rules/merge-approval-chain.md`
