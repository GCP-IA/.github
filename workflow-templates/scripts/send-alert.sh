#!/usr/bin/env bash
set -euo pipefail

if [ -z "${SECURITY_ALERT_WEBHOOK_URL:-}" ]; then
  echo "::warning::SECURITY_ALERT_WEBHOOK_URL no configurado; no se pudo enviar alerta externa."
  exit 0
fi

repo_name="${ALERT_REPOSITORY#*/}"
owner_user=""
owner_email=""

if [ -f ".github/devsecops-owner.json" ]; then
  owner_user=$(jq -r '.user // empty' .github/devsecops-owner.json)
  owner_email=$(jq -r '.email // empty' .github/devsecops-owner.json)
fi

if [ -z "$owner_user" ]; then
  owner_user="${repo_name%%_*}"
  if [ -z "$owner_user" ] || [ "$owner_user" = "$repo_name" ]; then
    owner_user="$ALERT_ACTOR"
  fi
fi

if [ -z "$owner_email" ]; then
  owner_email=""
fi

security_alert_to="ciberseguridad@casapellas.com"
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
  --arg email "$alert_recipients" \
  --arg to "$alert_recipients" \
  --arg subject "$subject" \
  --arg body "$body" \
  --arg vercel_deployment_url "$vercel_deployment_url" \
  --arg vercel_project_name "$vercel_project_name" \
  --arg vercel_project_id "$vercel_project_id" \
  --arg vercel_team_id "$vercel_team_id" \
  '{repository: $repository, actor: $actor, email: $email, workflow: $workflow, ref: $ref, run_url: $run_url, alert_type: $alert_type, type: $alert_type, status: $status, alert_to: $alert_to, owner_email: $owner_email, to: $to, vercel: {deployment_url: $vercel_deployment_url, project_name: $vercel_project_name, project_id: $vercel_project_id, team_id: $vercel_team_id}, deployment_url: $vercel_deployment_url, vercel_project_name: $vercel_project_name, vercel_project_id: $vercel_project_id, vercel_team_id: $vercel_team_id, emailMessage: {To: $email, Subject: $subject, Body: $body}}')

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
