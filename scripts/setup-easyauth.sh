#!/usr/bin/env bash
# One-time (optional hardening): create the Entra app registration for "Sign in with Entra ID"
# on the web app (App Service Easy Auth), and let it trust the persistent managed identity
# from infra/bootstrap-state instead of a client secret. Safe to re-run.
#
# Run it by YOU (needs permission to create app registrations), after `az login` and after
# `terraform apply` in infra/bootstrap-state (which creates the identity).
#
# Usage: ./scripts/setup-easyauth.sh <web-app-url>
#   e.g. ./scripts/setup-easyauth.sh https://schooldemo-1a2b3-web.azurewebsites.net
# The URL is stable across destroy -> deploy, so this is needed only once.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB_URL="${1:?Usage: $0 <web-app-url>}"
WEB_URL="${WEB_URL%/}"
APP_NAME="${APP_NAME:-school-agent-demo-web}"
REDIRECT_URI="$WEB_URL/.auth/login/aad/callback"

BOOT="$ROOT/infra/bootstrap-state"
IDENTITY_ID="$(terraform -chdir="$BOOT" output -raw easyauth_identity_id)"
IDENTITY_CLIENT_ID="$(terraform -chdir="$BOOT" output -raw easyauth_identity_client_id)"
IDENTITY_PRINCIPAL_ID="$(terraform -chdir="$BOOT" output -raw easyauth_identity_principal_id)"
TENANT_ID="$(az account show --query tenantId -o tsv)"

echo "Redirect URI: $REDIRECT_URI"

# 1. App registration: single tenant = only people from your own directory can sign in.
APP_ID="$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)"
if [[ -z "$APP_ID" ]]; then
  APP_ID="$(az ad app create --display-name "$APP_NAME" --sign-in-audience AzureADMyOrg \
    --web-redirect-uris "$REDIRECT_URI" --enable-id-token-issuance true --query appId -o tsv)"
  echo "Created app registration $APP_NAME"
else
  az ad app update --id "$APP_ID" --web-redirect-uris "$REDIRECT_URI" --enable-id-token-issuance true
  echo "Updated app registration $APP_NAME"
fi

# 2. Service principal (so people can sign in to it).
if [[ -z "$(az ad sp list --filter "appId eq '$APP_ID'" --query '[0].id' -o tsv)" ]]; then
  az ad sp create --id "$APP_ID" >/dev/null
fi

# 3. Trust the managed identity: it proves the app's identity in place of a client secret.
CRED_NAME="web-app-managed-identity"
if az ad app federated-credential list --id "$APP_ID" --query "[?name=='$CRED_NAME'].name" -o tsv | grep -q .; then
  echo "Federated credential already exists"
else
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"$CRED_NAME\",
    \"issuer\": \"https://login.microsoftonline.com/$TENANT_ID/v2.0\",
    \"subject\": \"$IDENTITY_PRINCIPAL_ID\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" >/dev/null
  echo "Created federated credential"
fi

cat <<EOF

Done. Add these as GitHub repository variables, then re-run the deploy workflow:

  EASY_AUTH_CLIENT_ID          = $APP_ID
  EASY_AUTH_IDENTITY_ID        = $IDENTITY_ID
  EASY_AUTH_IDENTITY_CLIENT_ID = $IDENTITY_CLIENT_ID

(Local terraform runs: -var enable_easy_auth=true plus the three easy_auth_* variables.)
Removing EASY_AUTH_CLIENT_ID switches sign-in off again.

EOF
