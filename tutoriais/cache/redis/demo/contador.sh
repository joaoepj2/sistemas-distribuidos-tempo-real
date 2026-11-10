#!/bin/sh
# Cliente de demonstração: escreve no Redis uma vez por segundo.
# A cada volta ele PERGUNTA AO SENTINEL quem é o primário atual,
# como faria uma aplicação real (bibliotecas como redis-py e Jedis fazem isso).
# Durante o failover as escritas falham por alguns segundos e depois voltam,
# agora em outro nó.
#
# Uso: docker compose exec sentinel1 sh /demo/contador.sh

MASTER_NAME="${SENTINEL_MASTER_NAME:-mymaster}"

while true; do
  # Resposta do Sentinel: duas linhas, host e porta
  ENDERECO=$(redis-cli -p 26379 SENTINEL get-master-addr-by-name "$MASTER_NAME" | tr '\n' ' ')
  HOST=$(echo "$ENDERECO" | cut -d' ' -f1)
  PORTA=$(echo "$ENDERECO" | cut -d' ' -f2)

  VALOR=$(timeout 2 redis-cli -h "$HOST" -p "$PORTA" -a "$REDIS_PASSWORD" --no-auth-warning \
          INCR demo:contador 2>&1)

  case "$VALOR" in
    ''|*[!0-9]*) echo "$(date +%H:%M:%S)  primário=$HOST  ERRO: ${VALOR:-sem resposta}" ;;
    *)           echo "$(date +%H:%M:%S)  primário=$HOST  contador=$VALOR" ;;
  esac
  sleep 1
done
