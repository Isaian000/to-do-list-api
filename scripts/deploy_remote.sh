#!/bin/bash
# Se ejecuta EN la EC2 vía SSH desde deploy.yml.
# Uso: deploy_remote.sh <tag> <owner/repo> <puerto>
set -euo pipefail

TAG="$1"
REPO="$2"
PORT="${3:-8000}"
BASE=/opt/todo-api
DEST="$BASE/releases/$TAG"
ZIP_URL="https://github.com/$REPO/releases/download/$TAG/todo-api-$TAG.zip"

echo ">> Descargando $ZIP_URL"
TMP=$(mktemp -d)
curl -fsSL -o "$TMP/app.zip" "$ZIP_URL"

rm -rf "$DEST"
mkdir -p "$DEST"
unzip -q "$TMP/app.zip" -d "$DEST"
rm -rf "$TMP"

echo ">> Instalando dependencias"
"$BASE/venv/bin/pip" install -q -r "$DEST/src/requirements.txt"

echo ">> Activando $TAG"
ln -sfn "$DEST" "$BASE/current"
sudo sed -i "s/^APP_VERSION=.*/APP_VERSION=$TAG/" /etc/todo-api.env
sudo systemctl restart todo-api

for i in $(seq 1 15); do
  if curl -fsS "http://localhost:$PORT/version" | grep -q "\"$TAG\""; then
    echo ">> $TAG corriendo"
    # conservar solo los 3 releases más recientes
    ls -1dt "$BASE"/releases/v* 2>/dev/null | tail -n +4 | xargs -r rm -rf
    exit 0
  fi
  sleep 2
done

echo ">> El servicio no respondió con $TAG"
sudo journalctl -u todo-api -n 50 --no-pager
exit 1
