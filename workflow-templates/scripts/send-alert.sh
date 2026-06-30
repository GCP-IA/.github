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
commit_author_email=""

if [ -f ".github/devsecops-owner.json" ]; then
  owner_user=$(jq -r '.user // empty' .github/devsecops-owner.json)
  owner_email=$(jq -r '.email // empty' .github/devsecops-owner.json)
  if [ -n "$owner_email" ] && [ "$owner_email" != "null" ] && [[ "$owner_email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
    owner_email_source=".github/devsecops-owner.json"
  else
    owner_email=""
    owner_email_source="invalid_or_missing_devsecops_owner_json"
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
fi

security_alert_to="${SECURITY_ALERT_DEFAULT_TO:-}"
if [ -z "$security_alert_to" ]; then
  echo "::error::SECURITY_ALERT_DEFAULT_TO no configurado; no se puede calcular el destinatario base de la alerta."
  exit 1
fi

if [ -n "$owner_email" ]; then
  alert_recipients="$owner_email"
else
  alert_recipients="$security_alert_to"
  owner_email="$security_alert_to"
  if [ "$owner_email_source" = "missing" ]; then
    owner_email_source="SECURITY_ALERT_DEFAULT_TO"
  else
    owner_email_source="${owner_email_source}->SECURITY_ALERT_DEFAULT_TO"
  fi
fi
alert_type="${ALERT_TYPE:-error}"
alert_status="${ALERT_STATUS:-Fallido}"
vercel_deployment_url="${VERCEL_DEPLOYMENT_URL:-}"
vercel_project_name="${VERCEL_PROJECT_NAME:-}"
vercel_project_id="${VERCEL_PROJECT_ID:-}"
vercel_team_id="${VERCEL_TEAM_ID:-}"
deployment_state="FAILED"

if [ "$alert_type" = "success" ]; then
  deployment_state="READY"
  subject="DevSecOps: despliegue exitoso en $ALERT_REPOSITORY"
  body="El workflow DevSecOps finalizo correctamente en $ALERT_REPOSITORY. Proyecto Vercel: $vercel_project_name ($vercel_project_id). URL: $vercel_deployment_url. Run: $ALERT_RUN_URL"
else
  subject="Alerta DevSecOps: fallo en $ALERT_REPOSITORY"
  body="El workflow DevSecOps fallo en $ALERT_REPOSITORY. Proyecto Vercel: $vercel_project_name ($vercel_project_id). URL: $vercel_deployment_url. Run: $ALERT_RUN_URL"
fi

payload=$(jq -n \
  --arg repository "$ALERT_REPOSITORY" \
  --arg actor "$ALERT_ACTOR" \
  --arg workflow "$ALERT_WORKFLOW" \
  --arg run_url "$ALERT_RUN_URL" \
  --arg ref "$ALERT_REF" \
  --arg alert_type "$alert_type" \
  --arg status "$alert_status" \
  --arg deployment_state "$deployment_state" \
  --arg alert_to "$security_alert_to" \
  --arg owner_email "$owner_email" \
  --arg owner_email_source "$owner_email_source" \
  --arg commit_author_email "$commit_author_email" \
  --arg email "$alert_recipients" \
  --arg to "$alert_recipients" \
  --arg subject "$subject" \
  --arg body "$body" \
  --arg vercel_deployment_url "$vercel_deployment_url" \
  --arg vercel_project_name "$vercel_project_name" \
  --arg vercel_project_id "$vercel_project_id" \
  --arg vercel_team_id "$vercel_team_id" \
  '{repository: $repository, actor: $actor, email: $email, workflow: $workflow, ref: $ref, run_url: $run_url, alert_type: $alert_type, type: $alert_type, status: $status, deployment_state: $deployment_state, alert_to: $alert_to, owner_email: $owner_email, owner_email_source: $owner_email_source, commit_author_email: $commit_author_email, to: $to, url: $vercel_deployment_url, URL: $vercel_deployment_url, vercel: {deployment_url: $vercel_deployment_url, project_name: $vercel_project_name, project_id: $vercel_project_id, team_id: $vercel_team_id}, deployment_url: $vercel_deployment_url, vercel_project_name: $vercel_project_name, vercel_project_id: $vercel_project_id, vercel_team_id: $vercel_team_id, emailMessage: {To: $email, Subject: $subject, Body: $body}}')

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
