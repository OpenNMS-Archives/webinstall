#!/bin/sh

pushd /var/ftp/pub/utilities/install/web >/dev/null 2>&1
cvs -z3 -q update -Pd
chown -R ranger:opennms .
find . -name \*.sh -exec chmod 755 {} \;
find . -name \*.pl -exec chmod 755 {} \;
find . -name \*.mperl -exec chmod 755 {} \;
find . -type d -exec chmod 2775 {} \;
find . -type f -exec chmod g+w {} \;
popd >/dev/null 2>&1
