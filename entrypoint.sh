#!/bin/sh

# update certs
/usr/sbin/update-ca-certificates

# Generate resolvers config for nginx
echo resolver $(awk 'BEGIN{ORS=" "} $1=="nameserver" {print $2}' /etc/resolv.conf) " ipv6=off;" > /var/run/openresty-assetry/resolvers.conf

# Check if ASSETRY_UPLOAD_API_KEY is set
if [ -z "$ASSETRY_UPLOAD_API_KEY" ]; then
    # Generate 32-character random alphanumeric key
    export ASSETRY_UPLOAD_API_KEY=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/random | head -c 32)
    echo "Generated ASSETRY_UPLOAD_API_KEY: $ASSETRY_UPLOAD_API_KEY"
else
    echo "ASSETRY_UPLOAD_API_KEY is already set"
fi

# Start openresty
exec \
    /usr/local/openresty/bin/openresty \
    -p /var/run/openresty-assetry \
    -c /var/run/openresty-assetry/nginx.conf
