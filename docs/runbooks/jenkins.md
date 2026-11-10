# Runbook: Jenkins

The Jenkins controller runs on the workstation, bound to `127.0.0.1:8080`, so nothing listens on the local network. It runs as the workstation's dedicated standard account, not as your everyday account, so a server full of plugins never runs with access to your own files, SSH keys or GitHub login. It runs no builds itself. It starts a build agent on the lab host over SSH, as the lab host's standard account `bot`, which owns the lab: Terraform runs there, next to Docker and `secrets.auto.tfvars`. GitHub cannot reach Jenkins, so its one job polls the `main` branch every 5 minutes. Decision: [research R15](../../specs/001-marketplace-local-cloud/research.md#r15-ci-hosts-and-how-they-are-reached).

> **Which account is which.** On the workstation, a dedicated standard account exists only to run Jenkins (the "Jenkins account"; its name is set in `scripts/lab/local.env`). On the lab host, `bot` is the standard account that owns the lab, and the agent logs in as it. The lab host also has an admin account; Jenkins never uses it. This runbook always says which machine it means.

```text
workstation                                          lab host
  everyday account: browser → http://localhost:8080
  Jenkins account:  Jenkins 127.0.0.1:8080 ──ssh──▶  bot: agent (label lab)
                    key sv_jenkins_agent             terraform, kind, docker
                                                     (key restricted: no forwarding, no pty)
```

Jenkins does not start at boot. You start it on the workstation at the beginning of a lab session and stop it at the end, so it uses no memory between sessions. It takes about 0.5–1 GB while running. If the workstation is also running a local model, check memory before a long session.

## One-time setup

**0. On the workstation, close your everyday home folder to other accounts.** macOS leaves it readable by the `staff` group, which includes the workstation's Jenkins account. From your everyday account:

```bash
chmod 700 ~
```

```bash
find ~ -maxdepth 3 -type f -perm -004 \( -iname '*cred*' -o -iname '*token*' -o -iname '*.pem' -o -iname '*key*' \)
```

The second command lists credential-looking files that every account on the Mac can read. Run `chmod 600` on each one it prints (for example `~/.aws/credentials`).

The workstation's Jenkins account must be a **standard** account, used for nothing else: no Apple ID, no browser sign-ins. The setup script refuses to run if it is an admin.

**1. On the workstation**, from your everyday account and this repository:

```bash
scripts/jenkins/air-setup.sh
```

It asks for your password. It installs `jenkins-lts` with Homebrew and stops the Homebrew service. It installs the plugins in `jenkins/plugins.txt` with the Jenkins Plugin Installation Manager (pinned, checksum-checked), copies `jenkins/casc.yaml` to `/Users/<jenkins-account>/.jenkins/`, and creates a random admin password in `/Users/<jenkins-account>/.jenkins/sv-admin-password`. It writes the LaunchDaemon `/Library/LaunchDaemons/com.sortedvintage.jenkins.plist`, which runs Jenkins as the workstation's Jenkins account, bound to loopback, with the setup wizard off, and does not start at boot. It creates the agent key `/Users/<jenkins-account>/.ssh/sv_jenkins_agent`, readable only by that account, gives that account the lab host's host key from your own verified `known_hosts`, and prints the command for step 2. It is safe to run again, for example after changing `plugins.txt` or `casc.yaml`.

**2. Authorize the key on the lab host.** Still on the workstation, paste the command step 1 printed. It logs in to the lab host as `bot` (`ssh lab`) and runs `scripts/jenkins/authorize-agent-key.sh` from `bot`'s clone of this repository:

```bash
ssh lab "~/Sorted-Vintage/src/sorted-vintage-infra/scripts/jenkins/authorize-agent-key.sh '<the public key step 1 printed>'"
```

The lab host needs Java for the agent: `openjdk@21` is in the [Brewfile](../../scripts/Brewfile), installed by the lab host's admin account. `/usr/bin/java` on a Mac is only a stub, so the agent uses `/opt/homebrew/opt/openjdk@21/bin/java`.

**3. Start Jenkins and sign in** at `http://localhost:8080` as `admin`. There is no setup wizard: `jenkins/casc.yaml` (T103) defines the admin user, the `lab-host` agent and the single `infra-terraform` job, which builds `main` only. The password is in a file only the workstation's Jenkins account can read; this copies it to your clipboard without printing it:

```bash
sudo cat /Users/<jenkins-account>/.jenkins/sv-admin-password | pbcopy
```

The agent's credential `mini-agent-ssh` is read from the key file, so no key is pasted into the UI or committed. Settings changed in the UI are lost at the next start; change `casc.yaml` and rerun step 1 instead.

## The pipeline

`infra-terraform` ([jenkins/Jenkinsfile](../../jenkins/Jenkinsfile), T014) runs on the lab host as `bot`: `fmt`, `init`, `validate`, `tfsec`, `plan`. If either plan has changes it waits for you to click **Apply** (up to an hour), then applies the cluster and bootstrap plans and waits for every Argo CD app to be healthy. With the `DESTROY` parameter it plans a destroy and needs two approvals. It reads and writes the same state as `make rebuild`: `~/sv-terraform` on the lab host (mode 700), with `secrets.auto.tfvars` beside it.

Every run that is not a destroy ends with `verify` (T107): it checks out `sorted-vintage-gitops` read-only beside the workspace and runs the current sprint's `sprints/sprint-N/verify_sprintN.sh` with `MINI=local`, so the commands run on the lab host as `bot` instead of over SSH. The build fails if the script fails. The `SPRINT` parameter picks the sprint; empty means the newest sprint that has its `verify_sprintN.sh` (T118). A sprint's folder lands with its plan and its script only at the end of the sprint, so the previous sprint's checks keep guarding every build until then. The script only reads: `get`, `terraform plan -lock=false`, server-side dry runs, and anonymous reads of the public GitHub and SonarQube Cloud APIs. The checks that only make sense on the workstation (its Jenkins account, port and keys) are skipped there; run the script from the workstation for those.

## Daily use

```bash
sudo launchctl kickstart system/com.sortedvintage.jenkins
```

```bash
sudo launchctl kill TERM system/com.sortedvintage.jenkins
```

The first command starts Jenkins and the second stops it. They are also in [lab-session.md](./lab-session.md) next to `make up` and `make down`, which run on the lab host. The Jenkins UI is at `http://localhost:8080`.

## Check it is closed

```bash
sudo lsof -nP -iTCP:8080 -sTCP:LISTEN
```

This must show `127.0.0.1:8080` only, with the Jenkins account in the USER column. It needs `sudo`: without it, `lsof` lists only your own processes, and Jenkins runs as another account. `verify_sprint1.sh` checks both without `sudo`, using `netstat` and `ps`.

## Rules for jobs

- One pipeline job, `infra-terraform`, on `main` of `sorted-vintage-infra`. No multibranch projects and no pull request or fork discovery: the repositories are public, and a stranger's Jenkinsfile must never run on the lab.
- Jenkins holds no GitHub write credentials; it reads the public repository.
- Keep plugins to the list in `jenkins/plugins.txt`.

## When something fails

| Symptom | Check |
| --- | --- |
| `localhost:8080` refuses | `sudo tail -50 /Users/<jenkins-account>/Library/Logs/sorted-vintage/jenkins.log`; was Jenkins started? `sudo launchctl print system/com.sortedvintage.jenkins` shows its state. |
| The `lab-host` agent is offline | `sudo -u <jenkins-account> -H ssh -i /Users/<jenkins-account>/.ssh/sv_jenkins_agent bot@<lab-host>.local /opt/homebrew/opt/openjdk@21/bin/java -version` on the workstation. `Permission denied` means step 2 was not run; `Host key verification failed` means rerun step 1 after `ssh lab true`; a Java error means Java is missing on the lab host. |
| A job never starts | The lab host is off, or its agent is offline; jobs wait for label `lab`. |
| A job fails to reach Docker | `bot` is not logged in at the lab host's screen, so Docker Desktop is not running. Log in as `bot` (use fast user switching, not Log Out, to reach other accounts). |
| `air-setup.sh` stops at "is an admin" | Make the workstation's Jenkins account a standard account in System Settings → Users & Groups. |
