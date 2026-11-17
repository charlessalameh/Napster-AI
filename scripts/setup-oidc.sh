#!/usr/bin/env bash
# One-time: let GitHub Actions log in to Azure with OIDC (no client secret).
# Creates an Entra app registration + service principal, a federated credential for
# your repo, and the role assignments Terraform needs. Safe to re-run.
#
# Usage:  az login
#         ./scripts/setup-oidc.sh <github-owner>/<repo> <state-storage-account-name>
# Example: ./scripts/setup-oidc.sh csalameh/napster-school-agent-demo schooldemotfab12c
set -euo pipefail

REPO="${1:?Usage: $0 <github-owner>/<repo> <state-storage-account-name>}"
STATE_SA="${2:?Usage: $0 <github-owner>/<repo> <state-storage-account-name>}"
APP_NAME="${APP_NAME:-school-agent-demo-github}"
BRANCH="${BRANCH:-main}"

SUB_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
echo "Subscription: $SUB_ID"
echo "Tenant:       $TENANT_ID"
echo "GitHub repo:  $REPO (branch $BRANCH)"

# 1. App registration (reuse if it already exists)
APP_ID="$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)"
if [[ -z "$APP_ID" ]]; then
  APP_ID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)"
  echo "Created app registration $APP_NAME"
else
  echo "Reusing app registration $APP_NAME"
fi

# 2. Service principal
if [[ -z "$(az ad sp list --filter "appId eq '$APP_ID'" --query '[0].id' -o tsv)" ]]; then
  az ad sp create --id "$APP_ID" >/dev/null
fi
SP_OBJECT_ID="$(az ad sp show --id "$APP_ID" --query id -o tsv)"

# 3. Federated credentials: workflows run by workflow_dispatch on the main branch.
add_federated_credential() {
  local name="$1" subject="$2"
  if [[ -n "$(az ad app federated-credential list --id "$APP_ID" --query "[?name=='$name'].name" -o tsv)" ]]; then
    echo "Federated credential $name already exists"
    return
  fi
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"$name\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"$subject\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" >/dev/null
  echo "Created federated credential $name ($subject)"
}
add_federated_credential "github-$BRANCH" "repo:$REPO:ref:refs/heads/$BRANCH"

# 4. Roles. Contributor creates resources; User Access Administrator lets Terraform
#    create the RBAC role assignments between the services (Managed Identity design).
assign_role() {
  local role="$1" scope="$2"
  if [[ -n "$(az role assignment list --assignee "$SP_OBJECT_ID" --role "$role" --scope "$scope" --query '[0].id' -o tsv)" ]]; then
    echo "Role '$role' already assigned"
  else
    az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal \
      --role "$role" --scope "$scope" >/dev/null
    echo "Assigned '$role' on $scope"
  fi
}
assign_role "Contributor" "/subscriptions/$SUB_ID"
assign_role "User Access Administrator" "/subscriptions/$SUB_ID"

STATE_SA_ID="$(az storage account show --name "$STATE_SA" --query id -o tsv)"
assign_role "Storage Blob Data Contributor" "$STATE_SA_ID"

cat <<EOF

Done. Add these as GitHub repository *variables* (Settings > Secrets and variables >
Actions > Variables). They are identifiers, not secrets:

  AZURE_CLIENT_ID       = $APP_ID
  AZURE_TENANT_ID       = $TENANT_ID
  AZURE_SUBSCRIPTION_ID = $SUB_ID
  TFSTATE_STORAGE_ACCOUNT = $STATE_SA

EOF
