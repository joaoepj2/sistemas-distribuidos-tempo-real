#!/bin/sh
# Gera /data/sentinel.conf a partir do modelo e inicia o Sentinel.
# Só gera na PRIMEIRA subida: depois disso o próprio Sentinel mantém o
# arquivo atualizado (por exemplo, com o novo primário após um failover).
set -e

CONF=/data/sentinel.conf

if [ ! -f "$CONF" ]; then
  # Na primeira subida o primário pode demorar a ganhar nome na rede Docker.
  # Esperar evita que o Sentinel suba sem conseguir resolver "redis-primario".
  # (Só na primeira vez: depois de um failover o primário pode estar desligado
  # de propósito, e o Sentinel já sabe quem é o primário atual.)
  until redis-cli -h redis-primario -a "$REDIS_PASSWORD" --no-auth-warning ping 2>/dev/null | grep -q PONG; do
    echo "aguardando o nome redis-primario..."
    sleep 1
  done
  sed \
    -e "s/__MASTER_NAME__/${SENTINEL_MASTER_NAME}/g" \
    -e "s/__REDIS_PASSWORD__/${REDIS_PASSWORD}/g" \
    -e "s/__SENTINEL_HOSTNAME__/${SENTINEL_HOSTNAME}/g" \
    /etc/redis/sentinel.conf.template > "$CONF"
  echo "sentinel.conf gerado para ${SENTINEL_HOSTNAME}"
fi

exec redis-sentinel "$CONF"
