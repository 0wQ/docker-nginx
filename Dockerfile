FROM alpine:3.9

LABEL maintainer="Mizore <me@mizore.cn>"

ENV NGINX_VERSION=1.15.11 OPENSSL_VERSION=1.1.1b

# RUN echo 'https://mirrors.ustc.edu.cn/alpine/v3.9/main' > /etc/apk/repositories \

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
#     && apk add jemalloc-dev --repository https://mirrors.ustc.edu.cn/alpine/v3.8/main \
    \
    && addgroup -g 82 -S www-data \
    && adduser -u 82 -D -S -h /var/cache/nginx -G www-data www-data \
    \
    && mkdir -p /usr/src/nginx \
    && cd /usr/src/nginx \
    && curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar xzf - --strip-components=1 \
#     && curl -fSL https://github.com/kn007/patch/raw/master/nginx.patch | patch -p1 \
#     && curl -fSL https://github.com/kn007/patch/raw/master/nginx_strict-sni.patch | patch -p1 \
#     && curl -fSL https://github.com/kn007/patch/raw/master/nginx_auto_using_PRIORITIZE_CHACHA.patch | patch -p1 \
#     && curl -fSL https://gist.github.com/CarterLi/f6e21d4749984a255edc7b358b44bf58/raw/4a7ad66a9a29ffade34d824549ed663bc4b5ac98/use_openssl_md5_sha1.diff | patch -p1 \
    \
    && mkdir -p /usr/src/openssl \
    && cd /usr/src/openssl \
    && curl -fSL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz | tar xzf - --strip-components=1 \
#     && git clone https://github.com/openssl/openssl --depth 1 . && git submodule update --init --recursive \
    && curl -fSL https://github.com/hakasenyang/openssl-patch/raw/master/openssl-equal-${OPENSSL_VERSION}_ciphers.patch | patch -p1 \
    && curl -fSL https://github.com/hakasenyang/openssl-patch/raw/master/openssl-${OPENSSL_VERSION}-chacha_draft.patch | patch -p1 \
    \
    && cd /usr/src \
    && git clone https://github.com/cloudflare/zlib --depth 1 && cd zlib && make -f Makefile.in distclean && cd .. \
    && git clone https://github.com/eustas/ngx_brotli --depth 1 && cd ngx_brotli && git submodule update --init --recursive && cd .. \
    && git clone https://github.com/arut/nginx-dav-ext-module --depth 1 \
#     && git clone https://github.com/openresty/headers-more-nginx-module --depth 1 \
#     && git clone https://github.com/nginx-modules/ngx_cache_purge --depth 1 \
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
#            --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
#            --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
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
#            --with-http_spdy_module \
           --with-http_v2_module \
#            --with-http_v2_hpack_enc \
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
#            --with-openssl-opt='zlib no-tests enable-ec_nistp_64_gcc_128 enable-tls1_3 -ljemalloc' \
#            --with-ld-opt='-ljemalloc' \
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
#            --add-module=../headers-more-nginx-module \
#            --add-module=../ngx_cache_purge \
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
#     && apk del .build-deps jemalloc-dev \
    && apk add --no-cache logrotate \
    && mv /etc/periodic/daily/logrotate /etc/periodic/hourly/logrotate \
    && rm -rf /var/cache/apk/*
#     \
#     && ln -sf /dev/stdout /var/log/nginx/access.log \
#     && ln -sf /dev/stderr /var/log/nginx/error.log

COPY ./etc/nginx/nginx.conf /etc/nginx/nginx.conf
COPY ./etc/logrotate.d/nginx /etc/logrotate.d/nginx

WORKDIR /var/www/html

EXPOSE 80

STOPSIGNAL SIGTERM

CMD ["sh", "-c", "crond && exec nginx -g 'daemon off;'"]
