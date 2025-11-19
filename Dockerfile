FROM openresty/openresty:alpine

ENV LIBVIPS_VERSION 8.17.3

WORKDIR /tmp
EXPOSE 8080

RUN apk add --no-cache --virtual build-deps gcc g++ make build-base curl perl \
    && \
    apk add --no-cache vips vips-dev ca-certificates

RUN /usr/local/openresty/bin/opm install pintsized/lua-resty-http \
    && \
    /usr/local/openresty/bin/opm install bungle/lua-resty-prettycjson \
    && \
    /usr/local/openresty/bin/opm install golgote/neturl \
    && \
    mkdir -p /usr/local/openresty/site/lualib/resty

COPY ./helper /tmp/helper

RUN cd /tmp/helper \
    && \
    touch * \
    && \
    make clean \
    && \
    make install \
    && \
    cd /tmp \
    && \
    rm -rf /tmp/helper \
    && \
    ldconfig /usr/local/lib \
    && \
    apk del build-deps \
    && \
    rm -rf /var/cache/apk/*

COPY ./entrypoint.sh /entrypoint.sh
RUN mkdir -p /var/run/openresty-assetry/logs \
    && \
    chmod +x /entrypoint.sh
COPY ./nginx.conf    /var/run/openresty-assetry/nginx.conf
COPY ./lib/resty/*   /usr/local/openresty/site/lualib/resty/

ENTRYPOINT [ "/bin/sh", "/entrypoint.sh" ]
