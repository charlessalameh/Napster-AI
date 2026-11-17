# CLAUDE.md — Napster-style School AI Agent Demo on Azure

Source brief: https://claude.ai/artifact/D1XrbcnXPUE3snnRjNAPuo

## Goal
Public GitHub repo that deploys a voice-enabled "School Front Desk" AI agent on Azure, fully
automated with Terraform + GitHub Actions. Destroyed when idle, back for a demo in a few clicks.
Owner: Charlie Salameh, Cloud Solutions Architect. Supports a technical interview with Napster
Corp (System Engineer / POC), so code quality, security and clarity matter as much as features.

## Demo behaviour
Parent speaks/types a question; agent answers by voice from the school's documents (RAG), refuses
anything not covered, and shows sources and response time (ms).
Napster mapping: browser speech = Azure Speech/realtime audio; chat deployment = Azure OpenAI
realtime + behaviour framework; voice reply = video avatar; Flask `/api/chat` = Omniagent-style
proxy API; AI Search = customer knowledge base; web page = website / kiosk / Teams embed.

## Architecture
- Browser (Chrome/Edge Web Speech API) -> App Service (Flask, gunicorn) `/api/chat`.
- Backend: hybrid (keyword + vector) query on AI Search index `school`, then top chunks + question
  to an Azure OpenAI chat deployment.
- Index built from Blob container `school-docs` by an AI Search indexer with an Azure OpenAI
  embedding skill (`text-embedding-3-small`) and integrated vectorizer.
- One resource group, one region (default `swedencentral`; needs a current mini chat model and
  `text-embedding-3-small`).

## Decisions already made
- IaC: Terraform (not Bicep), azurerm provider, remote state in a separate storage account.
- CI/CD: GitHub Actions, Azure login via OIDC federated credential (no secrets in GitHub).
- Service auth: Managed Identity + RBAC, no keys. Web app: Cognitive Services OpenAI User (AOAI),
  Search Index Data Reader (Search). Search service: Storage Blob Data Reader (storage),
  Cognitive Services OpenAI User (AOAI).
- Search index/data source/skillset/indexer created by a bootstrap step via the AI Search REST API
  after `terraform apply` (azurerm does not manage them).
- Workflows: `deploy.yml` (dispatch: plan, apply, bootstrap index, deploy app, smoke test) and
  `destroy.yml` (dispatch with confirmation input).
- Cost: App Service B1, AI Search Basic (or Free), small TPM, destroy when idle.

## Build order
1. Scaffold + README with architecture. **(done)**
2. `infra/bootstrap-state` + `scripts/setup-oidc.sh` (one-time, run locally with `az login`).
3. Main Terraform: resources, model deployments, identities, RBAC, app settings (endpoints/names
   only), Application Insights.
4. `search/*.json` + `bootstrap-search.sh`: data source (MI connection), skillset (split + AOAI
   embedding), index with `text_vector` + vectorizer, indexer; wait for success.
5. Flask app using `DefaultAzureCredential` for AOAI and Search; system prompt restricts answers
   to sources, short spoken replies, same language as the question.
6. `deploy.yml` + `destroy.yml`; smoke test asks "How much is the school bus?" expects AED 7,000.
7. Optional: Entra Easy Auth, Private Endpoints + VNet integration behind a variable flag.

## Acceptance tests
- "How much is the school bus?" -> AED 7,000, cites fees-transport.txt.
- "What documents do I need for admission?" -> lists the documents.
- "Do you have a swimming pool?" -> says it doesn't know, suggests contacting admissions.
- Pressing Speak while the agent talks stops its speech (barge-in).
- Full `destroy` then `deploy` works from a clean subscription with no manual steps.

## Working notes
- Charlie is strong on Azure/AWS/Terraform/infra, less on Python: keep Python simple, well commented.
- Never commit secrets, keys or tfstate.
- Check current Azure OpenAI model names/versions/API versions on Microsoft Learn before pinning.
- Use variables for region, name prefix, model names and SKUs (e.g. re-point to UAE North).
