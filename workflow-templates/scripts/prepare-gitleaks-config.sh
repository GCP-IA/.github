#!/usr/bin/env bash
set -euo pipefail

cat > .gitleaks-ci.toml <<'EOF'
title = "Corporate DevSecOps Gitleaks Config - Strict & Comprehensive"

[extend]
useDefault = true

[[rules]]
id = "corporate-strict-hardcoded-secret"
description = "Detects generic hardcoded credentials in English and Spanish, including short or weak values."
regex = '''(?i)(?:secret|token|api[_-]?key|access[_-]?key|client[_-]?secret|private[_-]?key|password|passwd|pwd|llave|clave|contrasena|secreto)[A-Za-z0-9_-]*\s*[:=]\s*['"`]([A-Za-z0-9_./+=:@-]{4,})['"`]'''
secretGroup = 1
keywords = [
  "secret",
  "token",
  "api_key",
  "apikey",
  "access_key",
  "client_secret",
  "private_key",
  "password",
  "passwd",
  "pwd",
  "llave",
  "clave",
  "contrasena",
  "secreto"
]

[[rules]]
id = "corporate-jwt-fragment"
description = "Detecta fragmentos de JWT (como los tokens de Supabase), incluso si están divididos en arreglos o concatenados."
# La cadena eyJhbGciOi es la codificación en Base64 de '{"alg":', la cual es casi universal en el encabezado de los JWTs modernos.
regex = '''['"`](eyJhbGciOi[A-Za-z0-9_-]{10,})['"`]'''
secretGroup = 1
keywords = [
  "eyJhbGciOi"
]

[[rules]]
id = "corporate-obfuscated-array"
description = "Detecta asignaciones sospechosas de arreglos a variables que normalmente contienen credenciales."
regex = '''(?i)(?:anon[_-]?key|supabase[_-]?key|secret|token|api[_-]?key|password|clave)\s*[:=]\s*\[\s*['"`]'''
secretGroup = 0
keywords = [
  "anonKey",
  "anon_key",
  "supabase",
  "secret",
  "token",
  "api_key",
  "clave"
]

[allowlist]
description = "Lista blanca corporativa para evitar falsos positivos comunes en el entorno de desarrollo."
paths = [
  '''\.github/workflows/.*''',
  '''\.gitleaks-ci\.toml'''
]
regexes = [
  '''(?i)placeholder''',
  '''(?i)example''',
  '''(?i)dummy''',
  '''(?i)test-token'''
]
EOF
