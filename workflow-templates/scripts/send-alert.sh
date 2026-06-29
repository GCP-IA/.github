#!/usr/bin/env bash
set -euo pipefail

if [ -z "${SECURITY_ALERT_WEBHOOK_URL:-}" ]; then
  echo "::warning::SECURITY_ALERT_WEBHOOK_URL no configurado; no se pudo enviar alerta externa."
  exit 0
fi

repo_name="${ALERT_REPOSITORY#*/}"
owner_user=""
owner_email=""
owner_email_source="missing"
github_actor_email=""
commit_author_email=""

if [ -f ".github/devsecops-owner.json" ]; then
  owner_user=$(jq -r '.user // empty' .github/devsecops-owner.json)
  owner_email=$(jq -r '.email // empty' .github/devsecops-owner.json)
  if [ -n "$owner_email" ]; then
    owner_email_source=".github/devsecops-owner.json"
  fi
fi

if [ -z "$owner_user" ]; then
  owner_user="${repo_name%%_*}"
  if [ -z "$owner_user" ] || [ "$owner_user" = "$repo_name" ]; then
    owner_user="$ALERT_ACTOR"
  fi
fi

if [ -z "$owner_email" ]; then
  commit_author_email=$(git show -s --format=%ae HEAD 2>/dev/null || true)
  github_user_response=$(mktemp)
  github_headers=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    github_headers=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi
  github_http_code=$(curl -sS -o "$github_user_response" -w "%{http_code}" \
    "${github_headers[@]}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/users/$ALERT_ACTOR" || true)

  if [ "$github_http_code" -ge 200 ] && [ "$github_http_code" -lt 300 ]; then
    github_actor_email=$(jq -r '.email // empty' "$github_user_response")
  fi

  if [ -n "$github_actor_email" ] && [ "$github_actor_email" != "null" ]; then
    owner_email="$github_actor_email"
    owner_email_source="github_actor_public_email"
  else
    owner_email=""
    owner_email_source="missing"
  fi
fi

security_alert_to="${SECURITY_ALERT_DEFAULT_TO:-}"
if [ -z "$security_alert_to" ]; then
  echo "::error::SECURITY_ALERT_DEFAULT_TO no configurado; no se puede calcular el destinatario base de la alerta."
  exit 1
fi

if [ -n "$owner_email" ]; then
  alert_recipients="${security_alert_to};${owner_email}"
else
  alert_recipients="$security_alert_to"
fi
alert_type="${ALERT_TYPE:-error}"
alert_status="${ALERT_STATUS:-Fallido}"
vercel_deployment_url="${VERCEL_DEPLOYMENT_URL:-}"
vercel_project_name="${VERCEL_PROJECT_NAME:-}"
vercel_project_id="${VERCEL_PROJECT_ID:-}"
vercel_team_id="${VERCEL_TEAM_ID:-}"

if [ "$alert_type" = "success" ]; then
  subject="DevSecOps: despliegue exitoso en $ALERT_REPOSITORY"
  body="El workflow DevSecOps finalizo correctamente en $ALERT_REPOSITORY. Proyecto Vercel: $vercel_project_name ($vercel_project_id). URL: $vercel_deployment_url. Run: $ALERT_RUN_URL"
else
  subject="Alerta DevSecOps: fallo en $ALERT_REPOSITORY"
  body="El workflow DevSecOps fallo en $ALERT_REPOSITORY. Run: $ALERT_RUN_URL"
fi

payload=$(jq -n \
  --arg repository "$ALERT_REPOSITORY" \
  --arg actor "$ALERT_ACTOR" \
  --arg workflow "$ALERT_WORKFLOW" \
  --arg run_url "$ALERT_RUN_URL" \
  --arg ref "$ALERT_REF" \
  --arg alert_type "$alert_type" \
  --arg status "$alert_status" \
  --arg alert_to "$security_alert_to" \
  --arg owner_email "$owner_email" \
  --arg owner_email_source "$owner_email_source" \
  --arg github_actor_email "$github_actor_email" \
  --arg commit_author_email "$commit_author_email" \
  --arg email "$alert_recipients" \
  --arg to "$alert_recipients" \
  --arg subject "$subject" \
  --arg body "$body" \
  --arg vercel_deployment_url "$vercel_deployment_url" \
  --arg vercel_project_name "$vercel_project_name" \
  --arg vercel_project_id "$vercel_project_id" \
  --arg vercel_team_id "$vercel_team_id" \
  '{repository: $repository, actor: $actor, email: $email, workflow: $workflow, ref: $ref, run_url: $run_url, alert_type: $alert_type, type: $alert_type, status: $status, alert_to: $alert_to, owner_email: $owner_email, owner_email_source: $owner_email_source, github_actor_email: $github_actor_email, commit_author_email: $commit_author_email, to: $to, vercel: {deployment_url: $vercel_deployment_url, project_name: $vercel_project_name, project_id: $vercel_project_id, team_id: $vercel_team_id}, deployment_url: $vercel_deployment_url, vercel_project_name: $vercel_project_name, vercel_project_id: $vercel_project_id, vercel_team_id: $vercel_team_id, emailMessage: {To: $email, Subject: $subject, Body: $body}}')

response_file=$(mktemp)
http_code=$(curl -sS -o "$response_file" -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -d "$payload" \
  "$SECURITY_ALERT_WEBHOOK_URL")

if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
  echo "::error::El webhook SECURITY_ALERT_WEBHOOK_URL respondio HTTP $http_code."
  cat "$response_file"
  exit 1
fi

echo "::notice::Alerta enviada correctamente a Power Automate."
