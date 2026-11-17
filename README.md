# Napster-style School AI Agent Demo on Azure

A voice-enabled "School Front Desk" AI agent on Azure, deployed with Terraform and
GitHub Actions. Destroy it when idle, bring it back for a demo in a few clicks.

Built as a proof of concept for a System Engineer / POC interview, so code quality,
security and clarity matter as much as the features. See `CLAUDE.md` for the full brief.

## What it does

A parent opens a web page, speaks or types a question (admissions, fees, bus, school day)
and the agent answers by voice from the school's own documents (RAG). It refuses to answer
anything the documents do not cover. Each answer shows its sources and response time in ms.

## Architecture

```
Browser (Web Speech API: speech in/out)
   |  HTTPS
   v
App Service (Flask + gunicorn)  /api/chat
   |  Managed Identity                |  Managed Identity
   v                                  v
Azure AI Search (hybrid query)    Azure OpenAI (chat deployment)
   ^
   |  indexer + embedding skill (text-embedding-3-small)
Blob Storage: school-docs
```

- One resource group, one region (default `swedencentral`).
- No keys anywhere: Managed Identity + RBAC between all services.
- GitHub Actions logs in to Azure with an OIDC federated credential (no client secrets).

| Role | Identity | Scope |
|---|---|---|
| Cognitive Services OpenAI User | web app | Azure OpenAI |
| Search Index Data Reader | web app | AI Search |
| Storage Blob Data Reader | search service | Storage account |
| Cognitive Services OpenAI User | search service | Azure OpenAI |

## Getting started (one-time, run locally)

Needs the Azure CLI, Terraform >= 1.6 and a subscription where you are Owner.

```bash
az login
az account show --query id -o tsv          # your subscription id

# 1. Remote state storage (keyless, Entra ID auth, versioned)
cd infra/bootstrap-state
terraform init
terraform apply -var subscription_id=<SUBSCRIPTION_ID>
# If it fails on the container with a 403, wait a minute (role propagation) and re-run apply.
terraform output -raw storage_account_name

# 2. GitHub OIDC login (no client secret)
cd ../..
./scripts/setup-oidc.sh <github-owner>/<repo> <storage_account_name>
```

The script prints four values; add them as GitHub repository **variables** (they are
identifiers, not secrets). The bootstrap state file stays local and is git-ignored.

## Deploy and destroy (GitHub Actions)

After the one-time setup above and pushing the repo to GitHub (the OIDC login only works for
the repo and `main` branch you gave `setup-oidc.sh`):

1. Actions tab > **deploy** > Run workflow (branch `main`). Tick *plan_only* first if you want
   to see what it would create. It runs plan, apply, search bootstrap, app deploy and the
   smoke test, and prints the demo URL in the run summary (about 10-15 minutes).
2. When finished with the demo: Actions > **destroy** > type `destroy`. The state storage is
   kept, so the next deploy works from scratch with no manual steps.

`scripts/smoke-test.sh <url>` can also be run by hand against any deployed URL.

## Run the app locally (optional)

After a deploy and `scripts/bootstrap-search.sh`, you can run the app on your laptop against
the real Azure services. Your `az login` account needs the OpenAI User and Search Index Data
Reader roles on those resources (the deployer already has Search access; add the OpenAI role
if needed).

```bash
cd app
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export AZURE_OPENAI_ENDPOINT=$(terraform -chdir=../infra output -raw openai_endpoint)
export AZURE_OPENAI_CHAT_DEPLOYMENT=chat
export AZURE_SEARCH_ENDPOINT=$(terraform -chdir=../infra output -raw search_endpoint)
export AZURE_SEARCH_INDEX=school
python app.py          # http://127.0.0.1:8000
```

## Status

Build order (see `CLAUDE.md`):

1. [x] Scaffold repo, README, sample data
2. [x] `infra/bootstrap-state` + `scripts/setup-oidc.sh`
3. [x] Main Terraform
4. [x] `search/*.json` + `scripts/bootstrap-search.sh`
5. [x] Flask app
6. [x] `deploy.yml` / `destroy.yml` + smoke test
7. [x] Optional hardening (Easy Auth, Private Endpoints)

## Hardening (optional, both off by default)

**Sign-in with Entra ID (Easy Auth).** Puts a Microsoft login in front of the whole site; only
people in your own tenant get in. No client secret: the app registration trusts a persistent
managed identity (created in `infra/bootstrap-state`), so nothing expires and nothing is
stored. The web app URL is stable across destroy/deploy, so this is set up once:

```bash
cd infra/bootstrap-state && terraform apply -var subscription_id=<ID>   # creates the identity
cd ../..
./scripts/setup-easyauth.sh https://<web-app>.azurewebsites.net         # url from the deploy summary
```

Add the three printed values as GitHub repository variables (`EASY_AUTH_CLIENT_ID`,
`EASY_AUTH_IDENTITY_ID`, `EASY_AUTH_IDENTITY_CLIENT_ID`) and re-run **deploy**. Delete
`EASY_AUTH_CLIENT_ID` to turn it off. With sign-in on, the smoke test only checks that `/` and
`/api/chat` demand a login; try the agent in a browser.

**Private networking.** Set the repository variable `ENABLE_PRIVATE_NETWORKING` to `true` and
re-run **deploy**. It adds a VNet, VNet integration for the web app, and Private Endpoints
(with private DNS) for Azure OpenAI, AI Search and Blob Storage, so the app's traffic to them
stays on the Microsoft network. (About $22/month for the three endpoints while deployed.)

Known limit, by design: the three services keep their public endpoint (still Entra ID + RBAC
only, keys are off). The deploy pipeline and Search's indexer need it. Closing it fully
means shared private links for the indexer, which needs a higher Search tier.

## Cost control

App Service B1, AI Search Basic (or Free), small TPM on model deployments.
Run the `destroy` workflow when not demoing.
