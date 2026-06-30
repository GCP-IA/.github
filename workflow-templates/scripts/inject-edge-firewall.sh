#!/usr/bin/env bash
set -euo pipefail

if [ -f "middleware.js" ] || [ -f "middleware.ts" ]; then
  echo "::notice::Middleware personalizado detectado. Se respeta el archivo existente y no se inyecta firewall."
  echo "middleware_generated=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

if [ -z "${ALLOWED_CIDRS:-}" ]; then
  echo "::error::La variable ALLOWED_CIDRS no está definida o está vacía. Configúrala en GitHub Variables."
  exit 1
fi

cat > middleware.js <<EOF
// IPs corporativas inyectadas dinámicamente por GitHub Actions
const CORPORATE_CIDRS_STRING = "${ALLOWED_CIDRS}";
const CORPORATE_CIDRS = CORPORATE_CIDRS_STRING.split(',').map(ip => ip.trim());
EOF

cat >> middleware.js <<'EOF'

function ipToLong(ip) {
  const cleanIp = String(ip || '').split(',')[0].trim();

  if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(cleanIp)) {
    return null;
  }

  const parts = cleanIp.split('.').map(Number);

  if (parts.some((part) => part < 0 || part > 255)) {
    return null;
  }

  return parts.reduce((acc, part) => ((acc << 8) + part) >>> 0, 0);
}

function cidrToRange(cidr) {
  const [baseIp, prefixText] = cidr.split('/');
  const baseLong = ipToLong(baseIp);
  const prefix = Number(prefixText);

  if (baseLong === null || Number.isNaN(prefix) || prefix < 0 || prefix > 32) {
    return null;
  }

  const mask = prefix === 0 ? 0 : (0xffffffff << (32 - prefix)) >>> 0;
  const start = baseLong & mask;
  const end = start | (~mask >>> 0);

  return { start: start >>> 0, end: end >>> 0 };
}

function isCorporateIp(ip) {
  const ipLong = ipToLong(ip);

  if (ipLong === null) {
    return false;
  }

  return CORPORATE_CIDRS.some((cidr) => {
    const range = cidrToRange(cidr);
    return range && ipLong >= range.start && ipLong <= range.end;
  });
}

export default function middleware(request) {
  const clientIp =
    request.headers.get('x-real-ip') ||
    request.headers.get('x-forwarded-for') ||
    '';

  if (isCorporateIp(clientIp)) {
    return;
  }

  return new Response(
    `<!DOCTYPE html>
    <html lang="es">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Acceso Denegado</title>
      <style>
        body { font-family: system-ui, sans-serif; background-color: #f3f4f6; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .container { background-color: white; padding: 2rem; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); text-align: center; max-width: 400px; }
        h1 { color: #dc2626; font-size: 1.5rem; margin-bottom: 1rem; }
        p { color: #4b5563; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>Security Gate: Acceso Denegado</h1>
        <p>Este sistema es de uso exclusivo para la red corporativa de Grupo Casa Pellas.</p>
      </div>
    </body>
    </html>`,
    {
      status: 403,
      headers: {
        'content-type': 'text/html; charset=utf-8',
      },
    }
  );
}

export const config = {
  matcher: '/:path*',
};
EOF

echo "::notice::Edge Firewall corporativo inyectado en middleware.js."
echo "middleware_generated=true" >> "$GITHUB_OUTPUT"
echo "middleware_path=middleware.js" >> "$GITHUB_OUTPUT"
