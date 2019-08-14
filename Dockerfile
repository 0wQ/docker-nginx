FROM alpine:3.10

LABEL maintainer="Mizore <me@mizore.cn>"

ENV NGINX_VERSION=1.17.3
ENV OPENSSL_VERSION=1.1.1c

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories

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
    && adduser -S -D -H -u 82 -h /var/cache/nginx -s /sbin/nologin -G www-data -g www-data www-data \
    \
    && mkdir -p /usr/src/nginx \
    && cd /usr/src/nginx \
    && curl -fsSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar xz --strip-components=1 \
    \
    && mkdir -p /usr/src/openssl \
    && cd /usr/src/openssl \
    && curl -fsSL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz | tar xz --strip-components=1 \
    && curl -fsSL https://github.com/hakasenyang/openssl-patch/raw/master/openssl-equal-1.1.1b_ciphers.patch | patch -p1 \
    && curl -fsSL https://github.com/hakasenyang/openssl-patch/raw/master/openssl-${OPENSSL_VERSION}-chacha_draft.patch | patch -p1 \
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
           --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
           --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
           --user=www-data \
           --group=www-data \
           --with-http_ssl_module \
           --with-http_v2_module \
           --with-http_realip_module \
           --with-http_sub_module \
           --with-http_dav_module \
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
           --add-module=../nginx-dav-ext-module \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install \
    && rm -rf /etc/nginx/html/ \
    && mkdir -p /var/www/html \
                /etc/nginx/conf.d \
                /var/log/nginx/old \
                /var/cache/nginx/client_temp \
                /var/cache/nginx/proxy_temp \
                /var/cache/nginx/fastcgi_temp \
                /var/cache/nginx/uwsgi_temp \
                /var/cache/nginx/scgi_temp \
    && install -m644 html/index.html /var/www/html/ \
    && strip /usr/sbin/nginx* \
    && rm -rf /usr/src/* \
    \
    && apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    \
    && runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx /tmp/envsubst \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )" \
    && apk add --no-cache --virtual .nginx-rundeps $runDeps \
    && apk del .build-deps .gettext \
    && mv /tmp/envsubst /usr/local/bin/ \
    \
    && apk add --no-cache tzdata logrotate \
    && mv /etc/periodic/daily/logrotate /etc/periodic/hourly/logrotate

COPY ./etc/nginx/nginx.conf /etc/nginx/nginx.conf
COPY ./etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf
COPY ./etc/logrotate.d/nginx /etc/logrotate.d/nginx

WORKDIR /var/www/html

EXPOSE 80

STOPSIGNAL SIGTERM

CMD ["sh", "-c", "crond && exec nginx -g 'daemon off;'"]
