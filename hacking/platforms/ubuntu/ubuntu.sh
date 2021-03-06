#!/bin/bash

set -e

. /etc/lsb-release

MYUSER=cif
MYGROUP=cif
VER=$DISTRIB_RELEASE

if [ `whoami` != 'root' ]; then
    echo 'this script must be run as root'
    exit 0
fi

apt-get update
apt-get install -qq python-software-properties

if [ ! -f /etc/apt/sources.list.d/chris-lea-zeromq-trusty.list ]; then
    echo 'adding updated zmq repo....'
    echo "yes" | sudo add-apt-repository "ppa:chris-lea/zeromq"
    wget -O - http://packages.elasticsearch.org/GPG-KEY-elasticsearch | apt-key add -
fi

if [ -f /etc/apt/sources.list.d/elasticsearch.list ]; then
    echo "sources.list.d/elasticsearch.list already exists, skipping..."
else
    echo "deb http://packages.elasticsearch.org/elasticsearch/1.0/debian stable main" >> /etc/apt/sources.list.d/elasticsearch.list
fi

debconf-set-selections <<< "postfix postfix/mailname string localhost"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"

apt-get update
apt-get install -y curl build-essential libmodule-build-perl libssl-dev elasticsearch apache2 libapache2-mod-perl2 curl mailutils build-essential git-core automake rng-tools openjdk-7-jre-headless libtool pkg-config vim htop bind9 libzmq3-dev libffi6 libmoose-perl libmouse-perl libanyevent-perl liblwp-protocol-https-perl libxml2-dev libexpat1-dev libgeoip-dev geoip-bin python-dev starman

#if [ ! -d /usr/share/elasticsearch/plugins/marvel ]; then
#    echo 'installing marvel for elasticsearch...'
#    /usr/share/elasticsearch/bin/plugin -i elasticsearch/marvel/latest
#fi

echo 'installing cpanm...'
curl -L https://cpanmin.us | sudo perl - App::cpanminus

cpanm -n --mirror http://cpan.metacpan.org Regexp::Common Mouse
cpanm http://backpan.perl.org/authors/id/M/MS/MSCHILLI/Log-Log4perl-1.44.tar.gz
cpanm https://cpan.metacpan.org/authors/id/E/EX/EXODIST/Test-Exception-0.35.tar.gz
cpanm https://github.com/csirtgadgets/p5-cif-sdk/archive/master.tar.gz
cpanm https://cpan.metacpan.org/authors/id/D/DR/DROLSKY/MaxMind-DB-Reader-0.050005.tar.gz
cpanm https://github.com/maxmind/GeoIP2-perl/archive/v0.040005.tar.gz

echo 'HRNGDEVICE=/dev/urandom' >> /etc/default/rng-tools
service rng-tools restart

echo 'setting up bind...'

if [ -z `grep -l '8.8.8.8' /etc/bind/named.conf.options` ]; then
    echo 'overwriting bind config'
    cp /etc/bind/named.conf.options /etc/bind/named.conf.options.orig
    cp named.conf.options /etc/bind/named.conf.options
fi

if [ -z `grep -l 'spamhaus.org' /etc/bind/named.conf.local` ]; then
    cat ./named.conf.local >> /etc/bind/named.conf.local
fi

echo 'restarting bind...'
service bind9 restart

if [ -z `grep -l '^prepend domain-name-servers 127.0.0.1;' /etc/dhcp/dhclient.conf` ]; then
    cp dhclient.conf /etc/dhcp/
fi

if [ -z `grep -l '127.0.0.1' /etc/resolvconf/resolv.conf.d/base` ]; then
    echo 'adding 127.0.0.1 as nameserver'
    echo "nameserver 127.0.0.1" >> /etc/resolvconf/resolv.conf.d/base
    echo "restarting network..."
    ifdown eth0 && sudo ifup eth0
fi

echo 'setting up apache'
if [ ! -f /etc/apache2/cif.conf ]; then
    cp cif.conf /etc/apache2/
fi

if [ $VER == "12.04" ]; then
    cp /etc/apache2/sites-available/default-ssl /etc/apache2/sites-available/default-ssl.orig
    cp default-ssl /etc/apache2/sites-available
    a2dissite default
    a2ensite default-ssl
    sed -i 's/^ServerTokens OS/ServerTokens Prod/' /etc/apache2/conf.d/security
    sed -i 's/^ServerSignature On/#ServerSignature On/' /etc/apache2/conf.d/security
    sed -i 's/^#ServerSignature Off/ServerSignature Off/' /etc/apache2/conf.d/security
elif [ $VER == "14.04" ]; then
    cp /etc/apache2/sites-available/default-ssl.conf /etc/apache2/sites-available/default-ssl.conf.orig
    cp default-ssl /etc/apache2/sites-available/default-ssl.conf
    a2dissite 000-default.conf
    a2ensite default-ssl.conf
    sed -i 's/^ServerTokens OS/ServerTokens Prod/' /etc/apache2/conf-enabled/security.conf
    sed -i 's/^ServerSignature On/#ServerSignature On/' /etc/apache2/conf-enabled/security.conf
    sed -i 's/^#ServerSignature Off/ServerSignature Off/' /etc/apache2/conf-enabled/security.conf
fi

a2enmod ssl proxy proxy_http

if [ -z `getent passwd $MYUSER` ]; then
    echo "adding user: $MYUSER"
    useradd $MYUSER -m -s /bin/bash
    adduser www-data $MYUSER
fi

echo 'starting elastic search'
update-rc.d elasticsearch defaults 95 10
service elasticsearch restart

cd ../../../

./configure --enable-geoip --sysconfdir=/etc/cif --localstatedir=/var --prefix=/opt/cif
make && make deps NOTESTS=-n
make test
make install
make fixperms
make elasticsearch

echo 'copying init.d scripts...'
cp ./hacking/packaging/ubuntu/init.d/cif-smrt /etc/init.d/
cp ./hacking/packaging/ubuntu/init.d/cif-router /etc/init.d/
cp ./hacking/packaging/ubuntu/init.d/cif-starman /etc/init.d/
cp ./hacking/packaging/ubuntu/init.d/cif-worker /etc/init.d/

echo 'setting /etc/default/cif'
cp ./hacking/packaging/ubuntu/default/cif /etc/default/cif

if [ ! -f /home/cif/.profile ]; then
    touch /home/cif/.profile
    chown $MYUSER:$MYGROUP /home/cif/.profile
fi

mkdir -p /var/smrt/cache
chown -R $MYUSER:$MYGROUP /var/smrt

if [ -z `grep -l '/opt/cif/bin' /home/cif/.profile` ]; then
    MYPROFILE=/home/$MYUSER/.profile
    echo "" >> $MYPROFILE
    echo "# automatically generated by CIF installation" >> $MYPROFILE
    echo 'PATH=/opt/cif/bin:$PATH' >> $MYPROFILE
fi

update-rc.d cif-router defaults 95 10
update-rc.d cif-smrt defaults 95 10
update-rc.d cif-starman defaults 95 10
update-rc.d cif-worker defaults 95 10

if [ ! -f /etc/cif/cif-smrt.yml ]; then
    echo 'setting up /etc/cif/cif-smrt.yml config...'
    /opt/cif/bin/cif-tokens --username cif-smrt --new --write --generate-config-remote http://localhost:5000 --generate-config-path /etc/cif/cif-smrt.yml
    chown cif:cif /etc/cif/cif-smrt.yml
    chmod 660 /etc/cif/cif-smrt.yml
fi

if [ ! -f /etc/cif/cif-worker.yml ]; then
    echo 'setting up /etc/cif/cif-worker.yml config...'
    /opt/cif/bin/cif-tokens --username cif-worker --new --read --write --generate-config-remote tcp://localhost:4961 --generate-config-path /etc/cif/cif-worker.yml
    chown cif:cif /etc/cif/cif-worker.yml
    chmod 660 /etc/cif/cif-worker.yml
fi

if [ ! -f ~/.cif.yml ]; then
    echo 'setting up ~/.cif.yml config for user: root@localhost...'
    /opt/cif/bin/cif-tokens --username root@localhost --new --read --write --generate-config-remote https://localhost --generate-config-path ~/.cif.yml
    chmod 660 ~/.cif.yml
fi

echo 'starting cif-router...'
service cif-router restart

echo 'restarting apache...'
service apache2 restart

echo 'starting cif-starman...'
service cif-starman restart

echo 'starting cif-worker'
service cif-worker restart
