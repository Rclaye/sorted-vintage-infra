# Runbook: Jenkins

The Jenkins controller runs on the MacBook Air, bound to `127.0.0.1:8080`, so nothing listens on the home network. It runs as the Air's dedicated standard account `ricomillz`, not as your everyday account, so a server full of plugins never runs with access to your own files, SSH keys or GitHub login. It runs no builds itself. It starts a build agent on the Mac mini over SSH, which is where Terraform runs, next to Docker and `secrets.auto.tfvars`. GitHub cannot reach Jenkins, so its one job polls the `main` branch every 5 minutes. Decision: [research R15](../../specs/001-marketplace-local-cloud/research.md#r15-ci-hosts-and-how-they-are-reached).

> **Two accounts named `ricomillz`.** The Air has a standard account `ricomillz` that exists only to run Jenkins. The mini has its own login `ricomillz`, which the agent logs in as. They are different accounts on different machines. This runbook always says which one it means.

```text
MacBook Air                                          Mac mini
  everyday account: browser → http://localhost:8080
  Air's ricomillz:  Jenkins 127.0.0.1:8080 ──ssh──▶  mini's ricomillz: agent (label lab)
                    key sv_jenkins_agent              terraform, kind, docker
                                                      (key restricted: no forwarding, no pty)
```

Jenkins does not start at boot. You start it on the Air at the beginning of a lab session and stop it at the end, so it uses no memory between sessions. It takes about 0.5–1 GB while running. If the Air is also running a local model, check memory before a long session.

## One-time setup

**0. On the Air, close your everyday home folder to other accounts.** macOS leaves it readable by the `staff` group, which includes the Air's `ricomillz`. From your everyday account:

```bash
chmod 700 ~
```

```bash
find ~ -maxdepth 3 -type f -perm -004 \( -iname '*cred*' -o -iname '*token*' -o -iname '*.pem' -o -iname '*key*' \)
```

The second command lists credential-looking files that every account on the Mac can read. Run `chmod 600` on each one it prints (for example `~/.aws/credentials`).

The Air's `ricomillz` must be a **standard** account, used for nothing else: no Apple ID, no browser sign-ins. The setup script refuses to run if it is an admin.

**1. On the Air**, from your everyday account and this repository:

```bash
scripts/jenkins/air-setup.sh
```

It asks for your password. It installs `jenkins-lts` with Homebrew and stops the Homebrew service. It writes the LaunchDaemon `/Library/LaunchDaemons/com.sortedvintage.jenkins.plist`, which runs Jenkins as the Air's `ricomillz`, bound to loopback, and does not start at boot. It copies `jenkins/casc.yaml` to `/Users/ricomillz/.jenkins/`, and creates the agent key `/Users/ricomillz/.ssh/sv_jenkins_agent`, readable only by that account. It gives that account the mini's host key from your own verified `known_hosts`, and prints the command for step 2.

**2. On the Mac mini**, logged in as the mini's `ricomillz`, paste the command step 1 printed:

```bash
scripts/jenkins/authorize-agent-key.sh '<the public key step 1 printed>'
```

The mini needs Java for the agent: `openjdk@21` is added to the [Brewfile](../../scripts/Brewfile) in Sprint 1, Ticket 1.1.

**3. Start Jenkins and finish the first-run wizard** at `http://localhost:8080`. The unlock password is in a file only the Air's `ricomillz` can read. This copies it to your clipboard without printing it:

```bash
sudo cat /Users/ricomillz/.jenkins/secrets/initialAdminPassword | pbcopy
```

Configuration as code (T103) defines the agent and the single `infra-terraform` job, which builds `main` only. The agent's credential `mini-agent-ssh` is read from the key file, so no key is pasted into the UI or committed.

## Daily use

```bash
sudo launchctl kickstart system/com.sortedvintage.jenkins
```

```bash
sudo launchctl kill TERM system/com.sortedvintage.jenkins
```

The first command starts Jenkins and the second stops it. They are also in [lab-session.md](./lab-session.md) next to `make up` and `make down`, which run on the mini. The Jenkins UI is at `http://localhost:8080`.

## Check it is closed

```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
```

This must show `127.0.0.1:8080` only, with `ricomillz` in the USER column. `verify_sprint1.sh` checks both.

## Rules for jobs

- One pipeline job, `infra-terraform`, on `main` of `sorted-vintage-infra`. No multibranch projects and no pull request or fork discovery: the repositories are public, and a stranger's Jenkinsfile must never run on the lab.
- Jenkins holds no GitHub write credentials; it reads the public repository.
- Keep plugins to the list in `jenkins/plugins.txt`.

## When something fails

| Symptom | Check |
| --- | --- |
| `localhost:8080` refuses | `sudo tail -50 /Users/ricomillz/Library/Logs/sorted-vintage/jenkins.log`; was Jenkins started? `sudo launchctl print system/com.sortedvintage.jenkins` shows its state. |
| The `mac-mini` agent is offline | `sudo -u ricomillz -H ssh -i /Users/ricomillz/.ssh/sv_jenkins_agent ricomillz@ricomillzs-Mac-mini.local java -version` on the Air. `Permission denied` means step 2 was not run; `Host key verification failed` means rerun step 1 after `ssh mac-mini true`; a Java error means Java is missing on the mini. |
| A job never starts | The mini is off, or its agent is offline; jobs wait for label `lab`. |
| `air-setup.sh` stops at "is an admin" | Make the Air's `ricomillz` a standard account in System Settings → Users & Groups. |
