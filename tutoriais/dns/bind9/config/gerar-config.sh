#!/bin/sh
# Executado pelo configurador em contêiner; não instala dependências no host.
set -eu
erro() { echo "Configuracao invalida: $*" >&2; exit 1; }
ipv4() {
    printf '%s\n' "$1" | awk -F. 'NF!=4 {exit 1} {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || $i>255 || (length($i)>1 && substr($i,1,1)=="0")) exit 1}'
}
case "$BIND_ROLE" in primario|secundario) ;; *) erro 'BIND_ROLE deve ser primario ou secundario' ;; esac
ipv4 "$DNS_PRIMARY_IP" || erro 'DNS_PRIMARY_IP deve ser IPv4'
ipv4 "$DNS_SECONDARY_IP" || erro 'DNS_SECONDARY_IP deve ser IPv4'
ipv4 "$DNS_BIND_ADDRESS" || erro 'DNS_BIND_ADDRESS deve ser IPv4'
[ "$DNS_PRIMARY_IP" != "$DNS_SECONDARY_IP" ] || erro 'Os dois nos precisam de IPs distintos'
case "$DNS_PORT" in ''|*[!0-9]*) erro 'DNS_PORT deve ser numerica' ;; esac
[ "$DNS_PORT" -ge 1 ] && [ "$DNS_PORT" -le 65535 ] || erro 'Porta fora do intervalo 1..65535'
case "$DNS_CLIENT_CIDR" in */*) ;; *) erro 'Rede de clientes deve ser CIDR IPv4' ;; esac
ipv4 "${DNS_CLIENT_CIDR%/*}" || erro 'Rede de clientes invalida'
prefixo=${DNS_CLIENT_CIDR##*/}
case "$prefixo" in ''|*[!0-9]*) erro 'Prefixo CIDR invalido' ;; esac
[ "$prefixo" -ge 0 ] && [ "$prefixo" -le 32 ] || erro 'Prefixo CIDR fora de 0..32'
if [ "$BIND_ROLE" = primario ]; then local_ip=$DNS_PRIMARY_IP; else local_ip=$DNS_SECONDARY_IP; fi
[ "$DNS_BIND_ADDRESS" = "$local_ip" ] || erro 'DNS_BIND_ADDRESS deve ser o IP do papel escolhido'
mkdir -p /generated/shared /generated/zones
render() {
    sed -e "s|@DNS_PRIMARY_IP@|$DNS_PRIMARY_IP|g" \
        -e "s|@DNS_SECONDARY_IP@|$DNS_SECONDARY_IP|g" \
        -e "s|@DNS_CLIENT_CIDR@|$DNS_CLIENT_CIDR|g" \
        -e "s|@DNS_PORT@|$DNS_PORT|g" "$1" > "$2.tmp"
    mv "$2.tmp" "$2"
}
render "/templates/$BIND_ROLE/named.conf" /generated/named.conf
render /templates/shared/options.conf /generated/shared/options.conf
cp /templates/shared/lab.key /templates/shared/rndc.conf /generated/shared/
if [ "$BIND_ROLE" = primario ]; then
    render /zonas/db.lab.test /generated/zones/db.lab.test
    chmod 644 /generated/zones/db.lab.test
else
    rm -f /generated/zones/db.lab.test
fi
chmod 644 /generated/named.conf /generated/shared/*
echo "Configuracao gerada: papel=$BIND_ROLE local=$DNS_BIND_ADDRESS primario=$DNS_PRIMARY_IP secundario=$DNS_SECONDARY_IP porta=$DNS_PORT"
