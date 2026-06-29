#!/usr/bin/env bash
set -euo pipefail

if [ -z "${VERCEL_TOKEN:-}" ]; then
  echo "::error::Falta configurar VERCEL_TOKEN o VERCEL_TOKEN_SECRET."
  exit 1
fi

if [ -z "${VERCEL_TEAM_ID:-}" ]; then
  echo "::error::Falta configurar VERCEL_TEAM_ID o VERCEL_ORG_ID con el ID del team de Vercel."
  exit 1
fi

PROJECT_NAME=$(printf '%s' "$REPO_NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')

if [ -z "$PROJECT_NAME" ]; then
  echo "::error::No se pudo derivar un nombre valido de proyecto Vercel desde el repositorio: $REPO_NAME"
  exit 1
fi

echo "Consultando proyecto Vercel: $PROJECT_NAME"

project_response=$(mktemp)
http_code=$(curl -sS -o "$project_response" -w "%{http_code}" \
  -H "Authorization: Bearer $VERCEL_TOKEN" \
  "https://api.vercel.com/v9/projects/$PROJECT_NAME?teamId=$VERCEL_TEAM_ID")

if [ "$http_code" = "200" ]; then
  PROJECT_ID=$(jq -r '.id // empty' "$project_response")
  if [ -z "$PROJECT_ID" ]; then
    echo "::error::La API encontro el proyecto, pero no devolvio un ID."
    cat "$project_response"
    exit 1
  fi
  echo "::notice::Proyecto existente encontrado en Vercel."
elif [ "$http_code" = "404" ]; then
  echo "::notice::El proyecto no existe. Creandolo automaticamente en Vercel."
  create_payload=$(jq -n --arg name "$PROJECT_NAME" '{name: $name}')
  create_response=$(mktemp)
  create_code=$(curl -sS -o "$create_response" -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $VERCEL_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$create_payload" \
    "https://api.vercel.com/v11/projects?teamId=$VERCEL_TEAM_ID")

  if [ "$create_code" != "200" ] && [ "$create_code" != "201" ]; then
    echo "::error::Fallo al crear el proyecto en Vercel mediante la API. HTTP $create_code"
    cat "$create_response"
    exit 1
  fi

  PROJECT_ID=$(jq -r '.id // empty' "$create_response")
  if [ -z "$PROJECT_ID" ]; then
    echo "::error::Vercel creo/respondio el proyecto, pero no devolvio un ID."
    cat "$create_response"
    exit 1
  fi
  echo "::notice::Proyecto creado exitosamente en Vercel."
elif [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
  echo "::error::Vercel rechazo el token para el team/scope configurado. Revisa que VERCEL_TOKEN tenga acceso al equipo correcto y que VERCEL_TEAM_ID apunte a ese mismo team."
  cat "$project_response"
  exit 1
else
  echo "::error::Error consultando Vercel API. HTTP $http_code"
  cat "$project_response"
  exit 1
fi

echo "project_id=$PROJECT_ID" >> "$GITHUB_OUTPUT"
echo "project_name=$PROJECT_NAME" >> "$GITHUB_OUTPUT"
