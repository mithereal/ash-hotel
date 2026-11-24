#!/usr/bin/env bash
set -euo pipefail

# List your OCI regional VM SSH targets (user@ip)
OCI_NODES=(
  "ubuntu@10.0.1.10"   # US Ashburn
  "ubuntu@10.0.2.10"   # EU Frankfurt
)

APP_NAME="ash_phoenix_starter"
REMOTE_DIR="/opt/${APP_NAME}"
TARBALL="/tmp/${APP_NAME}.tar.gz"

echo "==> 1. Building production Elixir release..."
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --overwrite

echo "==> 2. Packaging release tarball..."
tar -czf "${TARBALL}" -C "_build/prod/rel/${APP_NAME}" .

echo "==> 3. Running Ecto migrations once before rolling restart..."
scp -q "${TARBALL}" "${OCI_NODES[0]}:/tmp/${APP_NAME}.tar.gz"
ssh "${OCI_NODES[0]}" "mkdir -p ${REMOTE_DIR}_next && tar -xzf /tmp/${APP_NAME}.tar.gz -C ${REMOTE_DIR}_next && \
  set -a && source /etc/${APP_NAME}.env && set +a && \
  ${REMOTE_DIR}_next/bin/${APP_NAME} eval 'AshPhoenixStarter.Release.migrate()'"

echo "==> 4. Performing rolling restart across OCI cluster..."
for NODE in "${OCI_NODES[@]}"; do
  echo "--> Deploying to ${NODE}..."
  scp -q "${TARBALL}" "${NODE}:/tmp/${APP_NAME}.tar.gz"

  ssh "${NODE}" "
    sudo systemctl stop ${APP_NAME} &&
    rm -rf ${REMOTE_DIR} &&
    mkdir -p ${REMOTE_DIR} &&
    tar -xzf /tmp/${APP_NAME}.tar.gz -C ${REMOTE_DIR} &&
    rm -f /tmp/${APP_NAME}.tar.gz &&
    sudo systemctl start ${APP_NAME}
  "

  echo "--> Waiting 8s for ${NODE} to boot and rejoin libcluster + Horde..."
  sleep 8
done

rm -f "${TARBALL}"
echo "==> Rolling deploy complete across all OCI nodes!"
