FROM alpine:3.4

MAINTAINER Adrien M amaurel90@gmail.com

ENV DEBUG=false RAP_DEBUG="info"
ARG VERSION_RANCHER_GEN="artifacts/master"
ENV NGINX_VERSION 1.13.9
ENV NGINX_AUTH_LDAP_VERSION 8517bb05ecc896b54429ca5e95137b0a386bd41a

ENV CONFIG "\
	--prefix=/etc/nginx \
	--sbin-path=/usr/sbin/nginx \
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
	--user=nginx \
	--group=nginx \
	--with-http_ssl_module \
	--with-http_realip_module \
	--with-http_gunzip_module \
	--with-http_gzip_static_module \
	--with-http_stub_status_module \
	--with-file-aio \
	--with-http_v2_module \
	--with-ipv6 \
	"

ENV CFLAGS "-O2 -pipe -fomit-frame-pointer -march=core2 -mtune=intel"

RUN \
	addgroup -S nginx \
	&& adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
	&& apk add --no-cache --virtual .build-deps \
		gcc \
		libc-dev \
		make \
		openssl-dev \
		pcre-dev \
		zlib-dev \
		openldap-dev \
		linux-headers \
		curl \
		gnupg \
	&& curl -fSL http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz -o nginx.tar.gz \
	&& curl -fSL http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc  -o nginx.tar.gz.asc \
	&& mkdir -p /usr/src \
	&& tar -zxC /usr/src -f nginx.tar.gz \
	&& rm nginx.tar.gz* \

	&& curl -fSL https://github.com/kvspb/nginx-auth-ldap/archive/$NGINX_AUTH_LDAP_VERSION.tar.gz -o nginx-auth-ldap-$NGINX_AUTH_LDAP_VERSION.tar.gz \
	&& tar -zxC /usr/src -f nginx-auth-ldap-$NGINX_AUTH_LDAP_VERSION.tar.gz \
	&& rm nginx-auth-ldap-$NGINX_AUTH_LDAP_VERSION.tar.gz \

	&& cd /usr/src/nginx-$NGINX_VERSION \
	&& ./configure $CONFIG --add-module=/usr/src/nginx-auth-ldap-$NGINX_AUTH_LDAP_VERSION \
	&& make install \
	&& strip /usr/sbin/nginx \
	&& runDeps="$( \
		scanelf --needed --nobanner /usr/sbin/nginx \
			| awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
			| sort -u \
			| xargs -r apk info --installed \
			| sort -u \
	)" \
	&& apk add --virtual .nginx-rundeps $runDeps \
	&& apk del .build-deps \
	&& rm -rf /usr/src/nginx-* \
	\
	# forward request and error logs to docker log collector
	&& ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log

##END NGINX INSTALLATION

#RANCHER PROXY START
RUN apk add --no-cache nano ca-certificates unzip wget certbot bash openssl vim \
 && mkdir -p /var/cache/nginx \
 && rm -rf /var/cache/apk/*

# Install Forego & Rancher-Gen-RAP
ADD https://github.com/jwilder/forego/releases/download/v0.16.1/forego /usr/local/bin/forego

RUN wget "https://gitlab.com/adi90x/rancher-gen-rap/builds/$VERSION_RANCHER_GEN/download?job=compile-go" -O /tmp/rancher-gen-rap.zip \
	&& unzip /tmp/rancher-gen-rap.zip -d /usr/local/bin \
	&& chmod +x /usr/local/bin/rancher-gen \
	&& chmod u+x /usr/local/bin/forego \
	&& rm -f /tmp/rancher-gen-rap.zip

#Copying all templates and script
COPY /app/                       /app/
COPY /app/nginx.conf             /etc/nginx/nginx.conf

WORKDIR /app/

# Seting up repertories & Configure Nginx and apply fix for very long server names
RUN chmod +x /app/letsencrypt.sh \
    && mkdir -p /etc/nginx/certs /etc/nginx/vhost.d /etc/nginx/conf.d /usr/share/nginx/html /etc/letsencrypt \
    && echo "daemon off;" >> /etc/nginx/nginx.conf \
    && sed -i 's/^http {/&\n    server_names_hash_bucket_size 128;/g' /etc/nginx/nginx.conf \
    && chmod u+x /app/remove

ENTRYPOINT ["/bin/bash", "/app/entrypoint.sh" ]
CMD ["forego", "start", "-r"]
