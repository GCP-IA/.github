#!/usr/bin/env bash
set -euo pipefail

if [ -z "${VERCEL_TOKEN:-}" ]; then
  echo "::error::Falta configurar VERCEL_TOKEN o VERCEL_TOKEN_SECRET."
  exit 1
fi

if [ -z "${RESOLVED_PROJECT_ID:-}" ]; then
  echo "::error::No se recibio project_id desde el auto-aprovisionamiento de Vercel."
  exit 1
fi

if [ -z "${VERCEL_TEAM_ID:-}" ]; then
  echo "::error::Falta configurar VERCEL_TEAM_ID o VERCEL_ORG_ID para el deploy en Vercel."
  exit 1
fi

resolved_project_name="${RESOLVED_PROJECT_NAME:-}"

echo "project_id=$RESOLVED_PROJECT_ID" >> "$GITHUB_OUTPUT"
echo "project_name=$resolved_project_name" >> "$GITHUB_OUTPUT"

mkdir -p .vercel
jq -n \
  --arg orgId "$VERCEL_TEAM_ID" \
  --arg projectId "$RESOLVED_PROJECT_ID" \
  '{orgId: $orgId, projectId: $projectId}' > .vercel/project.json

commit_author_name=$(git show -s --format=%an HEAD 2>/dev/null || true)
commit_author_email=$(git show -s --format=%ae HEAD 2>/dev/null || true)
commit_sha=$(git rev-parse HEAD 2>/dev/null || true)
pull_log=$(mktemp)
build_log=$(mktemp)
deploy_stdout=$(mktemp)
deploy_stderr=$(mktemp)

if [ -f package.json ] && grep -q '"packageManager"[[:space:]]*:[[:space:]]*"pnpm@' package.json; then
  pnpm_version=$(node -e "const pkg=require('./package.json'); const pm=pkg.packageManager || ''; console.log(pm.startsWith('pnpm@') ? pm.slice(5) : 'latest')")

  echo "::group::Preparar pnpm"
  echo "Proyecto pnpm detectado. Activando pnpm@$pnpm_version para Vercel build..."
  corepack enable || true
  if ! corepack prepare "pnpm@$pnpm_version" --activate; then
    npm install -g "pnpm@$pnpm_version"
  fi
  pnpm --version
  echo "::endgroup::"
fi

echo "::group::Vercel pull"
npx --yes vercel@latest pull --yes --environment=production --token "$VERCEL_TOKEN" 2>&1 | tee "$pull_log"
echo "::endgroup::"

echo "::group::Vercel build"
npx --yes vercel@latest build --prod --token "$VERCEL_TOKEN" 2>&1 | tee "$build_log"
echo "::endgroup::"

echo "::group::Vercel deploy prebuilt"
set +e
npx --yes vercel@latest deploy --prebuilt --prod --yes --token "$VERCEL_TOKEN" \
  --meta "githubCommitSha=$commit_sha" \
  --meta "githubCommitAuthorName=$commit_author_name" \
  --meta "githubCommitAuthorEmail=$commit_author_email" \
  >"$deploy_stdout" 2>"$deploy_stderr"
deploy_code=$?
set -e
cat "$deploy_stderr" >&2
cat "$deploy_stdout"
echo "::endgroup::"

deployment_url=$(grep -Eo 'https://[^[:space:]]+\.vercel\.app' "$deploy_stdout" | tail -n 1 || true)

if [ -n "$deployment_url" ]; then
  echo "deployment_url=$deployment_url" >> "$GITHUB_OUTPUT"
fi

if [ "$deploy_code" -ne 0 ]; then
  if grep -qi "permission to create a Production Deployment" "$deploy_stderr"; then
    echo "::error::Vercel rechazo el despliegue de produccion. El token configurado no tiene permiso para crear Production Deployments en este proyecto/team."
  fi
  if grep -qi "commit email" "$deploy_stderr"; then
    echo "::error::Vercel bloqueo el deployment porque el email del commit no coincide con una cuenta GitHub. Corrige git config user.email usando un email verificado de GitHub y vuelve a publicar."
  fi
  exit "$deploy_code"
fi

if [ -z "$deployment_url" ]; then
  echo "::error::Vercel acepto el deploy, pero no se pudo extraer la URL publica desde la salida de Vercel CLI."
  exit 1
fi

echo "deployment_url=$deployment_url" >> "$GITHUB_OUTPUT"
echo "::notice::Deploy publicado correctamente en $deployment_url"
exit 0
