# Runbook: Jenkins

The Jenkins controller runs on the MacBook Air, bound to `127.0.0.1:8080`, so nothing listens on the home network. It runs no builds itself. It starts a build agent on the Mac mini over SSH, which is where Terraform runs, next to Docker and `secrets.auto.tfvars`. GitHub cannot reach Jenkins, so jobs poll Git every 5 minutes. Decision: [research R15](../../specs/001-marketplace-local-cloud/research.md#r15-ci-hosts-and-how-they-are-reached).

```text
MacBook Air                                     Mac mini
  Jenkins controller 127.0.0.1:8080 ──ssh──▶    agent (label lab): terraform, kind, docker
  browser → http://localhost:8080               (key sv_jenkins_agent, restricted)
```

Jenkins does not start at login. You start it on the Air at the beginning of a lab session and stop it at the end, so it uses no memory between sessions. It takes about 0.5–1 GB while running. If the Air is also running a local model, check memory before a long session.

## One-time setup

**1. On the Air**, from this repository:

```bash
scripts/jenkins/air-setup.sh
```

It installs `jenkins-lts`, replaces the Homebrew service with a LaunchAgent that binds to loopback, copies `jenkins/casc.yaml` into `~/.jenkins/`, creates the agent key `~/.ssh/sv_jenkins_agent`, and prints the command for step 2.

**2. On the Mac mini**, paste the command step 1 printed:

```bash
scripts/jenkins/authorize-agent-key.sh '<the public key step 1 printed>'
```

The mini needs Java for the agent: `openjdk@21` is added to the [Brewfile](../../scripts/Brewfile) in Sprint 1, Ticket 1.1.

**3. Start Jenkins and finish the first-run wizard** at `http://localhost:8080`. The unlock password is in `~/.jenkins/secrets/initialAdminPassword`. Configuration as code (T103) defines the agent and the `infra-terraform` job. The agent's credential `mini-agent-ssh` is read from `~/.ssh/sv_jenkins_agent` on the Air, so no key is pasted into the UI or committed.

## Daily use

```bash
launchctl kickstart gui/$(id -u)/com.sortedvintage.jenkins
launchctl kill TERM gui/$(id -u)/com.sortedvintage.jenkins
```

The first command starts Jenkins and the second stops it. They are also in [lab-session.md](./lab-session.md) next to `make up` and `make down`, which run on the mini. The Jenkins UI is at `http://localhost:8080`.

## Check it is closed

```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
```

This must show `127.0.0.1:8080` only. `verify_sprint1.sh` checks it.

## When something fails

| Symptom | Check |
| --- | --- |
| `localhost:8080` refuses | `~/Library/Logs/sorted-vintage/jenkins.log`; was Jenkins started? |
| The `mac-mini` agent is offline | `ssh -i ~/.ssh/sv_jenkins_agent mac-mini java -version` from the Air. `Permission denied` means step 2 was not run; a Java error means Java is missing on the mini. |
| A job never starts | The mini is off, or its agent is offline; jobs wait for label `lab`. |
