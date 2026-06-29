#!/usr/bin/env bash
set -euo pipefail

if [ -f "middleware.js" ] || [ -f "middleware.ts" ]; then
  echo "::notice::Middleware personalizado detectado. Se respeta el archivo existente y no se inyecta firewall."
  echo "middleware_generated=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

cat > middleware.js <<'EOF'
import { NextResponse } from 'next/server';

const CORPORATE_CIDRS = [
  '181.119.102.240/29',
  '186.33.30.96/27',
  '186.1.47.96/27',
];

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

export function middleware(request) {
  const clientIp =
    request.headers.get('x-real-ip') ||
    request.headers.get('x-forwarded-for') ||
    '';

  if (isCorporateIp(clientIp)) {
    return NextResponse.next();
  }

  return NextResponse.json(
    {
      error: 'Security Gate: Acceso Denegado',
      message: 'Este sistema es de uso exclusivo para la red corporativa de Grupo Casa Pellas.',
    },
    { status: 403 }
  );
}

export const config = {
  matcher: '/:path*',
};
EOF

echo "::notice::Edge Firewall corporativo inyectado en middleware.js."
echo "middleware_generated=true" >> "$GITHUB_OUTPUT"
echo "middleware_path=middleware.js" >> "$GITHUB_OUTPUT"
