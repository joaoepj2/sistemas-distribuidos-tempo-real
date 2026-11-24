#!/bin/sh
set -eu
: "${DNS_PRIMARY_IP:?Informe o IP do primario na rede do laboratorio}"
: "${DNS_SECONDARY_IP:?Informe o IP do secundario na rede do laboratorio}"
DNS_PORT=${DNS_PORT:-53}
falhar() { echo "FALHOU: $*" >&2; exit 1; }
consultar() { dig +time=1 +tries=1 -p "$DNS_PORT" "$@"; }
igual() { [ "$1" = "$2" ] || falhar "$3: esperado '$2', recebido '$1'"; }
verificar_servidor() {
    servidor=$1
    tentativas=0
    until [ "$(consultar "@$servidor" app.lab.test A +short 2>/dev/null || true)" = 192.0.2.80 ]; do
        tentativas=$((tentativas+1)); [ "$tentativas" -lt 20 ] || falhar "zona indisponivel em $servidor"; sleep 1
    done
    igual "$(consultar "@$servidor" app.lab.test A +tcp +short)" 192.0.2.80 'A/TCP'
    igual "$(consultar "@$servidor" www.lab.test CNAME +short)" app.lab.test. CNAME
    igual "$(consultar "@$servidor" _http._tcp.lab.test SRV +short)" '0 5 8080 app.lab.test.' SRV
    igual "$(consultar "@$servidor" lab.test NS +short | sort)" "$(printf 'ns1.lab.test.\nns2.lab.test.')" NS
    resposta=$(consultar "@$servidor" inexistente.lab.test A)
    echo "$resposta" | grep -q 'status: NXDOMAIN' || falhar NXDOMAIN
    echo "$resposta" | grep -Eq 'flags:.* aa[ ;]' || falhar 'resposta nao autoritativa'
    echo "OK: $servidor UDP/TCP, A, CNAME, SRV, NS e NXDOMAIN autoritativo"
}
case "${1:-normal}" in
    normal)
        verificar_servidor "$DNS_PRIMARY_IP"
        verificar_servidor "$DNS_SECONDARY_IP"
        igual "$(consultar "@$DNS_PRIMARY_IP" lab.test SOA +short)" "$(consultar "@$DNS_SECONDARY_IP" lab.test SOA +short)" 'SOA replicado'
        igual "$(consultar "@$DNS_PRIMARY_IP" ns1.lab.test A +short)" "$DNS_PRIMARY_IP" 'A do NS primario'
        igual "$(consultar "@$DNS_SECONDARY_IP" ns2.lab.test A +short)" "$DNS_SECONDARY_IP" 'A do NS secundario'
        transferencia=$(consultar "@$DNS_PRIMARY_IP" lab.test AXFR 2>&1 || true)
        echo "$transferencia" | grep -Eq 'Transfer failed|REFUSED' || falhar 'AXFR sem chave nao foi recusado'
        echo 'OK: replicacao pela rede e recusa de AXFR sem chave'
        ;;
    falha)
        if consultar "@$DNS_PRIMARY_IP" app.lab.test A +short >/dev/null 2>&1; then falhar 'o primario ainda responde'; fi
        verificar_servidor "$DNS_SECONDARY_IP"
        echo 'OK: secundario atende pela rede com a instancia primaria indisponivel'
        ;;
    local)
        # Apenas teste isolado de uma instancia primaria, usado na CI.
        DNS_PORT=53
        verificar_servidor dns
        ;;
    *) falhar 'modo esperado: normal, falha ou local' ;;
esac
