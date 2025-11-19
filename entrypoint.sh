#!/bin/sh

# update certs
/usr/sbin/update-ca-certificates

# Generate resolvers config for nginx
echo resolver $(awk 'BEGIN{ORS=" "} $1=="nameserver" {print $2}' /etc/resolv.conf) " ipv6=off;" > /var/run/openresty-assetry/resolvers.conf

# Start openresty
exec \
    /usr/local/openresty/bin/openresty \
    -p /var/run/openresty-assetry \
    -c /var/run/openresty-assetry/nginx.conf
