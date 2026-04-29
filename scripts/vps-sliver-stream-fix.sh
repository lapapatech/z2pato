# =============================================================================
# FIX: Sliver C2 SSL termination via nginx stream block on 51.222.84.105
# =============================================================================

set -e

echo "[1/5] Limpiando sites-enabled y conf.d..."
sudo tee /etc/nginx/sites-enabled/sliver.auth-verify-net.com > /dev/null << 'SITECONF'
# Placeholder - la config real va en nginx.conf nivel superior
SITECONF
sudo rm -f /etc/nginx/conf.d/sliver*.conf

echo "[2/5] Quitando restos de bloques Sliver anteriores..."
sudo sed -i '/^# Sliver C2/,/^stream {$/,/^}$/d' /etc/nginx/nginx.conf
sudo sed -i '/^stream {/,/^}$/d' /etc/nginx/nginx.conf

echo "[3/5] Añadiendo log_format y bloque stream en nginx.conf..."
# Backup
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak.$(date +%Y%m%d%H%M%S)

# Insertar ANTES de la línea "events {"
sudo sed -i '/^events {/i \
# =============================================================================\
# Sliver C2 SSL termination → TCP 31337\
# =============================================================================\
log_format sliver_tcp '\''$remote_addr [$time_local] '\''\
    '\''protocol=$protocol status=$status '\''\
    '\''bytes_sent=$bytes_sent bytes_received=$bytes_received '\''\
    '\''session_time=$session_time'\'';\
\
stream {\
    access_log /var/log/nginx/sliver-access.log sliver_tcp;\
    error_log  /var/log/nginx/sliver-error.log;\
\
    upstream sliver_c2 {\
        server 127.0.0.1:31337;\
    }\
\
    server {\
        listen 443 ssl;\
        server_name sliver.auth-verify-net.com;\
        ssl_certificate     /etc/letsencrypt/live/sliver.auth-verify-net.com/fullchain.pem;\
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

echo "[4/5] Verificando configuracion de nginx..."
sudo nginx -t

echo "[5/5] Recargando nginx y verificando Sliver..."
sudo systemctl reload nginx

echo ""
echo "=== VERIFICACION ==="
echo "Test curl:"
curl -sk --connect-timeout 5 https://sliver.auth-verify-net.com -o /dev/null -w "HTTP:%{http_code}\n"

echo ""
echo "Sliver esta corriendo?"
sudo systemctl status sliver --no-pager 2>/dev/null | head -5 || \
ps aux | grep sliver | grep -v grep | head -3 || echo "Sliver NO esta corriendo"

echo ""
echo "Logs de error recientes:"
sudo tail -5 /var/log/nginx/sliver-error.log 2>/dev/null || echo "(sin errores recientes)"
