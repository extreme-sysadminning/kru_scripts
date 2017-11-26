#!/bin/sh -e

# httpd.sh - very small webserver
#
# Karsten Kruse 2004 2005 www.tecneeq.de
# Idea from httpd.ksh www.shelldorado.com
#
# 1) Save this file as /usr/local/sbin/httpd.sh
# 2) Put this into inetd:
#    80 stream tcp nowait nobody /usr/local/sbin/httpd.sh
# 3) Let inetd reread it's configuration:
#    /etc/rc.d/inetd reload
# 4) Set the document root

root=${HTTP_DOC_ROOT:-/home/httpd/htdocs/}

gettype(){
  case "$1" in
    *.xhtml|*.html|*.htm|*.XHTML|*.HTML|*.HTM) type="text/html" ;;
  esac
  echo ${type:-$(file -i "$1" | awk '{print $2}' | sed 's/;//')}
}

while read line ; do
  [ "$line" = "$(printf \r\n)" ] && break # end of request header
  [ -z $requestline ] && requestline="$line" && break
done

set -- $requestline
doc="$root/$2"
[ -d "$doc" ] && doc="$doc/index.html"

if [ "$1" != GET ] ; then
  printf "HTTP/1.0 501 Not implemented\r\n\r\n501 Not implemented\r\n"
elif expr "$doc" : '.*/\.\./.*' >/dev/null ; then
  printf "HTTP/1.0 400 Bad Request\r\n\r\n400 Bad Request\r\n"
elif [ ! -f "$doc" ] ; then
  printf "HTTP/1.0 404 Not Found\r\n\r\n404 Not Found\r\n"
elif [ ! -r "$doc" ] ; then
  printf "HTTP/1.0 403 Forbidden\r\n\r\n403 Forbidden\r\n"
elif [ -r "$doc" -a -f "$doc" ] ; then
  printf "HTTP/1.0 200 OK\r\nContent-type: $(gettype "$doc")\r\n"
  printf "Content-Length: $(wc -c < "$doc")\r\n\r\n"
  exec cat "$doc"
else
  printf "HTTP/1.0 500 Server Error\r\n\r\n500 Server Error\r\n"
fi

# eof
