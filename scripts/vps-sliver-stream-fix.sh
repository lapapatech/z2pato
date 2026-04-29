#!/bin/bash
# =============================================================================
# FIX: Sliver C2 SSL termination via nginx stream block on 51.222.84.105
# =============================================================================

set -e

echo "[1/4] Limpiando sites-enabled (el stream NO va ahí)..."
sudo tee /etc/nginx/sites-enabled/sliver.auth-verify-net.com > /dev/null << 'EOF'
# Stream config movida a nginx.conf nivel superior
EOF

echo "[2/4] Verificando que no haya config stream residual en conf.d..."
sudo rm -f /etc/nginx/conf.d/sliver*.conf 2>/dev/null || true

echo "[3/4] Añadiendo bloque 'stream' al final de nginx.conf (antes de #mail)..."
# Eliminar bloque stream anterior si existe (por si hay restos)
sudo sed -i '/^# Sliver C2 SSL termination/,/^}$/d' /etc/nginx/nginx.conf

# Añadir el bloque stream justo antes de la línea "#mail {"
sudo sed -i '/^#mail {/i \
# Sliver C2 SSL termination → TCP 31337\
stream {\
    access_log /var/log/nginx/sliver-access.log;\
    error_log /var/log/nginx/sliver-error.log;\
\
    upstream sliver_c2 {\
        server 127.0.0.1:31337;\
    }\
\
    server {\
        listen 443 ssl;\
        server_name sliver.auth-verify-net.com;\
        ssl_certificate /etc/letsencrypt/live/sliver.auth-verify-net.com/fullchain.pem;\
        ssl_certificate_key /etc/letsencrypt/live/sliver.auth-verify-net.com/privkey.pem;\
        include /etc/letsencrypt/options-ssl-nginx.conf;\
        ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;\
        proxy_pass sliver_c2;\
        proxy_ssl off;\
        proxy_connect_timeout 86400s;\
        proxy_timeout 86400s;\
        tcp_nodelay on;\
    }\
}\
' /etc/nginx/nginx.conf

echo "[4/4] Testeando y recargando nginx..."
sudo nginx -t && sudo systemctl reload nginx

echo ""
echo "=== VERIFICACION ==="
echo "Test curl:"
curl -sk --connect-timeout 5 https://sliver.auth-verify-net.com -o /dev/null -w "HTTP:%{http_code}\n"

echo ""
echo "Estado de nginx:"
sudo systemctl status nginx --no-pager | head -5

echo ""
echo "Logs de error recientes:"
sudo tail -5 /var/log/nginx/sliver-error.log 2>/dev/null || echo "(sin errores recientes)"
