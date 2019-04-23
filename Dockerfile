FROM alpine:3.9

LABEL maintainer="Mizore <me@mizore.cn>"

ENV NGINX_VERSION=1.15.12 OPENSSL_VERSION=1.1.1b

RUN apk add --no-cache --virtual .build-deps \
        gcc \
        libc-dev \
        make \
        pcre-dev \
        zlib-dev \
        expat-dev \
        libxml2-dev \
        libxslt-dev \
        libatomic_ops-dev \
        linux-headers \
        patch \
        curl \
        perl \
        git \
    \
    && addgroup -g 82 -S www-data \
    && adduser -u 82 -D -S -h /var/cache/nginx -G www-data www-data \
    \
    && mkdir -p /usr/src/nginx \
    && cd /usr/src/nginx \
    && curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar xzf - --strip-components=1 \
    \
    && mkdir -p /usr/src/openssl \
    && cd /usr/src/openssl \
    && curl -fSL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz | tar xzf - --strip-components=1 \
    && curl -fSL https://github.com/hakasenyang/openssl-patch/raw/master/openssl-equal-${OPENSSL_VERSION}_ciphers.patch | patch -p1 \
    && curl -fSL https://github.com/hakasenyang/openssl-patch/raw/master/openssl-${OPENSSL_VERSION}-chacha_draft.patch | patch -p1 \
    \
    && cd /usr/src \
    && git clone https://github.com/cloudflare/zlib --depth 1 && cd zlib && make -f Makefile.in distclean && cd .. \
    && git clone https://github.com/eustas/ngx_brotli --depth 1 && cd ngx_brotli && git submodule update --init --recursive && cd .. \
    && git clone https://github.com/arut/nginx-dav-ext-module --depth 1 \
    \
    && cd /usr/src/nginx \
    && ./configure \
           --prefix=/etc/nginx \
           --sbin-path=/usr/sbin/nginx \
           --modules-path=/usr/lib/nginx/modules \
           --conf-path=/etc/nginx/nginx.conf \
           --error-log-path=/var/log/nginx/error.log \
           --http-log-path=/var/log/nginx/access.log \
           --pid-path=/var/run/nginx.pid \
           --lock-path=/var/run/nginx.lock \
           --http-client-body-temp-path=/var/cache/nginx/client_temp \
           --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
           --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
           --user=www-data \
           --group=www-data \
           --with-threads \
           --with-file-aio \
           --with-libatomic \
           --with-stream \
           --with-stream_realip_module \
           --with-stream_ssl_module \
           --with-stream_ssl_preread_module \
           --with-http_ssl_module \
           --with-http_v2_module \
           --with-http_realip_module \
           --with-http_dav_module \
           --with-http_sub_module \
           --with-http_gzip_static_module \
           --with-http_gunzip_module \
           --with-http_stub_status_module \
           --with-http_auth_request_module \
           --with-http_secure_link_module \
           --with-http_degradation_module \
           --with-pcre-jit \
           --with-zlib=../zlib \
           --with-openssl=../openssl \
           --with-openssl-opt='zlib no-tests enable-ec_nistp_64_gcc_128 enable-tls1_3' \
           --with-cc-opt='-O3 -flto -fPIC -fPIE -fstack-protector-strong -Wformat -Werror=format-security -Wno-deprecated-declarations -Wno-strict-aliasing' \
           --without-mail_pop3_module \
           --without-mail_imap_module \
           --without-mail_smtp_module \
           --without-http_ssi_module \
           --without-http_uwsgi_module \
           --without-http_scgi_module \
           --without-http_memcached_module \
           --add-module=../ngx_brotli \
           --add-module=../nginx-dav-ext-module \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install \
    \
    && mkdir -p /var/cache/nginx/fastcgi_cache_temp \
                /var/cache/nginx/proxy_cache_temp \
                /var/log/nginx/old \
                /var/www/html \
    && cp /etc/nginx/html/index.html /var/www/html/index.html \
    \
    && strip /usr/sbin/nginx \
    \
    && mv /etc/nginx/mime.types /tmp/mime.types \
    && rm -rf /usr/src/* \
              /etc/nginx/* \
    && mv /tmp/mime.types /etc/nginx/mime.types \
    \
    && runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )" \
    \
    && apk add --no-cache --virtual .nginx-rundeps $runDeps \
    && apk del .build-deps \
    && apk add --no-cache logrotate \
    && mv /etc/periodic/daily/logrotate /etc/periodic/hourly/logrotate \
    && rm -rf /var/cache/apk/*

COPY ./etc/nginx/nginx.conf /etc/nginx/nginx.conf
COPY ./etc/logrotate.d/nginx /etc/logrotate.d/nginx

WORKDIR /var/www/html

EXPOSE 80

STOPSIGNAL SIGTERM

CMD ["sh", "-c", "crond && exec nginx -g 'daemon off;'"]
