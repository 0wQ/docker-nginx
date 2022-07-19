FROM alpine:3.16

ARG NGINX_VERSION=1.23.0
ARG OPENSSL_VERSION=1.1.1q

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
    && adduser -S -D -H -u 82 -h /var/cache/nginx -s /sbin/nologin -G www-data -g www-data www-data \
    \
    && mkdir -p /tmp/build/nginx && cd /tmp/build/nginx \
    && curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar xz --strip-components=1 \
    && curl -fSL https://gist.githubusercontent.com/0wQ/2404ea3e4252ee113bb2cdd3ac1ef4c2/raw/5debc5de58b6674184639765eb754c9d267bfa03/ngx_http_autoindex_module.patch | patch -p1 \
    \
    && mkdir -p /tmp/build/openssl && cd /tmp/build/openssl \
    && curl -fSL https://github.com/openssl/openssl/archive/OpenSSL_${OPENSSL_VERSION//./_}.tar.gz | tar xz --strip-components=1 \
    \
    && cd /tmp/build \
    && git clone https://github.com/cloudflare/zlib --depth 1 && cd zlib && make -f Makefile.in distclean && cd .. \
    && git clone https://github.com/google/ngx_brotli --depth 1 && cd ngx_brotli && git submodule update --init --recursive && cd .. \
    && git clone https://github.com/openresty/headers-more-nginx-module --depth 1 \
    && git clone https://github.com/FRiCKLE/ngx_cache_purge --depth 1 \
    \
    && cd /tmp/build/nginx \
    && ./configure \
           --prefix=/etc/nginx \
           --sbin-path=/usr/sbin/nginx \
           --modules-path=/usr/lib/nginx/modules \
           --conf-path=/etc/nginx/nginx.conf \
           --error-log-path=/var/log/nginx/error.log \
           --http-log-path=/var/log/nginx/access.log \
           --pid-path=/var/run/nginx.pid \
           --lock-path=/var/run/nginx.lock \
           --http-client-body-temp-path=/var/cache/nginx/client_body_temp \
           --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
           --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
           --user=www-data \
           --group=www-data \
           --with-http_ssl_module \
           --with-http_v2_module \
           --with-http_realip_module \
           --with-http_sub_module \
           --with-http_gunzip_module \
           --with-http_gzip_static_module \
           --with-http_random_index_module \
           --with-http_secure_link_module \
           --with-http_stub_status_module \
           --with-http_auth_request_module \
           --with-threads \
           --with-stream \
           --with-stream_ssl_module \
           --with-stream_ssl_preread_module \
           --with-stream_realip_module \
           --with-compat \
           --with-file-aio \
           --with-libatomic \
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
           --add-module=../headers-more-nginx-module \
           --add-module=../ngx_cache_purge \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install \
    && rm -rf /etc/nginx/html/ \
    && mkdir -p /var/www/html \
                /etc/nginx/conf.d \
                /var/log/nginx/old \
                /var/cache/nginx/client_body_temp \
                /var/cache/nginx/proxy_temp \
                /var/cache/nginx/fastcgi_temp \
    && install -m644 html/index.html /var/www/html/ \
    && strip /usr/sbin/nginx* \
    && rm -rf /tmp/build \
    \
    && apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    \
    && runDeps="$( \
        scanelf --needed --nobanner /usr/sbin/nginx /tmp/envsubst \
            | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
            | sort -u \
            | xargs -r apk info --installed \
            | sort -u \
    )" \
    && apk add --no-cache $runDeps \
    && apk del .build-deps .gettext \
    && mv /tmp/envsubst /usr/local/bin/ \
    \
    && apk add --no-cache tzdata logrotate curl ca-certificates \
    && mv /etc/periodic/daily/logrotate /etc/periodic/hourly/logrotate \
    \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

COPY ./etc/nginx/nginx.conf /etc/nginx/nginx.conf
COPY ./etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf
COPY ./etc/logrotate.d/nginx /etc/logrotate.d/nginx

WORKDIR /var/www/html

EXPOSE 80

STOPSIGNAL SIGQUIT

CMD ["sh", "-c", "crond && exec nginx -g 'daemon off;'"]
