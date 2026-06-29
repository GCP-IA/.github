#!/usr/bin/env bash
set -euo pipefail

if [ -z "${VERCEL_TOKEN:-}" ]; then
  echo "::error::Falta configurar VERCEL_TOKEN o VERCEL_TOKEN_SECRET."
  exit 1
fi

if [ -z "${RESOLVED_PROJECT_ID:-}" ] || [ -z "${VERCEL_TEAM_ID:-}" ]; then
  echo "::error::No se recibio project_id/team_id desde el auto-aprovisionamiento de Vercel."
  exit 1
fi

mkdir -p .vercel
jq -n \
  --arg orgId "$VERCEL_TEAM_ID" \
  --arg projectId "$RESOLVED_PROJECT_ID" \
  '{orgId: $orgId, projectId: $projectId}' > .vercel/project.json

commit_author_name=$(git show -s --format=%an HEAD 2>/dev/null || true)
commit_author_email=$(git show -s --format=%ae HEAD 2>/dev/null || true)
commit_sha=$(git rev-parse HEAD 2>/dev/null || true)
deploy_log=$(mktemp)
set +e
npx --yes vercel@latest deploy --prod --yes --no-wait --token "$VERCEL_TOKEN" \
  --meta "githubCommitSha=$commit_sha" \
  --meta "githubCommitAuthorName=$commit_author_name" \
  --meta "githubCommitAuthorEmail=$commit_author_email" 2>&1 | tee "$deploy_log"
deploy_code=${PIPESTATUS[0]}
set -e

deployment_url=$(grep -Eo 'https://[^[:space:]]+\.vercel\.app[^[:space:]]*' "$deploy_log" | tail -n 1 || true)

if [ "$deploy_code" -ne 0 ]; then
  if grep -qi "permission to create a Production Deployment" "$deploy_log"; then
    echo "::error::Vercel rechazo el despliegue de produccion. El token configurado no tiene permiso para crear Production Deployments en este proyecto/team."
  fi
  if grep -qi "commit email" "$deploy_log"; then
    echo "::error::Vercel bloqueo el deployment porque el email del commit no coincide con una cuenta GitHub. Corrige git config user.email usando un email verificado de GitHub y vuelve a publicar."
  fi
  exit "$deploy_code"
fi

if [ -z "$deployment_url" ]; then
  echo "::warning::El deploy finalizo, pero no se pudo extraer la URL publica desde la salida de Vercel CLI."
else
  echo "deployment_url=$deployment_url" >> "$GITHUB_OUTPUT"
  echo "::notice::Deploy publicado en $deployment_url"
fi
