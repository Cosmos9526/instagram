# Automatic deploy

Every push to `main` runs `.github/workflows/deploy.yml`. It connects to the server with a key that is
**restricted to one command** (`/opt/postyar/deploy/update.sh`), which pulls `main`, rebuilds the
`postyar` compose project and checks health. The key cannot open a shell or run anything else.

One-time setup on the server (run once, from your machine):

```bash
ssh infivita 'bash -s' <<'SETUP'
set -e
ssh-keygen -t ed25519 -N "" -C postyar-deploy -f /opt/postyar/.deploy_key >/dev/null
echo "command=\"/opt/postyar/deploy/update.sh\",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty $(cat /opt/postyar/.deploy_key.pub)" >> /root/.ssh/authorized_keys
cat /opt/postyar/.deploy_key   # copy this private key into the GitHub secret DEPLOY_SSH_KEY
rm /opt/postyar/.deploy_key /opt/postyar/.deploy_key.pub
SETUP
```

Then in GitHub → Settings → Secrets and variables → Actions add:
- `DEPLOY_SSH_KEY`: the private key printed above
- `DEPLOY_HOST`: `169.58.112.63`

Manual run: GitHub → Actions → "Deploy to server" → Run workflow.
