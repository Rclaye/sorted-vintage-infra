# Runbook: a lab session

The lab runs only while I work (FR-024). A session starts with `make up` and ends with `make down`
on the lab host as `bot`; between sessions the lab host can be off. Data and history survive: Postgres
archives to Garage on `~/sv-data`, and Prometheus, Loki and Tempo keep their volumes.

Accounts and SSH aliases are in [remote-access.md](./remote-access.md).

## One-time setup on the workstation

### `/etc/hosts`

Every lab hostname points at the workstation's own loopback, where the SSH tunnel listens:

```bash
sudo sh -c 'printf "127.0.0.1 %s.sortedvtg.lan\n" dev prod grafana argocd mail auth >> /etc/hosts'
```

Check that each name appears once (the command above appends, so do not run it twice):

```bash
grep sortedvtg.lan /etc/hosts
```

### Trust the mkcert root CA

Traefik serves a `*.sortedvtg.lan` certificate made by mkcert on the lab host. Copy only the public
root certificate to the workstation. Never copy `rootCA-key.pem`: with it, anyone could mint certificates
the workstation trusts.

```bash
scp "lab:Library/Application Support/mkcert/rootCA.pem" ~/Downloads/sv-rootCA.pem
```
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/sv-rootCA.pem
```
```bash
rm ~/Downloads/sv-rootCA.pem
```

Firefox keeps its own trust store; Safari and Chrome use the keychain.

## Start a session

1. Quit Ollama in the lab host's admin account (local models and the lab do not fit in 16 GB together).
   `make up` refuses to start while it runs.
2. At the lab host's screen, switch to `bot` (fast user switching, not Log Out), so Docker Desktop
   runs. Keep the lab host awake.
3. On the workstation, start the lab:

   ```bash
   ssh lab
   ```
   ```bash
   cd ~/Sorted-Vintage/src/sorted-vintage-infra && make up
   ```

   `make up` checks it runs as `bot`, that Docker answers and that Ollama is off, starts the Kind
   node, then waits (up to 10 minutes) until every Argo CD app is Synced and Healthy.
4. In a second Terminal tab on the workstation, open the tunnel and leave it running:

   ```bash
   ssh -N -L 8443:127.0.0.1:443 lab
   ```

5. Browse to the lab on port 8443:

   | Host | What |
   | --- | --- |
   | `https://argocd.sortedvtg.lan:8443` | Argo CD |
   | `https://grafana.sortedvtg.lan:8443` | Grafana, user `admin`; password below |
   | `https://mail.sortedvtg.lan:8443/dev/` and `/prod/` | Mailpit, the email catcher |
   | `https://auth.sortedvtg.lan:8443` | Keycloak |
   | `https://dev.sortedvtg.lan:8443`, `https://prod.sortedvtg.lan:8443` | the marketplace (from Sprint 2) |

   Grafana's admin password is random, made by Terraform. Print it on the lab host as `bot` when you
   need it (it goes to your terminal only, so don't paste it anywhere):

   ```bash
   kubectl --context kind-sorted-vintage -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
   ```

## End a session

On the lab host as `bot`:

```bash
cd ~/Sorted-Vintage/src/sorted-vintage-infra && make down
```

`make down` only reads the cluster (research R14). For every Postgres cluster it checks that WAL
archiving is healthy and no WAL file is waiting, waits 60 seconds (`archive_timeout`) so a recent
write is archived, checks again, and then stops the Kind node. If an archive is behind or failing
it waits up to 5 minutes, then stops with an error and leaves the lab running. Do not stop Docker
Desktop or shut the lab host down until `make down` says `lab is down`.

Then close the tunnel (Ctrl-C) and, if you like, start Ollama again.

`make backups-check` runs the same checks without stopping anything.

## Other commands

| Command | Does |
| --- | --- |
| `make status` | the node's state and every Argo CD app |
| `make rebuild` | `terraform apply` for `cluster`, then `bootstrap`, then waits (up to 20 minutes) for every app; Terraform asks before each apply. State and `secrets.auto.tfvars` are in `~/sv-terraform` (mode 700), shared with the Jenkins pipeline |
| `make destroy` | `terraform destroy` for `bootstrap`, then `cluster`; Garage data in `~/sv-data` is kept |

## Jenkins (from Ticket 1.7)

Jenkins runs on the workstation as its Jenkins account and is started only for a session, from the
everyday account ([jenkins.md](./jenkins.md)):

```bash
sudo launchctl kickstart system/com.sortedvintage.jenkins
```
```bash
sudo launchctl kill TERM system/com.sortedvintage.jenkins
```

## If something goes wrong

| Symptom | Check |
| --- | --- |
| `make up`: "Docker does not answer" | Is `bot` logged in at the lab host's screen, and Docker Desktop running? |
| `make up`: "Ollama is running" | Quit Ollama in the admin account. |
| `make up` times out on apps | `make status`; the apps not Synced/Healthy are listed. Open Argo CD for the reason. |
| `make down`: "archives are not current" | `make backups-check` shows which cluster; check its Postgres pod and Garage in that namespace. Leave the lab running until it passes. |
| Browser shows a certificate warning | The mkcert root CA is not trusted on the workstation yet (see setup), or the URL lacks `:8443`. |
| Browser cannot connect | Is the tunnel running? Does `/etc/hosts` have the name? |
